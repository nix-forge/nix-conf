#[tokio::main(flavor = "current_thread")]
async fn main() {
    if actual_protocols::login(&std::env::args().skip(1).collect::<Vec<_>>())
        .await
        .is_err()
    {
        eprintln!("Actual login failed; credentials and session URLs were not logged");
        std::process::exit(1);
    }
}
