#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
image=ecmc-dev:v11.2.0_RC1
dry=0
args=()
while (($#)); do
    case "$1" in
        -h|--help)
            cat <<'HELP'
Usage: build-image.sh [options]
  --image TAG                  Output image tag
  --ecmc-ref REF               ECMC source tag, branch or commit
  --ecmccfg-ref REF            ecmccfg source tag, branch or commit
  --ecmccomp-ref REF           ecmccomp source tag, branch or commit
  --ecmc-version NAME          Installed ECMC module version
  --ecmccfg-version NAME       Installed ecmccfg module version
  --ecmccomp-version NAME      Installed ecmccomp module version
  --build-arg NAME=VALUE       Additional Containerfile argument (repeatable)
  --platform linux/arm64|linux/amd64  Target platform (default: native)
  --no-cache                  Rebuild all layers
  --dry-run                   Print the build command
Source refs and installed module names are independent. For forks use
--build-arg ECMC_REPOSITORY=https://... (also ECMCCFG_ and ECMCCOMP_).
HELP
            exit 0 ;;
        --no-cache) args+=(--no-cache); shift ;;
        --dry-run) dry=1; shift ;;
        --image|--build-arg|--platform|--ecmc-ref|--ecmccfg-ref|--ecmccomp-ref|--ecmc-version|--ecmccfg-version|--ecmccomp-version)
            (($# >= 2)) && [[ -n $2 ]] || { echo "$1 requires a value" >&2; exit 1; }
            case "$1" in
                --image) image=$2 ;;
                --build-arg|--platform) args+=("$1" "$2") ;;
                *)
                    if [[ $1 == *-version && ! $2 =~ ^[a-zA-Z0-9_.+-]+$ ]]; then
                        echo 'Module version names must use letters, digits, _, ., + or -' >&2
                        exit 1
                    fi
                    key=${1#--}; key=${key//-/_}; key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
                    args+=(--build-arg "$key=$2") ;;
            esac
            shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done
cmd=(podman build --format docker -t "$image" -f "$here/Containerfile")
if ((${#args[@]})); then cmd+=("${args[@]}"); fi
cmd+=("$here")
if ((dry)); then printf '%q ' "${cmd[@]}"; printf '\n'; else exec "${cmd[@]}"; fi
