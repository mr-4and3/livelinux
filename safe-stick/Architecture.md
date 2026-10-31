# Architecture Description: Shell Frontend GUI (Rust)


## 1. System Overview

This project is a lightweight, high-performance Graphical User Interface (GUI) written in Rust that serves as a frontend for running shell commands. It provides visual controls for automated DevOps and system tasks, specifically handling ISO modification and USB provisioning.

Technology Stack

• Language: Rust (Stable)
• GUI Framework: egui / eframe (Immediate Mode GUI)
• Process Execution and Terminal Emulation: `egui_term` with the Alacritty terminal backend

## 2. UI Layout Architecture

The interface is split vertically into two primary layers using egui's panel layout system.
+-----------------------------------------------------+

| [ ISO ]  (Active Tab)  [ USB ]  [ About ]          |
+-----------------------------------------------------+

| Path to ISO:      [_______________________] [Browse] |
| Custom ISO:       [_______________________] [Browse] |
| Work Directory:   [_______________________] [Browse] |
| Customize Script: [_______________________] [Browse] |
| Password Script:  [_______________________] [Browse] |
|                                                     |
| [Extract] [Customize] [Shell] [Make ISO] ...        |
+-----------------------------------------------------+

| CONSOLE OUTPUT                                      |
| line 1: Extracting files...                         |
| line 2: Enter password:                             |
|                                                     |
| (click terminal and type only when prompted)        |
+-----------------------------------------------------+

## 2.1 Top Panel (Configuration & Control)

Managed via a custom tab/swipe selector state switching between three contexts:
• ISO View: Form fields tracking file paths (Path to ISO, Custom ISO, Work Directory) and operational shell scripts (Customize Script, Password Script). Browse buttons open file pickers for file paths and a folder picker for the work directory. The Extract button runs the compile-time embedded scripts using the configured ISO, work directory, and output path. At build time, only Git-tracked files from `scripts/` are embedded; at startup, the complete embedded directory tree is restored to a temporary directory so the shell scripts can use their relative paths and assets.
• USB View: Fields targeting hardware deployment parameters (USB Device, Linux Partition Size, Encrypted Size, Unencrypted Size). The USB Device field includes a file picker. Buttons control device flashing and encryption lifecycles (Make, Update Linux, Open Encrypted, Close Encrypted).
• About View: Displays the application name and package version from Cargo metadata. Its top panel expands across the full window, with the terminal hidden.

## 2.2 Bottom Panel (Interactive Console)

A terminal area shown on the ISO and USB tabs, and hidden on the About tab. It shows the active process and accepts keyboard input directly.
• Output Area: A terminal screen that renders process output and terminal control sequences.
• Input: The `egui_term` widget handles terminal keyboard input, selection, scrolling, resizing, and terminal escape sequences. Password prompts can disable echo as usual.
• Controls: Clear removes saved terminal sessions after their processes have finished. The Interrupt button sends Ctrl+C to the active PTY process.
• Terminal Backend: `egui_term` launches each selected command in its own PTY. The most recent ten sessions can be revisited through the session selector.

## 3. Core Component Model

               +-----------------------+

               |   egui UI Thread      |
               | (State & Render Loop) |
               +-----------+-----------+
                           |
            Button Press   |   Terminal Keyboard Input
            / Trigger      v   / Key Press
  +------------------------+-----------------------+

  |  Command Dispatcher / Orchestrator             |
  +------------------------+-----------------------+
                           |
                           | Spawns Background Task
                           v
               +-----------------------+

               | PTY Child Process     | <--- OS Shell Execution
               +-----------+-----------+
                           |
                           | PTY output and keyboard input
                           v
               +-----------------------+

               | Console State Buffer |
               | (shared with workers) |
               +-----------------------+

## 3.1 Module Structure

The application is split into modules by responsibility:
• `src/main.rs`: Declares the modules, initializes the script manager, and starts the `eframe` application.
• `src/app.rs`: Contains `ShellGuiApp`, the ISO/USB/About views, file-picker helpers, and integration with the `egui_term` terminal widget.
• `src/script_manager.rs`: Embeds the tracked scripts and restores their directory tree for execution.
• `src/config.rs`: Defines the global configuration schema, including default values and numeric limits.
• `src/config_manager.rs`: Defines configuration values and provides validation and persistence logic.

The GUI implementation lives in `app.rs`; `main.rs` only constructs and launches `ShellGuiApp`. GUI-specific terminal-state tests are colocated with the app module.
The global schema is initialized once and cloned when passed to `ConfigManager`.

## 3.2 App State (struct ShellGuiApp)

Maintains the single source of truth for the continuous UI redraw loop.
• View state: Tracks whether ISO or USB configurations are being actively modified.
• String buffers: Holds live, mutable textual allocations matching every input field.
• Terminal screens: A bounded history of `egui_term` backends for recent commands.
• Active process: Tracks the active terminal ID and command until the backend reports its exit.

## 3.3 Threading & Asynchronous Concurrency

Because egui operates as an immediate-mode GUI framework executing at high frame rates, running a shell command blocking synchronous operations on the main thread would immediately cause the UI to freeze ("Not Responding").
• Process and PTY management: `egui_term` owns the PTY, terminal parser, output stream, and terminal input handling.
• Exit tracking: A small event listener updates the active-process state when the backend reports the process exit.
• UI Refresh: The terminal backend requests repaints as terminal events arrive.

# 4. UI-to-Shell Data Flow

1. Interaction: The user edits ISO configuration fields and clicks "Extract".
2. Context Construction: The application maps configured values to separate `st-iso.sh` arguments and appends the `extract` action.
3. Preparation: The script manager restores the embedded scripts and assets into a temporary directory, preserving relative paths and dependencies.
4. Execution: The application starts the selected script through the PTY runner; `sudo` is used when the application is not already running as root.
5. Terminal setup: The application passes the executable, arguments, and working directory to `egui_term`, which starts the command in its own PTY.
6. Streaming and input: `egui_term` parses PTY output and forwards terminal input, including keyboard shortcuts and paste.
7. Process state: The application tracks the backend's exit event; Interrupt sends Ctrl+C through the PTY.
