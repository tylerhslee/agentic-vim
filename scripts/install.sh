#!/usr/bin/env bash

set -euo pipefail

NVIM_VERSION="0.12.5"
NODE_VERSION="22.22.2"
NERD_FONT_VERSION="3.5.1"
TREE_SITTER_VERSION="0.27.0"
AGENTIC_PATCH_FILE_SHA256="e3be9b1b304e615593965766de5e7185fedb8d9c727b3dabcada505079781349"
AGENTIC_PATCH_DIFF_SHA256="56496103109ac4ea0293bff4590aefa6b1dc4aa105c0d81244ce5ce4b0e4ec0c"
NERD_FONT_SHA256="04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf"
PARSERS="bash css html javascript json lua markdown markdown_inline python toml tsx typescript yaml"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
APP_NAME="agentic-vim"
LAUNCHER_NAME="nvim"
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
BIN_HOME=${AGENTIC_VIM_BIN_HOME:-"$HOME/.local/bin"}
NVIM_CONFIG="$CONFIG_HOME/$APP_NAME"
MANAGED_ROOT="$DATA_HOME/$APP_NAME"
TOOLS_ROOT="$MANAGED_ROOT/tools"
PACK_ROOT="$MANAGED_ROOT/nvim-site/pack/agentic-vim"
PROVIDER_ROOT="$MANAGED_ROOT/provider"
MANAGED_BIN="$MANAGED_ROOT/bin"
BACKUP_ROOT="$STATE_HOME/agentic-vim/backups"
BACKUP_DIR=""
DRY_RUN=0
FORCE=0
SKIP_PARSERS=0
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh [--dry-run] [--force] [--skip-parsers]

Installs an isolated Agentic Vim distribution invoked with nvim.

  --dry-run       Describe changes without downloading or writing
  --force         Back up and replace conflicting Agentic Vim files
  --skip-parsers  Skip Tree-sitter parser compilation
EOF
}

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --skip-parsers) SKIP_PARSERS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

for command_name in git curl tar gzip; do
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

ensure_backup_dir() {
  if [[ -z "$BACKUP_DIR" ]]; then
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$BACKUP_DIR"
  fi
}

backup_target() {
  local target=$1 label=$2
  ensure_backup_dir
  mkdir -p "$BACKUP_DIR/$(dirname "$label")"
  mv "$target" "$BACKUP_DIR/$label"
  say "Backed up $target to $BACKUP_DIR/$label"
}

replace_with_symlink() {
  local source=$1 target=$2 label=$3 current=""
  if [[ -L "$target" ]]; then
    current=$(readlink "$target")
    [[ "$current" == "$source" ]] && return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    ((FORCE)) || die "$target already exists; rerun with --force to back it up and replace it"
    backup_target "$target" "$label"
  fi
  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  say "Linked $target -> $source"
}

download_verified() {
  local url=$1 expected=$2 destination=$3 actual
  curl -fL --retry 3 --output "$destination" "$url"
  actual=$(sha256_file "$destination")
  [[ "$actual" == "$expected" ]] || die "checksum mismatch for $url"
}

