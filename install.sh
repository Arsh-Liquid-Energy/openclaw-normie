#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# OpenClaw — One-Line Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/arshnoor/openclaw/main/install.sh | bash
#
# Steps:
#   1. Detects OS (macOS / Linux) and architecture (x64 / arm64)
#   2. Installs Node.js 22 if needed — no Homebrew dependency
#   3. Installs OpenClaw globally via npm
#   4. Launches the onboarding wizard
#
# Override defaults with environment variables:
#   OPENCLAW_NODE_VERSION   Node.js version to install   (default: 22.12.0)
#   OPENCLAW_DIR            Base install directory        (default: ~/.local/share/openclaw)
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────

OPENCLAW_NODE_VERSION="${OPENCLAW_NODE_VERSION:-22.12.0}"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.local/share/openclaw}"
NODE_DIR="$OPENCLAW_DIR/node"
NODE_MIN_MAJOR=22
NODE_MIN_MINOR=12
MANAGED_NODE=false

# ── Output helpers ──────────────────────────────────────────────

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'  DIM=$'\033[2m'
  GREEN=$'\033[32m' RED=$'\033[31m'
  RESET=$'\033[0m'
else
  BOLD="" DIM="" GREEN="" RED="" RESET=""
fi

step() { printf "  %-42s" "$1"; }
ok()   { printf "${GREEN}done${RESET}\n"; }
skip() { printf "${DIM}%s${RESET}\n" "${1:-skipped}"; }
die()  {
  printf "${RED}failed${RESET}\n"
  printf "\n  ${RED}Error:${RESET} %s\n\n" "$1" >&2
  exit 1
}

# ── Temp file cleanup ───────────────────────────────────────────

_TMP=""
cleanup() { [[ -n "$_TMP" && -d "$_TMP" ]] && rm -rf "$_TMP"; return 0; }
trap cleanup EXIT

# ── Platform detection ──────────────────────────────────────────

PLATFORM=""
NODE_ARCH=""

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin) PLATFORM="darwin" ;;
    Linux)  PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
      printf "\n  Windows is not supported directly.\n"
      printf "  Install WSL first: https://learn.microsoft.com/en-us/windows/wsl/install\n"
      printf "  Then re-run this installer inside WSL.\n\n"
      exit 1 ;;
    *)
      printf "\n  Unsupported operating system: %s\n\n" "$os" >&2
      exit 1 ;;
  esac

  case "$arch" in
    x86_64|amd64)  NODE_ARCH="x64" ;;
    arm64|aarch64) NODE_ARCH="arm64" ;;
    *)
      printf "\n  Unsupported architecture: %s\n\n" "$arch" >&2
      exit 1 ;;
  esac
}

platform_label() {
  local os_label=""
  case "$PLATFORM" in
    darwin) os_label="macOS" ;;
    linux)  os_label="Linux" ;;
  esac
  printf "%s %s" "$os_label" "$NODE_ARCH"
}

# ── Node.js version check ──────────────────────────────────────

# Returns 0 if the given node binary (default: `node` on PATH)
# is present and satisfies >= NODE_MIN_MAJOR.NODE_MIN_MINOR.
node_version_ok() {
  local bin="${1:-node}"
  local ver major minor rest

  # If an explicit path was given, check it exists and is executable
  if [[ "$bin" != "node" && ! -x "$bin" ]]; then
    return 1
  fi

  # If no explicit path, check node is on PATH
  if [[ "$bin" == "node" ]] && ! command -v node >/dev/null 2>&1; then
    return 1
  fi

  ver="$("$bin" --version 2>/dev/null)" || return 1
  ver="${ver#v}"                    # strip leading "v"

  major="${ver%%.*}"                # "22.12.0" → "22"
  rest="${ver#*.}"                  # "22.12.0" → "12.0"
  minor="${rest%%.*}"               # "12.0"    → "12"

  [[ "$major" -gt "$NODE_MIN_MAJOR" ]] && return 0
  [[ "$major" -eq "$NODE_MIN_MAJOR" && "$minor" -ge "$NODE_MIN_MINOR" ]] && return 0
  return 1
}

# ── Node.js installer ──────────────────────────────────────────

