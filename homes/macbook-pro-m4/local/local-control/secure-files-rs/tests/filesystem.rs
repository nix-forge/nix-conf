#![allow(missing_docs)] // Integration-test names describe the executable contract.
#![allow(clippy::expect_used, clippy::items_after_statements)]

use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output, Stdio},
};

use tempfile::TempDir;

fn command() -> Command {
    Command::new(env!("CARGO_BIN_EXE_local-control-secure-files"))
}

fn status(arguments: &[&str]) -> std::process::ExitStatus {
    command()
        .args(arguments)
        .status()
        .expect("command must run")
}

#[test]
fn creates_and_reads_a_private_file_without_following_symlinks() {
    // Resolve the fixture root because macOS /tmp is a compatibility symlink.
    // Production paths remain subject to the helper's no-symlink policy.
    let temporary = TempDir::new().expect("temporary directory");
    let root = fs::canonicalize(temporary.path()).expect("real temporary path");
    let directory = root.join("private");
    let file = directory.join("secret");
    let linked = root.join("linked");

    assert!(status(&["ensure-directory", directory.to_str().expect("UTF-8 path")]).success());
    let mut create = command();
    create
        .args(["create-file", file.to_str().expect("UTF-8 path"), "600"])
        .stdin(std::process::Stdio::piped());
    let mut child = create.spawn().expect("create child");
    child
        .stdin
        .take()
        .expect("child stdin")
        .write_all(b"secret\n")
        .expect("write stdin");
    assert!(child.wait().expect("wait child").success());

    let output = command()
        .args(["read-file", file.to_str().expect("UTF-8 path"), "600"])
        .output()
        .expect("read command");
    assert!(output.status.success());
    assert_eq!(output.stdout, b"secret\n");

    std::os::unix::fs::symlink(&file, &linked).expect("create symlink");
    assert!(!status(&["validate-file", linked.to_str().expect("UTF-8 path"), "600"]).success());
    let rejected_read = command()
        .args(["read-file", linked.to_str().expect("UTF-8 path"), "600"])
        .output()
        .expect("read symlink command");
    assert!(!rejected_read.status.success());
    assert!(rejected_read.stdout.is_empty());
}

#[test]
fn atomically_replaces_a_validated_target() {
    let temporary = TempDir::new().expect("temporary directory");
    let root = fs::canonicalize(temporary.path()).expect("real temporary path");
    let directory = root.join("private");
    let file = directory.join("state");
    fs::create_dir(&directory).expect("private directory");
    fs::set_permissions(&directory, fs::Permissions::from_mode(0o700)).expect("private mode");
    fs::write(&file, "old\n").expect("initial state");
    fs::set_permissions(&file, fs::Permissions::from_mode(0o600)).expect("state mode");

    assert!(atomic_write(&file).status.success());
    assert_eq!(fs::read_to_string(&file).expect("read state"), "new\n");
    assert_eq!(
        fs::metadata(&file)
            .expect("state metadata")
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
}

fn atomic_write(path: &Path) -> Output {
    let mut child = command()
        .args(["atomic-write", path.to_str().expect("UTF-8 path"), "600"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("write child");
    child
        .stdin
        .take()
        .expect("child stdin")
        .write_all(b"new\n")
        .expect("write stdin");
    child.wait_with_output().expect("wait child")
}

#[test]
fn atomic_write_rejects_a_symlink_without_replacing_it_or_its_target() {
    let temporary = TempDir::new().expect("temporary directory");
    let root = fs::canonicalize(temporary.path()).expect("real temporary path");
    fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).expect("private mode");
    let target = root.join("target");
    let link = root.join("link");
    fs::write(&target, "preserved\n").expect("initial target");
    fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).expect("target mode");
    std::os::unix::fs::symlink(&target, &link).expect("create symlink");

    assert!(!atomic_write(&link).status.success());
    assert_eq!(fs::read_link(&link).expect("symlink remains"), target);
    assert_eq!(
        fs::read_to_string(&target).expect("target remains"),
        "preserved\n"
    );
}

#[test]
fn atomic_write_rejects_an_unsafe_mode_without_changing_existing_state() {
    let temporary = TempDir::new().expect("temporary directory");
    let root = fs::canonicalize(temporary.path()).expect("real temporary path");
    fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).expect("private mode");
    let target = root.join("state");
    fs::write(&target, "preserved\n").expect("initial state");
    fs::set_permissions(&target, fs::Permissions::from_mode(0o644)).expect("unsafe mode");

    assert!(!atomic_write(&target).status.success());
    assert_eq!(
        fs::read_to_string(&target).expect("state remains"),
        "preserved\n"
    );
    assert_eq!(
        fs::metadata(&target)
            .expect("state metadata")
            .permissions()
            .mode()
            & 0o777,
        0o644
    );
}
