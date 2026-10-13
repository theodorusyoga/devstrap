# devstrap

Set up your dev tools in one command. Keep the package lists here and let the script handle setup.

Supports **Ubuntu 26.04** + **standard Fedora on x86_64 with DNF5**. Other Ubuntu versions show a warning and continue. Fedora Atomic variants, including Silverblue and Kinoite, are not supported. macOS is planned.

## Install

Run as your regular user. You need `wget` or `curl` to start. The script asks for your sudo password when needed.

Read [install.sh](install.sh) + the matching [Ubuntu](os/ubuntu.sh) or [Fedora](os/fedora.sh) script first. These commands download and run code from this repo. Setup also downloads and runs the FVM installer.

With `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | bash
```

With `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | bash
```

### Preview changes

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | DEVSTRAP_DRY_RUN=1 bash
```

Dry run checks installed tools and shows what would run. It still downloads and extracts the repo and may create temp files. It skips installs + config writes.

## What it sets up

### Ubuntu

| Tools | Source |
| --- | --- |
| ca-certificates, curl, wget, git, unzip, zip, xz-utils, gnupg | apt |
| scrcpy | apt |
| GitHub CLI (`gh`), GitLab CLI (`glab`) | Ubuntu apt packages |
| clang, cmake, ninja-build, pkg-config, libgtk-3-dev, libstdc++-12-dev, libglu1-mesa | apt; Flutter Linux build tools |
| QEMU/KVM, cpu-checker, libvirt + bridge-utils | apt; amd64 only |
| Google Cloud CLI (`gcloud`) | Google apt repository |
| VS Code, Android Studio, ONLYOFFICE Desktop Editors | Snap |
| Google Chrome | Google's `.deb` download; the script installs it only on amd64 |
| FVM | FVM installer |
| Flutter stable + Android/Linux artifacts | FVM + `flutter precache --android --linux` |

### Fedora

| Tools | Source |
| --- | --- |
| git, wget, unzip, zip, xz, gnupg2, ca-certificates | DNF; an existing curl or curl-minimal is reused |
| GitHub CLI (`gh`), GitLab CLI (`glab`) | Fedora DNF packages |
| clang, cmake, ninja-build, pkgconf-pkg-config, gtk3-devel, libstdc++-devel, mesa-libGLU | DNF; Flutter Linux build tools |
| QEMU/KVM + libvirt-client | DNF |
| scrcpy | `zeno/scrcpy` COPR, linked by scrcpy upstream |
| Google Cloud CLI (`gcloud`) | Google RPM repository + libxcrypt-compat |
| Google Chrome | Google RPM repository |
| VS Code, Android Studio, ONLYOFFICE Desktop Editors | Snap |
| FVM + Flutter | Same setup as Ubuntu |

Setup installs snapd + the DNF5 COPR plugin. It enables `snapd.socket` and creates `/snap` as a link to `/var/lib/snapd/snap` for classic Snaps. Log out and back in when setup finishes.

Fedora support has automated tests with fake package managers. A full install on a fresh Fedora machine is still unverified.

### Shared behavior

Both scripts:

- Adds FVM + Flutter to PATH in existing `.bashrc` and `.zshrc` files.
- Sets Git's global `init.defaultBranch` to `main` only if no value is configured.
- Adds your user to the `kvm` group on amd64. Log out and back in to apply it.

On Ubuntu, missing `snap` skips Snap apps. Fedora installs and starts Snap before installing apps.

Reruns skip tools that pass the installed checks. Existing tools stay on their current versions. Neither script runs a full system upgrade.

If `~/fvm/default/bin/flutter` is already executable, setup keeps that global SDK. Otherwise, it installs and selects stable. Every run checks Android + Linux artifacts with `flutter precache`, so a failed download can be retried.

Ubuntu's apt lists need Universe enabled. GitHub + GitLab CLI use each distro's packaged versions.

## Choose optional apps

Install all optional apps:

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | DEVSTRAP_OPTIONAL=all bash
```