platform_assets() {
  local system machine
  system=$(uname -s)
  machine=$(uname -m)
  case "$system:$machine" in
    Linux:x86_64)
      NVIM_ARCHIVE="nvim-linux-x86_64.tar.gz"
      NVIM_DIR="nvim-linux-x86_64"
      NVIM_SHA256="bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875"
      NODE_ARCHIVE="node-v$NODE_VERSION-linux-x64.tar.gz"
      NODE_DIR="node-v$NODE_VERSION-linux-x64"
      NODE_SHA256="978978a635eef872fa68beae09f0aad0bbbae6757e444da80b570964a97e62a3"
      TREE_SITTER_ASSET="tree-sitter-linux-x64.gz"
      TREE_SITTER_SHA256="20a1f39ec1c45f2211492dcb8881c802b643b554bb196869a29ac3778277fa77"
      FONT_DIR="$DATA_HOME/fonts/JetBrainsMonoNerdFont"
      ;;
    Linux:aarch64|Linux:arm64)
      NVIM_ARCHIVE="nvim-linux-arm64.tar.gz"
      NVIM_DIR="nvim-linux-arm64"
      NVIM_SHA256="1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725"
      NODE_ARCHIVE="node-v$NODE_VERSION-linux-arm64.tar.gz"
      NODE_DIR="node-v$NODE_VERSION-linux-arm64"
      NODE_SHA256="b2f3a96f31486bfc365192ad65ced14833ad2a3c2e1bcefec4846902f264fa28"
      TREE_SITTER_ASSET="tree-sitter-linux-arm64.gz"
      TREE_SITTER_SHA256="3a35a2dd961ad842384e982c75daf792c01d1a67e442fc3914d4de37bd8a59cb"
      FONT_DIR="$DATA_HOME/fonts/JetBrainsMonoNerdFont"
      ;;
    Darwin:arm64)
      NVIM_ARCHIVE="nvim-macos-arm64.tar.gz"
      NVIM_DIR="nvim-macos-arm64"
      NVIM_SHA256="65fb000099e47ca1b762584c484cc833f40e30851a0ec450d4174e16317c1f9b"
      NODE_ARCHIVE="node-v$NODE_VERSION-darwin-arm64.tar.gz"
      NODE_DIR="node-v$NODE_VERSION-darwin-arm64"
      NODE_SHA256="db4b275b83736df67533529a18cc55de2549a8329ace6c7bcc68f8d22d3c9000"
      TREE_SITTER_ASSET="tree-sitter-macos-arm64.gz"
      TREE_SITTER_SHA256="70f7573b2b2e5371a5b58cc5227d2ad981fd5374596b9874e770af486060774e"
      FONT_DIR="$HOME/Library/Fonts"
      ;;
    Darwin:x86_64)
      NVIM_ARCHIVE="nvim-macos-x86_64.tar.gz"
      NVIM_DIR="nvim-macos-x86_64"
      NVIM_SHA256="81f4518622cb059b450ee2e498c6a1082a222f6bd89589de5bbcf0c6a68aa3fd"
      NODE_ARCHIVE="node-v$NODE_VERSION-darwin-x64.tar.gz"
      NODE_DIR="node-v$NODE_VERSION-darwin-x64"
      NODE_SHA256="12a6abb9c2902cf48a21120da13f87fde1ed1b71a13330712949e8db818708ba"
      TREE_SITTER_ASSET="tree-sitter-macos-x64.gz"
      TREE_SITTER_SHA256="767528eaab3cca9d929fb96b4cb11cc9f03e09e293675151875c0fe5f79c06f0"
      FONT_DIR="$HOME/Library/Fonts"
      ;;
    *) die "unsupported platform: $system $machine" ;;
  esac
}

link_is_expected() {
  local target=$1 source=$2
  [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]
}

preflight_link() {
  local target=$1 source=$2
  if [[ -e "$target" || -L "$target" ]]; then
    link_is_expected "$target" "$source" && return 0
    ((FORCE)) || die "$target already exists; rerun with --force to back it up and replace it"
  fi
}

platform_assets
NVIM_INSTALL="$TOOLS_ROOT/$NVIM_DIR"
NODE_INSTALL="$TOOLS_ROOT/$NODE_DIR"
TREE_SITTER_INSTALL="$TOOLS_ROOT/tree-sitter-v$TREE_SITTER_VERSION"

if ((DRY_RUN)); then
  say "Would install Neovim $NVIM_VERSION and Node.js $NODE_VERSION for $(uname -s) $(uname -m)."
  say "Would install JetBrainsMono Nerd Font $NERD_FONT_VERSION for the current user."
  say "Would install pinned plugins from nvim/plugins.lock and apply the Agent HUD patch."
  say "Would install the pinned Codex CLI, codex-acp, and Tree-sitter CLI."
  say "Would link $NVIM_CONFIG to $ROOT/nvim without changing ~/.config/nvim."
  say "Would install the isolated Agentic Vim launcher at $BIN_HOME/$LAUNCHER_NAME."
  ((SKIP_PARSERS)) || say "Would compile the configured Tree-sitter parsers."
  exit 0
fi

