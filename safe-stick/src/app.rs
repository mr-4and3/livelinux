use crate::config::{KEY_EMBEDDED_SCRIPT, KEY_NONE, expand_home_path};
use crate::config_manager::{ConfigManager, ConfigValue};
use crate::script_manager::{EmbeddedScriptManager, UsbStick};
use egui_term::{BackendCommand, BackendSettings, PtyEvent, TerminalBackend, TerminalView};
use portable_pty::CommandBuilder;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, mpsc};

static NEXT_TERMINAL_ID: AtomicU64 = AtomicU64::new(1);
const MAX_TERMINAL_SESSIONS: usize = 10;

struct TerminalSession {
    id: u64,
    display: String,
    backend: TerminalBackend,
}

struct ConsoleState {
    active: bool,
    active_function: Option<String>,
    active_terminal_id: Option<u64>,
    notice: String,
}

impl Default for ConsoleState {
    fn default() -> Self {
        Self {
            active: false,
            active_function: None,
            active_terminal_id: None,
            notice: "Console initialized.".to_string(),
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
    path_custom_iso: String,
    work_directory: String,
    customize_script: String,
    password_script: String,

    // USB Tab Fields
    usb_device: String,
    usb_sticks: Vec<UsbStick>,
    is_safe_stick: bool,
    linux_size: String,
    encrypted_size: String,
    unencrypted_size: String,

    // Console / Shell State
    console: Arc<Mutex<ConsoleState>>,
    terminal_sessions: Vec<TerminalSession>,
    selected_terminal_id: Option<u64>,

    // Infos states
    path_to_iso_info: String,
    work_directory_info: String,
    custom_iso_info: String,
    customize_script_path_info: String,
    password_script_path_info: String,
    usb_device_info: String,

    extract_info: String,
    customize_info: String,
    shell_info: String,
    make_iso_info: String,
    clean_info: String,
    password_script_info: String,
    config_message: Option<String>,

    make_usb_info: String,
    update_linux_info: String,
    open_crypted_volume_info: String,
    close_crypted_volume_info: String,
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
            path_custom_iso: String::new(),
            work_directory: String::new(),
            customize_script: String::new(),
            password_script: String::new(),
            usb_device: String::new(),
            usb_sticks: Vec::new(),
            is_safe_stick: false,
            linux_size: String::new(),
            encrypted_size: String::new(),
            unencrypted_size: String::new(),
            console: Arc::new(Mutex::new(ConsoleState::default())),
            terminal_sessions: Vec::new(),
            selected_terminal_id: None,

            path_to_iso_info: String::new(),
            work_directory_info: String::new(),
            custom_iso_info: String::new(),
            customize_script_path_info: String::new(),
            password_script_path_info: String::new(),
            usb_device_info: String::new(),

            extract_info: String::new(),
            customize_info: String::new(),
            shell_info: String::new(),
            make_iso_info: String::new(),
            clean_info: String::new(),
            password_script_info: String::new(),
           
            make_usb_info: String::new(),
            update_linux_info: String::new(),
            open_crypted_volume_info: String::new(),
            close_crypted_volume_info: String::new(),
            config_message: None,
        };
        app.reload_settings_from_config();
        //app.refresh_usb_sticks();
        app
    }

    fn refresh_usb_sticks(&mut self) {
        match self.script_manager.list_usb_sticks() {
            Ok(sticks) => {
                self.usb_device_info = if sticks.is_empty() {
                    "No USB sticks found.".to_string()
                } else {
                    String::new()
                };
                self.usb_sticks = sticks;
            }
            Err(error) => {
                self.usb_device_info = format!("Failed to list USB sticks: {error}");
                self.usb_sticks.clear();
            }
        }
        self.check_selected_usb_stick();
    }

