use include_dir::{Dir, DirEntry};
use portable_pty::CommandBuilder;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static SCRIPTS_EMBEDDED: Dir<'_> = crate::embedded_scripts!();
static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(0);

pub struct EmbeddedScriptManager {
    temp_dir: PathBuf,
    project_dir: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UsbStick {
    pub path: String,
    pub description: String,
}

impl EmbeddedScriptManager {
    pub fn init() -> io::Result<Self> {
        let project_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("safe-stick crate must be inside the repository")
            .to_path_buf();
        let temp_dir = create_temp_dir()?;

        if let Err(error) = unpack_dir(&SCRIPTS_EMBEDDED, &temp_dir) {
            if let Err(cleanup_error) = std::fs::remove_dir_all(&temp_dir) {
                eprintln!(
                    "Failed to clean up incomplete script directory {}: {cleanup_error}",
                    temp_dir.display()
                );
            }
            return Err(error);
        }

        Ok(Self {
            temp_dir,
            project_dir,
        })
    }

    pub fn list_usb_sticks(&self) -> io::Result<Vec<UsbStick>> {
        let script = self.temp_dir.join("st-usb.sh");
        let output = Command::new("bash")
            .arg(script)
            .arg("list-sticks")
            .current_dir(&self.project_dir)
            .output()?;
        let stdout = String::from_utf8_lossy(&output.stdout);

        if !output.status.success() && stdout.contains("No USB sticks found.") {
            return Ok(Vec::new());
        }
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let message = if stderr.trim().is_empty() {
                stdout.trim()
            } else {
                stderr.trim()
            };
            return Err(io::Error::other(format!(
                "st-usb.sh list-sticks failed: {message}"
            )));
        }

        let sticks = parse_usb_sticks(&stdout)?;
        if sticks.is_empty() && stdout.contains("Available USB sticks:") {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "st-usb.sh list-sticks returned an unrecognized device list",
            ));
        }
        Ok(sticks)
    }

    pub fn is_safe_stick(&self, device: &str) -> io::Result<bool> {
        let script = self.temp_dir.join("st-usb.sh");
        let output = Command::new("bash")
            .arg(script)
            .args(["--usb-device", device, "is-safe-stick"])
            .current_dir(&self.project_dir)
            .output()?;

        safe_stick_result(
            output.status.success(),
            &String::from_utf8_lossy(&output.stdout),
            &String::from_utf8_lossy(&output.stderr),
            &output.status.to_string(),
        )
    }

    pub fn is_crypt_open(&self, device: &str) -> io::Result<bool> {
        let script = self.temp_dir.join("st-usb.sh");
        let output = Command::new("bash")
            .arg(script)
            .args(["--usb-device", device, "is-crypt-open"])
            .current_dir(&self.project_dir)
            .output()?;

        crypt_open_result(
            output.status.success(),
            &String::from_utf8_lossy(&output.stdout),
            &String::from_utf8_lossy(&output.stderr),
            &output.status.to_string(),
        )
    }

    pub fn prepare_command(
        &self,
        entry_script_path: &str,
        args: &[String],
    ) -> io::Result<CommandBuilder> {
        let relative_path = Path::new(entry_script_path);
        validate_relative_path(relative_path)?;
        let entry_script = self.temp_dir.join(relative_path);
        if !entry_script.is_file() {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                format!("Embedded script not found: {}", relative_path.display()),
            ));
        }

        let mut command = if nix::unistd::geteuid().is_root() {
            CommandBuilder::new("bash")
        } else {
            CommandBuilder::new("sudo")
        };
        if !nix::unistd::geteuid().is_root() {
            command.arg("bash");
        }
        command.arg(entry_script);
        command.args(args);
        command.cwd(&self.project_dir);
        Ok(command)
    }
}

fn safe_stick_result(
    status_success: bool,
    stdout: &str,
    stderr: &str,
    status: &str,
) -> io::Result<bool> {
    if stdout.lines().any(|line| line.starts_with("Checking if ")) {
        if status_success {
            return Ok(true);
        }

        let details = [stdout.trim(), stderr.trim()]
            .into_iter()
            .filter(|text| !text.is_empty())
            .collect::<Vec<_>>()
            .join("\n");
        return Err(io::Error::other(format!(
            "st-usb.sh is-safe-stick returned {status}: {}",
            if details.is_empty() {
                "no diagnostic output"
            } else {
                &details
            }
        )));
    }

    let details = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    Err(io::Error::other(format!(
        "st-usb.sh is-safe-stick did not complete ({status}): {}",
        if details.is_empty() {
            "no diagnostic output"
        } else {
            details
        }
    )))
}

