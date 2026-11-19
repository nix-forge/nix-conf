use crate::{
    policy::{Virsh, WindowsControlPolicy, WindowsReconcilePolicy},
    *,
};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};
use std::time::{Duration, Instant};
fn identity(
    connection: &Virsh<'_>,
    guest_name: &str,
    guest_uuid: &str,
    disk_path: &str,
    xml_helper: &str,
) -> Result {
    if !connection.domain(guest_name) {
        return Ok(());
    }
    let id = connection.query(&["domuuid", guest_name])?;
    ensure(
        id == guest_uuid,
        format!("{guest_name} has UUID {id}, expected {guest_uuid}; refusing to claim it"),
    )?;
    let xml = connection.query(&["dumpxml", guest_name, "--inactive"])?;
    let disk = pipe(xml_helper, &["disk-source", "sda"], xml.as_bytes())?;
    ensure(
        disk.is_empty() || disk == disk_path,
        format!("{guest_name} uses unexpected system disk {disk}"),
    )
}
pub fn reconcile(p: &WindowsReconcilePolicy) -> Result {
    if p.connection().domain(&p.guest_name) {
        identity(
            &p.connection(),
            &p.guest_name,
            &p.guest_uuid,
            &p.disk_path,
            &p.xml_helper,
        )?;
        if exists(&p.install_marker) {
            p.connection().autostart(&p.guest_name, false)?;
            println!(
                "Leaving {} in its explicit installation state.",
                p.guest_name
            );
        } else {
            p.connection()
                .query(&["define", &p.runtime_definition, "--validate"])?;
            if p.connection().active(&p.guest_name) {
                println!(
                    "Staged the persistent definition for {}; hardware changes apply after shutdown and start.",
                    p.guest_name
                );
            }
        }
    } else {
        ensure(
            !exists(&p.install_marker),
            "installation marker exists but domain is missing",
        )?;
        p.connection()
            .query(&["define", &p.runtime_definition, "--validate"])?;
    }
    if !exists(&p.install_marker) {
        p.connection().autostart(&p.guest_name, p.autostart)?;
    }
    Ok(())
}
fn inactive(p: &WindowsControlPolicy) -> Result {
    ensure(
        !p.connection().active(&p.guest_name),
        format!(
            "{} is running; request a graceful shutdown and retry",
            p.guest_name
        ),
    )
}
fn hash(sha256sum: &str, path: &str) -> Result<String> {
    ensure(
        regular(path),
        format!("file is missing or is a symlink: {path}"),
    )?;
    let s = output(sha256sum, &[path])?;
    Ok(s.split_whitespace()
        .next()
        .ok_or("missing hash")?
        .to_lowercase())
}
pub fn verify_hash(sha256sum: &str, expected: &str, path: &str) -> Result {
    ensure(
        expected.len() == 64
            && expected
                .bytes()
                .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)),
        "Windows ISO SHA-256 declared in Nix is invalid",
    )?;
    let h = hash(sha256sum, path)?;
    ensure(
        h == expected,
        format!("ISO hash is {h}, expected {expected}"),
    )
}
fn inspect_command(p: &WindowsControlPolicy, args: &[&str]) -> Command {
    let mut c = command(&p.setpriv, &[]);
    c.args([
        format!("--reuid={}", p.media_inspector_user),
        format!("--regid={}", p.media_inspector_group),
    ])
    .args([
        "--init-groups",
        "--inh-caps=-all",
        "--reset-env",
        "--",
        &p.env,
    ])
    .arg(format!("--chdir={}", p.media_inspection_directory))
    .args(["PATH=/run/wrappers/bin", "LC_ALL=C"])
    .args(args);
    c
}
fn verify_media(p: &WindowsControlPolicy) -> Result {
    verify_hash(&p.sha256sum, &p.iso_sha256, &p.iso_path)?;
    println!("PASS  Windows ISO matches SHA-256 {}", p.iso_sha256);
    fs::create_dir_all(&p.media_inspection_directory)?;
    let (f, _cleanup) = resources::temporary(Some(Path::new(&p.media_inspection_directory)))?;
    let path = f.path().to_str().ok_or("invalid temporary path")?;
    run(
        &p.chown,
        &[
            &format!("{}:{}", p.media_inspector_user, p.media_inspector_group),
            path,
        ],
    )?;
    let mut image = "sources/install.wim";
    for candidate in ["sources/install.wim", "sources/install.esd"] {
        image = candidate;
        let file = fs::OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(path)?;
        let status = inspect_command(
            p,
            &[&p.seven_zip, "e", "-so", "-tudf", &p.iso_path, candidate],
        )
        .stdout(file)
        .status()?;
        ensure(
            status.success(),
            "could not inspect verified Windows ISO as UDF",
        )?;
        if fs::metadata(path)?.len() > 0 {
            break;
        }
    }
    ensure(
        fs::metadata(path)?.len() > 0,
        "Windows ISO has no sources/install.wim or sources/install.esd",
    )?;
    if !inspect_command(p, &[&p.wiminfo, path, &p.image_name])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?
        .success()
    {
        eprintln!(
            "configured Windows image is absent: {}\nImages available in {image}:",
            p.image_name
        );
        let _diagnostic_result = inspect_command(p, &[&p.wiminfo, path])
            .stdout(Stdio::inherit())
            .status();
        return Err("stage released production media containing the configured image".into());
    }
    f.close()?;
    println!("PASS  Windows ISO contains image {}", p.image_name);
    ensure(regular(&p.virtio_iso), "pinned VirtIO ISO is missing")?;
    ensure(
        regular(&p.autologon_archive),
        "pinned Autologon archive is missing",
    )?;
    println!("PASS  pinned VirtIO and Sysinternals media are present");
    Ok(())
}
fn credential(p: &WindowsControlPolicy) -> Result {
    let s = one_line()?;
    let b = s.as_bytes();
    ensure(
        b.len() >= 16,
        "password must contain at least 16 characters",
    )?;
    ensure(
        b.iter().all(|c| c.is_ascii_graphic()),
        "password must contain printable ASCII characters only and no whitespace",
    )?;
    ensure(
        b[0].is_ascii_alphanumeric(),
        "password must begin with a letter or digit to avoid native CLI option ambiguity",
    )?;
    let n = [
        b.iter().any(u8::is_ascii_lowercase),
        b.iter().any(u8::is_ascii_uppercase),
        b.iter().any(u8::is_ascii_digit),
        b.iter().any(|c| !c.is_ascii_alphanumeric()),
    ]
    .into_iter()
    .filter(|b| *b)
    .count();
    ensure(
        n >= 3,
        "password must use at least three character categories",
    )?;
    fs::create_dir_all(&p.runtime_directory)?;
    atomic(&p.password_file, format!("{s}\n").as_bytes(), 0o400)?;
    run(&p.chown, &["root:root", &p.password_file])?;
    println!("Stored the temporary installer credential in volatile memory.");
    Ok(())
}
fn authorize(p: &WindowsControlPolicy) -> Result {
    let s = one_line()?;
    ensure(
        s.starts_with("ssh-ed25519 ") || s.starts_with("sk-ssh-ed25519@openssh.com "),
        "only an Ed25519 OpenSSH public key without authorized_keys options is accepted",
    )?;
    fs::create_dir_all(&p.state_directory)?;
    let (mut f, _cleanup) = resources::temporary(Some(Path::new(&p.state_directory)))?;
    writeln!(f, "{s}")?;
    output(
        &p.ssh_keygen,
        &[
            "-l",
            "-f",
            f.path().to_str().ok_or("invalid temporary path")?,
        ],
    )?;
    let mut existing = if Path::new(&p.authorized_keys_file).is_file() {
        fs::read_to_string(&p.authorized_keys_file)?
    } else {
        String::new()
    };
    if existing.lines().any(|l| l == s) {
        println!("Public key is already authorized.");
        return Ok(());
    }
    existing.push_str(&format!("{s}\n"));
    atomic(&p.authorized_keys_file, existing.as_bytes(), 0o600)?;
    run(&p.chown, &["root:root", &p.authorized_keys_file])?;
    println!("Authorized the Ed25519 key for the Windows administrator.");
    Ok(())
}
fn validate_tree(path: &Path, dev: u64) -> Result {
    use std::os::unix::fs::MetadataExt;
    let m = fs::symlink_metadata(path)?;
    ensure(
        m.is_file() || m.is_dir(),
        format!(
            "private provisioning contains a symlink or unsupported file type: {}",
            path.display()
        ),
    )?;
    if m.is_dir() && m.dev() == dev {
        for e in fs::read_dir(path)? {
            validate_tree(&e?.path(), dev)?;
        }
    }
    Ok(())
}
fn seed(p: &WindowsControlPolicy) -> Result {
    use std::os::unix::fs::MetadataExt;
    ensure(
        regular(&p.password_file),
        "temporary installer credential is absent; run windows-vm credential",
    )?;
    ensure(
        regular(&p.authorized_keys_file),
        "no SSH public key is staged; run windows-vm authorize",
    )?;
    let m = fs::symlink_metadata(&p.private_directory)?;
    ensure(
        m.is_dir(),
        "private provisioning directory is missing or is a symlink",
    )?;
    validate_tree(Path::new(&p.private_directory), m.dev())?;
    let tree = format!("{}/seed", p.runtime_directory);
    run(&p.rm, &["-rf", "--one-file-system", "--", &tree])?;
    let base = format!("{tree}/managed-vm-seed");
    fs::create_dir_all(format!("{base}/private"))?;
    for (src, dst) in [
        (&p.bootstrap_script, "Bootstrap.ps1"),
        (&p.baseline_test, "Test-Baseline.ps1"),
        (&p.authorized_keys_file, "authorized_keys"),
        (&p.autologon_archive, "AutoLogon.zip"),
    ] {
        run(&p.install, &["-m", "0600", src, &format!("{base}/{dst}")])?;
    }
    run(
        &p.cp,
        &[
            "-a",
            "--",
            &format!("{}/.", p.private_directory),
            &format!("{base}/private/"),
        ],
    )?;
    run(
        &p.seed_renderer,
        &[
            "--template",
            &p.answer_template,
            "--answer-file",
            &format!("{tree}/Autounattend.xml"),
            "--credential-file",
            &format!("{base}/administrator-password.txt"),
            "--password-file",
            &p.password_file,
        ],
    )?;
    run(
        &p.xorriso,
        &[
            "-as",
            "mkisofs",
            "-quiet",
            "-iso-level",
            "4",
            "-J",
            "-R",
            "-V",
            "MANAGEDVM",
            "-o",
            &p.seed_iso,
            &tree,
        ],
    )?;
    run(&p.chown, &[&format!("root:{}", p.qemu_group), &p.seed_iso])?;
    mode(&p.seed_iso, 0o640)?;
    run(&p.rm, &["-f", "--", &p.prime_disk])?;
    run(
        &p.qemu_img,
        &["create", "-q", "-f", "raw", &p.prime_disk, "64M"],
    )?;
    run(
        &p.chown,
        &[&format!("{}:{}", p.qemu_user, p.qemu_group), &p.prime_disk],
    )?;
    mode(&p.prime_disk, 0o600)
}
fn marker(p: &WindowsControlPolicy) -> String {
    format!(
        "schema=managed-windows-vm-install-v1\nuuid={}\ndisk={}\nfingerprint={}\n",
        p.guest_uuid, p.disk_path, p.recipe_fingerprint
    )
}
fn verify_marker(p: &WindowsControlPolicy) -> Result {
    ensure(
        regular(&p.install_marker),
        "there is no resumable installation",
    )?;
    let text = fs::read_to_string(&p.install_marker)?;
    for field in marker(p).lines() {
        ensure(
            text.lines().any(|l| l == field),
            "incomplete installation belongs to a different schema, guest, disk or public recipe; restore that configuration or discard it explicitly",
        )?;
    }
    Ok(())
}
fn disk(p: &WindowsControlPolicy) -> Result {
    ensure(
        regular(&p.disk_path),
        "system disk is missing or is a symlink",
    )?;
    let data: Value = serde_json::from_str(&output(
        &p.qemu_img,
        &["info", "--output=json", &p.disk_path],
    )?)?;
    ensure(
        data["format"] == "qcow2",
        "system disk format must be qcow2",
    )?;
    let expected = p
        .disk_size_gi_b
        .checked_mul(1024 * 1024 * 1024)
        .ok_or("disk size overflow")?;
    ensure(
        data["virtual-size"].as_u64() == Some(expected),
        "system disk has unexpected virtual size",
    )?;
    ensure(
        data.get("backing-filename")
            .is_none_or(|v| v.is_null() || v.as_str() == Some("")),
        "system disk has an unexpected backing file",
    )
}
struct Candidate {
    path: String,
    _cleanup: resources::Guard,
}
fn start(p: &WindowsControlPolicy, fresh: bool) -> Result {
    run(
        &p.xml_helper,
        &[
            "installer-topology",
            &p.installer_definition,
            &p.disk_path,
            &p.disk_serial,
            &p.prime_disk,
        ],
    )?;
    verify_media(p)?;
    inactive(p)?;
    identity(
        &p.connection(),
        &p.guest_name,
        &p.guest_uuid,
        &p.disk_path,
        &p.xml_helper,
    )?;
    if fresh {
        ensure(
            !exists(&p.install_marker),
            "an installation is already in progress; use resume",
        )?;
        ensure(
            !exists(&p.disk_path),
            "system disk already exists; this installer never overwrites it",
        )?;
        let path = format!("{}.installing", p.disk_path);
        let candidate = Candidate {
            _cleanup: resources::candidate(&path),
            path,
        };
        if exists(&candidate.path) {
            ensure(
                regular(&candidate.path),
                "stale candidate disk is not a regular file",
            )?;
            fs::remove_file(&candidate.path)?;
        }
        run(
            &p.qemu_img,
            &[
                "create",
                "-q",
                "-f",
                "qcow2",
                "-o",
                "cluster_size=2M,lazy_refcounts=on,preallocation=metadata",
                &candidate.path,
                &format!("{}G", p.disk_size_gi_b),
            ],
        )?;
        run(
            &p.chown,
            &[
                &format!("{}:{}", p.qemu_user, p.qemu_group),
                &candidate.path,
            ],
        )?;
        mode(&candidate.path, 0o600)?;
        run(
            &p.mv,
            &["--no-clobber", "--", &candidate.path, &p.disk_path],
        )?;
        ensure(
            !exists(&candidate.path) && regular(&p.disk_path),
            "could not atomically install the new system disk",
        )?;
        atomic(&p.install_marker, marker(p).as_bytes(), 0o600)?;
        run(&p.chown, &["root:root", &p.install_marker])?;
    } else {
        verify_marker(p)?;
        ensure(
            regular(&p.disk_path),
            "installation disk is missing or is a symlink",
        )?;
    }
    disk(p)?;
    seed(p)?;
    p.connection()
        .query(&["define", &p.installer_definition, "--validate"])?;
    p.connection().autostart(&p.guest_name, false)?;
    p.connection().run(&["start", &p.guest_name])?;
    if fresh {
        // DVD prompt accepts no readiness notification; send six bounded key presses.
        for _ in 0..6 {
            std::thread::sleep(Duration::from_secs(2));
            ensure(
                p.connection().active(&p.guest_name),
                "Windows installer stopped during boot",
            )?;
            p.connection()
                .query(&["send-key", &p.guest_name, "KEY_SPACE"])?;
        }
    }
    println!(
        "Windows installation started. Keep the host running until baseline status reports PASS."
    );
    Ok(())
}
fn agent(p: &WindowsControlPolicy, value: Value) -> Result<Value> {
    let text = p.connection().query(&[
        "qemu-agent-command",
        &p.guest_name,
        "--timeout",
        "10",
        &value.to_string(),
    ])?;
    let result: Value = serde_json::from_str(&text)?;
    ensure(
        result.get("error").is_none(),
        "QEMU guest agent request failed",
    )?;
    Ok(result["return"].clone())
}
fn guest_file(p: &WindowsControlPolicy, name: &str) -> Result<String> {
    ensure(
        p.connection().active(&p.guest_name),
        "guest must be running to read guest status",
    )?;
    let handle = agent(
        p,
        json!({"execute":"guest-file-open","arguments":{"path":format!("C:\\ProgramData\\ManagedVm\\{name}"),"mode":"r"}}),
    )?;
    ensure(
        handle.is_number(),
        "guest agent did not open requested file",
    )?;
    let data = agent(
        p,
        json!({"execute":"guest-file-read","arguments":{"handle":handle,"count":65536}}),
    );
    let _close_result = agent(
        p,
        json!({"execute":"guest-file-close","arguments":{"handle":handle}}),
    );
    let data = data?;
    let encoded = data["buf-b64"]
        .as_str()
        .ok_or("guest agent did not return file content")?;
    Ok(String::from_utf8(STANDARD.decode(encoded)?)?)
}
fn baseline(p: &WindowsControlPolicy) -> Result<String> {
    Ok(guest_file(p, "baseline-status.txt")?
        .replace('\r', "")
        .trim_end_matches('\n')
        .into())
}
fn current(p: &WindowsControlPolicy, s: &str) -> Result {
    ensure(
        s.lines()
            .any(|l| l == format!("fingerprint={}", p.recipe_fingerprint)),
        format!(
            "Windows reports a stale baseline; expected recipe {}",
            p.recipe_fingerprint
        ),
    )
}
fn wait(p: &WindowsControlPolicy, seconds: u64) -> Result {
    let deadline = Instant::now() + Duration::from_secs(seconds);
    let mut inactive_since = None;
    loop {
        if p.connection().active(&p.guest_name) {
            inactive_since = None;
        } else {
            let since = inactive_since.get_or_insert_with(Instant::now);
            ensure(
                since.elapsed() < Duration::from_secs(60),
                "Windows stopped for at least 60 seconds before its baseline passed; inspect installer console and resume",
            )?;
        }
        if let Ok(s) = baseline(p) {
            if s.lines().any(|l| l == "state=PASS") {
                current(p, &s)?;
                println!("{s}");
                return Ok(());
            }
            if s.lines().any(|l| l == "state=FAIL") {
                eprintln!("{s}");
                return Err("Windows baseline failed".into());
            }
        }
        ensure(
            Instant::now() < deadline,
            format!("Windows baseline did not pass within {seconds} seconds"),
        )?;
        // The provisioning status file exposes no host notification. Safe guest-agent reads
        // use positive backoff and one deadline; native shutdown uses the existing event bridge.
        std::thread::sleep(
            Duration::from_secs(5).min(deadline.saturating_duration_since(Instant::now())),
        );
    }
}
fn clear_seed(p: &WindowsControlPolicy) -> Result {
    run(
        &p.rm,
        &[
            "-rf",
            "--one-file-system",
            "--",
            &format!("{}/seed", p.runtime_directory),
        ],
    )?;
    run(
        &p.rm,
        &["-f", "--", &p.seed_iso, &p.prime_disk, &p.password_file],
    )
}
fn finalize(p: &WindowsControlPolicy) -> Result {
    ensure(
        regular(&p.install_marker),
        "there is no installation to finalize",
    )?;
    ensure(
        regular(&p.disk_path),
        "installation disk is missing or is a symlink",
    )?;
    let s = baseline(p)?;
    ensure(
        s.lines().any(|l| l == "state=PASS"),
        "Windows baseline has not reported PASS",
    )?;
    current(p, &s)?;
    run(
        &p.shutdown_guest,
        &[&p.libvirt_uri, &p.guest_name, "--timeout", "300"],
    )?;
    p.connection()
        .query(&["define", &p.runtime_definition, "--validate"])?;
    p.connection().autostart(&p.guest_name, p.autostart)?;
    ensure(
        p.runtime_directory.starts_with("/run/libvirt-workstation/"),
        "internal runtime path invariant failed",
    )?;
    clear_seed(p)?;
    p.connection().query(&["start", &p.guest_name]).map_err(
        |_| "VirtIO runtime definition did not start; installation marker retained for recovery",
    )?;
    wait(p,600).map_err(|_|"Windows did not return healthy through guest agent; installation marker retained for recovery")?;
    fs::remove_file(&p.install_marker)?;
    println!(
        "Installation finalized. Windows cold-booted from the VirtIO system disk and returned through the guest agent."
    );
    Ok(())
}
fn discard(p: &WindowsControlPolicy, token: &str) -> Result {
    ensure(
        token == "DISCARD-INCOMPLETE-INSTALL",
        "discard confirmation token is missing",
    )?;
    ensure(
        regular(&p.install_marker),
        "there is no incomplete installation to discard",
    )?;
    inactive(p)?;
    identity(
        &p.connection(),
        &p.guest_name,
        &p.guest_uuid,
        &p.disk_path,
        &p.xml_helper,
    )?;
    if p.connection().domain(&p.guest_name) {
        p.connection()
            .query(&["undefine", &p.guest_name, "--nvram", "--tpm"])?;
    }
    ensure(
        p.disk_path.starts_with(&format!("{}/", p.storage_root)),
        "internal disk path invariant failed",
    )?;
    run(
        &p.rm,
        &[
            "-f",
            "--",
            &p.disk_path,
            &format!("{}.installing", p.disk_path),
            &p.prime_disk,
            &p.seed_iso,
            &p.password_file,
            &p.install_marker,
        ],
    )?;
    run(
        &p.rm,
        &[
            "-rf",
            "--one-file-system",
            "--",
            &format!("{}/seed", p.runtime_directory),
        ],
    )?;
    p.connection()
        .query(&["define", &p.runtime_definition, "--validate"])?;
    p.connection().autostart(&p.guest_name, false)?;
    println!("Discarded the incomplete Windows installation and its firmware and TPM state.");
    Ok(())
}
fn phase(p: &WindowsControlPolicy) -> Result {
    identity(
        &p.connection(),
        &p.guest_name,
        &p.guest_uuid,
        &p.disk_path,
        &p.xml_helper,
    )?;
    let state = if exists(&p.install_marker) {
        ensure(
            regular(&p.install_marker),
            "installation marker is not a regular file",
        )?;
        "installing"
    } else if exists(&p.disk_path) {
        ensure(regular(&p.disk_path), "system disk is not a regular file")?;
        "runtime"
    } else {
        println!("uninstalled");
        return Ok(());
    };
    println!(
        "{state}-{}",
        if p.connection().active(&p.guest_name) {
            "running"
        } else {
            "stopped"
        }
    );
    Ok(())
}
fn plan(p: &WindowsControlPolicy) -> Result {
    identity(
        &p.connection(),
        &p.guest_name,
        &p.guest_uuid,
        &p.disk_path,
        &p.xml_helper,
    )?;
    let present = |s: &str| {
        if Path::new(s).is_file() {
            "present"
        } else {
            "missing"
        }
    };
    println!(
        "Guest:                 {}\nUUID:                  {}\nDomain:                {}\nSystem disk:           {} ({}, {} GiB maximum)\nInstall marker:        {}\nWindows ISO:           {} ({})\nWindows source:        {}\nWindows release:       {}\nWindows image:         {}\nWindows ISO SHA-256:   {}\nPublic recipe SHA-256: {}\nTemporary credential: {}\nAuthorized keys:       {}\nPrivate hook:          {} ({}/Install.ps1)\nAutostart after setup: {}\n\nThe fresh installer refuses to run if the system disk already exists.",
        p.guest_name,
        p.guest_uuid,
        if p.connection().domain(&p.guest_name) {
            p.connection().query(&["domstate", &p.guest_name])?
        } else {
            "missing".into()
        },
        present(&p.disk_path),
        p.disk_path,
        p.disk_size_gi_b,
        if Path::new(&p.install_marker).is_file() {
            "present"
        } else {
            "absent"
        },
        present(&p.iso_path),
        p.iso_path,
        p.download_page,
        p.release,
        p.image_name,
        p.iso_sha256,
        p.recipe_fingerprint,
        if Path::new(&p.password_file).is_file() {
            "present in tmpfs"
        } else {
            "absent"
        },
        p.authorized_keys_file,
        if Path::new(&format!("{}/Install.ps1", p.private_directory)).is_file() {
            "present"
        } else {
            "absent"
        },
        p.private_directory,
        u8::from(p.autostart)
    );
    Ok(())
}
pub fn control(p: &WindowsControlPolicy, a: &[String]) -> Result {
    let cmd = a.first().map(String::as_str).unwrap_or("");
    let commands = [
        "credential",
        "authorize",
        "plan",
        "verify-media",
        "install",
        "resume",
        "phase",
        "wait-baseline",
        "finalize",
        "discard",
        "baseline",
        "provisioning-log",
        "provisioning-log-previous",
        "host-key",
    ];
    if !commands.contains(&cmd) || a.len() != if cmd == "discard" { 3 } else { 2 } {
        usage("libvirt-windows-vm-control <command> <guest> [DISCARD-INCOMPLETE-INSTALL]")
    };
    ensure(
        a[1] == p.guest_name,
        format!("guest is not managed Windows VM: {}", a[1]),
    )?;
    match cmd {
        "credential" => credential(p),
        "authorize" => authorize(p),
        "plan" => plan(p),
        "verify-media" => verify_media(p),
        "install" => start(p, true),
        "resume" => start(p, false),
        "phase" => phase(p),
        "wait-baseline" => wait(p, 2700),
        "finalize" => finalize(p),
        "discard" => discard(p, &a[2]),
        "baseline" => {
            let s = baseline(p)?;
            println!("{s}");
            current(p, &s)
        }
        _ => {
            let name = match cmd {
                "provisioning-log" => "provisioning-steps.jsonl",
                "provisioning-log-previous" => "provisioning-steps.previous.jsonl",
                _ => "ssh-host-ed25519-key.pub",
            };
            print!("{}", guest_file(p, name)?);
            Ok(())
        }
    }
}
