#!/usr/bin/env bash
# Run a host-side ECMC startup file using the development container.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: run-sim.sh [options] STARTUP_FILE [MACRO=value ...]

Options:
  --image IMAGE       Container image (default: ecmc-dev:v11.2.0_RC1)
  --ioc-name NAME     IOC name and default PV prefix (iocsh -n)
  --root DIRECTORY    Mount this configuration tree instead of the startup directory
  --env NAME=value    Set a container environment variable (repeatable)
  --ecmc-version VER  Select an installed ecmc version if several exist
  --ecmccfg-version VER  Select an installed ecmccfg version if several exist
  --ecmccomp-version VER  Select installed component definitions
  --hardware-sim      Start Python hardware models alongside the IOC (headless)
  --sim-prefix PREFIX Simulation PV prefix (default: IOC_NAME:SIM:)
  --sim-master N      EtherCAT master for model discovery (default: 0)
  --sim-settings FILE Host JSON file with per-slave model settings
  --as-is            Skip startup rewriting
  --no-ports          Do not publish Channel Access ports on localhost
  --dry-run           Print the container command without running it
  -h, --help          Show this help

The startup directory is the IOC working directory. Configuration is mounted
read-only. Use --root for includes referring to parent/sibling directories.
By default, a temporary startup copy uses SIM=1 and installed ecmc/ecmccfg/ecmccomp
versions. Only require lines in the supplied startup file are rewritten.
Additional MACRO=value arguments are passed to the PSI iocsh launcher.
EOF
}

fail() { printf 'run-sim: %s\n' "$*" >&2; exit 1; }
image=ecmc-dev:v11.2.0_RC1
root=
ioc_name=
hardware_sim=0
sim_prefix=
sim_master=0
sim_settings=
ports=1
dry_run=0
env_args=()
auto_config=1
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --image|--root|--env|--ecmc-version|--ecmccfg-version|--ecmccomp-version|--ioc-name|--sim-prefix|--sim-master|--sim-settings)
            (($# >= 2)) || fail "$1 requires a value"
            case "$1" in
                --sim-prefix) sim_prefix=$2 ;;
                --sim-master)
                    [[ $2 =~ ^[0-9]+$ ]] || fail '--sim-master expects a nonnegative integer'
                    sim_master=$2 ;;
                --sim-settings) sim_settings=$2 ;;
                --ecmccomp-version) env_args+=(--env "RUN_SIM_ECMCCOMP_VERSION=$2") ;;
                --image) image=$2 ;;
                --root) root=$2 ;;
                --ioc-name)
                    [[ -n $2 && $2 != -* && $2 != *[[:space:]]* ]] || fail 'IOC name must be nonempty, contain no whitespace, and not start with -'
                    ioc_name=$2 ;;
                --ecmc-version) env_args+=(--env "RUN_SIM_ECMC_VERSION=$2") ;;
                --ecmccfg-version) env_args+=(--env "RUN_SIM_ECMCCFG_VERSION=$2") ;;
                --env)
                    [[ $2 =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]] || fail '--env expects NAME=value'
                    env_args+=(--env "$2") ;;
            esac
            shift 2 ;;
        --hardware-sim) hardware_sim=1; shift ;;
        --no-ports) ports=0; shift ;;
        --as-is) auto_config=0; shift ;;
        --dry-run) dry_run=1; shift ;;
        --) shift; break ;;
        -*) fail "unknown option: $1" ;;
        *) break ;;
    esac
done
(($#)) || { usage >&2; exit 1; }
startup=$1
shift
[[ -f $startup && -r $startup ]] || fail "startup file is not readable: $startup"
startup_dir=$(cd -- "$(dirname -- "$startup")" && pwd -P)
startup_name=$(basename -- "$startup")
root=${root:-$startup_dir}
[[ -d $root ]] || fail "configuration root is not a directory: $root"
root=$(cd -- "$root" && pwd -P)
[[ $root != / ]] || fail 'choose a configuration directory instead of /'
case "$startup_dir/" in
    "$root/"*) ;;
    *) fail 'startup file must be inside --root' ;;
esac
# Podman volume syntax cannot represent colons in host paths.
[[ $root != *:* ]] || fail 'configuration root must not contain a colon'
relative_dir=${startup_dir#"$root"}
for macro in "$@"; do
    [[ $macro =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]] || fail "expected MACRO=value: $macro"
done

if ((hardware_sim)); then
    sim_prefix=${sim_prefix:-${ioc_name:+$ioc_name:SIM:}}
    [[ -n $sim_prefix ]] || fail '--hardware-sim needs --ioc-name or --sim-prefix'
fi
if [[ -n $sim_settings ]]; then
    ((hardware_sim)) || fail '--sim-settings requires --hardware-sim'
    [[ -r $sim_settings && -f $sim_settings ]] || fail "cannot read model settings: $sim_settings"
    sim_settings=$(cd -- "$(dirname -- "$sim_settings")" && pwd -P)/$(basename -- "$sim_settings")
    [[ $sim_settings != *:* ]] || fail 'model settings path must not contain a colon'
fi

# Allow read-only source mounts on SELinux hosts without relabeling Git trees.
cmd=(podman run --rm -i --security-opt label=disable)
if [[ -t 0 && -t 1 ]]; then cmd+=(-t); fi
cmd+=(--volume "$root:/config:ro" --workdir "/config$relative_dir")
if ((ports)); then
    cmd+=(-p 127.0.0.1:5064:5064/tcp -p 127.0.0.1:5064:5064/udp
          -p 127.0.0.1:5065:5065/udp)
fi
cmd+=(--volume "$script_dir/prepare-startup.py:/run/ecmc-runner/prepare-startup.py:ro"
      --volume "$script_dir/container/run-ioc.sh:/run/ecmc-runner/run-ioc.sh:ro"
      --volume "$script_dir/container/supervise.py:/run/ecmc-runner/supervise.py:ro"
      --env "RUN_SIM_AUTO=$auto_config")
if ((${#env_args[@]})); then cmd+=("${env_args[@]}"); fi
cmd+=(--env "RUN_SIM_IOC_NAME=$ioc_name" --env "RUN_SIM_HARDWARE=$hardware_sim"
      --env "RUN_SIM_PREFIX=$sim_prefix" --env "RUN_SIM_MASTER=$sim_master")
if [[ -n $sim_settings ]]; then
    cmd+=(--volume "$sim_settings:/run/ecmc-models.json:ro"
          --env RUN_SIM_SETTINGS=/run/ecmc-models.json)
fi
cmd+=("$image" /bin/bash /run/ecmc-runner/run-ioc.sh "./$startup_name" "$@")
if ((dry_run)); then
    printf '%q ' "${cmd[@]}"
    printf '\n'
    exit 0
fi
command -v podman >/dev/null 2>&1 || fail 'podman is not installed or not on PATH'
exec "${cmd[@]}"
