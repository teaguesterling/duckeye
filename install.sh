#!/usr/bin/env bash
# install.sh — install duckeye and its agent skills.
#
#   ./install.sh                    # auto-detect everything
#   ./install.sh --no-bin           # skills only
#   ./install.sh --global           # /usr/local/bin instead of ~/.local/bin
#   ./install.sh --claude --no-agy  # explicit overrides
#   ./install.sh --uninstall        # remove symlinks
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat <<'EOF'
usage: install.sh [OPTION]...

Install duckeye and its AI agent skills via symlinks.

Binary:
  --user-bin       install to ~/.local/bin (default)
  --global         install to /usr/local/bin
  --no-bin         skip the binary

Agent skills (auto-detected by default):
  --agy            install the Antigravity (agy) skill
  --no-agy         skip agy
  --claude         install the Claude Code skill
  --no-claude      skip Claude Code
  --opencode       install the OpenCode skill
  --no-opencode    skip OpenCode

Other:
  --uninstall      remove all installed symlinks
  --no-init        skip running duckeye --init after install
  -h, --help       show this help

Auto-detection checks whether the agent's config directory exists
(~/.gemini/config, ~/.claude, ~/.config/opencode). Explicit flags
override detection.
EOF
}

die() { printf 'install.sh: %s\n' "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------- defaults
bin_mode=auto do_init=1 uninstall=
agy=auto claude=auto opencode=auto

while (( $# )); do
  case $1 in
    --user-bin)    bin_mode=user ;;
    --global)      bin_mode=global ;;
    --no-bin)      bin_mode=none ;;
    --agy)         agy=yes ;;
    --no-agy)      agy=no ;;
    --claude)      claude=yes ;;
    --no-claude)   claude=no ;;
    --opencode)    opencode=yes ;;
    --no-opencode) opencode=no ;;
    --uninstall)   uninstall=1 ;;
    --no-init)     do_init= ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown option: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- auto-detect
resolve() {
  local val=$1 dir=$2
  if [[ $val == auto ]]; then
    [[ -d "$dir" ]] && echo yes || echo no
  else
    echo "$val"
  fi
}

agy=$(resolve "$agy" "$HOME/.gemini/config")
claude=$(resolve "$claude" "$HOME/.claude")
opencode=$(resolve "$opencode" "$HOME/.config/opencode")
[[ $bin_mode == auto ]] && bin_mode=user

# ---------------------------------------------------------------- targets
bin_src=$here/duckeye
skill_dir=$here/skills/duckeye
skill_md=$skill_dir/SKILL.md

bin_dst=
case $bin_mode in
  user)   bin_dst=$HOME/.local/bin/duckeye ;;
  global) bin_dst=/usr/local/bin/duckeye ;;
  none)   ;;
esac

declare -A skill_targets=()
[[ $agy     == yes ]] && skill_targets[agy]=$HOME/.gemini/config/skills/duckeye
[[ $claude  == yes ]] && skill_targets[claude]=$HOME/.claude/commands/duckeye.md
[[ $opencode == yes ]] && skill_targets[opencode]=$HOME/.config/opencode/instructions/duckeye.md

# ---------------------------------------------------------------- helpers
installed=0

link() {
  local src=$1 dst=$2 label=$3
  if [[ -L $dst ]]; then
    local current; current=$(readlink -f "$dst" 2>/dev/null)
    local want; want=$(readlink -f "$src" 2>/dev/null)
    if [[ $current == "$want" ]]; then
      printf '  %-10s %s (already installed)\n' "$label" "$dst"
      return 0
    fi
    printf '  %-10s %s (updating)\n' "$label" "$dst"
    rm "$dst"
  elif [[ -e $dst ]]; then
    printf '  %-10s %s exists and is not a symlink, skipping\n' "$label" "$dst" >&2
    return 1
  else
    printf '  %-10s %s\n' "$label" "$dst"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst" && installed=$((installed + 1))
}

unlink() {
  local dst=$1 label=$2
  if [[ -L $dst ]]; then
    printf '  %-10s removed %s\n' "$label" "$dst"
    rm "$dst"
  elif [[ -e $dst ]]; then
    printf '  %-10s %s is not a symlink, skipping\n' "$label" "$dst" >&2
  fi
}

# ---------------------------------------------------------------- uninstall
if [[ -n $uninstall ]]; then
  echo 'uninstalling'
  [[ -n $bin_dst ]] && unlink "$bin_dst" binary
  for label in "${!skill_targets[@]}"; do
    unlink "${skill_targets[$label]}" "$label"
  done
  echo 'done'
  exit 0
fi

# ---------------------------------------------------------------- install
[[ -x $bin_src ]] || die "cannot find duckeye at $bin_src"
[[ -f $skill_md ]] || die "cannot find skill at $skill_md"

echo 'installing'

if [[ -n $bin_dst ]]; then
  if [[ $bin_mode == global && ! -w $(dirname "$bin_dst") ]]; then
    printf '  %-10s %s (needs sudo)\n' binary "$bin_dst"
    sudo mkdir -p "$(dirname "$bin_dst")"
    sudo ln -sf "$bin_src" "$bin_dst" && installed=$((installed + 1))
  else
    link "$bin_src" "$bin_dst" binary
  fi
fi

for label in "${!skill_targets[@]}"; do
  dst=${skill_targets[$label]}
  # agy gets the directory (it expects SKILL.md inside); others get the file
  if [[ $label == agy ]]; then
    link "$skill_dir" "$dst" "$label"
  else
    link "$skill_md" "$dst" "$label"
  fi
done

if (( ${#skill_targets[@]} == 0 )); then
  echo '  (no agent configs detected; use --agy, --claude, or --opencode to force)'
fi

# ---------------------------------------------------------------- post-install
if [[ -n $do_init && $installed -gt 0 && -n $bin_dst ]]; then
  echo 'running duckeye --init'
  "$bin_dst" --init
fi

echo 'done'
