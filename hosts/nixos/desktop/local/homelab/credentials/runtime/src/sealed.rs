use super::*;
pub const PREFIX: &str = "ianhollow/hosts/nixos/desktop/";
const SOURCES: &str = "hosts/nixos/desktop/local/secrets/";
fn allowed(name: &str) -> bool {
    matches!(
        name,
        "homelab-miniflux-username"
            | "homelab-miniflux-password"
            | "homelab-identity-realm"
            | "homelab-identity-admin-env"
            | "homelab-wardrowbe-env"
    )
}
pub fn id(plan: &Value, name: &str) -> Result<String> {
    let key = format!("{PREFIX}{name}");
    validate(plan, &key, &format!("{SOURCES}{name}.age"))?;
    Ok(key)
}
fn validate(plan: &Value, key: &str, source: &str) -> Result<()> {
    let name = key.strip_prefix(PREFIX).ok_or("unexpected secret owner")?;
    if !allowed(name) || source != format!("{SOURCES}{name}.age") {
        return fail("noncanonical credential source");
    }
    let entry = &plan["secrets"][key];
    if entry.is_null() || entry["source"] != source {
        return fail("plan/source mismatch");
    }
    // IDs bind the repository target owner; runtime ownership must stay privileged.
    if entry["runtime"]["owner"] != "root" {
        return fail("unexpected runtime secret owner");
    }
    if let Some(overrides) = entry["runtimeOverrides"].as_object()
        && overrides.values().any(|v| v["owner"] != "root")
    {
        return fail("unexpected runtime override owner");
    }
    Ok(())
}
pub fn path(root: &Path, source: &str) -> Result<PathBuf> {
    let root = root.canonicalize()?;
    let rel = Path::new(source);
    if rel.is_absolute()
        || rel
            .components()
            .any(|c| !matches!(c, std::path::Component::Normal(_)))
    {
        return fail("unsafe source path");
    }
    let mut p = root;
    for c in rel.components() {
        p.push(c);
        match std::fs::symlink_metadata(&p) {
            Ok(m) if m.file_type().is_symlink() => return fail("symlinked source path"),
            Ok(_) => (),
            Err(e) if e.kind() == io::ErrorKind::NotFound => (),
            Err(e) => return Err(e.into()),
        }
    }
    Ok(p)
}
async fn remote(host: &str, worker: &str, request: &Value) -> Result<String> {
    command(
        &["ssh", "-o", "BatchMode=yes", "--", host, worker],
        Some(&serde_json::to_string(request)?),
    )
    .await
}
pub async fn worker(name: &str, request: Value) -> Result<()> {
    let plan = &request["plan"];
    let key = string(&request["secret"]);
    let source = string(&request["source"]);
    validate(plan, key, source)?;
    let root = tempfile::tempdir()?;
    let target = path(root.path(), source)?;
    std::fs::create_dir_all(target.parent().ok_or("missing parent")?)?;
    let plan_path = root.path().join("plan.json");
    std::fs::write(&plan_path, serde_json::to_vec(plan)?)?;
    let reveal = name == "identity-reveal-worker";
    let op = if reveal {
        "reveal"
    } else {
        string(&request["operation"])
    };
    let value = string(&request["value"]);
    if op == "compare" || op == "reveal" {
        std::fs::write(&target, decode(string(&request["ciphertext"]))?)?;
        let output = command(
            &[
                "nix-seal",
                "secret",
                "reveal",
                "--plan",
                plan_path.to_str().ok_or("path")?,
                "--repository-root",
                root.path().to_str().ok_or("path")?,
                "--secret",
                key,
                "--identity",
                string(&request["identity"]),
            ],
            None,
        )
        .await?;
        if reveal {
            print!("{output}");
        } else {
            print!("{}", if output == value { "match" } else { "mismatch" });
        }
    } else if op == "create" {
        if string(&request["authorizer_key"]).is_empty() {
            return fail("missing authorizer");
        }
        command(
            &[
                "nix-seal",
                "secret",
                "bootstrap",
                "complete",
                "--bootstrap-plan",
                plan_path.to_str().ok_or("path")?,
                "--repository-root",
                root.path().to_str().ok_or("path")?,
                "--secret",
                key,
                "--authorizer-key",
                string(&request["authorizer_key"]),
            ],
            Some(value),
        )
        .await?;
        print!("{}", encode(&std::fs::read(&target)?));
    } else {
        return fail("unsupported worker operation");
    }
    Ok(())
}
pub struct Plans {
    pub normal: Value,
    pub bootstrap: Value,
    pub root: PathBuf,
}
impl Plans {
    pub fn load(a: &Args) -> Result<Self> {
        let normal = read_json(Path::new(a.required("plan")?))?;
        let bootstrap = if a.has("bootstrap-plan") {
            read_json(Path::new(a.required("bootstrap-plan")?))?
        } else {
            json!({"secrets":{}})
        };
        Ok(Self {
            normal,
            bootstrap,
            root: a.repo()?,
        })
    }
    pub fn entry(&self, name: &str) -> Result<(String, String)> {
        let key = format!("{PREFIX}{name}");
        let plan = if self.normal["secrets"].get(&key).is_some() {
            &self.normal
        } else {
            &self.bootstrap
        };
        id(plan, name)?;
        if self.normal["secrets"].get(&key).is_some()
            && self.bootstrap["secrets"].get(&key).is_some()
        {
            id(&self.bootstrap, name)?;
        }
        Ok((key, format!("{SOURCES}{name}.age")))
    }
    pub async fn existing(&self, a: &Args, name: &str) -> Result<Option<String>> {
        let (key, source) = self.entry(name)?;
        let path = path(&self.root, &source)?;
        if !path.try_exists()? {
            return Ok(None);
        }
        validate(&self.normal, &key, &source)?;
        if a.has("administrator-host") {
            Ok(Some(remote(a.required("administrator-host")?,"identity-reveal-worker",&json!({"plan":self.normal,"secret":key,"source":source,"identity":a.required("identity")?,"ciphertext":encode(&std::fs::read(path)?)})).await?))
        } else {
            Ok(Some(
                command(
                    &[
                        "nix-seal",
                        "secret",
                        "reveal",
                        "--plan",
                        a.required("plan")?,
                        "--repository-root",
                        self.root.to_str().ok_or("path")?,
                        "--secret",
                        &key,
                        "--identity",
                        a.required("identity")?,
                    ],
                    None,
                )
                .await?,
            ))
        }
    }
    pub async fn seal(&self, a: &Args, name: &str, value: &str) -> Result<()> {
        let (key, source) = self.entry(name)?;
        let target = path(&self.root, &source)?;
        let exists = target.try_exists()?;
        let plan = if exists {
            &self.normal
        } else {
            &self.bootstrap
        };
        validate(plan, &key, &source)?;
        if !exists {
            a.required("authorizer-key")?;
            a.required("bootstrap-plan")?;
        }
        if a.has("administrator-host") {
            let mut request = json!({"operation":if exists{"compare"}else{"create"},"plan":plan,"source":source,"secret":key,"identity":a.required("identity")?,"authorizer_key":a.get("authorizer-key",""),"value":value});
            if exists {
                request["ciphertext"] = json!(encode(&std::fs::read(&target)?));
            }
            let response = remote(
                a.required("administrator-host")?,
                "miniflux-seal-worker",
                &request,
            )
            .await?;
            if exists {
                if response != "match" {
                    return fail("existing ciphertext differs");
                }
            } else {
                let bytes = decode(&response)?;
                std::fs::create_dir_all(target.parent().ok_or("parent")?)?;
                let target = path(&self.root, &source)?;
                use std::os::unix::fs::OpenOptionsExt;
                let mut out = std::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .mode(0o600)
                    .open(target)?;
                out.write_all(&bytes)?;
                out.sync_all()?;
            }
        } else if exists {
            if self.existing(a, name).await?.as_deref() != Some(value) {
                return fail("existing ciphertext differs");
            }
        } else {
            command(
                &[
                    "nix-seal",
                    "secret",
                    "bootstrap",
                    "complete",
                    "--bootstrap-plan",
                    a.required("bootstrap-plan")?,
                    "--repository-root",
                    self.root.to_str().ok_or("path")?,
                    "--secret",
                    &key,
                    "--authorizer-key",
                    a.required("authorizer-key")?,
                ],
                Some(value),
            )
            .await?;
        }
        println!(
            "{} sealed credential",
            if exists { "Verified" } else { "Created" }
        );
        Ok(())
    }
}
