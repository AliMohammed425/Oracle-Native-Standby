# Oracle-Native-Standby

Oracle-Native-Standby automates creation and operation of Oracle physical standby databases using native RMAN and Data Guard capabilities.

## Capabilities

- Interactive and non-interactive standby build workflows
- RMAN active duplicate and offline backup/restore methods
- OCI placeholder database creation and validation
- Data Guard configuration, health checks, synchronization, switchover, and failover readiness
- Oracle RAC, ASM, TDE wallet, listener, password-file, and network handling
- Numbered task and production-step execution
- Background jobs, status, logs, stop, resume, and failed-task restart
- Production preflight, operator-access checks, and final validation reports

## Quick start

```bash
unzip Oracle-Native-Standby-v34.zip
cd Oracle-Native-Standby
chmod 750 bin/oracle-native-standby bin/oracle-native-standby-validate
chmod 600 conf/oracle-native-standby.drv
bin/oracle-native-standby-validate
bin/oracle-native-standby
```

Run all tasks in the background:

```bash
bin/oracle-native-standby -d conf/oracle-native-standby.drv all --background
```

Review job progress:

```bash
bin/oracle-native-standby jobs
bin/oracle-native-standby status <job-id>
bin/oracle-native-standby logs <job-id>
```

## Build methods

Set `STANDBY_BUILD_METHOD` in the driver file to one of:

- `ACTIVE_DUPLICATE` for a native RMAN duplicate from the active primary
- `OFFLINE_BACKUP` for a native RMAN backup/restore workflow

## Safety

Test the complete workflow in a representative non-production environment. Validate the exact Oracle Database RU, OCI service, RAC/Grid Infrastructure topology, ASM or filesystem design, network and listener configuration, TDE setup, backup design, and organizational change controls before production execution.

