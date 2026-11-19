use crate::{
    policy::{VmPolicy, WindowsCliPolicy, WindowsWizardPolicy},
    *,
};
use std::io::IsTerminal;
pub fn vm(p: &VmPolicy, a: &[String]) -> Result {
    let cmd = a.first().map(String::as_str).unwrap_or("");
    match cmd {
        "list" if a.len() == 1 => exec(
            &p.sudo,
            &["--non-interactive", "--", &p.privileged_control, "list"],
        ),
        "doctor" if a.len() <= 2 => {
            let mut args = vec!["--non-interactive", "--", &p.privileged_control, "doctor"];
            if let Some(g) = a.get(1) {
                args.push(g)
            }
            exec(&p.sudo, &args)
        }
        "status" | "start" | "stop" | "ip" | "console" if a.len() == 2 => exec(
            &p.sudo,
            &["--non-interactive", "--", &p.privileged_control, cmd, &a[1]],
        ),
        "ssh" if a.len() >= 2 => {
            let guests = manifest::guests(&p.guest_manifest)?;
            let guest = guests
                .iter()
                .find(|guest| guest.name == a[1])
                .ok_or_else(|| format!("guest is not allowlisted: {}", a[1]))?;
            let ssh_host = guest
                .ssh_host
                .as_deref()
                .ok_or_else(|| format!("no pinned SSH alias is configured for {}", guest.name))?;
            let mut args = vec![ssh_host];
            args.extend(a[2..].iter().map(String::as_str));
            exec(&p.ssh, &args)
        }
        "gui" if a.len() <= 2 => {
            let mut args = vec!["--connect", "qemu:///system"];
            if let Some(g) = a.get(1) {
                args.extend(["--show-domain-console", g]);
            }
            exec(&p.virt_manager, &args)
        }
        _ => usage("vm list|doctor [guest]|status|start|stop|ip|ssh|console <guest>|gui [guest]"),
    }
}
fn prompt(s: &str, hidden: bool) -> Result<String> {
    print!("{s}");
    io::stdout().flush()?;
    let mut terminal_guard = None;
    let original = if hidden {
        let mut t = rustix::termios::tcgetattr(io::stdin())?;
        let old = t.clone();
        terminal_guard = Some(resources::terminal(old.clone()));
        t.local_modes.remove(rustix::termios::LocalModes::ECHO);
        rustix::termios::tcsetattr(io::stdin(), rustix::termios::OptionalActions::Now, &t)?;
        Some(old)
    } else {
        None
    };
    let mut line = String::new();
    let result = io::stdin().read_line(&mut line);
    if let Some(t) = original {
        rustix::termios::tcsetattr(io::stdin(), rustix::termios::OptionalActions::Now, &t)?;
        println!();
    }
    drop(terminal_guard);
    result?;
    Ok(line.trim_end_matches('\n').to_owned())
}
fn interactive() -> Result {
    ensure(
        io::stdin().is_terminal() && io::stdout().is_terminal(),
        "this command requires an interactive terminal",
    )
}
fn confirm(s: &str) -> Result<bool> {
    Ok(prompt(&format!("  ? {s} [y/N] "), false)?.starts_with(['Y', 'y']))
}
fn privileged(p: &WindowsCliPolicy, cmd: &str) -> Result {
    exec(
        &p.sudo,
        &[
            "--non-interactive",
            "--",
            &p.privileged_control,
            cmd,
            &p.guest_name,
        ],
    )
}
fn existing_iso(p: &WindowsCliPolicy) -> Result<bool> {
    if exists(&p.iso_path) {
        ensure(
            regular(&p.iso_path),
            format!(
                "destination exists but is not a regular file: {}",
                p.iso_path
            ),
        )?;
        crate::windows::verify_hash(&p.sha256sum, &p.iso_sha256, &p.iso_path).map_err(
            |_| "a different ISO already exists; archive it explicitly before replacement",
        )?;
        println!("The verified ISO is already staged at {}.", p.iso_path);
        Ok(true)
    } else {
        Ok(false)
    }
}
fn stage(p: &WindowsCliPolicy, source: &str) -> Result {
    crate::windows::verify_hash(&p.sha256sum, &p.iso_sha256, source)?;
    if existing_iso(p)? {
        return Ok(());
    }
    let parent = Path::new(&p.iso_path).parent().ok_or("ISO has no parent")?;
    let (mut f, _cleanup) = resources::temporary(Some(parent))?;
    // Copy through the owned descriptor: install(1) replaces its inode and
    // would invalidate the identity recorded by cancellation cleanup.
    io::copy(&mut fs::File::open(source)?, f.as_file_mut())?;
    f.as_file()
        .set_permissions(fs::Permissions::from_mode(0o640))?;
    f.as_file().sync_all()?;
    f.persist(&p.iso_path)?;
    atomic(
        &p.iso_sha256_path,
        format!("{}\n", p.iso_sha256).as_bytes(),
        0o640,
    )?;
    println!("Staged and verified {}.", p.iso_path);
    Ok(())
}
fn fetch(p: &WindowsCliPolicy) -> Result {
    if existing_iso(p)? {
        return Ok(());
    }
    let o = command(
        &p.msdl,
        &[
            "--id",
            &p.iso_product_id,
            "--lang",
            &p.iso_language,
            "--no-contribute",
        ],
    )
    .env("MSDL_NO_TELEMETRY", "1")
    .env("MSDL_NO_CONTRIBUTE", "1")
    .stdin(Stdio::null())
    .output()?;
    ensure(
        o.status.success(),
        "Microsoft did not issue a Windows 11 download link",
    )?;
    let text = format!(
        "{}{}",
        String::from_utf8(o.stdout)?,
        String::from_utf8(o.stderr)?
    );
    let file = Path::new(&p.iso_path)
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or("invalid ISO filename")?;
    let urls: Vec<_> = text
        .lines()
        .filter(|s| {
            [
                "https://software.download.prss.microsoft.com/",
                "https://software-static.download.prss.microsoft.com/",
                "https://software-download.microsoft.com/",
            ]
            .iter()
            .any(|prefix| s.starts_with(prefix))
                && s.split('?').next().and_then(|s| s.rsplit('/').next()) == Some(file)
        })
        .collect();
    ensure(
        urls.len() == 1,
        "Microsoft did not return exactly one matching pinned ISO URL; review release and SHA-256 in Nix",
    )?;
    let (f, _cleanup) = resources::temporary(Some(
        Path::new(&p.iso_path).parent().ok_or("ISO has no parent")?,
    ))?;
    let path = f.path().to_str().ok_or("invalid temporary path")?;
    println!("Downloading {file} from Microsoft and checking its SHA-256.");
    run(
        &p.curl,
        &[
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--retry",
            "2",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--output",
            path,
            urls[0],
        ],
    )?;
    crate::windows::verify_hash(&p.sha256sum, &p.iso_sha256, path)?;
    mode(path, 0o640)?;
    f.persist_noclobber(&p.iso_path)
        .map_err(|_| "ISO destination appeared during download; no file was replaced")?;
    atomic(
        &p.iso_sha256_path,
        format!("{}\n", p.iso_sha256).as_bytes(),
        0o640,
    )?;
    println!("Downloaded and verified {}.", p.iso_path);
    Ok(())
}
pub fn windows(p: &WindowsCliPolicy, a: &[String]) -> Result {
    let cmd = a.first().map(String::as_str).unwrap_or("");
    let two = ["stage-iso", "authorize"];
    let one = [
        "setup",
        "fetch-iso",
        "credential",
        "plan",
        "verify-media",
        "install",
        "resume",
        "phase",
        "wait-baseline",
        "baseline",
        "provisioning-log",
        "provisioning-log-previous",
        "host-key",
        "finalize",
        "discard",
    ];
    if !(two.contains(&cmd) && a.len() == 2 || one.contains(&cmd) && a.len() == 1) {
        usage(
            "windows-vm setup|fetch-iso|stage-iso <path>|authorize <key-file>|credential|plan|verify-media|install|resume|phase|wait-baseline|baseline|provisioning-log|provisioning-log-previous|host-key|finalize|discard",
        )
    };
    match cmd {
        "setup" => exec(&p.setup_wizard, &[]),
        "stage-iso" => stage(p, &a[1]),
        "fetch-iso" => fetch(p),
        "authorize" => {
            ensure(
                regular(&a[1]),
                "public key must be a regular file, not a symlink",
            )?;
            output(&p.ssh_keygen, &["-l", "-f", &a[1]])?;
            let response = pipe_controller(
                &p.sudo,
                &[
                    "--non-interactive",
                    "--",
                    &p.privileged_control,
                    "authorize",
                    &p.guest_name,
                ],
                &fs::read(&a[1])?,
            )?;
            println!("{response}");
            Ok(())
        }
        "credential" => credential(&p.sudo, &p.privileged_control, &p.guest_name),
        "discard" => {
            interactive()?;
            println!(
                "This removes only the incomplete {} disk, NVRAM, and TPM state.",
                p.guest_name
            );
            let token = prompt("Type DISCARD-INCOMPLETE-INSTALL to continue: ", false)?;
            ensure(
                token == "DISCARD-INCOMPLETE-INSTALL",
                "confirmation did not match",
            )?;
            exec(
                &p.sudo,
                &[
                    "--non-interactive",
                    "--",
                    &p.privileged_control,
                    "discard",
                    &p.guest_name,
                    &token,
                ],
            )
        }
        _ => privileged(p, cmd),
    }
}
// Credentials stay in this foreground process and reach the controller on stdin.
fn credential(sudo: &str, controller: &str, guest: &str) -> Result {
    interactive()?;
    let first = prompt("Windows administrator password: ", true)?;
    let second = prompt("Confirm password: ", true)?;
    ensure(first == second, "passwords do not match")?;
    let s = pipe_controller(
        sudo,
        &["--non-interactive", "--", controller, "credential", guest],
        format!("{first}\n").as_bytes(),
    )?;
    println!("{s}");
    Ok(())
}
fn run_windows_command(cmd: &str) -> Result {
    run_controller("windows-vm", &[cmd])
}
fn phase() -> Result<String> {
    output("windows-vm", &["phase"])
}
fn stage_header(n: u8, s: &str) {
    if io::stdout().is_terminal() {
        print!("\x1b[2J\x1b[3J\x1b[H")
    }
    println!("\n▸ Stage {n}/6 · {s}\n");
}
fn gui(p: &WindowsWizardPolicy) -> Result {
    let _diagnostic_result = command("vm", &["gui", &p.guest_name]).spawn_detached()?;
    Ok(())
}
pub fn wizard(p: &WindowsWizardPolicy) -> Result {
    println!(
        "\n  Managed Windows VM setup\n  6 stages\n\n  You drive the browser; this wizard tells you exactly what to do and\n  captures the values you copy back. Stop any time with Ctrl-C and re-run\n  later, since it remembers values already saved."
    );
    prompt("Ready to start? ", false)?;
    stage_header(1, "Pinned Windows installation media");
    println!(
        "Fetch {} directly from Microsoft's CDN.\nThe generated link expires after 24 hours, so this command requests a fresh one.\nDeclared ISO: {}; image: {}; SHA-256: {}",
        p.media_description, p.iso_file_name, p.image_name, p.iso_sha256
    );
    run_windows_command("fetch-iso")?;
    stage_header(2, "Administrator SSH keys");
    println!("The VM accepts Ed25519 keys only. Password-based SSH stays disabled.");
    let default = format!("{}/.ssh/libvirt-dev.pub", std::env::var("HOME")?);
    if Path::new(&default).is_file() && confirm(&format!("Authorize {default}?"))? {
        run_controller("windows-vm", &["authorize", &default])?;
    }
    let previous = fs::read_to_string(std::env::var("ENV_FILE").unwrap_or_else(|_| ".env".into()))
        .unwrap_or_default();
    let previous = previous
        .lines()
        .filter_map(|l| l.strip_prefix("ADDITIONAL_KEY="))
        .next_back()
        .unwrap_or("");
    if !previous.is_empty() {
        print!("[Enter keeps current] ");
    }
    let additional = prompt(
        "Optional additional public-key path, or Enter to skip: ",
        false,
    )?;
    let additional = if additional.is_empty() {
        previous
    } else {
        &additional
    };
    if !additional.is_empty() {
        run_controller("windows-vm", &["authorize", additional])?;
    }
    stage_header(3, "Private provisioning overlay");
    println!(
        "Public setup is complete without any workload-specific names or credentials.\nPut optional private files under {}.\nName the private entry point Install.ps1. It receives -AdministratorName and -ManagedRoot.\nThis directory is not encrypted by Nix. Keep secrets in your private manager or encrypted host storage.",
        p.private_directory
    );
    prompt(
        "Press Enter after the private overlay is ready, or continue with an empty directory. ",
        false,
    )?;
    stage_header(4, "Review the immutable plan");
    run_windows_command("plan")?;
    run_windows_command("verify-media")?;
    ensure(
        confirm("Does this fixed-path plan look correct?")?,
        "plan declined",
    )?;
    stage_header(5, "Install Windows");
    println!(
        "The password is written only to /run, embedded in temporary seed media, then deleted at finalization."
    );
    match phase()?.as_str() {
        "uninstalled" => {
            credential(&p.sudo, &p.privileged_control, &p.guest_name)?;
            ensure(
                confirm("Create the new disk and start unattended installation?")?,
                "installation declined",
            )?;
            run_windows_command("install")?;
            gui(p)?;
            println!("Waiting up to 45 minutes for unattended setup and the private hook.");
            run_windows_command("wait-baseline")?;
        }
        "installing-stopped" => {
            println!("Use the same administrator password supplied when this installation began.");
            credential(&p.sudo, &p.privileged_control, &p.guest_name)?;
            ensure(
                confirm("Rebuild the volatile seed and resume the interrupted installation?")?,
                "resume declined",
            )?;
            run_windows_command("resume")?;
            gui(p)?;
            println!("Waiting up to 45 minutes for the resumed setup.");
            run_windows_command("wait-baseline")?;
        }
        "installing-running" => {
            println!(
                "The installer is already running. Waiting up to 45 minutes for its baseline."
            );
            gui(p)?;
            run_windows_command("wait-baseline")?;
        }
        "runtime-running" | "runtime-stopped" => {
            println!("The persistent runtime is already finalized; no installer action is needed.")
        }
        s => return Err(format!("Unknown managed VM phase: {s}").into()),
    }
    stage_header(6, "Verify and finalize");
    match phase()?.as_str() {
        "installing-running" => {
            run_windows_command("baseline")?;
            println!(
                "A PASS result means the public baseline and optional private hook completed."
            );
            ensure(
                confirm("Cold-boot onto the VirtIO disk and finalize the persistent domain?")?,
                "finalization declined",
            )?;
            run_windows_command("finalize")?;
            println!(
                "The finalizer cold-booted the VirtIO runtime disk and verified the guest agent."
            );
        }
        "runtime-running" => {
            run_windows_command("baseline")?;
            println!("The running VM was already finalized and still reports a passing baseline.");
        }
        "runtime-stopped" => println!(
            "The VM was already finalized and is currently stopped. Start it when needed with: vm start {}",
            p.guest_name
        ),
        s => return Err(format!("VM is not ready to finalize; current phase is {s}").into()),
    }
    println!(
        "Run the host validation with: vm doctor {}\nRetrieve the SSH host key through the guest agent with: windows-vm host-key\n\n  ✓ Setup complete",
        p.guest_name
    );
    Ok(())
}
