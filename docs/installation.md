# Installation

`duckeye` is distributed as a single executable script accompanied by an automatic multi-platform installer.

## Prerequisites

* **DuckDB**: Version 1.1+ (recommended 1.2+ or 1.5+)
* **Pandoc** *(optional, recommended)*: For rendering Office & Pandoc formats (`.docx`, `.epub`, `.odt`, `.tex`, `.rst`, `.org`, `.ipynb`, `.mediawiki`, `.man`).

---

## Quick Install

### One-line Install (via `curl`)

```bash
curl -fsSL https://raw.githubusercontent.com/teaguesterling/duckeye/main/install.sh | bash
```

### Local Checkout

```bash
git clone https://github.com/teaguesterling/duckeye.git
cd duckeye
./install.sh
```

By default, `install.sh`:

1. Installs or symlinks `duckeye` into `~/.local/bin/duckeye`.
2. Creates convenient command aliases:
   - `de` &rarr; short alias for `duckeye`
   - `dep` &rarr; automatically pages output through `$DUCKEYE_PAGER` (`less -R`)
   - `der` &rarr; forces raw data / tabular AST output mode
3. Runs `duckeye --init` to install all official and community DuckDB extensions.
4. Automatically detects AI coding harnesses (`~/.gemini/config`, `~/.claude`, `~/.config/opencode`) and installs the `duckeye` agent skill.

---

## Installer Options

```bash
# Install globally (requires sudo)
./install.sh --global

# Skip creating de, dep, and der aliases
./install.sh --no-aliases

# Skip installing the binary (skills only)
./install.sh --no-bin

# Install skills for specific harnesses
./install.sh --agy --claude --no-opencode

# Skip running duckeye --init after installation
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
