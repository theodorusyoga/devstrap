"""Exercise setup with fake system commands; never install host packages."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

STUB = r'''#!/usr/bin/env bash
set -eu
name="${0##*/}"
case "$name" in
  dpkg-query)
    if [[ " ${MISSING_PACKAGES:-} " == *" ${@: -1} "* ]]; then exit 1; fi
    printf 'install ok installed'
    ;;
  dpkg) echo "${TEST_ARCH:-amd64}" ;;
  id)
    if [ "$1" = "-un" ]; then echo testuser
    else echo "testuser ${TEST_GROUPS-kvm}"; fi
    ;;
  snap)
    [ "$1" = list ] && exit 1
    echo "snap $*" >> "$TEST_LOG"
    ;;
  git)
    if [[ "$*" == *"--get"* ]]; then
      if [ "${BRANCH_PRESENT:-1}" = 1 ]; then echo "${TEST_BRANCH:-develop}"; else exit 1; fi
    else echo "git $*" >> "$TEST_LOG"; fi
    ;;
  sudo)
    echo "sudo $*" >> "$TEST_LOG"
    if [ "$1" = tee ]; then cat >/dev/null; fi
    ;;
  wget) echo fake-key ;;
  gpg) cat ;;
  fvm)
    echo "fvm $*" >> "$TEST_LOG"
    if [ "$1" = global ]; then
      mkdir -p "$TEST_USER_DIR/fvm/default/bin"
      cp "$TEST_STUB" "$TEST_USER_DIR/fvm/default/bin/flutter"
    fi
    ;;
  flutter)
    echo "flutter $*" >> "$TEST_LOG"
    if [ -f "$TEST_USER_DIR/fail-precache" ]; then
      rm "$TEST_USER_DIR/fail-precache"
      exit 1
    fi
    ;;
  *) echo "Unexpected command: $name" >&2; exit 99 ;;
esac
'''


class UbuntuSetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.packages = self.root / 'packages/ubuntu'
        self.packages.mkdir(parents=True)
        for name in ('apt.txt', 'snap.txt', 'optional-snap.txt'):
            shutil.copy(ROOT / 'packages/ubuntu' / name, self.packages / name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.stub = self.root / 'stub'
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        for name in ('dpkg-query', 'dpkg', 'id', 'snap', 'git', 'sudo', 'wget', 'gpg'):
            (self.bin / name).symlink_to(self.stub)
        # Keep host CLIs (such as gcloud) out of installed-tool checks.
        for name in ('bash', 'awk', 'grep', 'basename', 'dirname', 'cat', 'mkdir', 'cp', 'rm'):
            (self.bin / name).symlink_to(shutil.which(name))
        self.user = self.root / 'user'
        for tool, rel in [('fvm', 'fvm/bin'), ('flutter', 'fvm/default/bin')]:
            folder = self.user / rel
            folder.mkdir(parents=True, exist_ok=True)
            shutil.copy(self.stub, folder / tool)
        (self.user / '.bashrc').write_text('# devstrap: fvm\n')
        # Redirect only the script's user-file references into the fixture.
        # Do not modify the process HOME or read/write real shell config.
        self.script = self.root / 'ubuntu.sh'
        self.script.write_text((ROOT / 'os/ubuntu.sh').read_text().replace('$HOME', '$TEST_USER_DIR'))
        self.log = self.root / 'events'
        self.env = dict(os.environ, PATH=str(self.bin),
                        REPO_DIR=str(self.root), TEST_USER_DIR=str(self.user),
                        TEST_STUB=str(self.stub), TEST_LOG=str(self.log),
                        DEVSTRAP_DRY_RUN='0', DEVSTRAP_OPTIONAL='',
                        MISSING_PACKAGES='', BRANCH_PRESENT='1', TEST_BRANCH='develop',
                        TEST_GROUPS='kvm', TEST_ARCH='amd64')

    def run_setup(self, **env):
        return subprocess.run(['/bin/bash', str(self.script)], env=dict(self.env, **env),
                              capture_output=True, text=True, timeout=10)

    def events(self):
        return self.log.read_text() if self.log.exists() else ''

    def test_missing_lists_fail_before_changes(self):
        for name in ('apt.txt', 'snap.txt', 'optional-snap.txt'):
            with self.subTest(name=name):
                path = self.packages / name
                data = path.read_text()
                path.unlink()
                result = self.run_setup()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Cannot read package list', result.stderr)
                self.assertEqual(self.events(), '')
                path.write_text(data)

    def test_unreadable_list_fails_before_changes(self):
        if os.geteuid() == 0:
            self.skipTest('root can read mode-000 files')
        path = self.packages / 'apt.txt'
        path.chmod(0)
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events(), '')

    def test_comments_and_empty_lists_are_valid(self):
        for path in self.packages.iterdir():
            path.write_text('  # comment\n\n\t')
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('apt-get install', self.events())
        self.assertNotIn('snap install', self.events())

    def test_final_entries_without_newline_are_installed(self):
        (self.packages / 'apt.txt').write_text('# comment\nlast-apt')
        (self.packages / 'snap.txt').write_text('last-snap --classic')
        (self.packages / 'optional-snap.txt').write_text('last-optional')
        result = self.run_setup(MISSING_PACKAGES='last-apt', DEVSTRAP_OPTIONAL='last-optional')
        self.assertEqual(result.returncode, 0, result.stderr)
        for command in ('apt-get install -y last-apt', 'snap install last-snap --classic',
                        'snap install last-optional'):
            self.assertIn(command, self.events())

    def test_failed_precache_is_retried_without_replacing_sdk(self):
        (self.user / 'fvm/default/bin/flutter').unlink()
        (self.user / 'fail-precache').touch()
        first = self.run_setup()
        self.assertNotEqual(first.returncode, 0)
        second = self.run_setup()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.events().count('fvm install stable'), 1)
        self.assertEqual(self.events().count('fvm global stable'), 1)
        self.assertEqual(self.events().count('flutter precache --android --linux'), 2)

    def test_existing_global_sdk_and_git_branch_are_preserved(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('default branch set to develop', result.stdout)
        self.assertNotIn('git config', self.events())
        self.assertNotIn('fvm global', self.events())
        self.assertIn('flutter precache --android --linux', self.events())

    def test_missing_git_branch_defaults_to_main(self):
        result = self.run_setup(BRANCH_PRESENT='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('git config --global init.defaultBranch main', self.events())

    def test_new_apps_and_kvm_setup(self):
        packages = 'gh glab clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev google-cloud-cli qemu-system-x86'
        result = self.run_setup(MISSING_PACKAGES=packages, TEST_GROUPS='')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        for package in packages.split():
            self.assertIn(package, events)
        self.assertIn('snap install onlyoffice-desktopeditors', events)
        self.assertIn('sudo usermod -aG kvm testuser', events)
        self.assertLess(events.index('tee /etc/apt/sources.list.d/google-cloud-sdk.list'),
                        events.rindex('apt-get update'))
        self.assertLess(events.rindex('apt-get update'), events.index('apt-get install -y google-cloud-cli'))

    def test_dry_run_does_not_execute_changes(self):
        result = self.run_setup(DEVSTRAP_DRY_RUN='1', TEST_GROUPS='', BRANCH_PRESENT='0',
                                MISSING_PACKAGES='gh glab google-cloud-cli qemu-system-x86')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), '')
        for command in ('usermod -aG kvm', 'apt-get install -y google-cloud-cli',
                        'snap install onlyoffice-desktopeditors', 'flutter precache --android --linux',
                        'git config --global init.defaultBranch main'):
            self.assertIn(command, result.stdout)

    def test_existing_gcloud_does_not_add_another_install(self):
        (self.bin / 'gcloud').symlink_to(self.stub)
        result = self.run_setup(MISSING_PACKAGES='google-cloud-cli')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('google-cloud-sdk.list', self.events())
        self.assertNotIn('install -y google-cloud-cli', self.events())

    def test_kvm_setup_skips_other_architectures(self):
        result = self.run_setup(TEST_ARCH='arm64', TEST_GROUPS='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('KVM setup currently targets amd64, skipping', result.stdout)
        self.assertNotIn('usermod', self.events())


if __name__ == '__main__':
    unittest.main()
