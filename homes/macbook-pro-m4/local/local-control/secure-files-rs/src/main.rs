#![forbid(unsafe_code)]
#![allow(missing_docs)]

use std::{
    env,
    io::{self, Read, Write},
    path::Path,
};

use local_control_secure_files::{
    ExpectedMode, atomic_write, cluster_state, create_file, ensure_private_directory, exec_cluster,
    exec_cluster_socket, exec_files, exec_private_directory, exec_proxy, exec_source,
    initialize_cluster, open_file, open_generation_file, open_private_directory, open_trusted,
    parse_mode, private_directory_is_empty, read_file, read_generation_file, repair_file_mode,
    snapshot_tree, validate_cluster,
};
use rustix::fs::OFlags;

const USAGE: &str = "Usage: local-control-secure-files COMMAND PATH [MODE]\n\
Commands: ensure-directory, validate-directory, validate-source-directory, validate-file, \
inspect-file, inspect-generation-file, repair-file-mode, read-file, read-generation-file, \
create-file, atomic-write, directory-empty, validate-cluster, cluster-state, \
initialize-cluster, exec-cluster, exec-cluster-socket, exec-private-directory, \
exec-empty-private-directory, exec-source, exec-files, exec-proxy, snapshot-tree\n";

fn usage() -> i32 {
    eprint!("{USAGE}");
    64
}

fn expected_mode(text: &str) -> Result<ExpectedMode, String> {
    if text == "private" {
        Ok(ExpectedMode::Private)
    } else {
        parse_mode(text)
            .map(ExpectedMode::Exact)
            .map_err(|error| error.to_string())
    }
}

fn read_stdin() -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    io::stdin()
        .read_to_end(&mut bytes)
        .map_err(|error| error.to_string())?;
    Ok(bytes)
}

fn inspect(
    result: Result<rustix::fd::OwnedFd, local_control_secure_files::Error>,
) -> Result<i32, String> {
    match result {
        Ok(_) => {
            println!("present");
            Ok(0)
        }
        Err(local_control_secure_files::Error::Io(error))
            if error.kind() == io::ErrorKind::NotFound =>
        {
            println!("missing");
            Ok(0)
        }
        Err(error) => Err(error.to_string()),
    }
}

fn split_program(arguments: &[String]) -> Result<(&str, &[String]), String> {
    let Some((program, arguments)) = arguments.split_first() else {
        return Err("missing executable arguments".to_owned());
    };
    Ok((program, arguments))
}

fn run_exec_files(path: &Path, rest: &[String]) -> Result<i32, String> {
    let Some((program, specifications_and_arguments)) = rest.split_first() else {
        return Ok(usage());
    };
    let separator = specifications_and_arguments
        .iter()
        .position(|argument| argument == "--")
        .ok_or("mapped file command is missing `--`")?;
    let specifications = &specifications_and_arguments[..separator];
    let child_arguments = &specifications_and_arguments[separator + 1..];
    if child_arguments.is_empty() || specifications.len() % 3 != 0 {
        return Ok(usage());
    }
    let mut mappings = Vec::new();
    for specification in specifications.chunks_exact(3) {
        let access = specification[0]
            .strip_prefix("--")
            .filter(|access| matches!(*access, "create" | "update" | "read"))
            .ok_or("mapped file access is invalid")?;
        let mode = parse_mode(&specification[2]).map_err(|error| error.to_string())?;
        mappings.push((
            access.to_owned(),
            specification[1].clone(),
            mode,
            specification[1].clone(),
        ));
    }
    exec_files(path, program, &mappings, child_arguments).map_err(|error| error.to_string())?;
    Ok(0)
}

