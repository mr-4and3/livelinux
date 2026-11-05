use crate::config::expand_home_path;
use crate::config_manager::{ConfigManager, ConfigValue};
use crate::script_manager::EmbeddedScriptManager;
use portable_pty::{ChildKiller, CommandBuilder, PtySize, native_pty_system};
use std::io::{Read, Write};
use std::path::Path;
use std::sync::{Arc, Mutex};

// Console state to manage terminal output and input
struct ConsoleState {
    parser: vt100::Parser,
    writer: Option<Arc<Mutex<Box<dyn Write + Send>>>>,
    active: bool,
    active_function: Option<String>,
    killer: Option<Box<dyn ChildKiller + Send + Sync>>,
    abort_requested: bool,
}

// Implement Default for ConsoleState to initialize the terminal parser
impl Default for ConsoleState {
    fn default() -> Self {
        let mut parser = vt100::Parser::new(24, 80, 10_000);
        parser.process(b"Console initialized.\r\n");
        Self {
            parser,
            writer: None,
            active: false,
            active_function: None,
            killer: None,
            abort_requested: false,
        }
    }
}

// Enum to represent the top-level tabs in the GUI
enum TopTab {
    Iso,
    Usb,
    About,
}

// Main application struct for the shell GUI
pub struct ShellGuiApp {
    script_manager: Arc<EmbeddedScriptManager>,
    config: ConfigManager,

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

    // Infos states
    extract_info: String,
    customize_info: String,
    shell_info: String,
    make_iso_info: String,
    clean_info: String,
    config_message: Option<String>,
}

// Implement methods for the ShellGuiApp,
impl ShellGuiApp {
    // Constructor to create a new instance of ShellGuiApp with the provided script manager and configuration
    pub fn new(script_manager: Arc<EmbeddedScriptManager>, config: ConfigManager) -> Self {
        let mut app = Self {
            script_manager,
            config,
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
            extract_info: String::new(),
            customize_info: String::new(),
            shell_info: String::new(),
            make_iso_info: String::new(),
            clean_info: String::new(),
            config_message: None,
        };
        app.reload_settings_from_config();
        app
    }

    fn reload_settings_from_config(&mut self) {
        let string_value = |key| match self.config.get(key) {
            Some(ConfigValue::String(value)) => value.clone(),
            _ => String::new(),
        };
        let integer_value = |key| match self.config.get(key) {
            Some(ConfigValue::Integer(value)) => value.to_string(),
            _ => String::new(),
        };

        self.path_to_iso = expand_home_path(&string_value("path_to_iso"));
        self.custom_iso = expand_home_path(&string_value("path_to_custom_iso"));
        self.work_directory = expand_home_path(&string_value("work_dir"));
        self.customize_script = expand_home_path(&string_value("customize_script"));
        self.password_script = expand_home_path(&string_value("passwort_script"));
        self.usb_device = string_value("usb_device");
        self.linux_size = integer_value("linux_size_gb");
        self.encrypted_size = integer_value("encrypt_size_gb");
        self.unencrypted_size = integer_value("none_encrypt_size_gb");
    }

    fn sync_to_config(&mut self) {
        let parse_integer = |value: &str, fallback: i64| match value.trim().parse::<i64>() {
            Ok(parsed) => parsed,
            Err(_) => fallback,
        };

        self.config
            .set("path_to_iso", ConfigValue::String(self.path_to_iso.clone()));
        self.config.set(
            "path_to_custom_iso",
            ConfigValue::String(self.custom_iso.clone()),
        );
        self.config
            .set("work_dir", ConfigValue::String(self.work_directory.clone()));
        self.config.set(
            "customize_script",
            ConfigValue::String(self.customize_script.clone()),
        );
        self.config.set(
            "passwort_script",
            ConfigValue::String(self.password_script.clone()),
        );
        self.config
            .set("usb_device", ConfigValue::String(self.usb_device.clone()));
        self.config.set(
            "linux_size_gb",
            ConfigValue::Integer(parse_integer(&self.linux_size, 5)),
        );
        self.config.set(
            "encrypt_size_gb",
            ConfigValue::Integer(parse_integer(&self.encrypted_size, 1)),
        );
        self.config.set(
            "none_encrypt_size_gb",
            ConfigValue::Integer(parse_integer(&self.unencrypted_size, 1)),
        );
    }

