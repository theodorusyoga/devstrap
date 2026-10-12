#!/usr/bin/env bash
# Setup for Ubuntu (targets 26.04)
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PKG_DIR="$REPO_DIR/packages/ubuntu"
DRY_RUN="${DEVSTRAP_DRY_RUN:-0}"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

# Write a system-owned file (needs sudo)
write_root_file() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] write to $1: $2"
  else
    printf '%s\n' "$2" | sudo tee "$1" >/dev/null
  fi
}

# Append a line to a user-owned file
append_line() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] append to $1: $2"
  else
    printf '\n%s\n' "$2" >> "$1"
  fi
}

step() { echo; echo "==> $1"; }
skip() { echo "    $1 already installed, skipping"; }

read_list() {
  grep -Ev '^\s*(#|$)' "$PKG_DIR/$1" || true
}

. /etc/os-release
if [ "$VERSION_ID" != "26.04" ]; then
  echo "Note: this script targets Ubuntu 26.04, you are on $VERSION_ID. Continuing, but some steps may differ"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "Dry-run mode: showing what would run, nothing gets installed"
fi

step "System update"
run sudo apt-get update -y
run sudo apt-get upgrade -y

step "apt packages"
mapfile -t APT_PKGS < <(read_list apt.txt)
if [ "${#APT_PKGS[@]}" -gt 0 ]; then
  run sudo apt-get install -y "${APT_PKGS[@]}"
fi

step "snap packages (VS Code, Android Studio)"
if ! command -v snap >/dev/null 2>&1; then
  echo "    snap not found, skipping this section"
else
  while read -r pkg flags; do
    [ -z "$pkg" ] && continue
    if snap list "$pkg" >/dev/null 2>&1; then
      skip "$pkg"
    else
      # shellcheck disable=SC2086
      run sudo snap install "$pkg" $flags
    fi
  done < <(read_list snap.txt)
fi

step "Google Chrome"
if dpkg -s google-chrome-stable >/dev/null 2>&1; then
  skip "google-chrome-stable"
elif [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "    Chrome for Linux is amd64 only, skipping"
else
  CHROME_DEB="$(mktemp --suffix=.deb)"
  run wget -qO "$CHROME_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  run sudo apt-get install -y "$CHROME_DEB"
  rm -f "$CHROME_DEB"
fi

step "Claude Desktop (beta)"
if dpkg -s claude-desktop >/dev/null 2>&1; then
  skip "claude-desktop"
else
  KEYRING=/usr/share/keyrings/claude-desktop-archive-keyring.asc
  run sudo curl -fsSLo "$KEYRING" https://downloads.claude.ai/claude-desktop/key.asc
  write_root_file /etc/apt/sources.list.d/claude-desktop.list \
    "deb [arch=amd64,arm64 signed-by=$KEYRING] https://downloads.claude.ai/claude-desktop/apt/stable stable main"
  run sudo apt-get update -y
  run sudo apt-get install -y claude-desktop
fi

step "FVM + Flutter"
FVM_BIN="$HOME/fvm/bin"
FLUTTER_BIN="$HOME/fvm/default/bin"
if [ -x "$FVM_BIN/fvm" ]; then
  skip "fvm"
else
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
    skip "fvm PATH in $(basename "$rc")"
  else
    append_line "$rc" "$PATH_MARKER"$'\n'"$PATH_LINE"
  fi
done
export PATH="$FVM_BIN:$FLUTTER_BIN:$PATH"

run fvm install stable
run fvm global stable
run flutter precache --android

step "Git"
run git config --global init.defaultBranch main

echo
echo "==> Done"
echo "    Close and reopen your terminal so fvm and flutter are on PATH"
echo "    Then open Android Studio once to download the Android SDK, and run: flutter doctor"
