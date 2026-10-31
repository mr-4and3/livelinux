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

mod script_manager;

use portable_pty::{CommandBuilder, PtySize, native_pty_system};
use script_manager::EmbeddedScriptManager;
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
    script_manager: Arc<EmbeddedScriptManager>,

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

impl ShellGuiApp {
    fn new(script_manager: Arc<EmbeddedScriptManager>) -> Self {
        Self {
            script_manager,
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

    fn append_output(&self, text: &str) {
        match self.console.lock() {
            Ok(mut console) => console.parser.process(text.as_bytes()),
            Err(error) => eprintln!("Failed to lock console: {error}"),
        }
    }

    fn clear_terminal(&self) {
        match self.console.lock() {
            Ok(mut console) => {
                console.parser = vt100::Parser::new(24, 80, 10_000);
            }
            Err(error) => eprintln!("Failed to lock console while clearing: {error}"),
        }
    }

    fn terminal_lines(&self) -> Result<Vec<String>, String> {
        let mut console = self
            .console
            .lock()
            .map_err(|error| format!("Failed to lock terminal state: {error}"))?;
        let screen = console.parser.screen_mut();
        let previous_scrollback = screen.scrollback();
        screen.set_scrollback(usize::MAX);
        let scrollback_len = screen.scrollback();
        let (rows, cols) = screen.size();
        let mut lines = Vec::with_capacity(scrollback_len + usize::from(rows));

        for offset in (0..=scrollback_len).rev() {
            screen.set_scrollback(offset);
            lines.push(
                screen
                    .rows(0, cols)
                    .next()
                    .unwrap_or_default()
                    .trim_end()
                    .to_owned(),
            );
        }

        screen.set_scrollback(0);
        lines.extend(
            screen
                .rows(0, cols)
                .skip(1)
                .map(|line| line.trim_end().to_owned()),
        );
        screen.set_scrollback(previous_scrollback);
        while lines.last().is_some_and(String::is_empty) {
            lines.pop();
        }

        Ok(lines)
    }

    fn run_command(&self, ctx: &egui::Context, cmd: &str, args: Vec<&str>) {
        let display = format!("{} {}", cmd, args.join(" "));
        let mut command = CommandBuilder::new(cmd);
        command.args(args);
        self.run_command_builder(ctx, command, &display);
    }

    fn run_command_builder(&self, ctx: &egui::Context, command: CommandBuilder, display: &str) {
        match self.console.lock() {
            Ok(mut console) if !console.active => {
                console.active = true;
                console.writer = None;
                console
                    .parser
                    .process(format!("\r\n$ {display}\r\n").as_bytes());
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
                                let mut args = Vec::new();
                                if !self.path_to_iso.is_empty() {
                                    args.extend(["--iso".to_owned(), self.path_to_iso.clone()]);
                                }
                                if !self.work_directory.is_empty() {
                                    args.extend([
                                        "--workdir".to_owned(),
                                        self.work_directory.clone(),
                                    ]);
                                }
                                if !self.custom_iso.is_empty() {
                                    args.extend([
                                        "--iso-output".to_owned(),
                                        self.custom_iso.clone(),
                                    ]);
                                }
                                args.push("extract".to_owned());

                                match self.script_manager.prepare_command("st-iso.sh", &args) {
                                    Ok(command) => {
                                        self.run_command_builder(ctx, command, "st-iso.sh extract")
                                    }
                                    Err(error) => self.append_output(&format!(
                                        "\r\nFailed to prepare embedded ISO script: {error}\r\n"
                                    )),
                                }
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
            ui.horizontal(|ui| {
                ui.heading("Terminal");
                if ui.button("Clear").clicked() {
                    self.clear_terminal();
                }
            });
            ui.separator();

            let lines = match self.terminal_lines() {
                Ok(lines) => lines,
                Err(error) => vec![error],
            };
            let font = egui::TextStyle::Monospace.resolve(ui.style());
            let row_height = ui.text_style_height(&egui::TextStyle::Monospace);

            egui::ScrollArea::vertical()
                .id_source("terminal_scroll")
                .auto_shrink([false, false])
                .stick_to_bottom(true)
                .show(ui, |ui| {
                    let content_height =
                        (lines.len() as f32 * row_height + 16.0).max(ui.available_height());
                    let (rect, response) = ui.allocate_exact_size(
                        egui::vec2(ui.available_width(), content_height),
                        egui::Sense::click(),
                    );
                    if response.clicked() {
                        response.request_focus();
                    }
                    ui.painter()
                        .rect_filled(rect, 2.0, egui::Color32::from_rgb(20, 20, 20));

                    for (row, line) in lines.iter().enumerate() {
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
                                egui::Event::Text(text) => {
                                    self.send_terminal_input(text.as_bytes())
                                }
                                egui::Event::Paste(text) => {
                                    self.send_terminal_input(text.as_bytes())
                                }
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
        });
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let native_options = eframe::NativeOptions::default();

    // Initialisiere the script manager
    let script_manager = Arc::new(EmbeddedScriptManager::init()?);

    eframe::run_native(
        "Safe Stick",
        native_options,
        Box::new(move |_cc| Ok(Box::new(ShellGuiApp::new(Arc::clone(&script_manager))))),
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_scroll_content_omits_unused_blank_rows_and_clear_keeps_process() {
        let manager = Arc::new(EmbeddedScriptManager::init().expect("initialize script manager"));
        let app = ShellGuiApp::new(manager);

        assert_eq!(
            app.terminal_lines().expect("read terminal lines"),
            vec!["Console initialized."]
        );

        {
            let mut console = app.console.lock().expect("lock console");
            console.active = true;
            console.parser.process(b"\r\nnew output");
        }
        app.clear_terminal();

        let console = app.console.lock().expect("lock console");
        assert!(console.active);
        assert_eq!(console.parser.screen().contents(), "");
    }

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