    // Append text to the terminal output, processing it through the vt100 parser
    fn append_output(&self, text: &str) {
        match self.console.lock() {
            Ok(mut console) => console.parser.process(text.as_bytes()),
            Err(error) => eprintln!("Failed to lock console: {error}"),
        }
    }

    // Clear the terminal output by resetting the vt100 parser
    fn clear_terminal(&self) {
        match self.console.lock() {
            Ok(mut console) => {
                console.parser = vt100::Parser::new(24, 80, 10_000);
            }
            Err(error) => eprintln!("Failed to lock console while clearing: {error}"),
        }
    }

    // Retrieve the current lines of terminal output, including scrollback, and return them as a vector of strings
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

    // Run a command with the specified arguments, displaying the command in the terminal output
    fn run_command(&self, ctx: &egui::Context, cmd: &str, args: Vec<&str>) {
        let display = format!("{} {}", cmd, args.join(" "));
        let mut command = CommandBuilder::new(cmd);
        command.args(args);
        self.run_command_builder(ctx, command, &display);
    }

    fn process_status(&self) -> (bool, Option<String>) {
        match self.console.lock() {
            Ok(console) => (console.active, console.active_function.clone()),
            Err(error) => {
                eprintln!("Failed to read process state: {error}");
                (true, Some("process state unavailable".to_string()))
            }
        }
    }

    fn abort_process(&self) {
        request_process_abort(&self.console);
    }

    // Run a command using a CommandBuilder, handling terminal output and input through a separate thread
    fn run_command_builder(&self, ctx: &egui::Context, command: CommandBuilder, display: &str) {
        match self.console.lock() {
            Ok(mut console) if !console.active => {
                console.active = true;
                console.active_function = Some(display.to_string());
                console.killer = None;
                console.abort_requested = false;
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

            let abort_requested = match console.lock() {
                Ok(mut state) => {
                    state.killer = Some(child.clone_killer());
                    state.abort_requested
                }
                Err(error) => {
                    eprintln!("Failed to store process abort handle: {error}");
                    false
                }
            };
            if abort_requested {
                request_process_abort(&console);
            }

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

    // Send input to the terminal, writing it to the PTY writer if available
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

// Extract function
impl ShellGuiApp {
    // Check if the conditions for extracting the ISO are met, returning true if all conditions are satisfied
    fn check_extract_conditions(&mut self) -> bool {
        self.extract_info = if self.path_to_iso.trim().is_empty() {
            "Path to ISO is empty.".to_string()
        } else if self.work_directory.trim().is_empty() {
            "Work directory is empty.".to_string()
        } else {
            match std::fs::metadata(&self.path_to_iso) {
                Ok(metadata) if metadata.is_file() => String::new(),
                Ok(_) => "ISO path is not a file.".to_string(),
                Err(_) => "ISO file not found.".to_string(),
            }
        };

        self.extract_info.is_empty()
    }

    // Extract the ISO using the specified path and work directory, preparing the command and running it in a separate thread
    fn extract_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_extract_conditions() {
            return Err(self.extract_info.clone());
        }

        let mut args = Vec::new();
        if !self.path_to_iso.is_empty() {
            args.extend(["--iso".to_owned(), self.path_to_iso.clone()]);
        }

        if !self.work_directory.is_empty() {
            args.extend(["--workdir".to_owned(), self.work_directory.clone()]);
        }
        if !self.custom_iso.is_empty() {
            args.extend(["--iso-output".to_owned(), self.custom_iso.clone()]);
        }

        args.push("extract".to_owned());

        let display = std::iter::once("st-iso.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-iso.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to extract ISO script: {error}"));
            }
        }
        Ok(())
    }
}

