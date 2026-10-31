// Rust GUI Template for Shell Command Frontend using `egui` and `eframe`
// To run this, add the following to your Cargo.toml:
// [dependencies]
// egui = "0.28"
// eframe = "0.28"
// portable-pty = "0.9"
// vt100 = "0.16"

#[macro_export]
macro_rules! embedded_scripts {
    () => {
        include_dir::include_dir!("$OUT_DIR/embedded-scripts")
    };
}

mod app;
mod config;
mod config_manager;
mod script_manager;

use script_manager::EmbeddedScriptManager;
use std::sync::Arc;

use app::ShellGuiApp;

use config::CONFIG_SCHEMA;
use config_manager::ConfigManager;
use std::path::PathBuf;

fn load_config() -> Result<ConfigManager, Box<dyn std::error::Error>> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or("Die Umgebungsvariable HOME ist nicht gesetzt")?;

    let config_dir = home.join(".config").join("safe-stick");
    std::fs::create_dir_all(&config_dir)?;

    let path = config_dir.join("config.json");
    let config = ConfigManager::init(&path, CONFIG_SCHEMA.to_vec());

    Ok(config)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let native_options = eframe::NativeOptions::default();

    // Initialisiere the script manager
    let script_manager = Arc::new(EmbeddedScriptManager::init()?);

    let config = load_config()?;
    eframe::run_native(
        "Safe Stick",
        native_options,
        Box::new(move |_cc| {
            Ok(Box::new(ShellGuiApp::new(
                Arc::clone(&script_manager),
                config,
            )))
        }),
    )?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use portable_pty::{CommandBuilder, PtySize, native_pty_system};
    use std::io::{Read, Write};

    #[test]
    fn pseudo_terminal_accepts_interactive_input() {
        let pair = native_pty_system()
            .openpty(PtySize {
                rows: 24,
                cols: 80,
                pixel_width: 0,
                pixel_height: 0,
            })
            .expect("open pseudo-terminal");
        let mut command = CommandBuilder::new("sh");
        command.args(["-c", "read answer; printf 'received:%s\\n' \"$answer\""]);
        let mut child = pair
            .slave
            .spawn_command(command)
            .expect("start interactive command");
        drop(pair.slave);

        let mut writer = pair.master.take_writer().expect("get terminal writer");
        writer.write_all(b"hello\r").expect("send terminal input");
        writer.flush().expect("flush terminal input");

        let mut reader = pair.master.try_clone_reader().expect("get terminal reader");
        child.wait().expect("wait for interactive command");

        let mut output = Vec::new();
        let mut buffer = [0; 1024];
        loop {
            match reader.read(&mut buffer) {
                Ok(0) => break,
                Ok(bytes_read) => {
                    output.extend_from_slice(&buffer[..bytes_read]);
                    if output
                        .windows(b"received:hello".len())
                        .any(|window| window == b"received:hello")
                    {
                        break;
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }

        assert!(
            output
                .windows(b"received:hello".len())
                .any(|window| window == b"received:hello"),
            "expected the process to receive and echo the input; got: {}",
            String::from_utf8_lossy(&output)
        );
    }
}
