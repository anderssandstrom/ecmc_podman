# Minimal terminal simulation, without external configuration files or motors.
# run-sim.sh selects the installed versions and forces SIM=1.
on error halt
require ecmccfg "MASTER_ID=0,ENG_MODE=1,EC_RATE=1000,MODE=DAQ,SIM=1"
${SCRIPTEXEC} ${ecmccfg_DIR}addSlave.cmd "SLAVE_ID=0,HW_DESC=EK1100"
${SCRIPTEXEC} ${ecmccfg_DIR}addSlave.cmd "SLAVE_ID=10,HW_DESC=EL7031"