    fn check_selected_usb_stick(&mut self) {
        self.is_safe_stick = false;
        self.usb_device_info.clear();
        if self.usb_device.is_empty() || self.usb_device == KEY_NONE {
            self.usb_device_info =
                "Select a USB stick to check whether it is a Safe Stick.".to_string();
            return;
        }
        if !self.selected_usb_device_is_available() {
            self.usb_device_info =
                "Selected USB device is not currently detected. Refresh the device list."
                    .to_string();
            return;
        }

        match self.script_manager.is_safe_stick(&self.usb_device) {
            Ok(true) => {
                self.is_safe_stick = true;
                self.usb_device_info = "Selected USB device is a Safe Stick.".to_string();
            }
            Ok(false) => {
                self.usb_device_info = "Selected USB device is not a Safe Stick.".to_string();
            }
            Err(error) => {
                self.usb_device_info = format!("Safe Stick check failed: {error}");
            }
        }
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
        self.path_custom_iso = expand_home_path(&string_value("path_to_custom_iso"));
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
            ConfigValue::String(self.path_custom_iso.clone()),
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

    // Keep application-level messages visible alongside the terminal widget.
    fn append_output(&self, text: &str) {
        match self.console.lock() {
            Ok(mut console) => console.notice.push_str(text),
            Err(error) => eprintln!("Failed to lock console: {error}"),
        }
    }

    fn clear_terminal(&mut self) {
        match self.console.lock() {
            Ok(mut console) if !console.active => {
                self.terminal_sessions.clear();
                self.selected_terminal_id = None;
                console.notice.clear();
            }
            Ok(_) => {}
            Err(error) => eprintln!("Failed to lock console while clearing: {error}"),
        }
    }

    // Run a command with the specified arguments, displaying the command in the terminal output
    fn run_command(&mut self, ctx: &egui::Context, cmd: &str, args: Vec<&str>) {
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

    fn interrupt_process(&mut self) {
        let terminal_id = match self.console.lock() {
            Ok(console) => console.active_terminal_id,
            Err(error) => {
                eprintln!("Failed to read active terminal: {error}");
                return;
            }
        };
        if let Some(terminal) = self
            .terminal_sessions
            .iter_mut()
            .find(|session| Some(session.id) == terminal_id)
        {
            terminal
                .backend
                .process_command(BackendCommand::Write(vec![0x03]));
        }
    }

    // Run a command in the terminal backend and track its process exit event.
    fn run_command_builder(&mut self, ctx: &egui::Context, command: CommandBuilder, display: &str) {
        let settings = match backend_settings_from_command(command) {
            Ok(settings) => settings,
            Err(error) => {
                self.append_output(&format!(
                    "\r\nFailed to prepare terminal command: {error}\r\n"
                ));
                return;
            }
        };
        let terminal_id = NEXT_TERMINAL_ID.fetch_add(1, Ordering::Relaxed);
        let (event_sender, event_receiver) = mpsc::channel();

        match self.console.lock() {
            Ok(mut console) if !console.active => {
                console.notice = format!("$ {display}\r\n");
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

        let backend = match TerminalBackend::new(terminal_id, ctx.clone(), event_sender, settings) {
            Ok(backend) => backend,
            Err(error) => {
                match self.console.lock() {
                    Ok(mut console) => {
                        console.notice = format!("\r\nFailed to start command: {error}\r\n");
                    }
                    Err(lock_error) => {
                        eprintln!("Failed to update terminal state: {lock_error}");
                    }
                }
                return;
            }
        };

        match self.console.lock() {
            Ok(mut console) => {
                console.active = true;
                console.active_function = Some(display.to_string());
                console.active_terminal_id = Some(terminal_id);
            }
            Err(error) => {
                eprintln!("Failed to update process state: {error}");
                return;
            }
        }
        self.terminal_sessions.push(TerminalSession {
            id: terminal_id,
            display: display.to_string(),
            backend,
        });
        self.selected_terminal_id = Some(terminal_id);
        if self.terminal_sessions.len() > MAX_TERMINAL_SESSIONS {
            self.terminal_sessions.remove(0);
        }

        let console = Arc::clone(&self.console);
        let monitor_context = ctx.clone();
        std::thread::spawn(move || {
            loop {
                match event_receiver.recv() {
                    Ok((event_id, event)) if event_id == terminal_id => {
                        if matches!(event, PtyEvent::Exit) {
                            match console.lock() {
                                Ok(mut state) if state.active_terminal_id == Some(terminal_id) => {
                                    state.active = false;
                                    state.active_function = None;
                                    state.active_terminal_id = None;
                                    state.notice.push_str("\r\n[Process finished]\r\n");
                                }
                                Ok(_) => {}
                                Err(error) => {
                                    eprintln!("Failed to update terminal process state: {error}")
                                }
                            }
                            monitor_context.request_repaint();
                            break;
                        }
                    }
                    Ok(_) => {}
                    Err(error) => {
                        match console.lock() {
                            Ok(mut state) if state.active_terminal_id == Some(terminal_id) => {
                                state.active = false;
                                state.active_function = None;
                                state.active_terminal_id = None;
                                state.notice.push_str(&format!(
                                    "\r\nTerminal process events ended unexpectedly: {error}\r\n"
                                ));
                            }
                            Ok(_) => {}
                            Err(lock_error) => {
                                eprintln!("Failed to update terminal process state: {lock_error}");
                            }
                        }
                        monitor_context.request_repaint();
                        break;
                    }
                }
            }
        });
    }
}

// Extract function
impl ShellGuiApp {
    // Check if the conditions for extracting the ISO are met, returning true if all conditions are satisfied

    fn check_extract_conditions(&mut self) -> bool {
        if !self.check_path_to_iso() {
            self.extract_info = self.path_to_iso_info.clone();
            return false;
        }
        return true;
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
        if !self.path_custom_iso.is_empty() {
            args.extend(["--iso-output".to_owned(), self.path_custom_iso.clone()]);
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
        if !self.check_work_directory() {
            self.customize_info = self.work_directory_info.clone();
            return false;
        }
        self.check_path_to_customize_script();
        return true;
    }

    fn customize_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_customize_conditions() {
            return Err(self.customize_info.clone());
        }

        let mut args = Vec::new();
        if !self.work_directory.is_empty() {
            args.extend(["--workdir".to_owned(), self.work_directory.clone()]);
        }
        if is_custom_script(&self.customize_script) {
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
        if !self.check_work_directory() {
            self.shell_info = self.work_directory_info.clone();
            return false;
        }
        return true;
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
        if !self.check_work_directory() {
            self.make_iso_info = self.work_directory_info.clone();
            return false;
        }
        return true;
    }

    fn make_iso_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_make_iso_conditions() {
            return Err(self.make_iso_info.clone());
        }

        let mut args = Vec::new();
        if !self.path_custom_iso.is_empty() {
            args.extend(["--iso-output".to_owned(), self.path_custom_iso.clone()]);
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
        if !self.check_work_directory() {
            self.clean_info = self.work_directory_info.clone();
            return false;
        }

        self.check_path_to_customize_iso();
        return true;
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

// password function
impl ShellGuiApp {
    fn check_password_script(&mut self) -> bool {
        if !self.check_work_directory() {
            self.password_script_info = self.work_directory_info.clone();
            return false;
        }
        self.check_path_to_password_script();
        self.password_script_info.is_empty()
    }

    fn check_password_conditions(&mut self) -> bool {
        self.check_password_script()
    }

    fn password_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_password_conditions() {
            return Err(self.password_script_info.clone());
        }

        let mut args = Vec::new();
        if !self.work_directory.is_empty() {
            args.extend(["--workdir".to_owned(), self.work_directory.clone()]);
        }
        if !self.password_script.is_empty() {
            args.extend([
                "--password-script".to_owned(),
                self.password_script.clone(),
            ]);
        }

        args.push("passwd".to_owned());

        let display = std::iter::once("st-iso.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-iso.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to start password script: {error}"));
            }
        }
        Ok(())
    }
}

// make usb function
impl ShellGuiApp {
    fn selected_usb_device_is_available(&self) -> bool {
        is_usb_device_detected(&self.usb_device, &self.usb_sticks)
    }

    fn check_make_usb_conditions(&mut self) -> bool {
        self.make_usb_info = if self.usb_device.is_empty() {
            "USB device is empty.".to_string()
        } else if self.usb_device == KEY_NONE {
            "Invalid USB device.".to_string()
        } else if !self.selected_usb_device_is_available() {
            "Selected USB device is not currently detected. Refresh the device list."
                .to_string()
        } else if self.path_custom_iso.trim().is_empty() {
            "Path to custom ISO is empty.".to_string()
        } else if !Path::new(&self.path_custom_iso).is_file() {
            "Custom ISO file not found.".to_string()    
        } else {
            String::new()
        };

        self.make_usb_info.is_empty()
    }

    fn make_usb_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_make_usb_conditions() {
            return Err(self.make_usb_info.clone());
        }

        let mut args = Vec::new();

        if !self.usb_device.is_empty() {
            args.extend([
                "--usb-device".to_owned(),
                self.usb_device.clone(),
            ]);
        }

        args.push("all".to_owned());

        let display = std::iter::once("st-usb.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-usb.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to start USB script with 'all': {error}"));
            }
        }
        Ok(())
    }
}

