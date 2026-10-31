use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let manifest_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let repo_dir = manifest_dir.parent().expect("safe-stick parent");
    let scripts_dir = repo_dir.join("scripts");
    let output_dir =
        PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR")).join("embedded-scripts");

    println!("cargo:rerun-if-changed={}", scripts_dir.display());
    println!(
        "cargo:rerun-if-changed={}",
        repo_dir.join(".git/index").display()
    );
    println!("cargo:rerun-if-changed=build.rs");

    let output = Command::new("git")
        .args(["ls-files", "--cached", "-z", "--", "scripts"])
        .current_dir(repo_dir)
        .output()
        .expect("run git ls-files to find tracked scripts");
    if !output.status.success() {
        panic!("git ls-files failed while collecting embedded scripts");
    }

    fs::create_dir_all(&output_dir).expect("create embedded scripts directory");
    let mut embedded_count = 0;
    for path in output
        .stdout
        .split(|byte| *byte == 0)
        .filter(|path| !path.is_empty())
    {
        let relative_path = Path::new(std::str::from_utf8(path).expect("script path is UTF-8"));
        let Some(relative_path) = relative_path.strip_prefix("scripts").ok() else {
            continue;
        };
        let source_path = repo_dir.join("scripts").join(relative_path);
        if !source_path.is_file() {
            continue;
        }

        let destination = output_dir.join(relative_path);
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent).expect("create embedded script subdirectory");
        }
        fs::copy(source_path, destination).expect("copy tracked script into build output");
        embedded_count += 1;
    }

    assert!(embedded_count > 0, "no Git-tracked scripts were found");
    assert!(
        output_dir.join("st-iso.sh").is_file(),
        "scripts/st-iso.sh must be tracked by Git"
    );
    assert!(
        output_dir.join("common.sh").is_file(),
        "scripts/common.sh must be tracked by Git"
    );
}
