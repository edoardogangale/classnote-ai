"""Portable packaging tests with synthetic bundles, not actual iPad executables."""
import contextlib
import io
from pathlib import Path
import plistlib
import stat
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from package_ipa import package
from select_ipad_simulator import select


class DeliveryTests(unittest.TestCase):
    def make_app(self, root, platform='iPhoneOS', executable='ClassNoteAI'):
        app = root / 'ClassNoteAI.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'test.synthetic.classnote',
            'CFBundleExecutable': executable,
            'CFBundleSupportedPlatforms': [platform]
        }))
        binary = app / 'ClassNoteAI'
        binary.write_bytes(b'SYNTHETIC-PACKAGING-FIXTURE-NOT-AN-IPAD-BINARY')
        binary.chmod(0o755)
        return app

    def test_payload_preserves_executable_and_relative_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = self.make_app(root)
            (app / 'alias').symlink_to('ClassNoteAI')
            with contextlib.redirect_stdout(io.StringIO()):
                result = package(app, root / 'result.ipa')
            with zipfile.ZipFile(result) as archive:
                executable = archive.getinfo('Payload/ClassNoteAI.app/ClassNoteAI')
                self.assertTrue((executable.external_attr >> 16) & stat.S_IXUSR)
                alias = archive.getinfo('Payload/ClassNoteAI.app/alias')
                self.assertEqual(stat.S_IFMT(alias.external_attr >> 16), stat.S_IFLNK)
                self.assertEqual(archive.read(alias), b'ClassNoteAI')
                self.assertIsNone(archive.testzip())

    def test_simulator_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = self.make_app(root, platform='iPhoneSimulator')
            with self.assertRaisesRegex(ValueError, 'Simulator'):
                package(app, root / 'result.ipa')
            self.assertFalse((root / 'result.ipa').exists())

    def test_executable_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = self.make_app(root, executable='../other')
            with self.assertRaisesRegex(ValueError, 'CFBundleExecutable'):
                package(app, root / 'result.ipa')

    def test_output_inside_app_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(Path(directory))
            with self.assertRaisesRegex(ValueError, 'outside'):
                package(app, app / 'recursive.ipa')

    def test_simulator_selection_ignores_newer_incompatible_and_unavailable_runtimes(self):
        def device(name, udid, available=True):
            return {'name': name, 'udid': udid, 'isAvailable': available}
        data = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [device('iPad Pro', 'too-new')],
            'com.apple.CoreSimulator.SimRuntime.iOS-18-5': [device('iPad Pro', 'chosen'), device('iPad Air', 'missing', False)],
            'com.apple.CoreSimulator.SimRuntime.iOS-18-4': [device('iPad Pro', 'older')]
        }}
        self.assertEqual(select(data, '18.5')[2], 'chosen')
        with self.assertRaises(RuntimeError):
            select(data, '17.5')


if __name__ == '__main__':
    unittest.main()
