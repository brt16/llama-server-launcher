# llama-server-launcher
Lightweight llama.cpp server launcher bat file with powershell windows gui for configuring and launching [llama-server](https://github.com/ggml-org/llama.cpp/tree/master/tools/server) (llama.cpp).

![llama-server-launcher screenshot](screenshot.jpg)

## How to use
1. Download `llama-server-launcher.bat`.
2. Optionally place it in the same folder as `llama-server.exe` for auto-detection.
3. Double-click the `.bat` file.
4. Browse to your `llama-server.exe` and pick a `.gguf` model (or use a Hugging Face repo).
5. Check any options you want to override - unchecked rows are omitted from the command.
6. Click **Run llama-server** or **Copy Command**. No install, no dependencies beyond Windows and PowerShell.

## Features

- **Single file** - one `.bat` that embeds a PowerShell/WinForms GUI. Nothing to install.
- **Two view modes** - *Basic* shows the settings most people touch; *Full* exposes the complete llama-server CLI surface.
- **Live command preview** - see the exact command line update in real time as you change options.
- **Copy or Run** - copy the built command to your clipboard, or launch llama-server directly from the GUI.
- **Auto-detection** - if the launcher sits next to `llama-server.exe`, the path fills in automatically.
- **Tooltips** - hover over the options to read tooltips explaining what it does and when to use it.
- **Searchable option index** - the *All Options* tab lets you search across every flag and jump to it.

## How it works
The `.bat` bootstrap extracts an embedded PowerShell script to a temp file, runs it, then cleans up. The PowerShell script builds a WinForms GUI entirely in memory - no extra files are created or modified on your system.

## License
MIT