fn crypt_open_result(
    status_success: bool,
    stdout: &str,
    stderr: &str,
    status: &str,
) -> io::Result<bool> {
    if stdout
        .lines()
        .any(|line| line == "[+] Encrypted partition is currently open.")
    {
        return if status_success {
            Ok(true)
        } else {
            Err(io::Error::other(format!(
                "st-usb.sh is-crypt-open returned {status} after reporting an open partition"
            )))
        };
    }

    if stdout
        .lines()
        .any(|line| line == "[-] Encrypted partition is not open.")
    {
        return if status_success {
            Err(io::Error::other(format!(
                "st-usb.sh is-crypt-open returned {status} after reporting a closed partition"
            )))
        } else {
            Ok(false)
        };
    }

    let details = [stdout.trim(), stderr.trim()]
        .into_iter()
        .filter(|text| !text.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    Err(io::Error::other(format!(
        "st-usb.sh is-crypt-open did not complete ({status}): {}",
        if details.is_empty() {
            "no diagnostic output"
        } else {
            &details
        }
    )))
}

fn create_temp_dir() -> io::Result<PathBuf> {
    loop {
        let id = NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("safe-stick-scripts-{}-{id}", std::process::id()));
        match std::fs::create_dir(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
}

fn parse_usb_sticks(output: &str) -> io::Result<Vec<UsbStick>> {
    let mut sticks = Vec::new();
    for line in output.lines() {
        let Some((_, description)) = line.trim().split_once(". ") else {
            continue;
        };
        let Some(details) = description.strip_prefix("Name: ") else {
            continue;
        };
        let Some((path, _)) = details.split_once(", ") else {
            continue;
        };
        if !path.starts_with("/dev/") {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("invalid USB device path from st-usb.sh: {path}"),
            ));
        }
        sticks.push(UsbStick {
            path: path.to_owned(),
            description: description.to_owned(),
        });
    }
    Ok(sticks)
}

fn validate_relative_path(path: &Path) -> io::Result<()> {
    if path
        .components()
        .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Embedded script path must be relative and cannot contain parent components",
        ));
    }
    Ok(())
}

fn unpack_dir(directory: &Dir<'_>, target_dir: &Path) -> io::Result<()> {
    for entry in directory.entries() {
        match entry {
            DirEntry::Dir(child_dir) => {
                let relative_path = child_dir.path();
                validate_relative_path(relative_path)?;
                std::fs::create_dir_all(target_dir.join(relative_path))?;
                unpack_dir(child_dir, target_dir)?;
            }
            DirEntry::File(file) => {
                let relative_path = file.path();
                validate_relative_path(relative_path)?;
                let destination = target_dir.join(relative_path);
                if let Some(parent) = destination.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                std::fs::write(destination, file.contents())?;
            }
        }
    }
    Ok(())
}

impl Drop for EmbeddedScriptManager {
    fn drop(&mut self) {
        if let Err(error) = std::fs::remove_dir_all(&self.temp_dir) {
            if error.kind() != io::ErrorKind::NotFound {
                eprintln!(
                    "Failed to clean up embedded scripts at {}: {error}",
                    self.temp_dir.display()
                );
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_stick_result_uses_script_exit_status() {
        assert_eq!(
            safe_stick_result(
                true,
                "Checking if /dev/sda is a Safe Stick...\n",
                "",
                "exit status: 0",
            )
            .expect("safe-stick result"),
            true
        );
    }

    #[test]
    fn safe_stick_result_reports_nonzero_script_output() {
        let error = safe_stick_result(
            false,
            "Checking if /dev/sdb is a Safe Stick...\n[!] First partition must use vfat.\n",
            "",
            "exit status: 1",
        )
        .expect_err("nonzero result should be visible");
        assert!(error.to_string().contains("First partition must use vfat"));
        assert!(
            safe_stick_result(false, "", "sudo password cancelled.", "exit status: 1").is_err()
        );
    }

    #[test]
    fn crypt_open_result_uses_script_output_and_exit_status() {
        assert_eq!(
            crypt_open_result(
                true,
                "[+] Encrypted partition is currently open.\n",
                "",
                "exit status: 0",
            )
            .expect("open partition result"),
            true
        );
        assert_eq!(
            crypt_open_result(
                false,
                "[-] Encrypted partition is not open.\n",
                "",
                "exit status: 1",
            )
            .expect("closed partition result"),
            false
        );
        assert!(
            crypt_open_result(false, "", "sudo authentication failed.", "exit status: 1").is_err()
        );
    }

    #[test]
    fn unpacks_tracked_script_tree_for_relative_dependencies() {
        let manager = EmbeddedScriptManager::init().expect("initialize script manager");

        for path in [
            "st-iso.sh",
            "st-usb.sh",
            "common.sh",
            "sh_ext_mx/customize_tor_browser.sh",
            "sh_ext_mx/set_passwd.sh",
            "sh_ext_mx/config/keyboard",
            "sh_ext_all/scripts/st-crypt.sh",
        ] {
            assert!(
                manager.temp_dir.join(path).is_file(),
                "expected embedded file {path}"
            );
        }
        assert!(
            !manager
                .temp_dir
                .join("sh_ext_mx/download/torbrowser/tor-browser-linux-x86_64-15.0.26.tar.xz")
                .exists(),
            "untracked download artifacts must not be embedded"
        );

        let _command = manager
            .prepare_command("st-iso.sh", &["extract".to_owned()])
            .expect("prepare embedded ISO script");
    }

    #[test]
    fn rejects_paths_outside_embedded_tree() {
        let manager = EmbeddedScriptManager::init().expect("initialize script manager");
        let error = manager
            .prepare_command("../st-iso.sh", &[])
            .expect_err("parent path should be rejected");

        assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
    }

    #[test]
    fn parses_usb_stick_list_output() {
        let sticks = parse_usb_sticks(
            "Available USB sticks:\n1. Name: /dev/sdb, Size: 16G, Model: Example, Transport: usb\n",
        )
        .expect("parse USB list");

        assert_eq!(
            sticks,
            vec![UsbStick {
                path: "/dev/sdb".to_owned(),
                description: "Name: /dev/sdb, Size: 16G, Model: Example, Transport: usb".to_owned(),
            }]
        );
    }

    #[test]
    fn parses_empty_usb_stick_list() {
        let sticks = parse_usb_sticks("No USB sticks found.\n").expect("parse empty USB list");

        assert!(sticks.is_empty());
    }
}
