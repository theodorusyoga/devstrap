#!/usr/bin/env bash
# Setup for Ubuntu (targets 26.04)
# Every tool is checked first. Anything already installed gets a green check and is left alone
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PKG_DIR="$REPO_DIR/packages/ubuntu"
DRY_RUN="${DEVSTRAP_DRY_RUN:-0}"
# Optional apps: empty (none), "all", or a list like "warp,slack"
OPTIONAL="${DEVSTRAP_OPTIONAL:-}"

if [ -t 1 ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; DIM=""; BOLD=""; RESET=""
fi

INSTALLED_NOW=0
APT_UPDATED=0

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

# Download an ASCII signing key and store it dearmored for apt
install_gpg_key() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "      ${DIM}[dry-run] add signing key $1 -> $2${RESET}"
  else
    sudo install -d -m 755 "$(dirname "$2")"
    wget -qO- "$1" | gpg --dearmor | sudo tee "$2" >/dev/null
    sudo chmod 644 "$2"
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

# Refresh the apt index once, and only when something actually needs installing
apt_update_once() {
  if [ "$APT_UPDATED" = "0" ]; then
    run sudo apt-get update -y -qq
    APT_UPDATED=1
  fi
}

apt_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

read_list() {
  if [ ! -f "$PKG_DIR/$1" ] || [ ! -r "$PKG_DIR/$1" ]; then
    echo "Cannot read package list: $PKG_DIR/$1" >&2
    return 1
  fi
  awk 'NF && $1 !~ /^#/' "$PKG_DIR/$1"
}

# Read every list before making changes. Assignments propagate read failures;
# awk also keeps a final entry that has no trailing newline.
APT_LIST="$(read_list apt.txt)"
SNAP_LIST="$(read_list snap.txt)"
OPTIONAL_SNAP_LIST="$(read_list optional-snap.txt)"

. /etc/os-release
if [ "$VERSION_ID" != "26.04" ]; then
  echo "Note: this script targets Ubuntu 26.04, you are on $VERSION_ID. Continuing, but some steps may differ"
fi
if [ "$DRY_RUN" = "1" ]; then
  echo "Dry-run mode: checks are real, installs are only shown"
fi

step "apt packages"
MISSING_APT=()
while read -r pkg; do
  [ -z "$pkg" ] && continue
  if apt_installed "$pkg"; then
    ok "$pkg"
  else
    installing "$pkg"
    MISSING_APT+=("$pkg")
  fi
done <<< "$APT_LIST"
if [ "${#MISSING_APT[@]}" -gt 0 ]; then
  apt_update_once
  run sudo apt-get install -y "${MISSING_APT[@]}"
fi

step "KVM"
if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  note "KVM setup currently targets amd64, skipping"
else
  MISSING_KVM=()
  for pkg in qemu-system-x86 cpu-checker libvirt-daemon-system libvirt-clients bridge-utils; do
    if apt_installed "$pkg"; then
      ok "$pkg"
    else
      installing "$pkg"
      MISSING_KVM+=("$pkg")
    fi
  done
  if [ "${#MISSING_KVM[@]}" -gt 0 ]; then
    apt_update_once
    run sudo apt-get install -y "${MISSING_KVM[@]}"
  fi
  CURRENT_USER="$(id -un)"
  if [[ " $(id -nG "$CURRENT_USER") " == *" kvm "* ]]; then
    ok "KVM group membership"
  else
    installing "KVM group membership"
    run sudo usermod -aG kvm "$CURRENT_USER"
    note "Log out and back in to apply KVM group access"
  fi
  note "Run kvm-ok after setup; hardware virtualization must be enabled in BIOS/UEFI"
fi

step "Google Cloud CLI"
if command -v gcloud >/dev/null 2>&1 || apt_installed google-cloud-cli; then
  ok "google-cloud-cli"
else
  installing "google-cloud-cli"
  install_gpg_key https://packages.cloud.google.com/apt/doc/apt-key.gpg /etc/apt/keyrings/cloud.google.gpg
  write_root_file /etc/apt/sources.list.d/google-cloud-sdk.list \
    "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main"
  # Refresh again because this repository was not available to earlier steps.
  run sudo apt-get update -y -qq
  APT_UPDATED=1
  run sudo apt-get install -y google-cloud-cli
fi

step "snap packages"
if ! command -v snap >/dev/null 2>&1; then
  note "snap not found, skipping this section"
else
  while read -r pkg flags; do
    [ -z "$pkg" ] && continue
    if snap list "$pkg" >/dev/null 2>&1; then
      ok "$pkg"
    else
      installing "$pkg"
      # shellcheck disable=SC2086
      run sudo snap install "$pkg" $flags
    fi
  done <<< "$SNAP_LIST"
fi

step "Google Chrome"
if apt_installed google-chrome-stable; then
  ok "google-chrome-stable"
elif [ "$(dpkg --print-architecture)" != "amd64" ]; then
  note "Chrome for Linux is amd64 only, skipping"
else
  installing "google-chrome-stable"
  apt_update_once
  CHROME_DEB="$(mktemp --suffix=.deb)"
  run wget -qO "$CHROME_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  run sudo apt-get install -y "$CHROME_DEB"
  rm -f "$CHROME_DEB"
fi

step "FVM + Flutter"
FVM_BIN="$HOME/fvm/bin"
FLUTTER_BIN="$HOME/fvm/default/bin"

if [ -x "$FVM_BIN/fvm" ]; then
  ok "fvm"
else
  installing "fvm"
  FVM_INSTALLER="$(mktemp)"
  run curl -fsSL -o "$FVM_INSTALLER" https://fvm.app/install.sh
  run bash "$FVM_INSTALLER"
  rm -f "$FVM_INSTALLER"
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
  note "None chosen. Add DEVSTRAP_OPTIONAL=all, or a list like DEVSTRAP_OPTIONAL=warp,slack"
else
  if want_optional warp; then
    if apt_installed warp-terminal; then
      ok "warp-terminal"
    elif [ "$(dpkg --print-architecture)" != "amd64" ]; then
      note "Warp's apt repository is amd64 only, skipping"
    else
      installing "warp-terminal"
      install_gpg_key https://releases.warp.dev/linux/keys/warp.asc /etc/apt/keyrings/warpdotdev.gpg
      write_root_file /etc/apt/sources.list.d/warpdotdev.list \
        "deb [arch=amd64 signed-by=/etc/apt/keyrings/warpdotdev.gpg] https://releases.warp.dev/linux/deb stable main"
      # New repo added, so this refresh is always needed
      run sudo apt-get update -y -qq
      APT_UPDATED=1
      run sudo apt-get install -y warp-terminal
    fi
  fi

  if command -v snap >/dev/null 2>&1; then
    while read -r pkg flags; do
      [ -z "$pkg" ] && continue
      want_optional "$pkg" || continue
      if snap list "$pkg" >/dev/null 2>&1; then
        ok "$pkg"
      else
        installing "$pkg"
        # shellcheck disable=SC2086
        run sudo snap install "$pkg" $flags
      fi
    done <<< "$OPTIONAL_SNAP_LIST"
  else
    note "snap not found, skipping snap-based optional apps"
  fi
fi

step "Git"
if DEFAULT_BRANCH="$(git config --global --get init.defaultBranch)"; then
  ok "default branch set to $DEFAULT_BRANCH"
else
  installing "default branch setting"
  run git config --global init.defaultBranch main
fi

echo
if [ "$INSTALLED_NOW" -eq 0 ]; then
  echo "${GREEN}${BOLD}✓ Everything is already installed. Nothing to do${RESET}"
else
  if [ "$DRY_RUN" = "1" ]; then
    echo "${BOLD}==> Dry run finished${RESET}, $INSTALLED_NOW item(s) would be installed"
    exit 0
  fi
  echo "${BOLD}==> Done${RESET}, $INSTALLED_NOW item(s) installed"
  echo "    Close and reopen your terminal so fvm and flutter are on PATH"
  echo "    Then open Android Studio once to download the Android SDK, and run: flutter doctor"
fi
