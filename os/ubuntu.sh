#!/usr/bin/env bash
# Setup buat Ubuntu (ditarget ke 26.04)
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

# Tulis file milik sistem (butuh sudo)
write_root_file() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] tulis ke $1: $2"
  else
    printf '%s\n' "$2" | sudo tee "$1" >/dev/null
  fi
}

# Tambah baris ke file milik user
append_line() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] tambah ke $1: $2"
  else
    printf '\n%s\n' "$2" >> "$1"
  fi
}

step() { echo; echo "==> $1"; }
skip() { echo "    $1 udah ada, lewati"; }

read_list() {
  grep -Ev '^\s*(#|$)' "$PKG_DIR/$1" || true
}

. /etc/os-release
if [ "$VERSION_ID" != "26.04" ]; then
  echo "Catatan: script ini ditarget ke Ubuntu 26.04, kamu pakai $VERSION_ID. Lanjut, tapi bisa aja ada yang beda"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "Mode dry-run: cuma nampilin apa yang bakal dijalanin, gak ada yang diinstall"
fi

step "Update sistem"
run sudo apt-get update -y
run sudo apt-get upgrade -y

step "Paket apt"
mapfile -t APT_PKGS < <(read_list apt.txt)
if [ "${#APT_PKGS[@]}" -gt 0 ]; then
  run sudo apt-get install -y "${APT_PKGS[@]}"
fi

step "Paket snap (VS Code, Android Studio)"
if ! command -v snap >/dev/null 2>&1; then
  echo "    snap gak ketemu, lewati bagian ini"
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
  echo "    Chrome buat Linux cuma ada versi amd64, lewati"
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
    skip "PATH fvm di $(basename "$rc")"
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
echo "==> Selesai"
echo "    Tutup terus buka lagi terminal-nya biar fvm dan flutter kebaca"
echo "    Habis itu buka Android Studio sekali buat download Android SDK, terus jalanin: flutter doctor"