// update linux function
impl ShellGuiApp {
    fn check_update_linux_conditions(&mut self) -> bool {
        self.update_linux_info = if self.usb_device.is_empty() {
            "USB device is empty.".to_string()
        } else if self.usb_device == KEY_NONE {
            "Invalid USB device.".to_string()
        } else if !self.selected_usb_device_is_available() {
            "Selected USB device is not currently detected. Refresh the device list."
                .to_string()
        } else if self.path_custom_iso.trim().is_empty() {
            "Path to custom ISO is empty.".to_string()
        } else if !Path::new(&self.path_custom_iso).is_file() {
            "Custom ISO file not found.".to_string()    
        } else {
            String::new()
        };

        self.update_linux_info.is_empty()
    }

    fn update_linux_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_update_linux_conditions() {
            return Err(self.update_linux_info.clone());
        }

        let mut args = Vec::new();

        if !self.usb_device.is_empty() {
            args.extend([
                "--usb-device".to_owned(),
                self.usb_device.clone(),
            ]);
        }

        args.push("update-linux".to_owned());

        let display = std::iter::once("st-usb.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-usb.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to start USB script with 'update-linux': {error}"));
            }
        }
        Ok(())
    }
}

// opencrypt function
impl ShellGuiApp {
    fn check_open_crypt_conditions(&mut self) -> bool {
        self.open_crypted_volume_info = if self.usb_device.is_empty() {
            "USB device is empty.".to_string()
        } else if self.usb_device == KEY_NONE {
            "Invalid USB device.".to_string()
        } else if !self.selected_usb_device_is_available() {
            "Selected USB device is not currently detected. Refresh the device list."
                .to_string()
        } else {
            String::new()
        };

        self.open_crypted_volume_info.is_empty()
    }

