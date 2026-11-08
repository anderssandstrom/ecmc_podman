#!/bin/bash
# EPICS_BASE and REQUIRE_VERSION are image ENV values.
export EPICS_HOST_ARCH="$("$EPICS_BASE/startup/EpicsHostArch")"
export EPICS_MODULES=/ioc/modules
export ETHERLAB=/opt/etherlab
export LD_LIBRARY_PATH="/opt/etherlab/lib:$EPICS_BASE/lib/$EPICS_HOST_ARCH:${LD_LIBRARY_PATH:-}"
export PATH="/opt/ecmc-python/bin:/opt/require:$EPICS_BASE/bin/$EPICS_HOST_ARCH:$PATH"
export PYEPICS_LIBCA="$EPICS_BASE/lib/$EPICS_HOST_ARCH/libca.so"
