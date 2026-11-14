# ECMC simulation container

Build an EPICS/ECMC runtime and run a machine startup file in Podman. Host
configuration files are mounted read-only. The image includes EPICS Base,
PSI require/misc, asyn, motorECMC, Ruckig, EtherLab userspace, ecmc, ecmccfg,
ecmccomp and Python hardware models. No host EPICS or Python installation is
needed to run simulations.

## Setup and quick start

Install Podman on macOS or Linux. On macOS, create and start its Linux VM once:

```bash
podman machine init
podman machine start
```

Skip `init` if you already have a machine. Native Linux Podman does not need a
VM. Allow enough VM memory for C++ compilation (8 GB is a useful starting point)
and several GB of disk space. The first build downloads sources/packages and
can take a while. Later builds reuse layers.

From this repository (or call the scripts by their full paths):

```bash
./build-image.sh
./run-sim.sh --ioc-name SIMIOC examples/smoke/startup.cmd
```

The bundled example configures an EL7031 terminal in memory, without a motor
axis. To start its Python drive model too:

```bash
./run-sim.sh --ioc-name SIMIOC --hardware-sim examples/smoke/startup.cmd
```

For your machine:

```bash
./run-sim.sh --ioc-name SIMIOC /path/to/configuration/startup.cmd
```
Connect to IOC with caqtdm:
```
export EPICS_CA_ADDR_LIST=127.0.0.1
caqtdm -macro IOC=SIMIOC ecmcMain.ui
```
Type `exit` at the IOC prompt to stop. The temporary container is removed.
The build defaults to tag `ecmc-dev:v11.2.0_RC1`; use `--image` on both scripts
for a different image. Rebuild older images to get packaged Python models and
dependencies. No manual installation inside a running container is needed.

## Custom ecmc, ecmccfg and ecmccomp versions

Each module has two independent build settings:

| Module | Source revision | Installed module name | Optional source URL |
| --- | --- | --- | --- |
| ecmc | `ECMC_REF` | `ECMC_VERSION` | `ECMC_REPOSITORY` |
| ecmccfg | `ECMCCFG_REF` | `ECMCCFG_VERSION` | `ECMCCFG_REPOSITORY` |
| ecmccomp | `ECMCCOMP_REF` | `ECMCCOMP_VERSION` | `ECMCCOMP_REPOSITORY` |

Refs can be tags, branches or full commits. Installed names should be simple
version strings, without slashes or whitespace. They are the names used by
`require`, not necessarily the Git revision. Use matching compatible sources;
selecting a version cannot make an old module understand newer configuration.

For example, build tagged ECMC/configuration sources into a separate image:

```bash
./build-image.sh --image ecmc-dev:my-machine \
  --ecmc-ref v11.2.0_RC1 --ecmc-version v11.2.0_RC1 \
  --ecmccfg-ref v11.2.0_RC1 --ecmccfg-version v11.2.0_RC1 \
  --ecmccomp-ref a90964dea22323fcf797a9286044c0d0f68a9fce \
  --ecmccomp-version PSI_default

./run-sim.sh --image ecmc-dev:my-machine --ioc-name SIMIOC startup.cmd
```

For a fork or development branch:

```bash
./build-image.sh --image ecmc-dev:custom \
  --build-arg ECMC_REPOSITORY=https://github.com/YOUR_ORG/ecmc.git \
  --ecmc-ref YOUR_BRANCH --ecmc-version custom
```

The other two repositories can be overridden the same way. Publish commits to
a reachable repository first; uncommitted host changes are not copied into the
build. Do not put credentials in build arguments. Private repository access is
not configured by these scripts.

You can also build and start the simulation in one command. Specify a remote
URL and a branch, tag or commit for each module you want to change:

```bash
./run-sim.sh --ioc-name SIMIOC --hardware-sim \
  --ecmc-remote https://github.com/anderssandstrom/ecmc.git \
  --ecmc-ref YOUR_ECMC_BRANCH \
  --ecmccfg-remote https://github.com/anderssandstrom/ecmccfg.git \
  --ecmccfg-ref YOUR_CFG_BRANCH \
  --ecmccomp-remote https://github.com/paulscherrerinstitute/ecmccomp.git \
  --ecmccomp-ref YOUR_COMPONENT_TAG \
  examples/smoke/startup.cmd
```

Each `--MODULE-ref` implies rebuilding; explicit `--rebuild-ecmc`,
`--rebuild-ecmccfg` and `--rebuild-ecmccomp` flags are also accepted and require
the corresponding ref. Remote URLs are optional and default to those shown
above. You can select just one module or any combination. Requested sources
are fetched on every rebuild so moving branches are refreshed. Earlier image
layers are reused when available; layers after a changed module may also rebuild.
The IOC starts only after a successful build.

