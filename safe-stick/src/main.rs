// Rust GUI Template for Shell Command Frontend using `egui` and `eframe`
// To run this, add the following to your Cargo.toml:
// [dependencies]
// egui = "0.28"
// eframe = "0.28"
// portable-pty = "0.9"
// vt100 = "0.16"

use portable_pty::{CommandBuilder, PtySize, native_pty_system};
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};

struct ConsoleState {
    parser: vt100::Parser,
    writer: Option<Arc<Mutex<Box<dyn Write + Send>>>>,
    active: bool,
}

impl Default for ConsoleState {
    fn default() -> Self {
        let mut parser = vt100::Parser::new(24, 80, 10_000);
        parser.process(b"Console initialized.\r\n");
        Self {
            parser,
            writer: None,
            active: false,
        }
    }
}

enum TopTab {
    Iso,
    Usb,
    About,
}

struct ShellGuiApp {
    // Tab State
    current_tab: TopTab,

    // ISO Tab Fields
    path_to_iso: String,
    custom_iso: String,
    work_directory: String,
    customize_script: String,
    password_script: String,

    // USB Tab Fields
    usb_device: String,
    linux_size: String,
    encrypted_size: String,
    unencrypted_size: String,

    // Console / Shell State
    console: Arc<Mutex<ConsoleState>>,
}

impl Default for ShellGuiApp {
    fn default() -> Self {
        Self {
            current_tab: TopTab::Iso,
            path_to_iso: String::new(),
            custom_iso: String::new(),
            work_directory: String::new(),
            customize_script: String::new(),
            password_script: String::new(),
            usb_device: String::new(),
            linux_size: String::new(),
            encrypted_size: String::new(),
            unencrypted_size: String::new(),
            console: Arc::new(Mutex::new(ConsoleState::default())),
        }
    }
}

impl ShellGuiApp {
    fn append_output(&self, text: &str) {
        match self.console.lock() {
            Ok(mut console) => console.parser.process(text.as_bytes()),
            Err(error) => eprintln!("Failed to lock console: {error}"),
        }
    }

    fn run_command(&self, ctx: &egui::Context, cmd: &str, args: Vec<&str>) {
        match self.console.lock() {
            Ok(mut console) if !console.active => {
                console.active = true;
                console.writer = None;
                console
                    .parser
                    .process(format!("\r\n$ {} {}\r\n", cmd, args.join(" ")).as_bytes());
            }
            Ok(_) => {
                self.append_output("\r\nA process is already running.\r\n");
                return;
            }
            Err(error) => {
                eprintln!("Failed to lock console: {error}");
                return;
            }
        }

        let cmd = cmd.to_string();
        let args: Vec<String> = args.into_iter().map(|s| s.to_string()).collect();
        let console = Arc::clone(&self.console);
        let ctx = ctx.clone();

        std::thread::spawn(move || {
            let pty_system = native_pty_system();
            let pair = match pty_system.openpty(PtySize {
                rows: 24,
                cols: 80,
                pixel_width: 0,
                pixel_height: 0,
            }) {
                Ok(pair) => pair,
                Err(error) => {
                    finish_process(
                        &console,
                        &format!("\r\nFailed to open terminal: {error}\r\n"),
                    );
                    ctx.request_repaint();
                    return;
                }
            };

            let mut command = CommandBuilder::new(&cmd);
            command.args(args);
            let mut child = match pair.slave.spawn_command(command) {
                Ok(child) => child,
                Err(error) => {
                    finish_process(
                        &console,
                        &format!("\r\nFailed to start command: {error}\r\n"),
                    );
                    ctx.request_repaint();
                    return;
                }
            };
            drop(pair.slave);

            let writer = match pair.master.take_writer() {
                Ok(writer) => Arc::new(Mutex::new(writer)),
                Err(error) => {
                    finish_process(
                        &console,
                        &format!("\r\nFailed to open terminal input: {error}\r\n"),
                    );
                    ctx.request_repaint();
                    return;
                }
            };

            match console.lock() {
                Ok(mut state) => state.writer = Some(Arc::clone(&writer)),
                Err(error) => {
                    finish_process(
                        &console,
                        &format!("\r\nFailed to lock console: {error}\r\n"),
                    );
                    ctx.request_repaint();
                    return;
                }
            }

            let mut reader = match pair.master.try_clone_reader() {
                Ok(reader) => reader,
                Err(error) => {
                    finish_process(
                        &console,
                        &format!("\r\nFailed to open terminal output: {error}\r\n"),
                    );
                    ctx.request_repaint();
                    return;
                }
            };
            let reader_console = Arc::clone(&console);
            let reader_ctx = ctx.clone();
            let reader_thread = std::thread::spawn(move || {
                let mut buffer = [0; 4096];
                loop {
                    match reader.read(&mut buffer) {
                        Ok(0) => break,
                        Ok(bytes_read) => match reader_console.lock() {
                            Ok(mut state) => state.parser.process(&buffer[..bytes_read]),
                            Err(error) => {
                                eprintln!("Failed to lock terminal output: {error}");
                                break;
                            }
                        },
                        Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                        Err(error) => {
                            if let Ok(mut state) = reader_console.lock() {
                                state.parser.process(
                                    format!("\r\nFailed to read terminal output: {error}\r\n")
                                        .as_bytes(),
                                );
                            }
                            break;
                        }
                    }
                    reader_ctx.request_repaint();
                }
            });

            let exit_message = match child.wait() {
                Ok(status) => format!("\r\n[Process exited: {status}]\r\n"),
                Err(error) => format!("\r\nFailed while waiting for command: {error}\r\n"),
            };
            if reader_thread.join().is_err() {
                finish_process(
                    &console,
                    "\r\nTerminal output reader stopped unexpectedly.\r\n",
                );
            }
            finish_process(&console, &exit_message);
            ctx.request_repaint();
        });
    }

