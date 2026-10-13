"""Run Fedora setup with isolated files + fake package managers."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tarfile
import unittest

from test_ubuntu import STUB as UBUNTU_STUB

ROOT = Path(__file__).resolve().parents[1]
STUB = UBUNTU_STUB.replace('  dpkg-query)', '''  rpm)
    if [[ " ${MISSING_PACKAGES:-} " == *" $2 "* ]]; then exit 1; fi
    ;;
  uname)
    if [ "$1" = -s ]; then echo Linux; else echo "${TEST_ARCH:-x86_64}"; fi
    ;;
  dnf5) exit 99 ;;
  systemctl) exit "${SOCKET_MISSING:-0}" ;;
  curl) exit 99 ;;
  dpkg-query)''').replace('if [ "$1" = "-un" ]; then echo testuser',
                        'if [ "$1" = "-u" ]; then echo "${TEST_UID:-1000}"\n    elif [ "$1" = "-un" ]; then echo testuser').replace(
                            '[ "$1" = list ] && exit 1',
                            '[ "$1" = list ] && exit "${SNAPS_MISSING:-0}"')


class FedoraSetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.packages = self.root / 'packages/fedora'
        self.packages.mkdir(parents=True)
        for name in ('dnf.txt', 'snap.txt', 'optional-snap.txt'):
            shutil.copy(ROOT / 'packages/fedora' / name, self.packages / name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.stub = self.root / 'stub'
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        for name in ('rpm', 'uname', 'id', 'dnf5', 'systemctl', 'snap', 'git', 'sudo', 'curl'):
            (self.bin / name).symlink_to(self.stub)
        for name in ('bash', 'awk', 'grep', 'basename', 'cat', 'mkdir', 'cp', 'rm', 'readlink'):
            (self.bin / name).symlink_to(shutil.which(name))
        self.user = self.root / 'user'
        for tool, folder in [('fvm', 'fvm/bin'), ('flutter', 'fvm/default/bin')]:
            path = self.user / folder
            path.mkdir(parents=True, exist_ok=True)
            shutil.copy(self.stub, path / tool)
        (self.user / '.bashrc').write_text('# devstrap: fvm\n')
        self.os_release = self.root / 'os-release'
        self.os_release.write_text('ID=fedora\nVERSION_ID=44\n')
        self.snap_link = self.root / 'snap'
        self.snap_link.symlink_to('/var/lib/snapd/snap')
        source = (ROOT / 'os/fedora.sh').read_text()
        source = source.replace('$HOME', '$TEST_USER_DIR')
        source = source.replace('/etc/os-release', str(self.os_release))
        source = source.replace('/run/ostree-booted', str(self.root / 'ostree-booted'))
        source = source.replace('[ ! -e /snap ]', f'[ ! -e {self.snap_link} ]')
        source = source.replace('[ ! -L /snap ]', f'[ ! -L {self.snap_link} ]')
        source = source.replace('readlink -f /snap', f'readlink -m {self.snap_link}')
        self.script = self.root / 'fedora.sh'
        self.script.write_text(source)
        self.log = self.root / 'events'
        self.env = dict(os.environ, PATH=str(self.bin), REPO_DIR=str(self.root),
                        TEST_USER_DIR=str(self.user), TEST_STUB=str(self.stub), TEST_LOG=str(self.log),
                        DEVSTRAP_DRY_RUN='0', DEVSTRAP_OPTIONAL='', MISSING_PACKAGES='',
                        BRANCH_PRESENT='1', TEST_BRANCH='develop', TEST_GROUPS='kvm',
                        TEST_ARCH='x86_64', TEST_UID='1000', SOCKET_MISSING='0', SNAPS_MISSING='0')

    def run_setup(self, **env):
        return subprocess.run(['/bin/bash', str(self.script)], env=dict(self.env, **env),
                              capture_output=True, text=True, timeout=10)

    def events(self):
        return self.log.read_text() if self.log.exists() else ''

    def test_installed_tools_and_preferences_are_preserved(self):
        result = self.run_setup(DEVSTRAP_OPTIONAL='all')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), 'sudo snap wait system seed.loaded\nflutter precache --android --linux\n')
        self.assertIn('default branch set to develop', result.stdout)

    def test_all_new_tools_use_correct_install_routes(self):
        result = self.run_setup(MISSING_PACKAGES='gh glab snapd qemu-kvm scrcpy google-cloud-cli google-chrome-stable warp-terminal',
                                DEVSTRAP_OPTIONAL='all', TEST_GROUPS='', SNAPS_MISSING='1', SOCKET_MISSING='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        for command in ('dnf5 install -y gh glab snapd qemu-kvm', 'dnf5 copr enable -y zeno/scrcpy',
                        'dnf5 install -y scrcpy', 'dnf5 install -y google-cloud-cli',
                        'dnf5 install -y google-chrome-stable', 'dnf5 install -y warp-terminal',
                        'systemctl enable --now snapd.socket', 'usermod -aG kvm testuser',
                        'snap install code --classic', 'snap install android-studio --classic',
                        'snap install onlyoffice-desktopeditors', 'snap install spotify', 'snap install slack'):
            self.assertIn(command, events)
        self.assertLess(events.index('google-cloud-sdk.repo'), events.index('install -y google-cloud-cli'))
        self.assertLess(events.index('snap wait'), events.index('snap install'))

    def test_dry_run_on_fresh_snap_setup_changes_nothing(self):
        self.snap_link.unlink()
        (self.bin / 'snap').unlink()
        result = self.run_setup(DEVSTRAP_DRY_RUN='1', MISSING_PACKAGES='snapd scrcpy google-cloud-cli',
                                SOCKET_MISSING='1', TEST_GROUPS='', BRANCH_PRESENT='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), '')
        for command in ('dnf5 install -y snapd', 'ln -s /var/lib/snapd/snap /snap',
                        'snap install code --classic', 'git config --global init.defaultBranch main'):
            self.assertIn(command, result.stdout)

    def test_missing_list_fails_before_changes(self):
        (self.packages / 'optional-snap.txt').unlink()
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Cannot read package list', result.stderr)
        self.assertEqual(self.events(), '')

    def test_last_line_without_newline_and_comments(self):
        (self.packages / 'dnf.txt').write_text('  # comment\n\nlast-package')
        (self.packages / 'snap.txt').write_text('# comment\nlast-snap --classic')
        result = self.run_setup(MISSING_PACKAGES='last-package', SNAPS_MISSING='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('dnf5 install -y last-package', self.events())
        self.assertIn('snap install last-snap --classic', self.events())

    def test_optional_selection(self):
        result = self.run_setup(DEVSTRAP_OPTIONAL='slack', SNAPS_MISSING='1', MISSING_PACKAGES='warp-terminal')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('snap install slack', self.events())
        self.assertNotIn('snap install spotify', self.events())
        self.assertNotIn('warp-terminal', self.events())

    def test_retry_flutter_without_reselecting_sdk(self):
        (self.user / 'fvm/default/bin/flutter').unlink()
        (self.user / 'fail-precache').touch()
        self.assertNotEqual(self.run_setup().returncode, 0)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events().count('fvm global stable'), 1)
        self.assertEqual(self.events().count('flutter precache --android --linux'), 2)

    def test_platform_guards_fail_before_changes(self):
        for content, env in [('ID=ubuntu\n', {}), ('ID=fedora\nVARIANT_ID=kinoite\n', {}),
                             ('ID=fedora\n', {'TEST_ARCH': 'aarch64'}),
                             ('ID=fedora\n', {'TEST_UID': '0'})]:
            with self.subTest(content=content, env=env):
                self.os_release.write_text(content)
                self.assertNotEqual(self.run_setup(**env).returncode, 0)
                self.assertEqual(self.events(), '')

    def test_existing_snap_path_is_not_overwritten(self):
        self.snap_link.unlink()
        self.snap_link.mkdir()
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('/snap already exists', result.stderr)
        self.assertNotIn('ln -s', self.events())

    def test_launcher_dispatches_fedora_from_local_archive(self):
        for name in ('mktemp', 'tar', 'gzip', 'find', 'head', 'ls', 'wget'):
            (self.bin / name).symlink_to(shutil.which(name))
        self.os_release.write_text('ID=fedora\nPRETTY_NAME="Fedora Linux"\n')
        launcher = self.root / 'install.sh'
        launcher.write_text((ROOT / 'install.sh').read_text().replace(
            '/etc/os-release', str(self.os_release)))
        payload = self.root / 'payload'
        (payload / 'os').mkdir(parents=True)
        (payload / 'os/fedora.sh').write_text(
            'test -f "$REPO_DIR/packages/fedora/dnf.txt" || exit 1\n'
            'echo "Fedora dispatched: dry-run=$DEVSTRAP_DRY_RUN"\n')
        shutil.copytree(self.root / 'packages', payload / 'packages')
        archive = self.root / 'repo.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            tar.add(payload, arcname='devstrap')
        result = subprocess.run(['/bin/bash', str(launcher)],
                                env=dict(self.env, DEVSTRAP_DRY_RUN='1', DEVSTRAP_TARBALL=str(archive)),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Fedora dispatched: dry-run=1', result.stdout)


if __name__ == '__main__':
    unittest.main()
