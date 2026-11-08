#!/usr/bin/env python3
"""Permit EPICS 7's empty link directory, but still reject installed releases."""
from pathlib import Path

path = Path('/ioc/tools/driver.makefile')
old = '@test ! -d ${MODULE_LOCATION}/R${EPICSVERSION}/lib/${T_A} ||'
new = '@test -z "$$(ls -A ${MODULE_LOCATION}/R${EPICSVERSION}/lib/${T_A} 2>/dev/null)" ||'
source = path.read_text()
# The first occurrence is the numeric-release guard. The second implements
# replaceable development releases and must retain its original behavior.
if old not in source:
    raise SystemExit('Unsupported PSI install rule; review patch-psi-install.py')
path.write_text(source.replace(old, new, 1))
