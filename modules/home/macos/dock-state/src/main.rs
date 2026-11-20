use hm_dock_state::fingerprint;
use std::process::ExitCode;
fn main() -> ExitCode {
    match fingerprint() {
        Ok(hash) => {
            println!("{hash}");
            ExitCode::SUCCESS
        }
        Err(_) => {
            eprintln!("Unable to read the current Dock layout");
            ExitCode::FAILURE
        }
    }
}
