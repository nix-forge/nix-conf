//! Explicitly owned task checkouts; never infer deletion authority from discovery.
use clap::{Parser, Subcommand};
use fs2::FileExt;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::HashSet,
    env,
    fs::{self, DirBuilder, File, OpenOptions},
    io::{self, Write},
    os::unix::{ffi::OsStrExt, fs::DirBuilderExt},
    path::{Path, PathBuf},
    process::{Command, Output},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn refuse<T>(message: &str) -> Result<T> {
    Err(io::Error::other(message).into())
}
fn text(value: &Value, key: &str) -> Result<String> {
    value[key]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| io::Error::other(format!("Missing string: {key}")).into())
}
fn git(repo: &Path, args: &[&str], check: bool) -> Result<Output> {
    let mut command = Command::new(env::var_os("DEV_WORKTREE_GIT").unwrap_or_else(|| "git".into()));
    command.arg("-C").arg(repo).args(args);
    for (key, _) in env::vars_os() {
        if key.as_bytes().starts_with(b"GIT_") {
            command.env_remove(key);
        }
    }
    let output = command
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_OPTIONAL_LOCKS", "0")
        .output()?;
    if check && !output.status.success() {
        return refuse("Git operation failed");
    }
    Ok(output)
}
fn g(repo: &Path, args: &[&str]) -> Result<String> {
    Ok(String::from_utf8(git(repo, args, true)?.stdout)?)
}
fn s(path: &Path) -> Result<&str> {
    path.to_str()
        .ok_or_else(|| io::Error::other("Path is not UTF-8").into())
}
// Resolve missing tails as pathlib.resolve does, without following discovery symlinks.
fn resolve(path: &Path) -> Result<PathBuf> {
    resolve_inner(path, 0)
}
fn resolve_inner(path: &Path, depth: usize) -> Result<PathBuf> {
    if depth > 40 {
        return refuse("Symlink resolution limit exceeded");
    }
    let absolute = if path.is_absolute() {
        path.to_owned()
    } else {
        env::current_dir()?.join(path)
    };
    let mut resolved = PathBuf::from("/");
    for component in absolute.components() {
        use std::path::Component;
        match component {
            Component::RootDir | Component::CurDir => {}
            Component::ParentDir => {
                resolved.pop();
            }
            Component::Normal(name) => {
                resolved.push(name);
                match fs::symlink_metadata(&resolved) {
                    Ok(metadata) if metadata.is_symlink() => {
                        let target = fs::read_link(&resolved)?;
                        resolved.pop();
                        resolved = resolve_inner(&resolved.join(target), depth + 1)?;
                    }
                    Ok(_) => {}
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error.into()),
                }
            }
            Component::Prefix(_) => return refuse("Unsupported path prefix"),
        }
    }
    Ok(resolved)
}
fn common(repo: &Path) -> Result<PathBuf> {
    resolve(Path::new(
        g(
            repo,
            &["rev-parse", "--path-format=absolute", "--git-common-dir"],
        )?
        .trim(),
    ))
}
fn key(path: &Path) -> String {
    format!("{:x}", Sha256::digest(path.as_os_str().as_bytes()))
}
fn private_dir(path: &Path) -> Result<()> {
    DirBuilder::new().recursive(true).mode(0o700).create(path)?;
    Ok(())
}
fn write_json(path: &Path, value: &Value) -> Result<()> {
    let parent = path.parent().ok_or("Record has no parent")?;
    private_dir(parent)?;
    let mut file = tempfile::Builder::new()
        .prefix(".record-")
        .tempfile_in(parent)?;
    serde_json::to_writer_pretty(&mut file, value)?;
    writeln!(file)?;
    file.flush()?;
    file.as_file().sync_all()?;
    file.persist(path).map_err(|e| e.error)?;
    Ok(())
}
fn lease(state: &Path, name: &str) -> Result<File> {
    let locks = state.join("locks");
    private_dir(&locks)?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(locks.join(name))?;
    file.try_lock_exclusive().map_err(|_| {
        io::Error::other("Another managed operation or session is using this checkout")
    })?;
    Ok(file)
}
fn scan(root: &Path, depth: usize) -> Result<Vec<PathBuf>> {
    if !root.is_dir() || root.is_symlink() {
        return Ok(vec![]);
    }
    if root.join(".git").exists() {
        return Ok(vec![root.to_owned()]);
    }
    if depth == 0 {
        return Ok(vec![]);
    }
    let mut children = fs::read_dir(root)?
        .map(|e| e.map(|e| e.path()))
        .collect::<io::Result<Vec<_>>>()?;
    children.sort();
    let mut result = vec![];
    for child in children {
        if !child
            .file_name()
            .is_some_and(|n| n.as_bytes().starts_with(b"."))
        {
            result.extend(scan(&child, depth - 1)?);
        }
    }
    Ok(result)
}
fn submodules(repo: &Path) -> Result<Vec<PathBuf>> {
    let output = g(repo, &["ls-files", "--stage", "-z"])?;
    let mut result = vec![];
    for entry in output.split('\0').filter(|v| v.starts_with("160000 ")) {
        let (_, name) = entry.split_once('\t').ok_or("Malformed Git index record")?;
        let path = repo.join(name);
        if path.join(".git").exists() {
            result.push(path.clone());
            result.extend(submodules(&path)?);
        }
    }
    Ok(result)
}
fn worktrees(repo: &Path) -> Result<Vec<Value>> {
    let output = g(repo, &["worktree", "list", "--porcelain", "-z"])?;
    let mut result = vec![];
    let mut current = json!({});
    for field in output.split('\0') {
        if field.is_empty() {
            if current.as_object().is_some_and(|m| !m.is_empty()) {
                result.push(current);
                current = json!({});
            }
        } else {
            let (key, value) = field.split_once(' ').unwrap_or((field, ""));
            current[key] = json!(value);
        }
    }
    if let Some(first) = result.first_mut()
        && first["worktree"].as_str() == Some(s(&common(repo)?)?)
    {
        first["worktree"] = json!(g(repo, &["rev-parse", "--show-toplevel"])?.trim());
    }
    Ok(result)
}
fn durable(configuration: &Value) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let manual = resolve(&PathBuf::from(text(configuration, "worktreeRoot")?).join("manual"))?;
    let configured = configuration["repositories"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or(&[])
        .iter()
        .map(|v| {
            v.as_str()
                .map(PathBuf::from)
                .ok_or("Invalid repository path")
        })
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let mut explicit = HashSet::new();
    for repo in &configured {
        if !repo.join(".git").exists() {
            return refuse(&format!(
                "Configured repository is unavailable: {}",
                repo.display()
            ));
        }
        explicit.insert(resolve(repo)?);
    }
    let mut roots = scan(Path::new(&text(configuration, "developerRoot")?), 4)?;
    roots.extend(scan(&manual, 8)?);
    let mut candidates = configured;
    let mut unavailable = vec![];
    for repo in roots {
        match submodules(&repo) {
            Ok(modules) => candidates.extend(modules),
            Err(error) => {
                let path = resolve(&repo)?;
                if repo.join(".git").is_file()
                    && path.starts_with(&manual)
                    && !explicit.contains(&path)
                    && common(&repo).is_err()
                {
                    unavailable.push(path);
                    continue;
                }
                return Err(error);
            }
        }
        if repo.join(".git").is_dir() {
            candidates.push(repo);
        }
    }
    let mut seen = HashSet::new();
    let mut unique = vec![];
    for repo in candidates {
        if repo.join(".git").exists() && seen.insert(common(&repo)?) {
            unique.push(resolve(&repo)?);
        }
    }
    Ok((unique, unavailable))
}
fn identity(repo: &Path) -> Result<PathBuf> {
    let mut remote =
        String::from_utf8(git(repo, &["config", "--get", "remote.origin.url"], false)?.stdout)?
            .trim()
            .to_owned();
    if !remote.contains("://") && regex::Regex::new(r"^[^/]+@[^:]+:")?.is_match(&remote) {
        remote = format!("ssh://{}", remote.replacen(':', "/", 1));
    }
    if let Some((scheme, rest)) = remote.split_once("://") {
        // Preserve raw URL path components: URL normalization must not turn an
        // unsafe forge identity into a different, apparently safe repository.
        let (authority, raw_path) = rest.split_once('/').unwrap_or((rest, ""));
        let host_port = authority.rsplit('@').next().unwrap_or("");
        let host = host_port.split(':').next().unwrap_or("").to_lowercase();
        let path = raw_path.split(['?', '#']).next().unwrap_or("");
        let path = path.strip_suffix(".git").unwrap_or(path).trim_matches('/');
        let parts = std::iter::once(host.as_str())
            .chain(path.split('/'))
            .collect::<Vec<_>>();
        let valid = regex::Regex::new(r"^[a-zA-Z0-9][a-zA-Z0-9._-]*$")?;
        if ["http", "https", "ssh", "git"].contains(&scheme.to_lowercase().as_str())
            && parts.len() >= 3
            && parts.iter().all(|p| valid.is_match(p))
        {
            return Ok(parts.iter().collect());
        }
    }
    Ok(PathBuf::from("local").join(format!(
        "{}-{}",
        repo.file_name()
            .ok_or("Missing repo name")?
            .to_string_lossy(),
        &key(&common(repo)?)[..8]
    )))
}
struct Manager {
    configuration: Value,
    manual: PathBuf,
    state: PathBuf,
}
impl Manager {
    fn new(configuration: Value) -> Result<Self> {
        Ok(Self {
            manual: resolve(Path::new(&text(&configuration, "worktreeRoot")?))?.join("manual"),
            state: resolve(Path::new(&text(&configuration, "stateDirectory")?))?,
            configuration,
        })
    }
    fn record_file(&self, path: &Path) -> PathBuf {
        self.state
            .join("records")
            .join(format!("{}.json", key(path)))
    }
    fn records(&self) -> Result<Vec<Value>> {
        let directory = self.state.join("records");
        if !directory.exists() {
            return Ok(vec![]);
        }
        let mut paths = fs::read_dir(directory)?
            .map(|e| e.map(|e| e.path()))
            .collect::<io::Result<Vec<_>>>()?;
        paths.sort();
        paths
            .into_iter()
            .filter(|p| p.extension().is_some_and(|e| e == "json"))
            .map(|p| Ok(serde_json::from_slice(&fs::read(p)?)?))
            .collect()
    }
    fn owned(&self, path: &Path) -> Result<Value> {
        let record = self.record_file(path);
        if !path.starts_with(&self.manual) || !record.exists() {
            return refuse("Checkout is not registered as manually owned");
        }
        let value: Value = serde_json::from_slice(&fs::read(record)?)?;
        if text(&value, "path")? != s(path)?
            || text(&value, "commonDirectory")? != s(&common(path)?)?
        {
            return refuse("Checkout no longer matches its ownership record");
        }
        Ok(value)
    }
    fn save(&self, path: &Path, repo: &Path, task: &str) -> Result<()> {
        write_json(
            &self.record_file(path),
            &json!({"path":path,"repository":repo,"commonDirectory":common(path)?,"task":task,"owner":"manual","createdHead":g(path,&["rev-parse","HEAD"])?.trim()}),
        )
    }
    fn create(&self, repo: &Path, task: &str, base: &str) -> Result<PathBuf> {
        if !regex::Regex::new(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$")?.is_match(task) {
            return refuse(
                "Task must be a short name containing letters, numbers, underscores, or hyphens",
            );
        }
        if !repo.join(".git").is_dir() {
            return refuse(
                "Create tasks from a main clone; submodule tasks need their own reviewed setup",
            );
        }
        let commit = g(
            repo,
            &["rev-parse", "--verify", &format!("{base}^{{commit}}")],
        )?
        .trim()
        .to_owned();
        let clone = g(repo, &["ls-tree", "-r", "-z", &commit])?
            .split('\0')
            .any(|e| e.starts_with("160000 "));
        let name = format!("{task}-{}", &uuid::Uuid::new_v4().simple().to_string()[..8]);
        let path = self.manual.join(identity(repo)?).join(&name);
        fs::create_dir_all(path.parent().ok_or("Missing parent")?)?;
        if clone {
            g(
                repo,
                &[
                    "clone",
                    "--no-hardlinks",
                    "--no-checkout",
                    "--",
                    s(repo)?,
                    s(&path)?,
                ],
            )?;
            g(
                &path,
                &["checkout", "-b", &format!("codex/{name}"), &commit],
            )?;
            let remote = String::from_utf8(
                git(repo, &["config", "--get", "remote.origin.url"], false)?.stdout,
            )?;
            if !remote.trim().is_empty() {
                g(&path, &["remote", "set-url", "origin", remote.trim()])?;
            }
        } else {
            g(
                repo,
                &[
                    "worktree",
                    "add",
                    "-b",
                    &format!("codex/{name}"),
                    s(&path)?,
                    &commit,
                ],
            )?;
        }
        self.save(&path, repo, task)?;
        Ok(path)
    }
    fn inspect(&self) -> Result<Vec<Value>> {
        let (mut repos, unavailable) = durable(&self.configuration)?;
        for record in self.records()? {
            let repo = PathBuf::from(text(&record, "repository")?);
            if repo.join(".git").exists() {
                let candidate = common(&repo)?;
                let mut found = false;
                for item in &repos {
                    if common(item)? == candidate {
                        found = true;
                        break;
                    }
                }
                if !found {
                    repos.push(repo);
                }
            }
        }
        let mut output: Vec<Value> = unavailable.iter().map(|p| json!({"repository":p,"worktree":p,"exists":p.exists(),"owner":if self.record_file(p).exists(){"manual"}else{"unknown"},"available":false,"diagnostic":"Git discovery unavailable; checkout preserved"})).collect();
        for repo in repos {
            for mut tree in worktrees(&repo)? {
                let path = PathBuf::from(text(&tree, "worktree")?);
                tree["repository"] = json!(repo);
                tree["exists"] = json!(path.exists());
                let manual = self.record_file(&path).exists()
                    || path
                        .ancestors()
                        .skip(1)
                        .any(|p| p.starts_with(&self.manual) && self.record_file(p).exists());
                tree["owner"] = json!(if manual {
                    "manual"
                } else if resolve(&path)? == repo {
                    "canonical"
                } else {
                    "unknown"
                });
                if path.exists() {
                    tree["dirty"] = json!(
                        !g(
                            &path,
                            &[
                                "status",
                                "--porcelain",
                                "--untracked-files=all",
                                "--ignore-submodules=none"
                            ]
                        )?
                        .is_empty()
                    );
                }
                output.push(tree);
            }
        }
        Ok(output)
    }
    fn remove(
        &self,
        path: &Path,
        requested: &str,
        apply: bool,
        completed: bool,
        discard: bool,
    ) -> Result<()> {
        let record = self.owned(path)?;
        if path.join(".git").is_dir() {
            return refuse(
                "Independent clones contain their own branches, stashes, and object storage; use reviewed archival",
            );
        }
        let tree = worktrees(path)?
            .into_iter()
            .find(|t| {
                t["worktree"]
                    .as_str()
                    .and_then(|p| resolve(Path::new(p)).ok())
                    .as_deref()
                    == Some(path)
            })
            .ok_or("Checkout missing from Git inventory")?;
        if tree.get("locked").is_some() {
            return refuse("Worktree is locked; finish its session before removal");
        }
        if !g(
            path,
            &[
                "status",
                "--porcelain",
                "--untracked-files=all",
                "--ignore-submodules=none",
            ],
        )?
        .is_empty()
        {
            return refuse("Checkout contains tracked, untracked, or submodule changes");
        }
        if !discard
            && !g(
                path,
                &[
                    "ls-files",
                    "--others",
                    "--ignored",
                    "--exclude-standard",
                    "-z",
                ],
            )?
            .is_empty()
        {
            return refuse(
                "Checkout contains ignored files; preserve them or explicitly pass --discard-ignored",
            );
        }
        let repo = PathBuf::from(text(&record, "repository")?);
        let references = if requested.is_empty() {
            g(
                &repo,
                &["for-each-ref", "--format=%(refname)", "refs/remotes/"],
            )?
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>()
        } else {
            if !requested.starts_with("refs/") || tree["branch"].as_str() == Some(requested) {
                return refuse("Retained ref must be a named ref other than this task's branch");
            }
            vec![requested.to_owned()]
        };
        let commit = g(path, &["rev-parse", "HEAD"])?;
        let mut retained = false;
        for reference in references {
            if git(
                &repo,
                &["merge-base", "--is-ancestor", commit.trim(), &reference],
                false,
            )?
            .status
            .success()
            {
                retained = true;
                break;
            }
        }
        if !retained {
            return refuse("HEAD is not retained by a ref in the canonical repository");
        }
        if !apply {
            println!("Would remove {}", path.display());
            return Ok(());
        }
        if !completed {
            return refuse(
                "Pass --completed after closing all editors and agent sessions for this checkout",
            );
        }
        g(path, &["worktree", "remove", s(path)?])?;
        fs::remove_file(self.record_file(path))?;
        Ok(())
    }
    fn relocate(&self, path: &Path, apply: bool, completed: bool) -> Result<()> {
        let developer = resolve(Path::new(&text(&self.configuration, "developerRoot")?))?;
        if !path.starts_with(developer) || path.join(".git").is_dir() {
            return refuse("Migration accepts only linked task checkouts under Developer");
        }
        let trees = worktrees(path)?;
        let tree = trees
            .iter()
            .find(|t| {
                t["worktree"]
                    .as_str()
                    .and_then(|p| resolve(Path::new(p)).ok())
                    .as_deref()
                    == Some(path)
            })
            .ok_or("Checkout missing from Git inventory")?;
        if tree.get("locked").is_some() || !submodules(path)?.is_empty() {
            return refuse(
                "Locked worktrees and initialized submodules require separate migration",
            );
        }
        let repo = resolve(Path::new(&text(
            trees.first().ok_or("Empty Git inventory")?,
            "worktree",
        )?))?;
        if repo == path {
            return refuse("Submodule main checkouts cannot be moved as task worktrees");
        }
        let name = path
            .file_name()
            .ok_or("Missing checkout name")?
            .to_string_lossy();
        let destination = self.manual.join(identity(&repo)?).join(format!(
            "{name}-{}",
            &uuid::Uuid::new_v4().simple().to_string()[..8]
        ));
        if !apply {
            println!("{} -> {}", path.display(), destination.display());
            return Ok(());
        }
        if !completed {
            return refuse(
                "Pass --completed after closing editors and agent sessions before moving",
            );
        }
        fs::create_dir_all(destination.parent().ok_or("Missing parent")?)?;
        g(&repo, &["worktree", "move", s(path)?, s(&destination)?])?;
        self.save(&destination, &repo, &name)
    }
    fn maintain(&self, schedule: &str) -> Result<i32> {
        let (repos, unavailable) = durable(&self.configuration)?;
        for path in unavailable {
            eprintln!(
                "Skipping unavailable discovered worktree: {}",
                path.display()
            );
        }
        let mut failed = 0;
        for repo in repos {
            if !git(
                &repo,
                &[
                    "-c",
                    "maintenance.strategy=incremental",
                    "-c",
                    "maintenance.prefetch.enabled=false",
                    "maintenance",
                    "run",
                    &format!("--schedule={schedule}"),
                ],
                false,
            )?
            .status
            .success()
            {
                eprintln!("Maintenance failed for {}", repo.display());
                failed = 1;
            }
        }
        Ok(failed)
    }
}
#[derive(Parser)]
#[command(about = "Manage explicitly owned task checkouts and maintain durable Git repositories.")]
struct Args {
    #[arg(long, default_value_os_t=default_config())]
    config: PathBuf,
    #[command(subcommand)]
    command: Operation,
}
fn default_config() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".config"))
        .join("dev-worktree/config.json")
}
#[derive(Subcommand)]
enum Operation {
    New {
        repository: PathBuf,
        task: String,
        #[arg(long)]
        base: String,
    },
    List,
    Doctor,
    Report,
    Move {
        path: PathBuf,
        #[arg(long)]
        apply: bool,
        #[arg(long)]
        completed: bool,
    },
    Remove {
        path: PathBuf,
        #[arg(long, default_value = "")]
        retained_ref: String,
        #[arg(long)]
        apply: bool,
        #[arg(long)]
        completed: bool,
        #[arg(long)]
        discard_ignored: bool,
    },
    Run {
        path: PathBuf,
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        arguments: Vec<std::ffi::OsString>,
    },
    Maintain {
        #[arg(long,value_parser=["hourly","daily","weekly"])]
        schedule: String,
    },
}
fn session(manager: &Manager, path: &Path, arguments: &[std::ffi::OsString]) -> Result<i32> {
    manager.owned(path)?;
    let arguments = if arguments.first().is_some_and(|s| s == "--") {
        &arguments[1..]
    } else {
        arguments
    };
    if arguments.is_empty() {
        return refuse("Supply a command after --");
    }
    let _lease = lease(&manager.state, &key(path))?;
    let linked = !path.join(".git").is_dir();
    // Subscribe before spawn. Forward parent-directed cancellation; wait before unlocking.
    let mut signals = signal_hook::iterator::Signals::new([
        signal_hook::consts::SIGINT,
        signal_hook::consts::SIGTERM,
        signal_hook::consts::SIGHUP,
    ])?;
    let handle = signals.handle();
    if linked {
        g(
            path,
            &[
                "worktree",
                "lock",
                "--reason",
                "dev-worktree managed session",
                s(path)?,
            ],
        )?;
    }
    let result = (|| -> Result<i32> {
        let mut child = Command::new(&arguments[0])
            .args(&arguments[1..])
            .current_dir(path)
            .spawn()?;
        let pid = rustix::process::Pid::from_raw(child.id() as i32).ok_or("Invalid child PID")?;
        let forward = std::thread::spawn(move || {
            for signal in signals.forever() {
                if let Some(signal) = rustix::process::Signal::from_named_raw(signal) {
                    let _signal_result = rustix::process::kill_process(pid, signal);
                }
            }
        });
        let result = child.wait();
        handle.close();
        let _forward_result = forward.join();
        use std::os::unix::process::ExitStatusExt;
        let status = result?;
        Ok(status
            .code()
            .unwrap_or_else(|| -status.signal().unwrap_or(1)))
    })();
    handle.close();
    if linked {
        g(path, &["worktree", "unlock", s(path)?])?;
    }
    result
}
fn execute(args: Args) -> Result<i32> {
    let manager = Manager::new(serde_json::from_slice(&fs::read(args.config)?)?)?;
    match args.command {
        Operation::List | Operation::Doctor => {
            println!("{}", serde_json::to_string_pretty(&manager.inspect()?)?)
        }
        Operation::Report => {
            let inventory = Value::Array(manager.inspect()?);
            write_json(&manager.state.join("inventory.json"), &inventory)?;
        }
        Operation::Maintain { schedule } => {
            let _lease = lease(&manager.state, "maintenance")?;
            return manager.maintain(&schedule);
        }
        Operation::Run { path, arguments } => {
            return session(&manager, &resolve(&path)?, &arguments);
        }
        operation => {
            let _mutation = lease(&manager.state, "mutation")?;
            match operation {
                Operation::New {
                    repository,
                    task,
                    base,
                } => println!(
                    "{}",
                    manager
                        .create(&resolve(&repository)?, &task, &base)?
                        .display()
                ),
                Operation::Move {
                    path,
                    apply,
                    completed,
                } => {
                    let path = resolve(&path)?;
                    let _lease = lease(&manager.state, &key(&path))?;
                    manager.relocate(&path, apply, completed)?;
                }
                Operation::Remove {
                    path,
                    retained_ref,
                    apply,
                    completed,
                    discard_ignored,
                } => {
                    let path = resolve(&path)?;
                    let _lease = lease(&manager.state, &key(&path))?;
                    manager.remove(&path, &retained_ref, apply, completed, discard_ignored)?;
                }
                _ => return refuse("Invalid operation"),
            }
        }
    }
    Ok(0)
}
fn main() {
    let code = match execute(Args::parse()) {
        Ok(code) => code,
        Err(error) => {
            eprintln!("dev-worktree: {error}");
            1
        }
    };
    std::process::exit(code);
}