The output image defaults to `ecmc-dev:simulation`; use `--image TAG` to choose
another tag. The build uses this repository's Containerfile and defaults for
unspecified sources, rather than modifying the existing image. Module version
options also set installed module names during a build. Without rebuild options,
they only select versions already installed in the image. Installed module names
do not automatically follow source branch/tag names.

Use `--dry-run` to print both commands without building or starting anything.

For example, rebuild ECMC and ecmccfg from `v11.2.0_RC1` in the
`anderssandstrom` repositories and start the smoke test with hardware simulation:

```bash
./run-sim.sh \
  --ioc-name SIMIOC \
  --hardware-sim \
  --ecmc-remote https://github.com/anderssandstrom/ecmc.git \
  --ecmc-ref v11.2.0_RC1 \
  --ecmc-version v11.2.0_RC1 \
  --ecmccfg-remote https://github.com/anderssandstrom/ecmccfg.git \
  --ecmccfg-ref v11.2.0_RC1 \
  --ecmccfg-version v11.2.0_RC1 \
  examples/smoke/startup.cmd
```

Both modules are installed with `LIBVERSION=v11.2.0_RC1`; ecmccomp uses its
default source and installed version. The resulting image is
`ecmc-dev:simulation`.

To start the IOC and hardware simulation again using that image without
fetching or rebuilding:

```bash
./run-sim.sh --image ecmc-dev:simulation \
  --ioc-name SIMIOC \
  --hardware-sim \
  examples/smoke/startup.cmd
```

Both examples start the Python hardware models with simulation PV prefix
`SIMIOC:SIM:`. Replace `examples/smoke/startup.cmd` with your startup file;
add `--root /path/to/configuration/tree` if it includes files from parent
directories.

## Reproducibility and architectures

Default Git revisions are pinned to commits in `Containerfile`. Recursive
submodules use their parent commit's recorded revisions. EPICS Base is pinned
to 7.0.10; Python packages are pinned in `container/requirements.txt` and
installed at build time. The ecmccfg Python activation script is adapted to use
that environment, avoiding pip downloads on each IOC startup.

Inspect the actual revisions and installed names:

```bash
podman run --rm ecmc-dev:v11.2.0_RC1 cat /opt/source-revisions.txt
podman run --rm ecmc-dev:v11.2.0_RC1 cat /opt/module-versions.txt
```

This pins application inputs, not a byte-for-byte OS build: `debian:12` and apt
security packages can change. For stricter deployments, set `BASE_IMAGE` to an
approved image digest and manage an apt snapshot. Branch refs are intentionally
mutable; use full commit SHAs for shared machine builds. A cached build will
not notice a remote branch moving: change the ref to its new SHA, or rebuild
with `--no-cache`.

The architecture is detected from EPICS Base; build natively on ARM64 or x86-64.
Optional `--platform linux/arm64` / `--platform linux/amd64` requests a target.
Cross-architecture builds require Podman VM emulation and can be much slower;
the flag does not set up emulation. Native builds are preferred. The helper uses
`--format docker`, required for Podman to preserve the build's `SHELL` directive.
If building directly, use `podman build --format docker -f Containerfile ...`.

## Use as an engineering submodule

Publish this directory as a Git repository first. It can then be added from the
engineering repository (replace the URL):

```bash
git submodule add <ecmc_podman-repository-url> tools/ecmc_podman
git commit -m "Add ECMC simulation container tooling"
```

Other users clone the engineering repository with:

```bash
git clone --recurse-submodules <ecmc_engineering-repository-url>
```

For an existing clone: `git submodule update --init --recursive`.
Run from the engineering root:

```bash
./tools/ecmc_podman/build-image.sh --image ecmc-dev:my-machine
./tools/ecmc_podman/run-sim.sh --image ecmc-dev:my-machine \
  --ioc-name SIMIOC --hardware-sim configurations/my-machine/startup.cmd
```

Keep machine configurations, model JSON settings and a build wrapper with your
chosen source refs in the engineering repository. Commit its submodule pointer
to pin the launcher version. All users need access to both Git repositories and
the build's upstream source/package hosts. The launcher does not assume a sibling
ecmc/ecmccfg checkout or a particular home directory.

## Startup preparation and naming

The launcher sources `/opt/ecmc-env.sh`, detects the installed modules, preloads
ecmccomp and runs PSI `iocsh`. By default it creates a temporary startup copy
with installed ecmc/ecmccfg/ecmccomp versions and `SIM=1` plus `ECMC_VER` in the
`require ecmccfg` arguments. Your original files are unchanged.

Only direct `require` lines in the supplied file are rewritten; included files
are not. Space/comma-separated and function-style require calls are supported.
A direct `require ecmccfg` is required; opaque macro argument lists like
`"${ARGS}"` are rejected. Use `--as-is` to retain the startup's versions and
simulation settings. It still preloads the selected ecmccomp module.