    fn send_terminal_input(&self, input: &[u8]) {
        let writer = match self.console.lock() {
            Ok(state) if state.active => state.writer.clone(),
            Ok(_) => None,
            Err(error) => {
                eprintln!("Failed to lock console: {error}");
                return;
            }
        };
        if let Some(writer) = writer {
            match writer.lock() {
                Ok(mut writer) => {
                    if let Err(error) = writer.write_all(input).and_then(|()| writer.flush()) {
                        self.append_output(&format!(
                            "\r\nFailed to send input to terminal: {error}\r\n"
                        ));
                    }
                }
                Err(error) => eprintln!("Failed to lock terminal input: {error}"),
            }
        }
    }
}

fn finish_process(console: &Arc<Mutex<ConsoleState>>, message: &str) {
    match console.lock() {
        Ok(mut state) => {
            state.parser.process(message.as_bytes());
            state.writer = None;
            state.active = false;
        }
        Err(error) => eprintln!("Failed to update terminal state: {error}"),
    }
}

fn terminal_key_bytes(key: egui::Key, modifiers: egui::Modifiers) -> Option<Vec<u8>> {
    if modifiers.ctrl {
        return match key {
            egui::Key::C => Some(vec![0x03]),
            egui::Key::D => Some(vec![0x04]),
            egui::Key::Z => Some(vec![0x1a]),
            egui::Key::L => Some(vec![0x0c]),
            _ => None,
        };
    }
    let bytes = match key {
        egui::Key::Enter => b"\r".as_slice(),
        egui::Key::Tab => b"\t",
        egui::Key::Backspace => b"\x7f",
        egui::Key::Escape => b"\x1b",
        egui::Key::ArrowUp => b"\x1b[A",
        egui::Key::ArrowDown => b"\x1b[B",
        egui::Key::ArrowRight => b"\x1b[C",
        egui::Key::ArrowLeft => b"\x1b[D",
        egui::Key::Home => b"\x1b[H",
        egui::Key::End => b"\x1b[F",
        egui::Key::Delete => b"\x1b[3~",
        egui::Key::PageUp => b"\x1b[5~",
        egui::Key::PageDown => b"\x1b[6~",
        _ => return None,
    };
    Some(bytes.to_vec())
}

