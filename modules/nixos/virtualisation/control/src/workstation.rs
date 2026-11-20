use crate::{
    policy::{ProfileGuardPolicy, SetupPolicy, SleepHookPolicy, WorkstationControlPolicy},
    *,
};
use std::collections::{BTreeMap, BTreeSet};
fn field(s: &str, key: &str, value: &str) -> bool {
    s.lines().any(|l| {
        l.split_once(':')
            .is_some_and(|(k, v)| k == key && v.trim() == value)
    })
}
fn link_name(path: impl AsRef<Path>) -> String {
    fs::canonicalize(path)
        .ok()
        .and_then(|p| p.file_name().map(|s| s.to_string_lossy().into_owned()))
        .unwrap_or_else(|| "unbound".into())
}
fn uuid(s: &str) -> bool {
    s.len() == 36
        && s.bytes().enumerate().all(|(i, c)| {
            if [8, 13, 18, 23].contains(&i) {
                c == b'-'
            } else {
                c.is_ascii_hexdigit()
            }
        })
}
pub fn setup(p: &SetupPolicy) -> Result {
    let network_manifest = fs::read_to_string(&p.network_manifest)?;
    for row in manifest::rows(&network_manifest) {
        let network = manifest::Network::parse(row)?;
        let mut temporary = None;
        let mut definition = network.definition.to_owned();
        if p.connection().query(&["net-info", network.name]).is_ok() {
            let id = p.connection().query(&["net-uuid", network.name])?;
            ensure(
                uuid(&id),
                "network returned invalid UUID; refusing redefinition",
            )?;
            let xml = output(
                &p.xml_helper,
                &["preserve-uuid", "network", network.name, &id, &definition],
            )?;
            let (mut f, _cleanup) = resources::temporary(None)?;
            f.write_all(xml.as_bytes())?;
            definition = f.path().to_string_lossy().into_owned();
            temporary = Some((f, _cleanup));
        }
        p.connection()
            .query(&["net-define", &definition, "--validate"])?;
        drop(temporary);
        p.connection().query(&["net-autostart", network.name])?;
        if !field(
            &p.connection().query(&["net-info", network.name])?,
            "Active",
            "yes",
        ) {
            p.connection().query(&["net-start", network.name])?;
        }
    }
    let mut temporary = None;
    let mut definition = p.pool_definition.clone();
    if p.connection().query(&["pool-info", &p.pool_name]).is_ok() {
        let xml = p
            .connection()
            .query(&["pool-dumpxml", "--inactive", &p.pool_name])?;
        let path = pipe(&p.xml_helper, &["pool-path"], xml.as_bytes())?;
        ensure(
            path == p.pool_path,
            format!(
                "storage pool {} targets {path}, expected {}; refusing replacement",
                p.pool_name, p.pool_path
            ),
        )?;
        let id = p.connection().query(&["pool-uuid", &p.pool_name])?;
        ensure(uuid(&id), "pool returned invalid UUID")?;
        let xml = output(
            &p.xml_helper,
            &["preserve-uuid", "pool", &p.pool_name, &id, &definition],
        )?;
        let (mut f, _cleanup) = resources::temporary(None)?;
        f.write_all(xml.as_bytes())?;
        definition = f.path().to_string_lossy().into_owned();
        temporary = Some((f, _cleanup));
    }
    p.connection()
        .query(&["pool-define", &definition, "--validate"])?;
    drop(temporary);
    p.connection().query(&["pool-autostart", &p.pool_name])?;
    if !field(
        &p.connection().query(&["pool-info", &p.pool_name])?,
        "State",
        "running",
    ) {
        p.connection().query(&["pool-start", &p.pool_name])?;
    }
    p.connection().query(&["pool-refresh", &p.pool_name])?;
    for guest in manifest::guests(&p.guest_manifest)? {
        if p.connection().domain(&guest.name) {
            p.connection().autostart(&guest.name, guest.autostart)?;
        }
    }
    Ok(())
}
fn boot_profile(path: &str) -> String {
    fs::read_to_string(path)
        .unwrap_or_else(|_| "unknown".into())
        .trim_end_matches('\n')
        .into()
}
fn vfio(
    manifest_path: &str,
    profile_marker: &str,
    vfio_profile: &str,
    strict: bool,
) -> Result<Vec<(bool, String)>> {
    let mut checks = vec![];
    let mut groups: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for configured_device in manifest::vfio_devices(manifest_path)? {
        let path = format!("/sys/bus/pci/devices/{}", configured_device.pci_address);
        if !Path::new(&path).exists() {
            checks.push((
                false,
                format!(
                    "configured VFIO device {} ({}) is missing",
                    configured_device.name, configured_device.pci_address
                ),
            ));
            continue;
        }
        let vendor = fs::read_to_string(format!("{path}/vendor"))?;
        let device = fs::read_to_string(format!("{path}/device"))?;
        let id = format!(
            "{}:{}",
            vendor.trim().trim_start_matches("0x"),
            device.trim().trim_start_matches("0x")
        );
        checks.push((
            id.to_lowercase() == configured_device.vendor_device_id,
            format!(
                "{} identifies as {id}, expected {}",
                configured_device.pci_address, configured_device.vendor_device_id
            ),
        ));
        let group = link_name(format!("{path}/iommu_group"));
        checks.push((
            group == configured_device.iommu_group,
            format!(
                "{} IOMMU group is {group}, expected {}",
                configured_device.pci_address, configured_device.iommu_group
            ),
        ));
        let driver = link_name(format!("{path}/driver"));
        if strict || boot_profile(profile_marker) == vfio_profile {
            checks.push((
                driver == "vfio-pci",
                format!(
                    "{} driver is {driver}, expected vfio-pci",
                    configured_device.pci_address
                ),
            ))
        } else {
            println!(
                "INFO  {} uses host driver {driver} in the default profile",
                configured_device.pci_address
            );
        }
        groups
            .entry(configured_device.iommu_group)
            .or_default()
            .insert(configured_device.pci_address);
    }
    for (group, members) in groups {
        let path = format!("/sys/kernel/iommu_groups/{group}/devices");
        if let Ok(entries) = fs::read_dir(path) {
            for e in entries {
                let e = e?;
                let name = e.file_name().to_string_lossy().into_owned();
                if e.path().exists() && !members.contains(&name) {
                    checks.push((
                        false,
                        format!(
                            "undeclared PCI function {name} is in selected IOMMU group {group}"
                        ),
                    ));
                }
            }
        }
    }
    Ok(checks)
}
pub fn guard(p: &ProfileGuardPolicy, a: &[String]) -> Result {
    if a.get(1).map(String::as_str) != Some("prepare")
        || a.get(2).map(String::as_str) != Some("begin")
    {
        return Ok(());
    };
    let guests = manifest::guests(&p.guest_manifest)?;
    let Some(guest) = guests.iter().find(|guest| Some(&guest.name) == a.first()) else {
        return Ok(());
    };
    let Some(required_profile) = guest.required_profile.as_deref() else {
        return Ok(());
    };
    ensure(
        boot_profile(&p.profile_marker) == required_profile,
        format!(
            "Refusing to start {}: boot profile {} is active, but {required_profile} is required",
            guest.name,
            boot_profile(&p.profile_marker),
        ),
    )?;
    if required_profile == p.vfio_profile {
        for (ok, msg) in vfio(
            &p.vfio_device_manifest,
            &p.profile_marker,
            &p.vfio_profile,
            true,
        )? {
            ensure(ok, format!("Refusing to start {}: {msg}", guest.name))?;
        }
    }
    Ok(())
}
pub fn sleep_hook(policy: &SleepHookPolicy, arguments: &[String]) -> Result {
    let guests = manifest::guests(&policy.guest_manifest)?;
    let Some(guest) = guests
        .iter()
        .find(|guest| Some(&guest.name) == arguments.first())
    else {
        return Ok(());
    };
    if !guest.inhibit_sleep {
        return Ok(());
    }
    let unit = output(
        &policy.systemd_escape,
        &[
            "--template=libvirt-workstation-sleep-inhibit@.service",
            &guest.name,
        ],
    )?;
    let operation = arguments.get(1).map(String::as_str).unwrap_or("");
    let phase = arguments.get(2).map(String::as_str).unwrap_or("");
    match (operation, phase) {
        ("prepare", "begin") => run(&policy.systemctl, &["start", &unit]),
        ("reconnect", "begin") | ("release", "end") => {
            let action = if operation == "release" {
                "stop"
            } else {
                "start"
            };
            if run(&policy.systemctl, &[action, &unit]).is_err() {
                eprintln!("Could not update host sleep inhibitor for {}", guest.name);
            }
            Ok(())
        }
        _ => Ok(()),
    }
}
struct Doctor {
    failures: usize,
    warnings: usize,
}
impl Doctor {
    fn check(&mut self, ok: bool, yes: impl AsRef<str>, no: impl AsRef<str>) {
        if ok {
            println!("PASS  {}", yes.as_ref())
        } else {
            self.failures += 1;
            println!("FAIL  {}", no.as_ref())
        }
    }
    fn warn(&mut self, msg: &str) {
        self.warnings += 1;
        println!("WARN  {msg}")
    }
}
fn doctor(p: &WorkstationControlPolicy, guest: Option<&manifest::Guest>) -> Result {
    let mut d = Doctor {
        failures: 0,
        warnings: 0,
    };
    println!("Boot profile: {}\n", boot_profile(&p.profile_marker));
    d.check(
        output(&p.systemctl, &["is-active", "--quiet", "libvirtd.service"]).is_ok(),
        "libvirtd is active",
        "libvirtd is not active",
    );
    use std::os::unix::fs::FileTypeExt;
    d.check(
        fs::metadata("/dev/kvm").is_ok_and(|m| m.file_type().is_char_device()),
        "/dev/kvm exists for native-architecture acceleration",
        "/dev/kvm is missing; enable CPU virtualization in firmware and load KVM",
    );
    d.check(
        p.connection().query(&["uri"]).is_ok(),
        format!("libvirt accepts {} connections", p.libvirt_uri),
        format!("cannot connect to {}", p.libvirt_uri),
    );
    let network_manifest = fs::read_to_string(&p.network_manifest)?;
    for row in manifest::rows(&network_manifest) {
        let network = manifest::Network::parse(row)?;
        d.check(
            p.connection()
                .query(&["net-info", network.name])
                .is_ok_and(|info| field(&info, "Active", "yes")),
            format!("network {} is active on {}", network.name, network.bridge),
            format!("network {} is missing or inactive", network.name),
        );
        println!(
            "INFO  route for {}: {}",
            network.subnet,
            output(&p.ip, &["route", "show", network.subnet])
                .unwrap_or_else(|_| "unavailable".into())
        );
    }
    let pool = p
        .connection()
        .query(&["pool-info", &p.pool_name])
        .is_ok_and(|s| field(&s, "State", "running"));
    d.check(
        pool,
        format!("storage pool {} is running", p.pool_name),
        format!("storage pool {} is missing or inactive", p.pool_name),
    );
    if pool {
        let xml = p
            .connection()
            .query(&["pool-dumpxml", "--inactive", &p.pool_name])?;
        let path = pipe(&p.xml_helper, &["pool-path"], xml.as_bytes())?;
        d.check(
            path == p.pool_path,
            format!("storage pool targets {}", p.pool_path),
            format!("storage pool targets {path}, expected {}", p.pool_path),
        );
    }
    if Path::new(&p.pool_path).is_dir() {
        println!(
            "INFO  storage filesystem: {}",
            output(
                &p.findmnt,
                &[
                    "--noheadings",
                    "--output",
                    "FSTYPE",
                    "--target",
                    &p.pool_path
                ]
            )
            .unwrap_or_else(|_| "unknown".into())
        );
        if p.storage_nocow {
            let attr = output(&p.lsattr, &["-d", &p.pool_path]).unwrap_or_default();
            d.check(
                attr.split_whitespace()
                    .next()
                    .is_some_and(|s| s.contains('C')),
                "storage directory has the NOCOW inheritance attribute",
                "storage.nocow is enabled but the storage directory lacks the NOCOW attribute",
            );
        }
    } else {
        d.check(
            false,
            "",
            format!("storage directory does not exist: {}", p.pool_path),
        );
    }
    if p.emulate_aarch64 {
        let ok = fs::metadata(&p.qemu_aarch64).is_ok_and(|m| m.permissions().mode() & 0o111 != 0);
        d.check(
            ok,
            "qemu-system-aarch64 is installed",
            "AArch64 emulation is enabled but qemu-system-aarch64 is missing",
        );
        if ok {
            d.warn("AArch64 on x86_64 uses TCG; use Apple Silicon for normal ARM development");
        }
    }
    let iommu = fs::read_dir("/sys/kernel/iommu_groups").is_ok_and(|mut e| e.next().is_some());
    if iommu {
        d.check(true, "the kernel exposes IOMMU groups", "")
    } else if p.iommu_enabled || p.vfio_enabled {
        d.check(
            false,
            "",
            "IOMMU policy is enabled but the kernel exposes no groups",
        )
    } else {
        d.warn("the kernel exposes no IOMMU groups; this matters before PCI passthrough")
    };
    if p.vfio_enabled {
        d.check(
            Path::new(&format!(
                "/run/current-system/specialisation/{}",
                p.vfio_profile
            ))
            .exists()
                || boot_profile(&p.profile_marker) == p.vfio_profile,
            format!("VFIO boot profile {} is installed", p.vfio_profile),
            format!(
                "VFIO is configured but profile {} is not installed",
                p.vfio_profile
            ),
        );
        for (ok, msg) in vfio(
            &p.vfio_device_manifest,
            &p.profile_marker,
            &p.vfio_profile,
            false,
        )? {
            d.check(ok, &msg, &msg)
        }
    }
    let sockets =
        output(&p.ss, &["--listening", "--tcp", "--numeric", "--process"]).unwrap_or_default();
    d.check(
        !sockets
            .split_whitespace()
            .any(|s| s.ends_with(":16509") || s.ends_with(":16514")),
        "libvirt management is not listening on TCP or TLS",
        "a libvirt TCP or TLS management port is listening",
    );
    let processes = output(&p.ps, &["-eo", "user=,comm="])?;
    d.check(
        !processes.lines().any(|l| {
            let v: Vec<_> = l.split_whitespace().collect();
            v.len() >= 2 && v[0] == "root" && v[1].starts_with("qemu-system-")
        }),
        "no QEMU system process is running as root",
        "at least one QEMU system process is running as root",
    );
    println!("\nlibvirt host validation");
    if run(&p.virt_host_validate, &["qemu"]).is_ok() {
        d.check(true, "virt-host-validate accepted the QEMU host", "")
    } else {
        d.warn("virt-host-validate reported at least one warning or failure above")
    }
    if let Some(guest) = guest {
        println!("\nGuest: {}", guest.name);
        if !p.connection().domain(&guest.name) {
            d.check(
                false,
                "",
                format!("libvirt domain is not installed: {}", guest.name),
            );
        } else {
            let info = p.connection().query(&["dominfo", &guest.name])?;
            let expected = if guest.autostart { "enable" } else { "disable" };
            d.check(
                field(&info, "Autostart", expected),
                format!("guest autostart is {expected}"),
                format!("guest autostart differs from {expected}"),
            );
            if guest.inhibit_sleep {
                let unit = output(
                    &p.systemd_escape,
                    &[
                        "--template=libvirt-workstation-sleep-inhibit@.service",
                        &guest.name,
                    ],
                )?;
                let active = p.connection().active(&guest.name);
                let inhibited = output(&p.systemctl, &["is-active", "--quiet", &unit]).is_ok();
                d.check(
                    active == inhibited,
                    "host sleep inhibitor follows guest activity",
                    "host sleep inhibitor does not match guest activity",
                );
            }
            match guest.required_profile.as_deref() {
                Some(required_profile) if required_profile != boot_profile(&p.profile_marker) => {
                    d.warn(&format!(
                        "guest requires {required_profile}; current profile is {}",
                        boot_profile(&p.profile_marker)
                    ));
                }
                _ => d.check(
                    true,
                    format!(
                        "boot profile {} permits this guest",
                        boot_profile(&p.profile_marker)
                    ),
                    "",
                ),
            }
            p.connection().run(&["domstate", &guest.name, "--reason"])?;
            println!("\nBlock devices");
            p.connection()
                .run(&["domblklist", &guest.name, "--details"])?;
            println!("\nNetwork interfaces");
            p.connection().run(&["domiflist", &guest.name])?;
        }
    }
    println!(
        "\nSummary: {} failure(s), {} warning(s)",
        d.failures, d.warnings
    );
    ensure(d.failures == 0, "host validation failed")
}
pub fn control(p: &WorkstationControlPolicy, a: &[String]) -> Result {
    let cmd = a.first().map(String::as_str).unwrap_or("");
    let guests = manifest::guests(&p.guest_manifest)?;
    if cmd == "list" && a.len() == 1 {
        println!("{:<24} {:<16} {:<18} SSH_ALIAS", "NAME", "STATE", "PROFILE");
        for guest in guests {
            println!(
                "{:<24} {:<16} {:<18} {}",
                guest.name,
                p.connection()
                    .query(&["domstate", &guest.name])
                    .unwrap_or_else(|_| "missing".into()),
                guest.required_profile.as_deref().unwrap_or("any"),
                guest.ssh_host.as_deref().unwrap_or("unconfigured")
            );
        }
        return Ok(());
    }
    if cmd == "doctor" && a.len() == 1 {
        return doctor(p, None);
    }
    if a.len() != 2 || !["doctor", "status", "start", "stop", "ip", "console"].contains(&cmd) {
        usage(
            "libvirt-workstation-control list|doctor [guest]|status|start|stop|ip|console <guest>",
        )
    };
    let guest = guests
        .iter()
        .find(|guest| guest.name == a[1])
        .ok_or_else(|| format!("guest is not allowlisted: {}", a[1]))?;
    if cmd == "doctor" {
        return doctor(p, Some(guest));
    }
    ensure(
        p.connection().domain(&guest.name),
        format!("libvirt domain does not exist: {}", guest.name),
    )?;
    match cmd {
        "start" => {
            if let Some(required_profile) = guest.required_profile.as_deref() {
                ensure(
                    required_profile == boot_profile(&p.profile_marker),
                    format!(
                        "{} requires boot profile {required_profile}; current profile is {}",
                        guest.name,
                        boot_profile(&p.profile_marker),
                    ),
                )?;
            }
            if let Some(exclusive_group) = guest.exclusive_group.as_deref() {
                for peer in &guests {
                    ensure(
                        peer.name == guest.name
                            || peer.exclusive_group.as_deref() != Some(exclusive_group)
                            || !p.connection().active(&peer.name),
                        format!(
                            "{} is already active in exclusive group {exclusive_group}",
                            peer.name
                        ),
                    )?;
                }
            }
            p.connection().exec(&["start", &guest.name])
        }
        "stop" => p.connection().exec(&["shutdown", &guest.name]),
        "console" => p.connection().exec(&["console", &guest.name]),
        "status" => {
            println!(
                "Host profile: {}\nRequired profile: {}",
                boot_profile(&p.profile_marker),
                guest.required_profile.as_deref().unwrap_or("-")
            );
            p.connection().run(&["dominfo", &guest.name])
        }
        "ip" => {
            for source in ["agent", "lease"] {
                let text = p
                    .connection()
                    .query(&["domifaddr", &guest.name, "--source", source])
                    .unwrap_or_default();
                let ips: Vec<_> = text
                    .lines()
                    .filter_map(|l| {
                        let v: Vec<_> = l.split_whitespace().collect();
                        if v.len() >= 2 && ["ipv4", "ipv6"].contains(&v[v.len() - 2]) {
                            v.last().map(|s| s.split('/').next().unwrap_or(""))
                        } else {
                            None
                        }
                    })
                    .collect();
                if !ips.is_empty() {
                    println!("{}", ips.join("\n"));
                    return Ok(());
                }
            }
            Err(format!(
                "no guest-agent or DHCP lease address is available for {}",
                guest.name
            )
            .into())
        }
        _ => Ok(()),
    }
}
