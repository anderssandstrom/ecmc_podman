import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'prepare_startup', Path(__file__).resolve().parents[1] / 'prepare-startup.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class StartupTests(unittest.TestCase):
    def test_component_version_is_replaced(self):
        source = 'require ecmccomp "old"\nrequire ecmccfg "old"\n'
        result = prepare.rewrite(source, 'motor', 'cfg', 'components')
        self.assertIn('require ecmccomp "components"\n', result)
        self.assertIn('require ecmccfg "cfg" "SIM=1,ECMC_VER=motor"\n', result)

    def test_require_formats(self):
        for source in (
            'require ecmccfg ${CFG=old} "MASTER_ID=0,SIM=0,ECMC_VER=${VER=old}"',
            'require("ecmccfg", "old", "MASTER_ID=0,SIM=0") # comment',
            'require ecmccfg,old,"MASTER_ID=0"',
            'require ecmccfg "MASTER_ID=0"',
        ):
            with self.subTest(source=source):
                self.assertEqual(prepare.rewrite(source, 'new', 'cfg'),
                                 'require ecmccfg "cfg" "MASTER_ID=0,SIM=1,ECMC_VER=new"\n')

    def test_preserves_other_commands_and_macros(self):
        source = ('# require ecmccfg old\nrequire asyn old\n'
                  'require ecmc "old"\n'
                  'require ecmccfg old "MASTER_ID=-1,OTHER=${X=a,b},SIM=${SIM=0}"\n'
                  'iocshLoad "./cfg/axis.cmd"\n')
        result = prepare.rewrite(source, 'new', 'cfg')
        self.assertIn('require ecmc "new"\n', result)
        self.assertIn('MASTER_ID=-1,OTHER=${X=a,b},SIM=1,ECMC_VER=new', result)
        self.assertTrue(result.startswith('# require ecmccfg old\nrequire asyn old\n'))
        self.assertTrue(result.endswith('iocshLoad "./cfg/axis.cmd"\n'))

    def test_refuses_opaque_or_indirect_startup(self):
        for source in ('iocshLoad "other.cmd"', 'require ecmccfg old "${ARGS}"'):
            with self.assertRaises(ValueError):
                prepare.rewrite(source, 'new', 'cfg')

    def test_version_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            modules = Path(directory)
            def add(version, arch='linux-aarch64'):
                library = modules / 'ecmc' / version / 'R7.0.10/lib' / arch / 'libecmc.so'
                library.parent.mkdir(parents=True)
                library.touch()
            def select(requested=None):
                return prepare.installed_version('ecmc', modules, '7.0.10',
                                                 'linux-aarch64', requested)
            with self.assertRaises(ValueError):
                select()
            add('v1')
            add('wrong-arch', 'linux-x86_64')
            self.assertEqual(select(), 'v1')
            add('v2')
            with self.assertRaises(ValueError):
                select()
            self.assertEqual(select('v2'), 'v2')
            with self.assertRaises(ValueError):
                select('missing')


if __name__ == '__main__':
    unittest.main()