impl eframe::App for ShellGuiApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if matches!(self.current_tab, TopTab::About) {
            egui::CentralPanel::default().show(ctx, |ui| {
                ui.horizontal(|ui| {
                    if ui
                        .selectable_label(matches!(self.current_tab, TopTab::Iso), "ISO")
                        .clicked()
                    {
                        self.current_tab = TopTab::Iso;
                    }
                    if ui
                        .selectable_label(matches!(self.current_tab, TopTab::Usb), "USB")
                        .clicked()
                    {
                        self.current_tab = TopTab::Usb;
                    }
                    if ui
                        .selectable_label(matches!(self.current_tab, TopTab::About), "About")
                        .clicked()
                    {
                        self.current_tab = TopTab::About;
                    }
                });
                ui.separator();
                ui.heading("Safe Stick");
                ui.label(format!("Version {}", env!("CARGO_PKG_VERSION")));
            });
            return;
        }

        egui::TopBottomPanel::top("top_panel")
            .resizable(true)
            .default_height(300.0)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    if ui
                        .selectable_label(matches!(self.current_tab, TopTab::Iso), "ISO")
                        .clicked()
                    {
                        self.current_tab = TopTab::Iso;
                    }
                    if ui
                        .selectable_label(matches!(self.current_tab, TopTab::Usb), "USB")
                        .clicked()
                    {
                        self.current_tab = TopTab::Usb;
                    }
                    if ui
                        .selectable_label(matches!(self.current_tab, TopTab::About), "About")
                        .clicked()
                    {
                        self.current_tab = TopTab::About;
                    }
                });

                ui.separator();

                match self.current_tab {
                    TopTab::Iso => {
                        egui::Grid::new("iso_grid")
                            .num_columns(2)
                            .spacing([40.0, 10.0])
                            .show(ui, |ui| {
                                ui.label("Path to ISO:");
                                ui.text_edit_singleline(&mut self.path_to_iso);
                                ui.end_row();

                                ui.label("Custom ISO:");
                                ui.text_edit_singleline(&mut self.custom_iso);
                                ui.end_row();

                                ui.label("Work Directory:");
                                ui.text_edit_singleline(&mut self.work_directory);
                                ui.end_row();

                                ui.label("Customize Script:");
                                ui.text_edit_singleline(&mut self.customize_script);
                                ui.end_row();

                                ui.label("Password Script:");
                                ui.text_edit_singleline(&mut self.password_script);
                                ui.end_row();
                            });

                        ui.add_space(15.0);

                        ui.horizontal(|ui| {
                            if ui.button("Extract").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Extracting ISO...", &self.path_to_iso],
                                );
                            }
                            if ui.button("Customize").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Running customize script...", &self.customize_script],
                                );
                            }
                            if ui.button("Shell").clicked() {
                                self.run_command(ctx, "sh", vec!["-i"]);
                            }
                            if ui.button("Make ISO").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Creating custom ISO at:", &self.custom_iso],
                                );
                            }
                            if ui.button("Clean").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Cleaning work directory...", &self.work_directory],
                                );
                            }
                            if ui.button("Set Password").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Setting password via script...", &self.password_script],
                                );
                            }
                        });
                    }
                    TopTab::Usb => {
                        egui::Grid::new("usb_grid")
                            .num_columns(2)
                            .spacing([40.0, 10.0])
                            .show(ui, |ui| {
                                ui.label("USB Device:");
                                ui.text_edit_singleline(&mut self.usb_device);
                                ui.end_row();

                                ui.label("Linux Size:");
                                ui.text_edit_singleline(&mut self.linux_size);
                                ui.end_row();

                                ui.label("Encrypted Size:");
                                ui.text_edit_singleline(&mut self.encrypted_size);
                                ui.end_row();

                                ui.label("Unencrypted Size:");
                                ui.text_edit_singleline(&mut self.unencrypted_size);
                                ui.end_row();
                            });

                        ui.add_space(15.0);

                        ui.horizontal(|ui| {
                            if ui.button("Make").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Writing to USB device:", &self.usb_device],
                                );
                            }
                            if ui.button("Update Linux").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Updating Linux partition size...", &self.linux_size],
                                );
                            }
                            if ui.button("Open Encrypted").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Unlocking encrypted container..."],
                                );
                            }
                            if ui.button("Close Encrypted").clicked() {
                                self.run_command(
                                    ctx,
                                    "echo",
                                    vec!["Locking encrypted container..."],
                                );
                            }
                        });
                    }
                    TopTab::About => {}
                }
            });

        // Bottom Panel: Terminal output and direct keyboard input
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("Terminal");
            let output_text = match self.console.lock() {
                Ok(console) => console.parser.screen().contents(),
                Err(error) => format!("Failed to lock terminal state: {error}"),
            };

            let (rect, response) =
                ui.allocate_exact_size(ui.available_size(), egui::Sense::click());
            if response.clicked() {
                response.request_focus();
            }
            ui.painter()
                .rect_filled(rect, 2.0, egui::Color32::from_rgb(20, 20, 20));
            let font = egui::TextStyle::Monospace.resolve(ui.style());
            let row_height = ui.text_style_height(&egui::TextStyle::Monospace);
            let scroll_delta = if response.hovered() {
                ui.input(|input| input.smooth_scroll_delta.y)
            } else {
                0.0
            };
            if scroll_delta != 0.0 {
                if let Ok(mut console) = self.console.lock() {
                    let current = console.parser.screen().scrollback() as i32;
                    let rows = (scroll_delta / row_height.max(1.0)).round() as i32;
                    console
                        .parser
                        .screen_mut()
                        .set_scrollback((current + rows).max(0) as usize);
                }
            }
            for (row, line) in output_text.lines().enumerate() {
                ui.painter().text(
                    egui::pos2(
                        rect.left() + 8.0,
                        rect.top() + 8.0 + row as f32 * row_height,
                    ),
                    egui::Align2::LEFT_TOP,
                    line,
                    font.clone(),
                    egui::Color32::LIGHT_GRAY,
                );
            }

            if response.has_focus() || response.clicked() {
                let events = ui.input(|input| input.events.clone());
                for event in events {
                    match event {
                        egui::Event::Text(text) => self.send_terminal_input(text.as_bytes()),
                        egui::Event::Paste(text) => self.send_terminal_input(text.as_bytes()),
                        egui::Event::Key {
                            key,
                            pressed: true,
                            modifiers,
                            ..
                        } => {
                            if let Some(bytes) = terminal_key_bytes(key, modifiers) {
                                self.send_terminal_input(&bytes);
                            }
                        }
                        _ => {}
                    }
                }
            }
        });
    }
}

fn main() -> eframe::Result<()> {
    let native_options = eframe::NativeOptions::default();
    eframe::run_native(
        "Shell Command Frontend",
        native_options,
        Box::new(|_cc| Ok(Box::new(ShellGuiApp::default()))),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

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
