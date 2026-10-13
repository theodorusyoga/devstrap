#!/usr/bin/env bash
# Setup for standard Fedora installations with DNF5 on x86_64.
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PKG_DIR="$REPO_DIR/packages/fedora"
DRY_RUN="${DEVSTRAP_DRY_RUN:-0}"
OPTIONAL="${DEVSTRAP_OPTIONAL:-}"

. /etc/os-release
if [ "$ID" != "fedora" ]; then
  echo "This script needs Fedora"
  exit 1
fi
if [ -e /run/ostree-booted ] || [[ "${VARIANT_ID:-}" =~ ^(silverblue|kinoite|sericea|onyx|coreos)$ ]]; then
  echo "Fedora Atomic variants are not supported; use a standard DNF-based installation"
  exit 1
fi
if [ "$(uname -m)" != "x86_64" ]; then
  echo "Fedora setup currently supports x86_64 only"
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "Run as your regular user; setup asks for sudo when needed"
  exit 1
fi
if ! command -v dnf5 >/dev/null 2>&1; then
  echo "Fedora setup needs DNF5"
  exit 1
fi

if [ -t 1 ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; DIM=""; BOLD=""; RESET=""
fi

INSTALLED_NOW=0

step()       { echo; echo "${BOLD}==> $1${RESET}"; }
ok()         { echo "    ${GREEN}✓${RESET} $1 ${DIM}already installed${RESET}"; }
installing() { echo "    ${YELLOW}→${RESET} installing $1"; INSTALLED_NOW=$((INSTALLED_NOW + 1)); }
note()       { echo "    ${DIM}$1${RESET}"; }

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "      ${DIM}[dry-run] $*${RESET}"
  else
    "$@"
  fi
}

# Write a system-owned file (needs sudo)
write_root_file() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "      ${DIM}[dry-run] write to $1: $2${RESET}"
  else
    printf '%s\n' "$2" | sudo tee "$1" >/dev/null
  fi
}

# True if an optional app was chosen
want_optional() {
  [ "$OPTIONAL" = "all" ] && return 0
  case ",${OPTIONAL// /,}," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# Append a line to a user-owned file
append_line() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "      ${DIM}[dry-run] append to $1${RESET}"
  else
    printf '\n%s\n' "$2" >> "$1"
  fi
}

read_list() {
  if [ ! -f "$PKG_DIR/$1" ] || [ ! -r "$PKG_DIR/$1" ]; then
    echo "Cannot read package list: $PKG_DIR/$1" >&2
    return 1
  fi
  awk 'NF && $1 !~ /^#/' "$PKG_DIR/$1"
}


rpm_installed() { rpm -q "$1" >/dev/null 2>&1; }

dnf_install_missing() {
  local pkg
  local missing=()
  for pkg in "$@"; do
    [ -z "$pkg" ] && continue
    if rpm_installed "$pkg"; then
      ok "$pkg"
    else
      installing "$pkg"
      missing+=("$pkg")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    run sudo dnf5 install -y "${missing[@]}"
  fi
}

# Read all lists before changing the machine, including optional apps.
DNF_LIST="$(read_list dnf.txt)"
SNAP_LIST="$(read_list snap.txt)"
OPTIONAL_SNAP_LIST="$(read_list optional-snap.txt)"
if [ "$DRY_RUN" = "1" ]; then
  echo "Dry-run mode: checks are real, installs are only shown"
fi

step "DNF packages"
PACKAGES=()
while read -r pkg; do
  [ -z "$pkg" ] || PACKAGES+=("$pkg")
done <<< "$DNF_LIST"
dnf_install_missing "${PACKAGES[@]}"
# Fedora often ships curl-minimal. Avoid replacing it with the conflicting curl RPM.
if ! command -v curl >/dev/null 2>&1; then dnf_install_missing curl; fi

step "KVM"
CURRENT_USER="$(id -un)"
if [[ " $(id -nG "$CURRENT_USER") " == *" kvm "* ]]; then
  ok "KVM group membership"
else
  installing "KVM group membership"
  run sudo usermod -aG kvm "$CURRENT_USER"
fi
note "Log out and back in after setup; enable hardware virtualization in BIOS/UEFI"
note "Check KVM with: virt-host-validate qemu"

step "scrcpy"
if rpm_installed scrcpy; then
  ok "scrcpy"
else
  # This community COPR is the Fedora install route linked by scrcpy upstream.
  run sudo dnf5 copr enable -y zeno/scrcpy
  dnf_install_missing scrcpy
fi

step "Google Cloud CLI"
if command -v gcloud >/dev/null 2>&1 || rpm_installed google-cloud-cli; then
  ok "google-cloud-cli"
