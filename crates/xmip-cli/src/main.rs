fn main() {
    println!("Xmip prototype CLI");
    println!("Startup sequence:");

    for step in xmip_service::startup_sequence() {
        println!("  - {step}");
    }
}