// The explicit dispatch table is intentionally kept together so the public
// compatibility surface can be audited against the former helper at a glance.
#[allow(clippy::too_many_lines)]
fn run(arguments: &[String]) -> Result<i32, String> {
    let [command, path, rest @ ..] = arguments else {
        return Ok(usage());
    };
    let path = Path::new(path);
    match (command.as_str(), rest) {
        ("ensure-directory", []) => {
            ensure_private_directory(path).map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("validate-directory", []) => {
            open_private_directory(path).map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("validate-source-directory", []) => {
            let descriptor =
                open_trusted(path, OFlags::DIRECTORY).map_err(|error| error.to_string())?;
            let metadata = rustix::fs::fstat(&descriptor).map_err(|error| error.to_string())?;
            if rustix::fs::FileType::from_raw_mode(metadata.st_mode)
                != rustix::fs::FileType::Directory
                || metadata.st_uid != rustix::process::geteuid().as_raw()
            {
                return Err("source directory is not an owned real directory".to_owned());
            }
            Ok(0)
        }
        ("validate-file", [mode]) => {
            open_file(path, expected_mode(mode)?).map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("inspect-file", [mode]) => inspect(open_file(path, expected_mode(mode)?)),
        ("inspect-generation-file", [mode]) => {
            inspect(open_generation_file(path, expected_mode(mode)?))
        }
        ("repair-file-mode", [mode]) => {
            let repaired =
                repair_file_mode(path, parse_mode(mode).map_err(|error| error.to_string())?)
                    .map_err(|error| error.to_string())?;
            println!("{}", if repaired { "present" } else { "missing" });
            Ok(0)
        }
        ("read-file", [mode]) => {
            io::stdout()
                .write_all(
                    &read_file(path, expected_mode(mode)?).map_err(|error| error.to_string())?,
                )
                .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("read-generation-file", [mode]) => {
            io::stdout()
                .write_all(
                    &read_generation_file(path, expected_mode(mode)?)
                        .map_err(|error| error.to_string())?,
                )
                .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("create-file", [mode]) => {
            create_file(
                path,
                parse_mode(mode).map_err(|error| error.to_string())?,
                &read_stdin()?,
            )
            .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("atomic-write", [mode]) => {
            atomic_write(
                path,
                parse_mode(mode).map_err(|error| error.to_string())?,
                &read_stdin()?,
            )
            .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("directory-empty", []) => Ok(i32::from(
            !private_directory_is_empty(path).map_err(|error| error.to_string())?,
        )),
        ("validate-cluster", [version]) => {
            let directory = open_private_directory(path).map_err(|error| error.to_string())?;
            validate_cluster(&directory, version).map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("cluster-state", [version]) => {
            println!(
                "{}",
                cluster_state(path, version).map_err(|error| error.to_string())?
            );
            Ok(0)
        }
        ("initialize-cluster", [version, command, command_arguments @ ..]) => {
            initialize_cluster(path, version, command, command_arguments)
                .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("exec-cluster", [version, command, command_arguments @ ..]) => {
            exec_cluster(path, version, command, command_arguments)
                .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("exec-cluster-socket", [version, socket, command, command_arguments @ ..]) => {
            exec_cluster_socket(path, version, Path::new(socket), command, command_arguments)
                .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("exec-private-directory", program_and_arguments) if !program_and_arguments.is_empty() => {
            let (program, program_arguments) = split_program(program_and_arguments)?;
            exec_private_directory(path, false, program, program_arguments)
                .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("exec-empty-private-directory", program_and_arguments)
            if !program_and_arguments.is_empty() =>
        {
            let (program, program_arguments) = split_program(program_and_arguments)?;
            exec_private_directory(path, true, program, program_arguments)
                .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("exec-source", program_and_arguments) if !program_and_arguments.is_empty() => {
            let (program, program_arguments) = split_program(program_and_arguments)?;
            exec_source(path, program, program_arguments).map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("exec-files", rest) => run_exec_files(path, rest),
        ("exec-proxy", [environment_file, command, command_arguments @ ..]) => {
            exec_proxy(
                path,
                Path::new(environment_file),
                command,
                command_arguments,
            )
            .map_err(|error| error.to_string())?;
            Ok(0)
        }
        ("snapshot-tree", []) => {
            snapshot_tree(path, &mut io::stdout()).map_err(|error| error.to_string())?;
            Ok(0)
        }
        _ => Ok(usage()),
    }
}

fn main() {
    let arguments: Vec<String> = env::args().skip(1).collect();
    match run(&arguments) {
        Ok(status) => std::process::exit(status),
        Err(message) => {
            eprintln!("local-control-secure-files: {message}");
            std::process::exit(1);
        }
    }
}
