//! Fail closed unless the exact booted EFI generation is uniquely protected.
use std::{
    env, fs,
    os::unix::process::CommandExt,
    process::{Command, ExitCode},
};
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = env::args_os().skip(1);
    let upstream = args
        .next()
        .ok_or("usage: desktop-guard-boot-install UPSTREAM ARGS...")?;
    let args: Vec<_> = args.collect();
    let install = args.iter().any(|v| v == "install");
    let mut limit = None;
    let mut protected = None;
    let mut links = Vec::new();
    let mut iter = args.iter();
    while let Some(argument) = iter.next() {
        let arg = argument
            .to_str()
            .ok_or("boot installation arguments must be UTF-8")?;
        if arg == "--configuration-limit" {
            limit = iter.next().and_then(|v| v.to_str());
        } else if let Some(path) = arg.strip_prefix("--protected-system=") {
            protected = Some(path);
        } else if arg
            .strip_prefix("/nix/var/nix/profiles/system-")
            .is_some_and(|tail| {
                tail.starts_with(|c: char| c.is_ascii_digit()) && tail.ends_with("-link")
            })
        {
            links.push(arg);
        }
    }
    if install {
        if !limit.is_some_and(|v| {
            !v.starts_with('0') && !v.is_empty() && v.bytes().all(|c| c.is_ascii_digit())
        }) || protected.is_none()
            || links.is_empty()
        {
            return Err("cannot verify the protected boot generation before installation".into());
        }
        let entry = fs::read(
            "/sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f",
        )?;
        let bytes = entry.get(4..).ok_or("running EFI entry is truncated")?;
        let current = String::from_utf16(
            &bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|b| u16::from_le_bytes(*b))
                .take_while(|v| *v != 0)
                .collect::<Vec<_>>(),
        )?;
        if bytes.len() % 2 != 0 {
            return Err("running EFI entry is truncated".into());
        }
        let generation = current
            .strip_prefix("nixos-generation-")
            .and_then(|v| v.split_once('-'))
            .filter(|(g, tail)| {
                !g.is_empty() && g.bytes().all(|c| c.is_ascii_digit()) && tail.ends_with(".efi")
            })
            .map(|(g, _)| g)
            .ok_or("cannot identify the running NixOS EFI entry")?;
        let target = fs::canonicalize(protected.ok_or("protected generation missing")?)?;
        if fs::canonicalize(format!("/nix/var/nix/profiles/system-{generation}-link"))? != target {
            return Err("protected system does not match the booted generation".into());
        }
        let mut count = 0;
        for link in links {
            if fs::canonicalize(link)? == target {
                count += 1;
            }
        }
        if count != 1 {
            return Err(format!(
                "booted system matches {count} profile links; cannot protect its exact EFI entry"
            )
            .into());
        }
    }
    Err(Command::new(upstream).args(args).exec().into())
}
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lzbt: {e}");
            ExitCode::FAILURE
        }
    }
}