// customize function
impl ShellGuiApp {
    fn check_customize_conditions(&mut self) -> bool {
        self.customize_info = if self.work_directory.trim().is_empty() {
            "Work directory is empty.".to_string()
        } else {
            let work_directory_info = match std::fs::metadata(&self.work_directory) {
                Ok(metadata) if metadata.is_dir() => String::new(),
                Ok(_) => "Work directory path is not a directory.".to_string(),
                Err(_) => "Work directory not found.".to_string(),
            };

            if !work_directory_info.is_empty() {
                work_directory_info
            } else if !self.customize_script.trim().is_empty() {
                match std::fs::metadata(&self.customize_script) {
                    Ok(metadata) if metadata.is_file() => String::new(),
                    Ok(_) => "Customize script path is not a file.".to_string(),
                    Err(_) => "Customize script file not found.".to_string(),
                }
            } else {
                String::new()
            }
        };
        self.customize_info.is_empty()
    }

    fn customize_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_customize_conditions() {
            return Err(self.customize_info.clone());
        }

        let mut args = Vec::new();
        if !self.work_directory.is_empty() {
            args.extend(["--workdir".to_owned(), self.work_directory.clone()]);
        }
        if !self.customize_script.is_empty() {
            args.extend([
                "--customize-script".to_owned(),
                self.customize_script.clone(),
            ]);
        }

        args.push("customize".to_owned());

        let display = std::iter::once("st-iso.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-iso.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to start customize script: {error}"));
            }
        }
        Ok(())
    }
}

// shell function
impl ShellGuiApp {
    fn check_shell_conditions(&mut self) -> bool {
        self.shell_info = if self.work_directory.trim().is_empty() {
            "Work directory is empty.".to_string()
        } else {
            let work_directory_info = match std::fs::metadata(&self.work_directory) {
                Ok(metadata) if metadata.is_dir() => String::new(),
                Ok(_) => "Work directory path is not a directory.".to_string(),
                Err(_) => "Work directory not found.".to_string(),
            };

            if !work_directory_info.is_empty() {
                work_directory_info
            } else {
                String::new()
            }
        };
        self.shell_info.is_empty()
    }

    fn shell_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_shell_conditions() {
            return Err(self.shell_info.clone());
        }

        let mut args = Vec::new();
        if !self.work_directory.is_empty() {
            args.extend(["--workdir".to_owned(), self.work_directory.clone()]);
        }

        args.push("shell".to_owned());

        let display = std::iter::once("st-iso.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-iso.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to start shell script: {error}"));
            }
        }
        Ok(())
    }
}

// Make ISO function
impl ShellGuiApp {
    // Check if the conditions for making the ISO are met, returning true if all conditions are satisfied
    fn check_make_iso_conditions(&mut self) -> bool {
        self.make_iso_info = if self.custom_iso.trim().is_empty() {
            "Custom ISO path is empty.".to_string()
        } else if self.work_directory.trim().is_empty() {
            "Work directory is empty.".to_string()
        } else {
            match std::fs::metadata(&self.custom_iso) {
                Ok(metadata) if metadata.is_file() => String::new(),
                Ok(_) => "Custom ISO path is not a file.".to_string(),
                Err(_) => "Custom ISO file not found.".to_string(),
            }
        };

        self.make_iso_info.is_empty()
    }

    fn make_iso_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_make_iso_conditions() {
            return Err(self.make_iso_info.clone());
        }

        let mut args = Vec::new();
        if !self.custom_iso.is_empty() {
            args.extend(["--iso-output".to_owned(), self.custom_iso.clone()]);
        }

        if !self.work_directory.is_empty() {
            args.extend(["--workdir".to_owned(), self.work_directory.clone()]);
        }

        args.push("make-iso".to_owned());

        let display = std::iter::once("st-iso.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-iso.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to prepare embedded ISO script: {error}"));
            }
        }
        Ok(())
    }
}

