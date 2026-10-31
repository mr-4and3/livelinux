use include_dir::{Dir, DirEntry};
use portable_pty::CommandBuilder;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static SCRIPTS_EMBEDDED: Dir<'_> = crate::embedded_scripts!();
static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(0);

pub struct EmbeddedScriptManager {
    temp_dir: PathBuf,
    project_dir: PathBuf,
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
    fn unpacks_tracked_script_tree_for_relative_dependencies() {
        let manager = EmbeddedScriptManager::init().expect("initialize script manager");

        for path in [
            "st-iso.sh",
            "common.sh",
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
}