`--ioc-name SIMIOC` passes `-n SIMIOC` to iocsh before modules load. A startup
that explicitly sets `IOC` can override it. Axis records may use a separate
`DEV` macro: `DEV=${IOC}_TEST` produces `SIMIOC_TEST:M1`, while controller and
terminal records still use `SIMIOC:`. Change that machine setting to
`DEV=${IOC}` if you want the same prefix. These records belong to one IOC.

The startup directory is the working directory, mounted read-only at `/config`.
The launcher disables container SELinux labeling so these read-only mounts also
work on SELinux hosts without relabeling the source tree.
For relative includes outside it, mount a common parent:

```bash
./run-sim.sh --root /path/to/configs /path/to/configs/machine/startup.cmd
```

Absolute host paths need to be changed to container paths. Generated files
should go under `/tmp`. Startup macros follow the filename; environment values
use `--env NAME=value`. `--dry-run` prints the command without starting anything.
A masterless `MASTER_ID=-1` remains masterless; SIM does not fabricate a master.

## Optional Python hardware models

`--hardware-sim` runs the packaged `ioc.py` model scanner inside the same
container. It waits up to 120 seconds for the simulation `FirstSlave` PV, then
starts supported models. Unsupported terminals are reported and skipped. No
host Python setup or host CA ports are needed for this internal connection.

The default simulation prefix is `IOC_NAME:SIM:`. It is the I/O simulation
prefix, not necessarily the motor prefix (`SIMIOC_TEST:`). For a startup that
sets its own IOC name or `ECMC_SIM_PREFIX`, pass the actual simulation prefix:

```bash
./run-sim.sh --ioc-name SIMIOC --hardware-sim \
  --sim-prefix SIMIOC:SIM: --sim-master 0 \
  --sim-settings /path/to/models.json startup.cmd
```

`--sim-prefix` selects records to connect to; it does not rename IOC records.
The settings JSON maps slave identities to model settings, for example:

```json
{
  "ec0.s10": {
    "full_steps_per_second": 2000,
    "motor_steps_per_rev": 200,
    "encoder_counts_per_rev": 12800,
    "enable_delay": 0.05
  }
}
```

Only use settings supported by the model for that terminal. Models provide
functional feedback, not deterministic real-time or full electrical simulation.
External encoders are not automatically mechanically coupled to a nearby drive.
This option is headless; it does not open the simulator's Tk GUI on the Mac.
The simulator is stopped when the IOC exits. A readiness timeout or simulator
process failure stops the IOC with an error. Individual model failures are
reported by the scanner, which may continue running its remaining models.

Models are copied from the selected ecmccfg sources, or from ecmc for older
releases. For sources without models, set `SIM_REPOSITORY` / `SIM_REF` to a
compatible ecmccfg revision containing `tools/simulation/ioc.py`. A build fails
if it cannot package a simulator. Its metadata and I/O records must match the
selected ecmc/ecmccfg versions; arbitrary mixed versions are not guaranteed.

## Access PVs from macOS or the Linux host

Channel Access ports 5064 (TCP/UDP) and 5065 (UDP) are published on localhost.
Default broadcast discovery does not reach the container through this setup
and can produce `Channel connect timed out`. Set this in the client terminal:

```bash
export EPICS_CA_AUTO_ADDR_LIST=NO
export EPICS_CA_ADDR_LIST=127.0.0.1
caget SIMIOC_TEST:M1
```

For a configuration providing that motor, a successful read can look like:

```text
SIMIOC_TEST:M1                 0
```

The bundled terminal-only example has no M1 motor; query `SIMIOC:MODULES` instead.
Launch caQtDM and other CA clients from the same terminal to inherit settings.
For example, with an ecmccfg checkout and caQtDM installed on your Mac:

```bash
cd /path/to/ecmccfg/qt
/Applications/caQtDM.app/Contents/MacOS/caQtDM -macro "IOC=SIMIOC" ecmcMain.ui
```

Only one IOC can bind these host ports at a time. Use `--no-ports` when host
access is not needed. PVA ports are not published. The IOC still needs to start
successfully and provide the requested PV; inspect its startup output first.

## Checks and troubleshooting

```bash
bash -n build-image.sh run-sim.sh container/*.sh
python3 -m unittest discover -s tests -v
```

If Podman cannot connect on macOS, check `podman machine list` and start the VM.
If a module version is missing or ambiguous, inspect `/ioc/modules` in the
image. If hardware model discovery times out, check the simulation prefix and
that the startup enabled simulation and reached `iocRun: All initialization
complete`. Configuration features newer than the image may require rebuilding
with matching source revisions.