Or pick the apps you need:

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | DEVSTRAP_OPTIONAL=warp,slack bash
```

| Name | App | Source |
| --- | --- | --- |
| `warp` | Warp terminal | Warp apt repository on Ubuntu amd64; Warp RPM repository on Fedora x86_64 |
| `spotify` | Spotify | Snap |
| `slack` | Slack | Snap |

Optional apps are off by default. Unknown names are ignored, so check for typos.

## Finish setup

1. Log out and back in to load the PATH changes + KVM group access.
2. Open Android Studio to download the Android SDK.
3. Run `flutter doctor` and follow the remaining setup steps.
4. Check KVM with `kvm-ok` on Ubuntu amd64 or `virt-host-validate qemu` on Fedora. Enable hardware virtualization in BIOS/UEFI if needed. Fedora's check also reports requirements for other VM features; focus on KVM support + access for the Android Emulator.

Sign in to the services you use:

```bash
gh auth login
glab auth login
gcloud init
```

Setup installs the CLIs but does not sign in or choose a Google Cloud project.

If neither `.bashrc` nor `.zshrc` existed during setup, add `~/fvm/bin` + `~/fvm/default/bin` to your shell's PATH yourself. Do the same if you use another shell.

## Configure a run

Set these variables on the `bash` side of the pipe, as shown above.

| Variable | Default | Purpose |
| --- | --- | --- |
| `DEVSTRAP_DRY_RUN` | `0` | Set to `1` to preview changes |
| `DEVSTRAP_OPTIONAL` | Empty | Use `all` or a comma-separated list of optional apps |
| `DEVSTRAP_REPO` | `theodorusyoga/devstrap` | Choose the GitHub `owner/repo` to fetch |
| `DEVSTRAP_BRANCH` | `main` | Choose the branch archive to fetch |
| `DEVSTRAP_TARBALL` | Unset | Use a local repo archive instead of downloading one |

`DEVSTRAP_REPO` and `DEVSTRAP_BRANCH` choose which archive the launcher downloads. To change the launcher too, update the URL in the command.

A local tarball needs one top-level repo directory containing `os/` + `packages/`. Installing tools still needs network access.

## Change the setup

```text
install.sh                         Detect the OS, fetch the repo, run its setup script
os/ubuntu.sh                       Install tools and configure Ubuntu
os/fedora.sh                       Install tools and configure Fedora
packages/ubuntu/apt.txt             Default apt packages
packages/ubuntu/snap.txt            Default Snap packages and flags
packages/ubuntu/optional-snap.txt   Optional Snap packages and flags
packages/fedora/dnf.txt             Default Fedora packages
packages/fedora/snap.txt            Fedora Snap packages and flags
packages/fedora/optional-snap.txt   Optional Fedora Snap packages and flags
```

Add one package per line to the matching list. Snap entries accept flags, like `code --classic`. Blank lines and full-line comments are ignored. Entries without a final newline are supported. Missing or unreadable lists stop setup before any changes.

For an optional Snap app, add it to the distro's `optional-snap.txt` and use its package name in `DEVSTRAP_OPTIONAL`. Put custom install steps in the OS script.

To add a Linux distro, create `os/<id>.sh` using its `ID` from `/etc/os-release`. macOS maps to `os/macos.sh`. The launcher passes the extracted repo path as `REPO_DIR`.

Running `bash install.sh` from a checkout still downloads an archive. To preview local changes, run the script for your distro:

```bash
DEVSTRAP_DRY_RUN=1 bash os/ubuntu.sh
# Or, on Fedora:
DEVSTRAP_DRY_RUN=1 bash os/fedora.sh
```

Run the isolated installer tests with:

```bash
python3 -B -m unittest discover -s tests -v
```

## Install references

- [GitHub CLI package](https://packages.ubuntu.com/resolute/gh) + [GitLab CLI package](https://packages.ubuntu.com/resolute/glab)
- [Google Cloud CLI](https://docs.cloud.google.com/sdk/docs/install-sdk)
- [ONLYOFFICE Snap](https://helpcenter.onlyoffice.com/desktop/installation/desktop-install-snap.aspx)
- [Ubuntu QEMU/KVM](https://ubuntu.com/server/docs/how-to/virtualisation/qemu/)
- [Fedora Snap setup](https://snapcraft.io/docs/tutorials/install-the-daemon/fedora/)
- [scrcpy Fedora setup](https://github.com/Genymobile/scrcpy/blob/master/doc/linux.md)
- [Warp RPM setup](https://docs.warp.dev/getting-started/quickstart/installation-and-setup)
- [Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)

## Roadmap

- Add macOS support with Homebrew, CocoaPods, FVM, Android Studio, Sourcetree, VS Code, Chrome, and scrcpy.
