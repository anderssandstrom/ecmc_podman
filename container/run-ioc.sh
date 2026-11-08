#!/bin/bash
set -euo pipefail
source /opt/ecmc-env.sh
runner=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
component=$(python3 "$runner/prepare-startup.py" --component-version)
if [[ ${RUN_SIM_AUTO:-1} == 1 ]]; then
    prepared=$(mktemp /tmp/ecmc-startup.XXXXXX.cmd)
    python3 "$runner/prepare-startup.py" "$1" "$prepared"
    shift
    set -- "$prepared" "$@"
fi
name_args=()
if [[ -n ${RUN_SIM_IOC_NAME:-} ]]; then name_args=(-n "$RUN_SIM_IOC_NAME"); fi
cmd=(/opt/require/iocsh --nolock "${name_args[@]}" -r "ecmccomp,$component" "$@")
if [[ ${RUN_SIM_HARDWARE:-0} == 1 ]]; then
    [[ -x /opt/ecmc-python/bin/python && -f /opt/ecmc-simulation/ioc.py ]] || {
        echo 'Hardware simulation requires a rebuilt image: ./build-image.sh' >&2; exit 1;
    }
    exec /opt/ecmc-python/bin/python "$runner/supervise.py" "${cmd[@]}"
fi
exec "${cmd[@]}"
