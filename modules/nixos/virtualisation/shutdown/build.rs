fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("linux") {
        return;
    }
    if let Err(error) = pkg_config::Config::new().probe("libvirt") {
        eprintln!("libvirt development files are required: {error}");
        std::process::exit(1);
    }
}