install_node() {
  step "Installing Node.js ${OPENCLAW_NODE_VERSION}..."

  # Require a download tool
  local dl=""
  command -v curl >/dev/null 2>&1 && dl="curl"
  if [[ -z "$dl" ]]; then
    command -v wget >/dev/null 2>&1 && dl="wget"
  fi
  [[ -z "$dl" ]] && die "curl or wget is required but neither was found"

  local tarball="node-v${OPENCLAW_NODE_VERSION}-${PLATFORM}-${NODE_ARCH}.tar.gz"
  local url="https://nodejs.org/dist/v${OPENCLAW_NODE_VERSION}/${tarball}"

  _TMP="$(mktemp -d)"

  # Download the tarball
  if [[ "$dl" == "curl" ]]; then
    curl -fsSL "$url" -o "$_TMP/$tarball" || die "Download failed — $url"
  else
    wget -q "$url" -O "$_TMP/$tarball"    || die "Download failed — $url"
  fi

  # Remove any previous managed install, then extract
  rm -rf "$NODE_DIR"
  mkdir -p "$NODE_DIR"
  tar -xzf "$_TMP/$tarball" -C "$NODE_DIR" --strip-components=1 \
    || die "Failed to extract Node.js tarball"

  # Clean up temp download
  rm -rf "$_TMP"
  _TMP=""

  # Sanity check
  [[ -x "$NODE_DIR/bin/node" ]] \
    || die "Node binary not found after extraction"

  export PATH="$NODE_DIR/bin:$PATH"
  MANAGED_NODE=true
  ok
}

# Adds the managed Node.js to PATH in shell rc files so future
# terminal sessions pick it up automatically.
persist_path() {
  local line='export PATH="$HOME/.local/share/openclaw/node/bin:$PATH"'
  local marker="# openclaw-managed-node"
  local targets=()

  if [[ "$PLATFORM" == "darwin" ]]; then
    # macOS: zsh is the default shell
    targets+=("$HOME/.zshrc")
    [[ -f "$HOME/.bashrc" ]] && targets+=("$HOME/.bashrc")
  else
    # Linux: bash is typically the default
    targets+=("$HOME/.bashrc")
    [[ -f "$HOME/.zshrc" ]] && targets+=("$HOME/.zshrc")
  fi

  # .profile covers login shells on both platforms
  [[ -f "$HOME/.profile" ]] && targets+=("$HOME/.profile")

  for rc in "${targets[@]}"; do
    # Already present — skip
    if [[ -f "$rc" ]] && grep -qF "$marker" "$rc" 2>/dev/null; then
      continue
    fi
    printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
  done
}

# ── Ensure Node.js ──────────────────────────────────────────────

ensure_node() {
  # Priority 1: Previously-installed managed Node.js
  if [[ -x "$NODE_DIR/bin/node" ]] && node_version_ok "$NODE_DIR/bin/node"; then
    export PATH="$NODE_DIR/bin:$PATH"
    MANAGED_NODE=true
    step "Checking Node.js..."
    skip "$("$NODE_DIR/bin/node" --version) (managed)"
    return
  fi

  # Priority 2: System node that meets requirements
  if node_version_ok; then
    step "Checking Node.js..."
    skip "$(node --version) (system)"
    return
  fi

  # Priority 3: Install our own
  install_node
  persist_path
}

# ── OpenClaw installer ─────────────────────────────────────────

install_openclaw() {
  step "Installing OpenClaw..."

  if npm install -g openclaw@latest \
       --no-audit --no-fund --loglevel=error >/dev/null 2>&1; then
    ok
    return
  fi

  # npm install -g failed. If we're already using our managed node
  # (user-writable prefix), there's nothing else to try.
  if [[ "$MANAGED_NODE" == true ]]; then
    die "npm install -g openclaw@latest failed"
  fi

  # Likely a permissions issue with the system node's global prefix.
  # Switch to a managed Node.js install (user-writable) and retry.
  skip "retrying with managed Node"
  install_node
  persist_path

  step "Installing OpenClaw..."
  npm install -g openclaw@latest \
    --no-audit --no-fund --loglevel=error >/dev/null 2>&1 \
    || die "npm install -g openclaw@latest failed"
  ok
}

verify_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    printf "\n  ${RED}Error:${RESET} openclaw was installed but is not on PATH.\n"
    printf "  Try opening a new terminal and running: openclaw --version\n\n"
    exit 1
  fi
}

# ── Onboarding ──────────────────────────────────────────────────

run_onboarding() {
  printf "\n"

  # When invoked via curl | bash, stdin is the pipe (not the
  # terminal). Reattach stdin from /dev/tty so the interactive
  # onboarding wizard can read user input.
  if [[ ! -t 0 ]]; then
    if [[ -r /dev/tty ]]; then
      openclaw onboard </dev/tty
    else
      printf "  No interactive terminal detected — skipping onboarding.\n"
      printf "  Run ${BOLD}openclaw onboard${RESET} to complete setup.\n\n"
      return 0
    fi
  else
    openclaw onboard
  fi
}

# ── Main ────────────────────────────────────────────────────────

main() {
  detect_platform

  printf "\n"
  printf "  ${BOLD}OpenClaw Installer${RESET}\n"
  printf "  ──────────────────\n"
  printf "  Platform: %s\n\n" "$(platform_label)"

  ensure_node
  install_openclaw
  verify_openclaw
  run_onboarding

  printf "\n"
  printf "  ${GREEN}${BOLD}OpenClaw is ready!${RESET}\n"
  printf "  Check your Telegram/WhatsApp for a welcome message.\n"
  printf "\n"
}

main "$@"
