use helium_crx_to_zip::convert;
use std::{io, path::Path};
fn main() -> std::process::ExitCode {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let result = if let [source, destination] = args.as_slice() {
        convert(Path::new(source), Path::new(destination))
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "usage: helium-crx-to-zip INPUT OUTPUT",
        ))
    };
    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("helium-crx-to-zip: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}
