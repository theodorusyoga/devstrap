#!/usr/bin/env bash
# devstrap: siapin laptop buat ngoding dalam satu perintah
# Pemakaian:
#   wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | bash
set -euo pipefail

REPO="${DEVSTRAP_REPO:-theodorusyoga/devstrap}"
BRANCH="${DEVSTRAP_BRANCH:-main}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Jangan dijalanin pakai sudo atau sebagai root ya, script-nya bakal minta password sendiri kalau perlu"
  exit 1
fi

download() {
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  else
    echo "Butuh wget atau curl, dua-duanya gak ketemu"
    exit 1
  fi
}

case "$(uname -s)" in
  Linux)
    . /etc/os-release
    OS_ID="$ID"
    OS_NAME="$PRETTY_NAME"
    ;;
  Darwin)
    OS_ID="macos"
    OS_NAME="macOS"
    ;;
  *)
    echo "OS ini belum didukung: $(uname -s)"
    exit 1
    ;;
esac

echo "==> Kedeteksi: $OS_NAME"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Ambil isi repo"
if [ -n "${DEVSTRAP_TARBALL:-}" ]; then
  cp "$DEVSTRAP_TARBALL" "$WORKDIR/repo.tar.gz"
else
  download "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" "$WORKDIR/repo.tar.gz"
fi
tar -xzf "$WORKDIR/repo.tar.gz" -C "$WORKDIR"
REPO_DIR="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"

OS_SCRIPT="$REPO_DIR/os/$OS_ID.sh"
if [ ! -f "$OS_SCRIPT" ]; then
  echo "Belum ada setup buat $OS_NAME. Yang udah ada:"
  ls "$REPO_DIR/os"
  exit 1
fi

# stdin dialihkan supaya perintah di dalam gak "makan" sisa script ini
REPO_DIR="$REPO_DIR" bash "$OS_SCRIPT" < /dev/null