else
  write_root_file /etc/yum.repos.d/google-cloud-sdk.repo '[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg'
  dnf_install_missing google-cloud-cli
fi

step "Google Chrome"
if rpm_installed google-chrome-stable; then
  ok "google-chrome-stable"
else
  write_root_file /etc/yum.repos.d/google-chrome.repo '[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub'
  dnf_install_missing google-chrome-stable
fi

step "Snap setup"
if ! systemctl is-enabled --quiet snapd.socket || ! systemctl is-active --quiet snapd.socket; then
  run sudo systemctl enable --now snapd.socket
fi
if [ ! -e /snap ] && [ ! -L /snap ]; then
  run sudo ln -s /var/lib/snapd/snap /snap
elif [ "$(readlink -f /snap)" != /var/lib/snapd/snap ]; then
  echo "Cannot set up classic Snaps: /snap already exists with a different target" >&2
  exit 1
fi
# Wait for initial seeding before requesting installs on a fresh snapd.
run sudo snap wait system seed.loaded

install_snap_list() {
  local pkg flags
  while read -r pkg flags; do
    [ -z "$pkg" ] && continue
    if command -v snap >/dev/null 2>&1 && snap list "$pkg" >/dev/null 2>&1; then
      ok "$pkg"
    else
      installing "$pkg"
      # shellcheck disable=SC2086
      run sudo snap install "$pkg" $flags
    fi
  done <<< "$1"
}
step "Snap packages"
install_snap_list "$SNAP_LIST"

step "FVM + Flutter"
FVM_BIN="$HOME/fvm/bin"
FLUTTER_BIN="$HOME/fvm/default/bin"

if [ -x "$FVM_BIN/fvm" ]; then
  ok "fvm"
else
  installing "fvm"
  if [ "$DRY_RUN" = "1" ]; then
    FVM_INSTALLER="<temporary-fvm-installer>"
  else
    FVM_INSTALLER="$(mktemp)"
    trap 'rm -f "$FVM_INSTALLER"' EXIT
  fi
  run curl -fsSL -o "$FVM_INSTALLER" https://fvm.app/install.sh
  run bash "$FVM_INSTALLER"
  if [ "$DRY_RUN" != "1" ]; then rm -f "$FVM_INSTALLER"; fi
fi

PATH_MARKER="# devstrap: fvm"
PATH_LINE="export PATH=\"$FVM_BIN:$FLUTTER_BIN:\$PATH\""
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  if grep -qF "$PATH_MARKER" "$rc"; then
    ok "fvm PATH in $(basename "$rc")"
  else
    installing "fvm PATH in $(basename "$rc")"
    append_line "$rc" "$PATH_MARKER"$'\n'"$PATH_LINE"
  fi
done
export PATH="$FVM_BIN:$FLUTTER_BIN:$PATH"

if [ -x "$FLUTTER_BIN/flutter" ]; then
  ok "flutter (global via fvm)"
else
  installing "flutter stable"
  run fvm install stable
  run fvm global stable
fi
# Flutter tracks cached artifacts itself. Retry this even when a previous run
# selected the SDK successfully but failed while downloading artifacts.
note "Check Flutter Android + Linux artifacts (keep the current global SDK)"
run flutter precache --android --linux

step "Optional apps"
if [ -z "$OPTIONAL" ]; then
  note "None chosen. Use DEVSTRAP_OPTIONAL=all or DEVSTRAP_OPTIONAL=warp,slack"
else
  if want_optional warp; then
    if rpm_installed warp-terminal; then
      ok "warp-terminal"
    else
      write_root_file /etc/yum.repos.d/warpdotdev.repo '[warpdotdev]
name=warpdotdev
baseurl=https://releases.warp.dev/linux/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://releases.warp.dev/linux/keys/warp.asc'
      dnf_install_missing warp-terminal
    fi
  fi
  while read -r pkg flags; do
    [ -z "$pkg" ] && continue
    if want_optional "$pkg"; then install_snap_list "$pkg $flags"; fi
  done <<< "$OPTIONAL_SNAP_LIST"
fi

step "Git"
if DEFAULT_BRANCH="$(git config --global --get init.defaultBranch)"; then
  ok "default branch set to $DEFAULT_BRANCH"
else
  installing "default branch setting"
  run git config --global init.defaultBranch main
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "==> Dry run finished, $INSTALLED_NOW item(s) would be installed or configured"
else
  echo "==> Done, $INSTALLED_NOW item(s) installed or configured"
  echo "    Log out and back in for Snap, FVM, Flutter, and KVM access"
  echo "    Open Android Studio to download the Android SDK, then run flutter doctor"
fi
