use serde_json::{Map, Value};
use std::{
    env, fs,
    path::Path,
    process::{Command, Output},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn run(program: &str, args: &[&str]) -> std::io::Result<Output> {
    Command::new(program).args(args).output()
}
fn success(args: &[&str]) -> bool {
    run("git", args).is_ok_and(|o| o.status.success())
}
fn git_text(args: &[&str]) -> Option<String> {
    run("git", args)
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_owned())
}
// A JSON string is a Nix string literal once interpolation is escaped.
fn nix_json(value: &Value) -> Result<String> {
    Ok(serde_json::to_string(&serde_json::to_string(value)?)?.replace("${", "\\${"))
}
fn drv_map(bytes: &[u8], policy: &Map<String, Value>) -> Result<Map<String, Value>> {
    let Value::Object(mut map) = serde_json::from_slice(bytes)? else {
        return Err("Invalid package derivation map".into());
    };
    for (name, value) in &map {
        let valid = if policy.contains_key(name) {
            value.is_null()
        } else {
            value
                .as_str()
                .is_some_and(|path| path.starts_with("/nix/store/") && path.ends_with(".drv"))
        };
        if !valid {
            return Err("Invalid package derivation map".into());
        }
    }
    for (name, reason) in policy {
        if map.remove(name).is_some() {
            eprintln!(
                "::notice::Skipping {name}: {}",
                reason.as_str().unwrap_or_default()
            );
        }
    }
    Ok(map)
}
fn eval(installable: &str, apply: &str, policy: &Map<String, Value>) -> Result<Map<String, Value>> {
    let args = [
        "eval",
        "--json",
        "--option",
        "min-free",
        "0",
        "--option",
        "max-free",
        "0",
        "--option",
        "eval-cores",
        "1",
        "--no-allow-import-from-derivation",
        // --no-write-lock-file would still permit a recalculated lock in memory.
        "--no-update-lock-file",
        installable,
        "--apply",
        apply,
    ];
    let output = run("nix", &args)?;
    // Preserve evaluator diagnostics on stderr only.
    use std::io::Write;
    std::io::stderr().write_all(&output.stderr)?;
    if !output.status.success() {
        return Err("Package evaluation failed".into());
    }
    drv_map(&output.stdout, policy)
}
fn select() -> Result<()> {
    // Validate the checked-out submodule's policy before invoking any evaluator.
    let policy: Value = fs::read("pkgs/.github/ci-policy.json")
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or(Value::Null);
    let valid_name = |s: &str| {
        !s.is_empty()
            && s.bytes()
                .next()
                .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
            && s.bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b"+._-".contains(&c))
    };
    let Some(policy) = policy.as_object().filter(|m| {
        m.iter()
            .all(|(k, v)| valid_name(k) && v.as_str().is_some_and(|s| !s.trim().is_empty()))
    }) else {
        return Err("::error::Invalid hosted-build policy in pkgs; expected package names and nonblank reasons.".into());
    };
    for name in policy.keys() {
        if !Path::new(&format!(
            "pkgs/pkgs/by-name/{}/{name}/package.nix",
            &name[..2.min(name.len())]
        ))
        .is_file()
        {
            return Err(
                format!("::error::Hosted-build policy names an unknown package: {name}").into(),
            );
        }
    }
    let system = env::var("TARGET_SYSTEM")?;
    let requested: Vec<String> = env::args().skip(1).collect();
    let projection = format!(
        r#"packages:
          let
            requested = builtins.fromJSON {};
            excluded = builtins.fromJSON {};
            names = if requested == [] then builtins.attrNames packages else requested;
            project = names: builtins.listToAttrs (map (name: {{
              inherit name;
              value =
                if !builtins.hasAttr name packages then throw ("Unknown requested package: " + name)
                else if builtins.hasAttr name excluded then null
                else packages.${{name}}.drvPath;
            }}) names);
          in "#,
        nix_json(&serde_json::to_value(requested)?)?,
        nix_json(&Value::Object(policy.clone()))?
    );
    let current = eval(
        &format!(".#packages.{system}"),
        &format!("{projection}project names"),
        policy,
    )?;
    let mut base_sha = env::var("BASE_SHA").unwrap_or_default();
    if base_sha.is_empty()
        && env::var("GITHUB_EVENT_NAME").as_deref() == Ok("workflow_dispatch")
        && env::var("GITHUB_REF")
            .unwrap_or_default()
            .starts_with("refs/heads/gh-readonly-queue/main/")
        && git_text(&["rev-parse", "HEAD"])
            .is_some_and(|s| env::var("GITHUB_SHA").as_deref() == Ok(s.as_str()))
        && let Some(parents) = git_text(&["rev-list", "--parents", "-n", "1", "HEAD"])
        && let Some(parent) = parents.split_whitespace().nth(1)
    {
        base_sha = parent.to_owned();
    }
    let mut base = Map::new();
    if base_sha.len() == 40
        && base_sha
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
        && success(&["cat-file", "-e", &format!("{base_sha}^{{commit}}")])
        && success(&["merge-base", "--is-ancestor", &base_sha, "HEAD"])
    {
        let names = nix_json(&serde_json::to_value(current.keys().collect::<Vec<_>>())?)?;
        let apply = format!(
            "{projection}project (builtins.filter (name: builtins.hasAttr name packages) (builtins.fromJSON {names}))"
        );
        match eval(
            &format!(
                "git+file://{}?rev={base_sha}&submodules=1#packages.{system}",
                env::current_dir()?.display()
            ),
            &apply,
            policy,
        ) {
            Ok(map) => base = map,
            Err(_) => eprintln!(
                "::notice::Base package evaluation unavailable; selecting all eligible candidates."
            ),
        }
    } else {
        eprintln!("::notice::Base history unavailable; selecting all eligible candidates.");
    }
    let selected: Vec<String> = current
        .iter()
        .filter(|(name, value)| base.get(*name) != Some(*value))
        .map(|(name, _)| {
            Ok(format!(
                ".#packages.{system}.{}",
                serde_json::to_string(name)?
            ))
        })
        .collect::<Result<_>>()?;
    println!("{}", serde_json::to_string(&selected)?);
    Ok(())
}
fn main() {
    if let Err(error) = select() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