preflight_link "$NVIM_CONFIG" "$ROOT/nvim"
preflight_link "$BIN_HOME/$LAUNCHER_NAME" "$MANAGED_BIN/nvim"

if [[ -e "$PROVIDER_ROOT" && ! -f "$PROVIDER_ROOT/.agentic-vim-managed" ]] && ((!FORCE)); then
  die "$PROVIDER_ROOT is not owned by agentic-vim; rerun with --force to back it up"
fi
if [[ -e "$PACK_ROOT" && ! -f "$PACK_ROOT/.agentic-vim-managed" ]] && ((!FORCE)); then
  die "$PACK_ROOT is not owned by agentic-vim; rerun with --force to back it up"
fi

if ((!SKIP_PARSERS)); then
  command -v cc >/dev/null 2>&1 || die "a C compiler is required for Tree-sitter parsers (Xcode Command Line Tools on macOS; build-essential on Debian/Ubuntu)"
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agentic-vim-install.XXXXXX")
cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$TOOLS_ROOT" "$MANAGED_ROOT" "$BIN_HOME"

FONT_ARCHIVE="JetBrainsMono.tar.xz"
FONT_FILES="JetBrainsMonoNerdFontMono-Regular.ttf JetBrainsMonoNerdFontMono-Bold.ttf JetBrainsMonoNerdFontMono-Italic.ttf JetBrainsMonoNerdFontMono-BoldItalic.ttf"
FONT_STAGE="$TMP_DIR/fonts"
mkdir -p "$FONT_STAGE"
say "Installing JetBrainsMono Nerd Font $NERD_FONT_VERSION..."
download_verified \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v$NERD_FONT_VERSION/$FONT_ARCHIVE" \
  "$NERD_FONT_SHA256" "$TMP_DIR/$FONT_ARCHIVE"
tar -xJf "$TMP_DIR/$FONT_ARCHIVE" -C "$FONT_STAGE" $FONT_FILES
mkdir -p "$FONT_DIR"
for font_file in $FONT_FILES; do
  if [[ -e "$FONT_DIR/$font_file" ]] \
      && [[ "$(sha256_file "$FONT_DIR/$font_file")" != "$(sha256_file "$FONT_STAGE/$font_file")" ]] \
      && ((!FORCE)); then
    die "$FONT_DIR/$font_file differs; rerun with --force to back it up"
  fi
done
for font_file in $FONT_FILES; do
  if [[ -f "$FONT_DIR/$font_file" ]] \
      && [[ "$(sha256_file "$FONT_DIR/$font_file")" == "$(sha256_file "$FONT_STAGE/$font_file")" ]]; then
    continue
  fi
  if [[ -e "$FONT_DIR/$font_file" ]]; then
    ((FORCE)) || die "$FONT_DIR/$font_file differs; rerun with --force to back it up"
    backup_target "$FONT_DIR/$font_file" "fonts/$font_file"
  fi
  cp "$FONT_STAGE/$font_file" "$FONT_DIR/$font_file"
done
if [[ "$(uname -s)" == "Linux" ]] && command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f "$FONT_DIR" >/dev/null
fi

if [[ ! -x "$NVIM_INSTALL/bin/nvim" ]] || ! "$NVIM_INSTALL/bin/nvim" --version | head -n1 | grep -q "v$NVIM_VERSION"; then
  say "Downloading Neovim $NVIM_VERSION..."
  download_verified \
    "https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/$NVIM_ARCHIVE" \
    "$NVIM_SHA256" "$TMP_DIR/$NVIM_ARCHIVE"
  tar -xzf "$TMP_DIR/$NVIM_ARCHIVE" -C "$TMP_DIR"
  [[ -x "$TMP_DIR/$NVIM_DIR/bin/nvim" ]] || die "Neovim archive had an unexpected layout"
  if [[ -e "$NVIM_INSTALL" ]]; then
    ((FORCE)) || die "$NVIM_INSTALL is incomplete; rerun with --force to back it up"
    backup_target "$NVIM_INSTALL" "tools/$NVIM_DIR"
  fi
  mv "$TMP_DIR/$NVIM_DIR" "$NVIM_INSTALL"
fi

