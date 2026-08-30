# Installation

`duckeye` is distributed as a single executable script accompanied by an automatic multi-platform installer.

## Prerequisites

* **DuckDB**: Version 1.1+ (recommended 1.2+ or 1.5+)
* **Pandoc** *(optional, recommended)*: For rendering Office & Pandoc formats (`.docx`, `.epub`, `.odt`, `.tex`, `.rst`, `.org`, `.ipynb`, `.mediawiki`, `.man`).

---

## Quick Install

Clone the repository and run the included installer:

```bash
git clone https://github.com/teaguesterling/duckeye.git
cd duckeye
./install.sh
```

By default, `install.sh`:

1. Symlinks `duckeye` into `~/.local/bin/duckeye` (and creates the `dep` alias for paged viewing).
2. Runs `duckeye --init` to install all official and community DuckDB extensions.
3. Automatically detects AI coding harnesses (`~/.gemini/config`, `~/.claude`, `~/.config/opencode`) and installs the `duckeye` agent skill.

---

## Installer Options

```bash
# Install globally (requires sudo)
./install.sh --global

# Install binary only without modifying AI agent skill directories
./install.sh --no-skills

# Install skills for specific harnesses
./install.sh --agy --claude --no-opencode

# Skip installing DuckDB extensions during setup
./install.sh --no-init

# Uninstall duckeye binary, aliases, and agent skills
./install.sh --uninstall
```

---

## Manual Installation

If you prefer to install manually:

```bash
# 1. Symlink binary
ln -sf "$PWD/duckeye" ~/.local/bin/duckeye

# 2. Install required DuckDB extensions
duckeye --init
```

---

## Extension Initialization

Running `duckeye --init` installs:

* **Official Extensions**: `http`, `aws`, `excel`
* **Community Extensions**: `duck_block_utils`, `markdown`, `webbed`, `zim`, `pdf`, `sitting_duck`, `yaml`, `toml`, `read_lines`, `duck_tails`, `zipfs`, `textplot`
