import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'supervise', Path(__file__).resolve().parents[1] / 'container/supervise.py')
supervisor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(supervisor)


class Ready:
    def wait_for_connection(self, timeout):
        return True


class NotReady:
    def wait_for_connection(self, timeout):
        return False


class SupervisorTests(unittest.TestCase):
    def run_pair(self, ioc_code, model_code, ready=Ready, timeout=120):
        original = subprocess.Popen
        processes = []
        def launch(*args, **kwargs):
            process = original(*args, **kwargs)
            processes.append(process)
            return process
        try:
            with patch.dict(os.environ, {'RUN_SIM_PREFIX': 'TEST:SIM:'}), \
                    patch.object(supervisor.subprocess, 'Popen', launch):
                return supervisor.supervise(
                    [sys.executable, '-c', ioc_code],
                    [sys.executable, '-c', model_code],
                    lambda *args, **kwargs: ready(), timeout)
        finally:
            self.assertTrue(processes)
            self.assertTrue(all(p.poll() is not None for p in processes),
                            'supervisor left a child running')

    def test_ioc_exit_stops_models(self):
        self.assertEqual(self.run_pair('import time; time.sleep(.2)',
                                       'import time; time.sleep(30)'), 0)

    def test_model_failure_stops_ioc(self):
        with self.assertRaisesRegex(RuntimeError, 'simulator exited'):
            self.run_pair('import time; time.sleep(30)', 'raise SystemExit(2)')

    def test_readiness_timeout_stops_ioc(self):
        with self.assertRaisesRegex(RuntimeError, 'timed out'):
            self.run_pair('import time; time.sleep(30)', '', NotReady, .01)


if __name__ == '__main__':
    unittest.main()