    fn open_crypt_function(&mut self, ctx: &egui::Context) -> Result<(), String> {
        if !self.check_open_crypt_conditions() {
            return Err(self.update_linux_info.clone());
        }

        let mut args = Vec::new();

        if !self.usb_device.is_empty() {
            args.extend([
                "--usb-device".to_owned(),
                self.usb_device.clone(),
            ]);
        }

        args.push("encrypt".to_owned());

        let display = std::iter::once("st-usb.sh".to_owned())
            .chain(args.iter().map(|arg| format_command_argument(arg)))
            .collect::<Vec<_>>()
            .join(" ");

        match self.script_manager.prepare_command("st-usb.sh", &args) {
            Ok(command) => {
                self.run_command_builder(ctx, command, &display);
            }
            Err(error) => {
                return Err(format!("Failed to start USB script with 'encrypt': {error}"));
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

// input checking functions
impl ShellGuiApp {
    fn check_path_to_iso(&mut self) -> bool {
        self.path_to_iso_info = if self.path_to_iso.trim().is_empty() {
            "Path to ISO is empty.".to_string()
        } else {
            match std::fs::metadata(&self.path_to_iso) {
                Ok(metadata) if metadata.is_file() => String::new(),
                Ok(_) => "ISO path is not a file.".to_string(),
                Err(_) => "ISO file not found.".to_string(),
            }
        };
        self.path_to_iso_info.is_empty()
    }

    fn check_work_directory(&mut self) -> bool {
        self.work_directory_info = if self.work_directory.trim().is_empty() {
            "Work directory is empty.".to_string()
        } else {
            match std::fs::metadata(&self.work_directory) {
                Ok(metadata) if metadata.is_dir() => String::new(),
                Ok(_) => "Work directory path is not a directory.".to_string(),
                Err(_) => "Work directory not found.".to_string(),
            }
        };
        self.work_directory_info.is_empty()
    }

    fn check_path_to_customize_iso(&mut self) -> bool {
        self.custom_iso_info = if self.path_custom_iso.trim().is_empty() {
            "Path to custom ISO is empty.".to_string()
        } else {
            match std::fs::metadata(&self.path_custom_iso) {
                Ok(metadata) if metadata.is_file() => String::new(),
                Ok(_) => "Customized ISO path is not a file.".to_string(),
                Err(_) => "Customized ISO not found.".to_string(),
            }
        };
        self.path_to_iso_info.is_empty()
    }


    fn check_path_to_customize_script(&mut self) -> bool {
        let customize_script_info = "No customize script, default is used".to_string();
        self.customize_script_path_info = if self.customize_script.trim().is_empty() {
            customize_script_info
        } else {
            match std::fs::metadata(&self.customize_script) {
                Ok(metadata) if metadata.is_file() => String::new(),
                Ok(_) => "Customize script path is not a file.".to_string(),
                Err(_) => "Customize script not found.".to_string(),
            }
        };
        self.customize_script_path_info.is_empty()
    }

    fn check_path_to_password_script(&mut self) -> bool {
        let password_script_info = "No password script, default is used".to_string();
        self.password_script_path_info = if self.password_script.trim().is_empty() {
            password_script_info
        } else {
            match std::fs::metadata(&self.password_script) {
                Ok(metadata) if metadata.is_file() => String::new(),
                Ok(_) => "Password script path is not a file.".to_string(),
                Err(_) => "Password script not found.".to_string(),
            }
        };
        self.password_script_path_info.is_empty()
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
                                    path_input(
                                        ui, "Path to ISO:", 
                                        &mut self.path_to_iso, 
                                        false, 
                                        self.path_to_iso_info.clone().as_str()
                                    );
                                    path_input(
                                        ui,
                                        "Custom ISO:",
                                        &mut self.path_custom_iso,
                                        false,
                                        self.custom_iso_info.clone().as_str(),
                                    );
                                    path_input(
                                        ui,
                                        "Work Directory:",
                                        &mut self.work_directory,
                                        true,
                                        self.work_directory_info.clone().as_str()
                                    );
                                    path_input(
                                        ui,
                                        "Customize Script:",
                                        &mut self.customize_script,
                                        false,
                                        self.customize_script_path_info.clone().as_str()
                                    );
                                    path_input(
                                        ui,
                                        "Password Script:",
                                        &mut self.password_script,
                                        false,
                                        self.password_script_path_info.clone().as_str()
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

                                let check_password = self.check_password_conditions();
                                let password_button = ui
                                    .add_enabled(check_password, egui::Button::new("Set Password"))
                                    .on_disabled_hover_text(self.password_script_info.clone()); 

                                if password_button.clicked() {
                                    self.password_function(ctx).unwrap_or_else(|error| {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    });
                                }
                            });
                        });

                        ui.horizontal(|ui| {
                            if interrupt_button(ui, process_active, active_function.as_deref()) {
                                self.interrupt_process();
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
                                    ui.label("USB Device:");
                                    ui.horizontal(|ui| {
                                        let previous_usb_device = self.usb_device.clone();
                                        let selected_text = self
                                            .usb_sticks
                                            .iter()
                                            .find(|stick| stick.path == self.usb_device)
                                            .map(|stick| stick.description.as_str())
                                            .or_else(|| {
                                                (!self.usb_device.is_empty()
                                                    && self.usb_device != KEY_NONE)
                                                    .then_some(
                                                        "Previously selected device (not detected)",
                                                    )
                                            })
                                            .unwrap_or("Select a USB stick");
                                        egui::ComboBox::from_id_salt("usb_device_select")
                                            .selected_text(selected_text)
                                            .show_ui(ui, |ui| {
                                                for stick in &self.usb_sticks {
                                                    ui.selectable_value(
                                                        &mut self.usb_device,
                                                        stick.path.clone(),
                                                        &stick.description,
                                                    );
                                                }
                                            });
                                        if self.usb_device != previous_usb_device {
                                            self.check_selected_usb_stick();
                                        }
                                        if ui.button("Refresh").clicked() {
                                            self.refresh_usb_sticks();
                                        }
                                    });
                                    ui.end_row();
                                    if !self.usb_device_info.is_empty() {
                                        ui.label("");
                                        ui.label(&self.usb_device_info);
                                        ui.end_row();
                                    }

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

                                let check_make_usb = self.check_make_usb_conditions();
                                let make_usb_button = ui
                                    .add_enabled(check_make_usb, egui::Button::new("Make USB"))
                                    .on_disabled_hover_text(self.make_usb_info.clone());

                                if make_usb_button.clicked() {
                                    if let Err(error) = self.make_usb_function(ctx) {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    }
                                }

                                let check_update_linux = self.check_update_linux_conditions();
                                let update_linux_button = ui
                                    .add_enabled(check_update_linux, egui::Button::new("Update Linux"))
                                    .on_disabled_hover_text(self.update_linux_info.clone());

                                if update_linux_button.clicked() {
                                    if let Err(error) = self.update_linux_function(ctx) {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    }
                                }

                                let check_open_crypt = self.check_open_crypt_conditions();
                                let open_crypt_button = ui
                                    .add_enabled(check_open_crypt, egui::Button::new("Open Encrypted"))
                                    .on_disabled_hover_text(self.open_crypted_volume_info.clone());

                                if open_crypt_button.clicked() {
                                    if let Err(error) = self.open_crypt_function(ctx) {
                                        self.append_output(&format!("\r\n{error}\r\n"));
                                    }
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
                            if interrupt_button(ui, process_active, active_function.as_deref()) {
                                self.interrupt_process();
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

        // Bottom Panel: terminal emulator
        egui::CentralPanel::default().show(ctx, |ui| {
            let notice = match self.console.lock() {
                Ok(console) => console.notice.clone(),
                Err(error) => format!("Failed to read terminal state: {error}"),
            };
            egui::Frame::new()
                .fill(egui::Color32::from_rgb(20, 20, 20))
                .inner_margin(8.0)
                .show(ui, |ui| {
                    if !notice.is_empty() {
                        ui.label(
                            egui::RichText::new(notice)
                                .monospace()
                                .color(egui::Color32::LIGHT_GRAY),
                        );
                    }
                    let sessions = self
                        .terminal_sessions
                        .iter()
                        .map(|session| (session.id, session.display.clone()))
                        .collect::<Vec<_>>();
                    if !sessions.is_empty() {
                        let selected_text = sessions
                            .iter()
                            .find(|(id, _)| Some(*id) == self.selected_terminal_id)
                            .map(|(_, display)| display.as_str())
                            .unwrap_or("Select terminal session");
                        egui::ComboBox::from_label("Terminal session")
                            .selected_text(selected_text)
                            .show_ui(ui, |ui| {
                                for (id, display) in &sessions {
                                    ui.selectable_value(
                                        &mut self.selected_terminal_id,
                                        Some(*id),
                                        display,
                                    );
                                }
                            });
                    }
                    let selected_terminal_id = self.selected_terminal_id;
                    if let Some(terminal) = self
                        .terminal_sessions
                        .iter_mut()
                        .find(|session| Some(session.id) == selected_terminal_id)
                    {
                        let view = TerminalView::new(ui, &mut terminal.backend).set_focus(true);
                        ui.add(view);
                    } else {
                        ui.allocate_space(ui.available_size());
                    }
                });
        });
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

fn backend_settings_from_command(command: CommandBuilder) -> Result<BackendSettings, String> {
    if command.iter_extra_env_as_str().next().is_some() {
        return Err("custom environment variables are not supported by egui_term".to_string());
    }

    let argv = command
        .get_argv()
        .iter()
        .map(|arg| {
            arg.to_str()
                .map(str::to_owned)
                .ok_or_else(|| "command arguments must be valid UTF-8".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    if argv.is_empty() {
        return Err("command has no executable".to_string());
    }

    let command_line = argv
        .iter()
        .map(|argument| shell_quote_argument(argument))
        .collect::<Vec<_>>()
        .join(" ");
    // Let the PTY reader consume the final output before its exit event is processed.
    let shell_script = format!(
        "{command_line}; status=$?; printf '\\r\\n[Process exited: %s]\\r\\n' \"$status\"; sleep 0.1; exit \"$status\""
    );

    Ok(BackendSettings {
        shell: "bash".to_string(),
        args: vec!["-c".to_string(), shell_script],
        working_directory: command.get_cwd().map(PathBuf::from),
    })
}

fn shell_quote_argument(argument: &str) -> String {
    format!("'{}'", argument.replace('\'', "'\\''"))
}

fn is_custom_script(path: &str) -> bool {
    !path.trim().is_empty() && path.trim() != KEY_EMBEDDED_SCRIPT
}

fn is_usb_device_detected(device: &str, sticks: &[UsbStick]) -> bool {
    sticks.iter().any(|stick| stick.path == device)
}

// Helper function to create a labeled path input field with a "Browse..." button
fn path_input(ui: &mut egui::Ui, 
    label: &str, 
    value: &mut String, 
    directory: bool,
    info_text: &str) {
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
        ui.label(info_text);
    });
    ui.end_row();
}

fn interrupt_button(
    ui: &mut egui::Ui,
    process_active: bool,
    active_function: Option<&str>,
) -> bool {
    let response = ui.add_enabled(process_active, egui::Button::new("Interrupt"));
    let response = if process_active {
        response.on_hover_text(format!(
            "send Ctrl+C: {}",
            active_function.unwrap_or("unknown")
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
    fn terminal_settings_preserve_command_arguments_and_working_directory() {
        let mut command = CommandBuilder::new("bash");
        command.args(["script.sh", "--workdir", "/tmp/work dir"]);
        command.cwd("/tmp/project");

        let settings = backend_settings_from_command(command).expect("convert command");

        assert_eq!(settings.shell, "bash");
        assert_eq!(settings.args[0], "-c");
        assert_eq!(
            settings.args[1],
            "'bash' 'script.sh' '--workdir' '/tmp/work dir'; status=$?; printf '\\r\\n[Process exited: %s]\\r\\n' \"$status\"; sleep 0.1; exit \"$status\""
        );
        assert_eq!(
            settings.working_directory,
            Some(PathBuf::from("/tmp/project"))
        );
    }

    #[test]
    fn shell_argument_quoting_preserves_single_quotes() {
        assert_eq!(shell_quote_argument("it's safe"), "'it'\\''s safe'");
    }

    #[test]
    fn embedded_customize_script_uses_the_shell_default() {
        assert!(!is_custom_script(KEY_EMBEDDED_SCRIPT));
        assert!(!is_custom_script("  embedded_script  "));
        assert!(!is_custom_script(""));
        assert!(is_custom_script("/tmp/customize.sh"));
    }

    #[test]
    fn usb_device_must_be_in_the_currently_detected_list() {
        let sticks = vec![UsbStick {
            path: "/dev/sdb".to_owned(),
            description: "Name: /dev/sdb".to_owned(),
        }];

        assert!(is_usb_device_detected("/dev/sdb", &sticks));
        assert!(!is_usb_device_detected("/dev/sdc", &sticks));
        assert!(!is_usb_device_detected("/dev/sdb", &[]));
    }

    #[test]
    fn terminal_backend_reports_completion_of_a_command() {
        let (event_sender, event_receiver) = mpsc::channel();
        let context = egui::Context::default();
        let mut command = CommandBuilder::new("sh");
        command.args(["-c", "printf 'terminal-ready\\n'"]);
        let settings = backend_settings_from_command(command).expect("prepare terminal command");
        let mut terminal = TerminalBackend::new(1, context.clone(), event_sender, settings)
            .expect("start terminal command");

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let mut process_finished = false;
        let mut output_received = false;
        while !process_finished || !output_received {
            let _ = context.run(egui::RawInput::default(), |ctx| {
                egui::CentralPanel::default().show(ctx, |ui| {
                    let view = TerminalView::new(ui, &mut terminal).set_focus(true);
                    ui.add(view);
                });
            });

            while let Ok((terminal_id, event)) = event_receiver.try_recv() {
                assert_eq!(terminal_id, 1);
                process_finished |= matches!(event, PtyEvent::Exit);
            }

            let output = terminal
                .sync()
                .grid
                .display_iter()
                .map(|cell| cell.c)
                .collect::<String>();
            output_received |=
                output.contains("terminal-ready") && output.contains("[Process exited: 0]");
            assert!(
                std::time::Instant::now() < deadline,
                "process_finished={process_finished}, output={output}"
            );
            if !process_finished || !output_received {
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
        }
    }

    #[test]
    fn terminal_backend_ctrl_c_interrupts_the_active_command() {
        let (event_sender, event_receiver) = mpsc::channel();
        let mut command = CommandBuilder::new("sh");
        command.args(["-c", "sleep 10"]);
        let settings = backend_settings_from_command(command).expect("prepare terminal command");
        let mut terminal =
            TerminalBackend::new(2, egui::Context::default(), event_sender, settings)
                .expect("start long-running terminal command");

        std::thread::sleep(std::time::Duration::from_millis(100));
        terminal.process_command(BackendCommand::Write(vec![0x03]));

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        loop {
            let remaining = deadline.saturating_duration_since(std::time::Instant::now());
            let (terminal_id, event) = event_receiver
                .recv_timeout(remaining)
                .expect("receive terminal exit after Ctrl+C");
            assert_eq!(terminal_id, 2);
            if matches!(event, PtyEvent::Exit) {
                break;
            }
        }
    }

    #[test]
    fn clear_terminal_does_not_change_active_process_state() {
        let manager = Arc::new(EmbeddedScriptManager::init().expect("initialize script manager"));
        let config_path = std::env::temp_dir().join(format!(
            "safe-stick-test-config-{}-{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        let config = ConfigManager::init(&config_path, crate::config::CONFIG_SCHEMA.to_vec());
        std::fs::remove_file(config_path).expect("remove temporary test config");
        let mut app = ShellGuiApp::new(manager, config);
        app.console.lock().expect("lock console").active = true;
        app.clear_terminal();

        let console = app.console.lock().expect("lock console");
        assert!(console.active);
    }
}