if [[ ! -x "$NODE_INSTALL/bin/node" ]] || [[ "$($NODE_INSTALL/bin/node --version)" != "v$NODE_VERSION" ]]; then
  say "Downloading Node.js $NODE_VERSION..."
  download_verified \
    "https://nodejs.org/dist/v$NODE_VERSION/$NODE_ARCHIVE" \
    "$NODE_SHA256" "$TMP_DIR/$NODE_ARCHIVE"
  tar -xzf "$TMP_DIR/$NODE_ARCHIVE" -C "$TMP_DIR"
  [[ -x "$TMP_DIR/$NODE_DIR/bin/npm" ]] || die "Node.js archive had an unexpected layout"
  if [[ -e "$NODE_INSTALL" ]]; then
    ((FORCE)) || die "$NODE_INSTALL is incomplete; rerun with --force to back it up"
    backup_target "$NODE_INSTALL" "tools/$NODE_DIR"
  fi
  mv "$TMP_DIR/$NODE_DIR" "$NODE_INSTALL"
fi

if [[ ! -x "$TREE_SITTER_INSTALL" ]] \
    || [[ "$($TREE_SITTER_INSTALL --version)" != "tree-sitter $TREE_SITTER_VERSION" ]]; then
  say "Downloading Tree-sitter CLI $TREE_SITTER_VERSION..."
  download_verified \
    "https://github.com/tree-sitter/tree-sitter/releases/download/v$TREE_SITTER_VERSION/$TREE_SITTER_ASSET" \
    "$TREE_SITTER_SHA256" "$TMP_DIR/$TREE_SITTER_ASSET"
  gzip -dc "$TMP_DIR/$TREE_SITTER_ASSET" > "$TMP_DIR/tree-sitter"
  chmod 755 "$TMP_DIR/tree-sitter"
  if [[ -e "$TREE_SITTER_INSTALL" ]]; then
    ((FORCE)) || die "$TREE_SITTER_INSTALL is incomplete; rerun with --force to back it up"
    backup_target "$TREE_SITTER_INSTALL" "tools/tree-sitter-v$TREE_SITTER_VERSION"
  fi
  mv "$TMP_DIR/tree-sitter" "$TREE_SITTER_INSTALL"
fi

provider_is_current() {
  [[ -f "$PROVIDER_ROOT/.agentic-vim-managed" ]] \
    && cmp -s "$ROOT/provider/package.json" "$PROVIDER_ROOT/package.json" \
    && cmp -s "$ROOT/provider/package-lock.json" "$PROVIDER_ROOT/package-lock.json" \
    && [[ -x "$PROVIDER_ROOT/node_modules/.bin/codex" ]] \
    && [[ -x "$PROVIDER_ROOT/node_modules/.bin/codex-acp" ]] \
    && [[ -x "$PROVIDER_ROOT/node_modules/.bin/pyright-langserver" ]]
}

if provider_is_current; then
  say "Pinned provider tools are already current."
else
  STAGED_PROVIDER="$TMP_DIR/provider"
  mkdir -p "$STAGED_PROVIDER"
  cp "$ROOT/provider/package.json" "$ROOT/provider/package-lock.json" "$STAGED_PROVIDER/"
  say "Installing pinned provider tools..."
  PATH="$NODE_INSTALL/bin:$PATH" npm_config_cache="$TMP_DIR/npm-cache" "$NODE_INSTALL/bin/npm" ci \
    --prefix "$STAGED_PROVIDER" --no-audit --no-fund
  [[ -x "$STAGED_PROVIDER/node_modules/.bin/codex" ]] || die "Codex CLI installation failed"
  [[ -x "$STAGED_PROVIDER/node_modules/.bin/codex-acp" ]] || die "codex-acp installation failed"
  [[ -x "$STAGED_PROVIDER/node_modules/.bin/pyright-langserver" ]] \
    || die "Pyright language server installation failed"
  printf 'managed by agentic-vim\n' > "$STAGED_PROVIDER/.agentic-vim-managed"
  if [[ -e "$PROVIDER_ROOT" ]]; then
    if [[ -f "$PROVIDER_ROOT/.agentic-vim-managed" ]]; then
      mv "$PROVIDER_ROOT" "$TMP_DIR/provider-old"
    else
      backup_target "$PROVIDER_ROOT" "provider"
    fi
  fi
  mv "$STAGED_PROVIDER" "$PROVIDER_ROOT"
