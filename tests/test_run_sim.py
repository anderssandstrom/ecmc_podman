import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RunSimTests(unittest.TestCase):
    def run_script(self, *args, env=None):
        return subprocess.run(
            [str(ROOT / 'run-sim.sh'), *args,
             str(ROOT / 'examples/smoke/startup.cmd')],
            text=True, capture_output=True, env=env)

    def test_dry_run_all_sources(self):
        args = ['--dry-run']
        for module in ('ecmc', 'ecmccfg', 'ecmccomp'):
            args += [f'--{module}-remote', f'https://example.org/{module}.git',
                     f'--{module}-ref', 'feature/test',
                     f'--{module}-version', 'custom']
        result = self.run_script(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].startswith('podman build '))
        self.assertTrue(lines[1].startswith('podman run '))
        for module in ('ECMC', 'ECMCCFG', 'ECMCCOMP'):
            self.assertIn(f'{module}_REF=feature/test', lines[0])
            self.assertIn(f'{module}_REFRESH=', lines[0])
            self.assertIn(f'{module}_VERSION=custom', lines[0])
            self.assertIn(f'RUN_SIM_{module}_VERSION=custom', lines[1])
        self.assertTrue(all('ecmc-dev:simulation' in line for line in lines))

    def test_missing_refs_fail(self):
        for module in ('ecmc', 'ecmccfg', 'ecmccomp'):
            result = self.run_script('--dry-run', f'--rebuild-{module}')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f'requires --{module}-ref', result.stderr)

    def test_existing_image_does_not_build(self):
        result = self.run_script('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1)
        self.assertIn('ecmc-dev:v11.2.0_RC1', result.stdout)

    def test_build_failure_prevents_run_and_success_uses_same_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'podman'
            log = Path(tmp) / 'calls.jsonl'
            fake.write_text(
                '#!/usr/bin/env python3\n'
                'import json, os, sys\n'
                'with open(os.environ["CALL_LOG"], "a") as f:\n'
                '    f.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                'sys.exit(int(os.environ["BUILD_STATUS"]) '
                'if sys.argv[1] == "build" else 0)\n')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=tmp + os.pathsep + os.environ['PATH'],
                       CALL_LOG=str(log), BUILD_STATUS='7')
            args = ('--image', 'ecmc-dev:test', '--ecmccfg-ref', 'main')
            result = self.run_script(*args, env=env)
            self.assertEqual(result.returncode, 7)
            self.assertEqual(len(log.read_text().splitlines()), 1)
            log.write_text('')
            env['BUILD_STATUS'] = '0'
            result = self.run_script(*args, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual([call[0] for call in calls], ['build', 'run'])
            self.assertTrue(all('ecmc-dev:test' in call for call in calls))


if __name__ == '__main__':
    unittest.main()
