use std::fs;

fn main() {
    // Prefer Yocto-provisioned flavor marker, then env, then fallback.
    let flavor = fs::read_to_string("/etc/build-flavor")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .or_else(|| std::env::var("BUILD_FLAVOR").ok())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string());

    println!("Smoke-core is running on {}!!", flavor);
}
