#![allow(missing_docs)] // Integration-test names describe the executable contract.
#![allow(clippy::expect_used, clippy::items_after_statements)]

use std::{fs, os::unix::fs::PermissionsExt, process::Command};

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
    // `/tmp` is a compatibility symlink to `/private/tmp` on macOS.  The
    // production helper deliberately rejects every symlink component, so the
    // fixture must use the kernel's real path rather than the convenience one.
    let temporary = TempDir::new_in("/private/tmp").expect("temporary directory");
    let directory = temporary.path().join("private");
    let file = directory.join("secret");
    let linked = temporary.path().join("linked");

    assert!(status(&["ensure-directory", directory.to_str().expect("UTF-8 path")]).success());
    let mut create = command();
    create
        .args(["create-file", file.to_str().expect("UTF-8 path"), "600"])
        .stdin(std::process::Stdio::piped());
    let mut child = create.spawn().expect("create child");
    use std::io::Write;
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
}

#[test]
fn atomically_replaces_only_a_validated_target() {
    let temporary = TempDir::new_in("/private/tmp").expect("temporary directory");
    let directory = temporary.path().join("private");
    let file = directory.join("state");
    fs::create_dir(&directory).expect("private directory");
    fs::set_permissions(&directory, fs::Permissions::from_mode(0o700)).expect("private mode");
    fs::write(&file, "old\n").expect("initial state");
    fs::set_permissions(&file, fs::Permissions::from_mode(0o600)).expect("state mode");

    let mut write = command();
    write
        .args(["atomic-write", file.to_str().expect("UTF-8 path"), "600"])
        .stdin(std::process::Stdio::piped());
    let mut child = write.spawn().expect("write child");
    use std::io::Write;
    child
        .stdin
        .take()
        .expect("child stdin")
        .write_all(b"new\n")
        .expect("write stdin");
    assert!(child.wait().expect("wait child").success());
    assert_eq!(fs::read_to_string(&file).expect("read state"), "new\n");
}
