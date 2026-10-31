# Architecture Description: Shell Frontend GUI (Rust)


## 1. System Overview

This project is a lightweight, high-performance Graphical User Interface (GUI) written in Rust that serves as a frontend for running shell commands. It provides visual controls for automated DevOps and system tasks, specifically handling ISO modification and USB provisioning.

Technology Stack

• Language: Rust (Stable)
• GUI Framework: egui / eframe (Immediate Mode GUI)
• Process Execution: portable-pty (asynchronous worker threads)
• Terminal Parsing: vt100

## 2. UI Layout Architecture

The interface is split vertically into two primary layers using egui's panel layout system.
+-----------------------------------------------------+

| [ ISO ]  (Active Tab)  [ USB ]  [ About ]          |
+-----------------------------------------------------+

| Path to ISO:      [_______________________]         |
| Custom ISO:       [_______________________]         |
| Work Directory:   [_______________________]         |
| Customize Script: [_______________________]         |
| Password Script:  [_______________________]         |
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
• ISO View: Form fields tracking file paths (Path to ISO, Custom ISO, Work Directory) and operational shell scripts (Customize Script, Password Script). The Extract button runs the compile-time embedded scripts using the configured ISO, work directory, and output path. At build time, only Git-tracked files from `scripts/` are embedded; at startup, the complete embedded directory tree is restored to a temporary directory so the shell scripts can use their relative paths and assets.
• USB View: Fields targeting hardware deployment parameters (USB Device, Linux Partition Size, Encrypted Size, Unencrypted Size). Buttons control device flashing and encryption lifecycles (Make, Update Linux, Open Encrypted, Close Encrypted).
• About View: Displays the application name and package version from Cargo metadata. Its top panel expands across the full window, with the terminal hidden.

## 2.2 Bottom Panel (Interactive Console)

A terminal area shown on the ISO and USB tabs, and hidden on the About tab. It shows the active process and accepts keyboard input directly.
• Output Area: A terminal screen that renders process output and terminal control sequences.
• Input: There is no separate input line. Click the terminal area to focus it; key presses go directly to the running process's pseudo-terminal. The terminal itself displays typed input when the process has echo enabled, and password prompts can disable echo.
• Controls: A Clear button clears the displayed terminal and its scrollback without terminating a running process. A native vertical scrollbar appears only when the terminal history exceeds the visible area; mouse-wheel scrolling navigates history.
• Terminal Backend: Commands run attached to a pseudo-terminal (PTY), so programs can detect an interactive terminal and prompt for input. The Shell button starts an interactive `sh` process; commands can then be entered in that same terminal.

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

## 3.1 App State (struct ShellGuiApp)

Maintains the single source of truth for the continuous UI redraw loop.
• View state: Tracks whether ISO or USB configurations are being actively modified.
• String buffers: Holds live, mutable textual allocations matching every input field.
• Terminal screen: A shared VT100-compatible screen buffer.
• Active process: Tracks whether a process is running and retains the PTY writer for direct keyboard input.

## 3.2 Threading & Asynchronous Concurrency

Because egui operates as an immediate-mode GUI framework executing at high frame rates, running a shell command blocking synchronous operations on the main thread would immediately cause the UI to freeze ("Not Responding").
• Worker Spawning: Each action runs in a background worker thread so shell execution does not block the UI.
• Streaming: Child processes run on a PTY. A reader thread feeds output into the terminal parser while keyboard events are written directly to the PTY.
• UI Refresh: Output readers request a repaint when new text arrives.

# 4. UI-to-Shell Data Flow

1. Interaction: The user edits ISO configuration fields and clicks "Extract".
2. Context Construction: The application maps configured values to separate `st-iso.sh` arguments and appends the `extract` action.
3. Preparation: The script manager restores the embedded scripts and assets into a temporary directory, preserving relative paths and dependencies.
4. Execution: The application starts the selected script through the PTY runner; `sudo` is used when the application is not already running as root.
5. Streaming: A reader thread feeds PTY output to the terminal parser and requests UI repaints.
6. Input: When the terminal area is focused, keyboard events are sent directly to the active process through the PTY. No permanent input line is shown.
7. Re-render: The GUI displays the parsed terminal screen, including output and any echoed input.
