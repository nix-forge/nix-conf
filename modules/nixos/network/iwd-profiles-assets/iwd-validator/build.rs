fn main() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::var("CARGO_CFG_TARGET_OS")? == "linux" {
        pkg_config::Config::new().probe("ell")?;
    }
    Ok(())
}