// clean function
impl ShellGuiApp {
    fn check_clean_conditions(&mut self) -> bool {
        self.clean_info = if self.work_directory.trim().is_empty() {
            "Work directory is empty.".to_string()
        } else {
            let work_directory_info = match std::fs::metadata(&self.work_directory) {
                Ok(metadata) if metadata.is_dir() => String::new(),
                Ok(_) => "Work directory path is not a directory.".to_string(),
                Err(_) => "Work directory not found.".to_string(),
            };

            if !work_directory_info.is_empty() {
                work_directory_info
            } else {
                String::new()
            }
        };
        self.clean_info.is_empty()
    }

    fn clean_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_clean_conditions() {
            return Err(self.clean_info.clone());
        }

        let mut args = Vec::new();
        if !self.work_directory.is_empty() {
            args.extend(["--workdir".to_owned(), self.work_directory.clone()]);
        }

        args.push("clean".to_owned());

        let display = std::iter::once("st-iso.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-iso.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to start clean script: {error}"));
            }
        }
        Ok(())
    }
}

// Reset configuration to default values
impl ShellGuiApp {
    fn reset_config_to_defaults(&mut self) {
        match self.config.reset_to_defaults() {
            Ok(()) => {
                self.reload_settings_from_config();
                self.extract_info.clear();
                self.make_iso_info.clear();
                self.config_message = Some("Configuration reset to default values.".to_string());
            }
            Err(error) => {
                self.config_message = Some(format!("Failed to reset configuration: {error}"));
            }
        }
    }
}

fn format_command_argument(argument: &str) -> String {
    if !argument.is_empty()
        && argument
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "/._-:=+".contains(character))
    {
        argument.to_owned()
    } else {
        format!("'{}'", argument.replace('\'', "'\\''"))
    }
}

