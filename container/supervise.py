#!/usr/bin/env python3
"""Run an interactive IOC and its CA hardware models in the same container."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def supervise(command, model_command, pv_factory, timeout=120):
    ioc = model = None
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    old_handlers = {sig: signal.signal(sig, interrupted)
                    for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        # IOC inherits the terminal; Python models never read its input.
        ioc = subprocess.Popen(command)
        prefix = os.environ['RUN_SIM_PREFIX']
        ready = pv_factory(prefix + 'FirstSlave', auto_monitor=False)
        deadline = time.monotonic() + timeout
        print(f'run-sim: waiting for {prefix}FirstSlave (up to {timeout}s)', flush=True)
        while not ready.wait_for_connection(timeout=0.5):
            if ioc.poll() is not None:
                return ioc.returncode or 1
            if time.monotonic() >= deadline:
                raise RuntimeError(f'timed out waiting for {prefix}FirstSlave; '
                                   'check IOC startup and --sim-prefix')
        model = subprocess.Popen(model_command, stdin=subprocess.DEVNULL)
        print(f'run-sim: hardware models started for {prefix}', flush=True)
        while ioc.poll() is None:
            if model.poll() is not None:
                raise RuntimeError(f'hardware simulator exited ({model.returncode}); stopping IOC')
            time.sleep(0.2)
        return ioc.returncode
    except KeyboardInterrupt:
        return 130
    finally:
        # Models can clear enabled feedback while the IOC is still alive.
        for sig in old_handlers:
            signal.signal(sig, signal.SIG_IGN)
        stop(model)
        stop(ioc)
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)


def main():
    os.environ['EPICS_CA_AUTO_ADDR_LIST'] = 'NO'
    os.environ['EPICS_CA_ADDR_LIST'] = '127.0.0.1'
    from epics import PV
    command = [sys.executable, '-u', '/opt/ecmc-simulation/ioc.py',
               '--prefix', os.environ['RUN_SIM_PREFIX'],
               '--master', os.environ.get('RUN_SIM_MASTER', '0')]
    settings = os.environ.get('RUN_SIM_SETTINGS')
    if settings:
        if not Path(settings).is_file():
            raise RuntimeError(f'model settings not found: {settings}')
        command += ['--settings', settings]
    return supervise(sys.argv[1:], command, PV)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ImportError) as error:
        sys.exit(f'run-sim: {error}')
