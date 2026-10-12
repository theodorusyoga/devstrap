# devstrap

Set up a new machine in one command. The repo stores a list of the tools you need, and the script works out how to install them on whichever OS you're on

Currently supports **Ubuntu 26.04**. More operating systems to come

## Usage

A fresh Ubuntu install doesn't ship with `curl`, so use `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | bash
```

If you already have `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | bash
```

Don't prefix it with `sudo`. The script asks for your password when it needs it

**Read the script before running it.** The commands above download a script from the internet and run it immediately. That's normal for a repo you trust, but check what it does first

### Preview without installing anything

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | DEVSTRAP_DRY_RUN=1 bash
```

## What gets installed on Ubuntu

| Tool | Installed via |
|---|---|
| git, curl, wget, unzip, zip, xz-utils | apt |
| scrcpy | apt |
| VS Code | snap |
| Android Studio | snap |
| Google Chrome | Official .deb from Google (amd64) |
| FVM + Flutter stable | Official FVM installer |

Safe to run more than once. Every tool is checked first: anything already installed shows a green ✓ and is left alone, and on a fully set-up machine the script does nothing at all

The script does not run a full `apt upgrade`. Keep your system updated the usual way

## Optional apps

Not installed by default. Choose them with `DEVSTRAP_OPTIONAL`:

```bash
# all optional apps
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | DEVSTRAP_OPTIONAL=all bash

# only some of them
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | DEVSTRAP_OPTIONAL=warp,slack bash
```

| Name | App | Installed via |
|---|---|---|
| `warp` | Warp terminal | Official Warp apt repository (amd64) |
| `spotify` | Spotify | Official snap |
| `slack` | Slack | Official snap |

To add your own, put a line in `packages/ubuntu/optional-snap.txt` and use the snap name with `DEVSTRAP_OPTIONAL`

## After installing

1. Close and reopen your terminal so `fvm` and `flutter` are on your PATH
2. Open Android Studio once to download the Android SDK
3. Run `flutter doctor`

## Structure

```
install.sh              detects the OS, fetches the repo, hands off to the matching OS script
os/ubuntu.sh            how to install on Ubuntu
packages/ubuntu/        apt and snap package lists
```

To add a tool, add one line to `packages/ubuntu/apt.txt` or `snap.txt`. To add an OS, create `os/<id>.sh`, where `<id>` matches `ID` in `/etc/os-release`

## Roadmap

- **macOS**: Homebrew, CocoaPods, FVM, Android Studio, Sourcetree, VS Code, Chrome, scrcpy
- **Fedora**
