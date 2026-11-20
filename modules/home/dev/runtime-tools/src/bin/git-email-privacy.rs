//! Inspect immutable Git objects and identifiers without exposing private values.
use serde_json::Value;
use std::{
    collections::HashSet, error::Error, fs, os::unix::fs::MetadataExt, path::PathBuf,
    process::Stdio, time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    process::Command,
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
const BLOCKED: &str = "Blocked private email in Git data. Use your public noreply identity and remove private addresses from published content.";
async fn capture(executable: &str, args: &[&str], input: Option<&[u8]>) -> Result<Vec<u8>> {
    let output = nix_conf_process::run(
        Command::new(executable)
            .args(args)
            .env("GIT_NO_REPLACE_OBJECTS", "1"),
        input,
        Duration::from_secs(120),
    )
    .await?;
    if !output.status.success() {
        return Err("Privacy check failed; no data was published.".into());
    }
    Ok(output.stdout)
}
struct Guard {
    git: String,
    gh: String,
    patterns: Vec<Vec<u8>>,
    overlap: usize,
    private: Vec<String>,
    github: regex::Regex,
}
impl Guard {
    fn new(git: String, gh: String, policy: PathBuf) -> Result<Self> {
        if fs::metadata(&policy)?.mode() & 0o077 != 0 {
            return Err("Private email policy must be readable only by its owner.".into());
        }
        let policy: Value = serde_json::from_slice(&fs::read(policy)?)?;
        let addresses = policy
            .get("blockedEmails")
            .and_then(Value::as_array)
            .ok_or("invalid policy")?;
        if addresses.is_empty() {
            return Err("invalid policy".into());
        }
        let mut patterns = Vec::new();
        for address in addresses {
            let address = address
                .as_str()
                .filter(|a| a.contains('@'))
                .ok_or("invalid policy")?
                .to_lowercase();
            for encoded in [
                address.clone(),
                address.replace('@', "\\@"),
                address.replace('@', "%40"),
                address.replace('@', "&#64;"),
                address.replace('@', "&#x40;"),
            ] {
                patterns.push(encoded.into_bytes());
            }
        }
        let overlap = patterns
            .iter()
            .map(Vec::len)
            .max()
            .ok_or("invalid policy")?
            - 1;
        let private = match policy.get("privateContentRepositories") {
            None => Vec::new(),
            Some(v) => v
                .as_array()
                .ok_or("invalid policy")?
                .iter()
                .map(|v| v.as_str().map(str::to_owned).ok_or("invalid policy"))
                .collect::<std::result::Result<_, _>>()?,
        };
        Ok(Self {
            git,
            gh,
            patterns,
            overlap,
            private,
            github: regex::Regex::new(
                r"^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$",
            )?,
        })
    }
    fn inspect(&self, bytes: &[u8]) -> Result<()> {
        let bytes = bytes.to_ascii_lowercase();
        if self
            .patterns
            .iter()
            .any(|pattern| bytes.windows(pattern.len()).any(|part| part == pattern))
        {
            return Err(BLOCKED.into());
        }
        Ok(())
    }
    async fn git(&self, args: &[&str], input: Option<&[u8]>) -> Result<Vec<u8>> {
        capture(&self.git, args, input).await
    }
    async fn private_content(&self, destination: Option<&str>) -> Result<bool> {
        if self.private.is_empty() {
            return Ok(false);
        }
        let urls = match destination {
            Some(s) => vec![s.to_owned()],
            None => {
                let remotes = String::from_utf8(self.git(&["remote"], None).await?)?;
                let mut urls = Vec::new();
                for remote in remotes.lines() {
                    urls.push(
                        String::from_utf8(self.git(&["remote", "get-url", remote], None).await?)?
                            .trim()
                            .to_owned(),
                    );
                }
                urls
            }
        };
        if urls.is_empty() {
            return Ok(false);
        }
        for url in urls {
            let Some(captures) = self.github.captures(&url) else {
                return Ok(false);
            };
            let repository = captures.get(1).ok_or("invalid repository")?.as_str();
            if !self.private.iter().any(|p| p == repository) {
                return Ok(false);
            }
            if destination.is_some() {
                let repo: Value = serde_json::from_slice(
                    &capture(
                        &self.gh,
                        &[
                            "api",
                            "--hostname",
                            "github.com",
                            &format!("repos/{repository}"),
                        ],
                        None,
                    )
                    .await?,
                )?;
                if repo.get("private").and_then(Value::as_bool) != Some(true) {
                    return Ok(false);
                }
            }
        }
        Ok(true)
    }
    async fn objects(&self, ids: Vec<Vec<u8>>, allow_content: bool) -> Result<()> {
        let mut child = Command::new(&self.git)
            .args(["cat-file", "--batch"])
            .env("GIT_NO_REPLACE_OBJECTS", "1")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()?;
        let mut input = child.stdin.take().ok_or("Git stdin unavailable")?;
        let mut output = BufReader::new(child.stdout.take().ok_or("Git stdout unavailable")?);
        let mut seen = HashSet::new();
        for id in ids {
            if !seen.insert(id.clone()) {
                continue;
            }
            if ![40, 64].contains(&id.len())
                || !id
                    .iter()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
            {
                return Err("Invalid Git object ID.".into());
            }
            input.write_all(&id).await?;
            input.write_all(b"\n").await?;
            input.flush().await?;
            let mut line = String::new();
            output.read_line(&mut line).await?;
            let fields: Vec<_> = line.split_whitespace().collect();
            let [returned, kind, size] = fields.as_slice() else {
                return Err("Cannot inspect an outgoing Git object.".into());
            };
            if returned.as_bytes() != id {
                return Err("Git object mismatch".into());
            }
            let mut remaining = size.parse::<u64>()?;
            let mut tail = Vec::new();
            let mut chunk = vec![0; 1024 * 1024];
            while remaining > 0 {
                let len = usize::try_from(remaining.min(chunk.len() as u64))?;
                output.read_exact(&mut chunk[..len]).await?;
                if !(allow_content && *kind == "blob") {
                    tail.extend_from_slice(&chunk[..len]);
                    self.inspect(&tail)?;
                    if tail.len() > self.overlap {
                        tail.drain(..tail.len() - self.overlap);
                    }
                }
                remaining -= len as u64;
            }
            if output.read_u8().await? != b'\n' {
                return Err("Invalid Git object boundary.".into());
            }
        }
        drop(input);
        if !child.wait().await?.success() {
            return Err("Git object inspection failed.".into());
        }
        Ok(())
    }
    async fn before_commit(&self) -> Result<()> {
        for identity in ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"] {
            self.inspect(&self.git(&["var", identity], None).await?)?;
        }
        let staged = self.git(&["ls-files", "--stage", "-z"], None).await?;
        let mut objects = Vec::new();
        for record in staged.split(|b| *b == 0).filter(|r| !r.is_empty()) {
            let position = record
                .iter()
                .position(|b| *b == b'\t')
                .ok_or("invalid index record")?;
            self.inspect(&record[position + 1..])?;
            let metadata: Vec<_> = record[..position]
                .split(|b| b.is_ascii_whitespace())
                .collect();
            let [mode, oid, stage] = metadata.as_slice() else {
                return Err("invalid index record".into());
            };
            if *stage != b"0" {
                return Err("Resolve the unmerged index before committing.".into());
            }
            if *mode != b"160000" {
                objects.push(oid.to_vec());
            }
        }
        self.objects(objects, self.private_content(None).await?)
            .await
    }
    async fn before_push(&self, destination: &str, updates: &[u8]) -> Result<()> {
        let mut tips = Vec::new();
        for line in updates.split(|b| *b == b'\n').filter(|s| !s.is_empty()) {
            let fields: Vec<_> = line
                .split(|b| b.is_ascii_whitespace())
                .filter(|s| !s.is_empty())
                .collect();
            let [local_ref, local_oid, remote_ref, _] = fields.as_slice() else {
                return Err("invalid ref update".into());
            };
            self.inspect(local_ref)?;
            self.inspect(remote_ref)?;
            if local_oid.iter().any(|b| *b != b'0') {
                tips.push(local_oid.to_vec());
            }
        }
        if tips.is_empty() {
            return Ok(());
        }
        let advertised = self
            .git(
                &[
                    "ls-remote",
                    "--refs",
                    "--",
                    destination,
                    "refs/heads/*",
                    "refs/tags/*",
                ],
                None,
            )
            .await?;
        let mut bases = Vec::new();
        for line in advertised.split(|b| *b == b'\n').filter(|s| !s.is_empty()) {
            let base = line
                .split(|b| b.is_ascii_whitespace())
                .next()
                .ok_or("invalid advertised ref")?;
            bases.extend_from_slice(base);
            bases.push(b'\n');
        }
        let known = self
            .git(
                &["cat-file", "--batch-check=%(objectname) %(objecttype)"],
                Some(&bases),
            )
            .await?;
        let mut input = Vec::new();
        for tip in &tips {
            input.extend_from_slice(tip);
            input.push(b'\n');
        }
        for line in known.split(|b| *b == b'\n') {
            let fields: Vec<_> = line
                .split(|b| b.is_ascii_whitespace())
                .filter(|s| !s.is_empty())
                .collect();
            if let [oid, kind] = fields.as_slice()
                && [b"commit".as_slice(), b"tag".as_slice()].contains(kind)
            {
                input.push(b'^');
                input.extend_from_slice(oid);
                input.push(b'\n');
            }
        }
        let objects = self
            .git(
                &["rev-list", "--objects", "--no-object-names", "--stdin"],
                Some(&input),
            )
            .await?;
        tips.extend(
            objects
                .split(|b| *b == b'\n')
                .filter(|s| !s.is_empty())
                .map(<[u8]>::to_vec),
        );
        self.objects(tips, self.private_content(Some(destination)).await?)
            .await
    }
}
async fn run() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let mut git = "git".to_owned();
    let mut gh = "gh".to_owned();
    let mut policy = None;
    let mut hook = None;
    let mut rest = Vec::new();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--git" if hook.is_none() => git = args.next().ok_or("Git missing")?,
            "--gh" if hook.is_none() => gh = args.next().ok_or("gh missing")?,
            "--policy-file" if hook.is_none() => {
                policy = Some(PathBuf::from(args.next().ok_or("policy missing")?))
            }
            "commit-msg" | "pre-push" if hook.is_none() => hook = Some(arg),
            _ if hook.is_some() => rest.push(arg),
            _ => return Err("invalid arguments".into()),
        }
    }
    let guard = Guard::new(git, gh, policy.ok_or("policy required")?)?;
    match hook.as_deref() {
        Some("commit-msg") => {
            guard.before_commit().await?;
            guard.inspect(&fs::read(rest.first().ok_or("message required")?)?)?;
        }
        Some("pre-push") => {
            let mut updates = Vec::new();
            std::io::Read::read_to_end(&mut std::io::stdin(), &mut updates)?;
            guard
                .before_push(rest.get(1).ok_or("destination required")?, &updates)
                .await?;
        }
        _ => return Err("hook required".into()),
    }
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            // Only our fixed privacy diagnostics are public; parser/OS/Git errors
            // may contain protected values and are deliberately replaced.
            let text = error.to_string();
            let safe = [
                BLOCKED,
                "Private email policy must be readable only by its owner.",
                "Privacy check failed; no data was published.",
                "Resolve the unmerged index before committing.",
            ];
            eprintln!(
                "{}",
                if safe.contains(&text.as_str()) {
                    &text
                } else {
                    "Private email protection failed closed."
                }
            );
            std::process::ExitCode::FAILURE
        }
    }
}