fi

mkdir -p "$MANAGED_BIN"
{
  printf '#!/bin/sh\n'
  printf 'export NVIM_APPNAME=%q\n' "$APP_NAME"
  printf 'export VIMRUNTIME=%q\n' "$NVIM_INSTALL/share/nvim/runtime"
  printf 'exec %q "$@"\n' "$NVIM_INSTALL/bin/nvim"
} > "$MANAGED_BIN/nvim"
chmod 755 "$MANAGED_BIN/nvim"
write_node_wrapper() {
  local destination=$1 entrypoint=$2
  {
    printf '#!/bin/sh\n'
    printf 'exec %q %q "$@"\n' "$NODE_INSTALL/bin/node" "$entrypoint"
  } > "$destination"
  chmod 755 "$destination"
}
write_node_wrapper "$MANAGED_BIN/codex" \
  "$PROVIDER_ROOT/node_modules/@openai/codex/bin/codex.js"
write_node_wrapper "$MANAGED_BIN/codex-acp" \
  "$PROVIDER_ROOT/node_modules/@agentclientprotocol/codex-acp/dist/index.js"
write_node_wrapper "$MANAGED_BIN/pyright-langserver" \
  "$PROVIDER_ROOT/node_modules/pyright/langserver.index.js"
"$MANAGED_BIN/codex" --version >/dev/null || die "Codex wrapper verification failed"