// Implement the eframe::App trait for ShellGuiApp, defining the update method to handle GUI rendering and user interactions
impl eframe::App for ShellGuiApp {
    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        self.sync_to_config();
        if let Err(error) = self.config.save() {
            eprintln!("Failed to save configuration on exit: {error}");
        }
    }

    // Update the GUI, handling user interactions and rendering the appropriate content based on the current tab
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        let (process_active, active_function) = self.process_status();

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
                if ui
                    .add_enabled(!process_active, egui::Button::new("Default"))
                    .clicked()
                {
                    self.reset_config_to_defaults();
                }
                if let Some(message) = &self.config_message {
                    ui.label(message);
                }
            });
            return;
        }

        // Top Panel: Tabs and controls for ISO and USB operations
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

                // Display the appropriate content based on the current tab selection
                match self.current_tab {
                    TopTab::Iso => {
                        ui.add_enabled_ui(!process_active, |ui| {
                            egui::Grid::new("iso_grid")
                                .num_columns(2)
                                .spacing([40.0, 10.0])
                                .show(ui, |ui| {
                                    path_input(ui, "Path to ISO:", &mut self.path_to_iso, false);
                                    path_input(ui, "Custom ISO:", &mut self.custom_iso, false);
                                    path_input(
                                        ui,
                                        "Work Directory:",
                                        &mut self.work_directory,
                                        true,
                                    );
                                    path_input(
                                        ui,
                                        "Customize Script:",
                                        &mut self.customize_script,
                                        false,
                                    );
                                    path_input(
                                        ui,
                                        "Password Script:",
                                        &mut self.password_script,
                                        false,
                                    );
                                });

                            ui.add_space(15.0);

                            ui.horizontal(|ui| {
                                let check_extract = self.check_extract_conditions();
                                let extract_button = ui
                                    .add_enabled(check_extract, egui::Button::new("Extract"))
                                    .on_disabled_hover_text(self.extract_info.clone());

                                // Handle button clicks for extracting, customizing, and shell operations
                                if extract_button.clicked() {
                                    if let Err(error) = self.extract_function(ctx) {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    }
                                }

                                let check_customize = self.check_customize_conditions();
                                let customize_button = ui
                                    .add_enabled(check_customize, egui::Button::new("Customize"))
                                    .on_disabled_hover_text(self.customize_info.clone());

                                if customize_button.clicked() {
                                    if let Err(error) = self.customize_function(ctx) {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    }
                                }

                                let check_shell = self.check_shell_conditions();
                                let shell_button = ui
                                    .add_enabled(check_shell, egui::Button::new("Shell"))
                                    .on_disabled_hover_text(self.shell_info.clone());

                                if shell_button.clicked() {
                                    if let Err(error) = self.shell_function(ctx) {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    }
                                }

                                let check_make_iso = self.check_make_iso_conditions();
                                let make_iso_button = ui
                                    .add_enabled(check_make_iso, egui::Button::new("Make ISO"))
                                    .on_disabled_hover_text(self.make_iso_info.clone());

                                if make_iso_button.clicked() {
                                    self.make_iso_function(ctx).unwrap_or_else(|error| {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    });
                                }

                                let check_clean = self.check_clean_conditions();
                                let clean_button = ui
                                    .add_enabled(check_clean, egui::Button::new("Clean"))
                                    .on_disabled_hover_text(self.clean_info.clone());

                                if clean_button.clicked() {
                                    self.clean_function(ctx).unwrap_or_else(|error| {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    });
                                }

                                if ui.button("Set Password").clicked() {
                                    self.run_command(
                                        ctx,
                                        "echo",
                                        vec![
                                            "Setting password via script...",
                                            &self.password_script,
                                        ],
                                    );
                                }
                            });
                        });

                        ui.horizontal(|ui| {
                            if abort_button(ui, process_active, active_function.as_deref()) {
                                self.abort_process();
                            }
                            if ui
                                .add_enabled(!process_active, egui::Button::new("Clear"))
                                .clicked()
                            {
                                self.clear_terminal();
                            }
                        });
                    }
                    TopTab::Usb => {
                        ui.add_enabled_ui(!process_active, |ui| {
                            egui::Grid::new("usb_grid")
                                .num_columns(2)
                                .spacing([40.0, 10.0])
                                .show(ui, |ui| {
                                    path_input(ui, "USB Device:", &mut self.usb_device, false);

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
                        });

                        ui.horizontal(|ui| {
                            if abort_button(ui, process_active, active_function.as_deref()) {
                                self.abort_process();
                            }
                            if ui
                                .add_enabled(!process_active, egui::Button::new("Clear"))
                                .clicked()
                            {
                                self.clear_terminal();
                            }
                        });
                    }
                    TopTab::About => {}
                }
            });

        // Bottom Panel: selectable terminal output and direct keyboard input
        egui::CentralPanel::default().show(ctx, |ui| {
            let lines = match self.terminal_lines() {
                Ok(lines) => lines,
                Err(error) => vec![error],
            };
            let text = lines.join("\n");

            egui::ScrollArea::vertical()
                .id_source("terminal_scroll")
                .auto_shrink([false, false])
                .stick_to_bottom(true)
                .show(ui, |ui| {
                    egui::Frame::none()
                        .fill(egui::Color32::from_rgb(20, 20, 20))
                        .inner_margin(8.0)
                        .show(ui, |ui| {
                            ui.set_min_width(ui.available_width());
                            ui.set_min_height(ui.available_height());
                            let response = ui.add(
                                egui::Label::new(
                                    egui::RichText::new(text)
                                        .monospace()
                                        .color(egui::Color32::LIGHT_GRAY),
                                )
                                .selectable(true)
                                .sense(egui::Sense::click()),
                            );
                            if response.clicked() {
                                response.request_focus();
                            }
                            if response.has_focus() {
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
                                            key: egui::Key::C,
                                            pressed: true,
                                            modifiers,
                                            ..
                                        } if modifiers.ctrl => {}
                                        egui::Event::Key {
                                            key,
                                            pressed: true,
                                            modifiers,
                                            ..
                                        } => {
                                            if let Some(bytes) = terminal_key_bytes(key, modifiers)
                                            {
                                                self.send_terminal_input(&bytes);
                                            }
                                        }
                                        _ => {}
                                    }
                                }
                            }
                        });
                });
        });
    }
}

