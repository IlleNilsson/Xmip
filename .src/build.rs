//! The Xmip mark linked into every executable of this package as its
//! Windows icon: the resource `Sync-XmipEstate -Brand` makes from the mark
//! (`asset/brand/README.md`), handed to the MSVC linker beside the objects.

const RESOURCE: &str = "asset/brand/xmip-x.res";

fn main() {
    println!("cargo:rerun-if-changed={RESOURCE}");
    let windows = std::env::var("CARGO_CFG_TARGET_OS").is_ok_and(|os| os == "windows");
    let msvc = std::env::var("CARGO_CFG_TARGET_ENV").is_ok_and(|env| env == "msvc");
    if let (true, true, Ok(root)) = (windows, msvc, std::env::var("CARGO_MANIFEST_DIR")) {
        let resource = std::path::Path::new(&root).join(RESOURCE);
        println!("cargo:rustc-link-arg-bins={}", resource.display());
    }
}