pack_is_current() {
  local name url commit patch plugin_dir patch_hash expected_hash actual_hash
  local -a expected_names=()
  [[ -f "$PACK_ROOT/.agentic-vim-managed" ]] || return 1
  while IFS='|' read -r name url commit patch; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    expected_names+=("$name")
    plugin_dir="$PACK_ROOT/start/$name"
    [[ -d "$plugin_dir/.git" ]] || return 1
    [[ "$(git -C "$plugin_dir" rev-parse HEAD 2>/dev/null)" == "$commit" ]] || return 1
    if [[ -n "$patch" ]]; then
      patch_hash=$(git -C "$plugin_dir" diff --cached --binary HEAD | sha256_stream)
      [[ "$patch_hash" == "$AGENTIC_PATCH_DIFF_SHA256" ]] || return 1
      [[ -z "$(git -C "$plugin_dir" diff --binary)" ]] || return 1
      [[ -z "$(git -C "$plugin_dir" ls-files --others --exclude-standard)" ]] || return 1
    elif [[ -n "$(git -C "$plugin_dir" status --porcelain)" ]]; then
      return 1
    fi
  done < "$ROOT/nvim/plugins.lock"
  expected_hash=$(printf '%s\n' "${expected_names[@]}" | LC_ALL=C sort | sha256_stream)
  actual_hash=$(
    for plugin_dir in "$PACK_ROOT/start"/*; do
      [[ -d "$plugin_dir" ]] || continue
      basename "$plugin_dir"
    done | LC_ALL=C sort | sha256_stream
  )
  [[ "$actual_hash" == "$expected_hash" ]] || return 1
}

if pack_is_current; then
  say "Pinned Neovim plugins are already current."
else
  STAGED_PACK="$TMP_DIR/pack"
  mkdir -p "$STAGED_PACK/start"
  while IFS='|' read -r name url commit patch; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    say "Installing $name at ${commit:0:12}..."
    git init -q "$STAGED_PACK/start/$name"
    git -C "$STAGED_PACK/start/$name" remote add origin "$url"
    git -C "$STAGED_PACK/start/$name" fetch -q --depth 1 origin "$commit"
    git -C "$STAGED_PACK/start/$name" checkout -q --detach FETCH_HEAD
    if [[ -n "$patch" ]]; then
      [[ "$(sha256_file "$ROOT/$patch")" == "$AGENTIC_PATCH_FILE_SHA256" ]] \
        || die "Agent HUD patch checksum mismatch"
      git -C "$STAGED_PACK/start/$name" apply --check --index "$ROOT/$patch"
      git -C "$STAGED_PACK/start/$name" apply --index "$ROOT/$patch"
      [[ "$(git -C "$STAGED_PACK/start/$name" diff --cached --binary HEAD | sha256_stream)" \
        == "$AGENTIC_PATCH_DIFF_SHA256" ]] || die "Agent HUD patch verification failed"
      [[ -z "$(git -C "$STAGED_PACK/start/$name" diff --binary)" ]] \
        || die "Agent HUD checkout contains unexpected unstaged changes"
      [[ -z "$(git -C "$STAGED_PACK/start/$name" ls-files --others --exclude-standard)" ]] \
        || die "Agent HUD checkout contains unexpected files"
    fi
  done < "$ROOT/nvim/plugins.lock"
  printf 'managed by agentic-vim\n' > "$STAGED_PACK/.agentic-vim-managed"
  if [[ -e "$PACK_ROOT" ]]; then
    backup_target "$PACK_ROOT" "pack/agentic-vim"
  fi
  mkdir -p "$(dirname "$PACK_ROOT")"
  mv "$STAGED_PACK" "$PACK_ROOT"
fi

replace_with_symlink "$ROOT/nvim" "$NVIM_CONFIG" "config/nvim"
replace_with_symlink "$MANAGED_BIN/nvim" "$BIN_HOME/$LAUNCHER_NAME" "bin/$LAUNCHER_NAME"

append_path_config() {
  local shell_file=$1 backup_label=$2
  if [[ ! -f "$shell_file" ]] || ! grep -q '# agentic-vim PATH' "$shell_file"; then
    [[ -f "$shell_file" ]] && { ensure_backup_dir; cp "$shell_file" "$BACKUP_DIR/$backup_label"; }
    {
      printf '\n# agentic-vim PATH\n'
      printf 'export PATH=%q:"$PATH"\n' "$BIN_HOME"
    } >> "$shell_file"
    say "Added $BIN_HOME to PATH in $shell_file"
  fi
}

case "${SHELL:-}" in
  */zsh)
    append_path_config "$HOME/.zshrc" ".zshrc"
    append_path_config "$HOME/.zprofile" ".zprofile"
    ;;
  *)
    append_path_config "$HOME/.bashrc" ".bashrc"
    if [[ -f "$HOME/.bash_profile" ]]; then
      append_path_config "$HOME/.bash_profile" ".bash_profile"
    elif [[ -f "$HOME/.bash_login" ]]; then
      append_path_config "$HOME/.bash_login" ".bash_login"
    else
      append_path_config "$HOME/.profile" ".profile"
    fi
    ;;
esac

VERIFY_PARSERS=""
if ((!SKIP_PARSERS)); then
  say "Installing and verifying Tree-sitter parsers..."
  VERIFY_PARSERS="$PARSERS"
fi
say "Verifying Neovim startup and provider configuration..."
PATH="$BIN_HOME:$MANAGED_BIN:$NODE_INSTALL/bin:$PATH" \
  XDG_CACHE_HOME="$TMP_DIR/cache" XDG_STATE_HOME="$TMP_DIR/state" NVIM_CODEX_USAGE_DISABLED=1 \
  NVIM_LOG_FILE="$TMP_DIR/nvim.log" \
  AGENTIC_VIM_PARSERS="$VERIFY_PARSERS" \
  AGENTIC_VIM_CHECK_SCRIPT="$ROOT/scripts/nvim-install-check.lua" \
  AGENTIC_VIM_CHECK_MARKER="$TMP_DIR/nvim-verified" \
  "$BIN_HOME/$LAUNCHER_NAME" --headless -i NONE \
  '+lua dofile(vim.env.AGENTIC_VIM_CHECK_SCRIPT)' +qa
[[ -f "$TMP_DIR/nvim-verified" ]] || die "Neovim verification did not complete"

say ""
say "Agentic Vim is installed."
say "Next: $ROOT/scripts/setup-credentials.sh"
say "Then restart your shell and run: $LAUNCHER_NAME"
if [[ -n "$BACKUP_DIR" ]]; then
  say "Backups from this run: $BACKUP_DIR"
fi