// Request to abort the currently running process, if any, by signaling the child process to terminate
fn request_process_abort(console: &Arc<Mutex<ConsoleState>>) {
    match console.lock() {
        Ok(mut state) if state.active => {
            state.abort_requested = true;
            let result = if let Some(killer) = state.killer.as_mut() {
                Some(killer.kill())
            } else {
                None
            };

            match result {
                Some(Ok(())) => state.parser.process(b"\r\nAbort requested.\r\n"),
                Some(Err(error)) => state
                    .parser
                    .process(format!("\r\nFailed to abort process: {error}\r\n").as_bytes()),
                None => state
                    .parser
                    .process(b"\r\nAbort requested; waiting for process startup.\r\n"),
            }
        }
        Ok(_) => {}
        Err(error) => eprintln!("Failed to abort process: {error}"),
    }
}

// Helper function to finish a process, updating the console state and marking it as inactive
fn finish_process(console: &Arc<Mutex<ConsoleState>>, message: &str) {
    match console.lock() {
        Ok(mut state) => {
            state.parser.process(message.as_bytes());
            state.writer = None;
            state.active = false;
            state.active_function = None;
            state.killer = None;
            state.abort_requested = false;
        }
        Err(error) => eprintln!("Failed to update terminal state: {error}"),
    }
}

// Convert egui key events to terminal input bytes, handling control key combinations and special keys
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

// Helper function to create a labeled path input field with a "Browse..." button
fn path_input(ui: &mut egui::Ui, label: &str, value: &mut String, directory: bool) {
    ui.label(label);
    ui.horizontal(|ui| {
        let response = ui.text_edit_singleline(value);
        if response.lost_focus() {
            *value = expand_home_path(value);
        }
        if ui.button("Browse...").clicked() {
            let current_path = Path::new(value);
            let initial_directory = if directory && current_path.is_dir() {
                Some(current_path)
            } else {
                current_path.parent().filter(|path| path.is_dir())
            };
            let dialog = match initial_directory {
                Some(initial_directory) => rfd::FileDialog::new().set_directory(initial_directory),
                None => rfd::FileDialog::new(),
            };

            let selected_path = if directory {
                dialog.pick_folder()
            } else {
                dialog.pick_file()
            };
            if let Some(selected_path) = selected_path {
                *value = selected_path.display().to_string();
            }
        }
    });
    ui.end_row();
}

// Helper function to create an "Abort" button that is enabled only when a process is active
fn abort_button(ui: &mut egui::Ui, process_active: bool, active_function: Option<&str>) -> bool {
    let response = ui.add_enabled(process_active, egui::Button::new("Abort"));
    let response = if process_active {
        response.on_hover_text(format!(
            "abort: {}",
            active_function.unwrap_or("unbekannte Funktion")
        ))
    } else {
        response.on_disabled_hover_text("Gerade läuft kein Prozess.")
    };
    response.clicked()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_enter_key_sends_carriage_return() {
        assert_eq!(
            terminal_key_bytes(egui::Key::Enter, egui::Modifiers::default()),
            Some(b"\r".to_vec())
        );
    }

    #[test]
    fn terminal_scroll_content_omits_unused_blank_rows_and_clear_keeps_process() {
        let manager = Arc::new(EmbeddedScriptManager::init().expect("initialize script manager"));
        let config_path = std::env::temp_dir().join(format!(
            "safe-stick-test-config-{}-{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        let config = ConfigManager::init(&config_path, crate::config::CONFIG_SCHEMA.to_vec());
        std::fs::remove_file(config_path).expect("remove temporary test config");
        let app = ShellGuiApp::new(manager, config);

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
}
