# Oracle-Native-Standby

Oracle-Native-Standby automates creation and operation of Oracle physical standby databases using native RMAN and Data Guard capabilities.

## Capabilities

- Interactive and non-interactive standby build workflows
- Guided three-phase menu: target placeholder, primary setup, and target standby build
- Target placeholder engine selection: `dbaascli` first, `dbcli` second, and native `dbca` fallback
- RMAN active duplicate and offline backup/restore methods
- OCI placeholder database creation and validation
- Data Guard configuration, health checks, synchronization, switchover, and failover readiness
- Oracle RAC, ASM, TDE wallet, listener, password-file, and network handling
- Target-only TDE conversion: online after target switchover, or offline on the mounted target standby after build
- Numbered task and production-step execution
- Every process can run individually through the interactive menu or non-interactive CLI
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

The interactive menu clears and redraws the screen, and exposes the build in operational order:

1. Create or validate the target placeholder database.
2. Prepare the primary database for Data Guard.
3. Build and validate the physical standby on the target.
4. Run the complete end-to-end build.

Run the toolkit as `opc`. With `OCI_TARGET_PLATFORM=AUTO`, target provisioning checks for `dbaascli`, then `/opt/oracle/dcs/bin/dbcli`, and uses `$TARGET_ORACLE_HOME/bin/dbca` when neither lifecycle utility exists.

Run all tasks in the background:

```bash
bin/oracle-native-standby -d conf/oracle-native-standby.drv all --background
```

Run individual processes non-interactively:

```bash
bin/oracle-native-standby process-list
bin/oracle-native-standby -d conf/oracle-native-standby.drv process 10 --foreground
bin/oracle-native-standby -d conf/oracle-native-standby.drv process 19 --background
bin/oracle-native-standby -d conf/oracle-native-standby.drv processes 1-10 --foreground
bin/oracle-native-standby -d conf/oracle-native-standby.drv processes 1,4,7 --background
bin/oracle-native-standby -d conf/oracle-native-standby.drv steps 044 --foreground
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

Set `TDE_ENCRYPTION_MODE` to `TARGET_ONLINE_AFTER_SWITCHOVER` or `TARGET_OFFLINE_AFTER_BUILD` when target-only encryption is required. Online mode is blocked unless the target is `PRIMARY` and `READ WRITE`. Offline mode stops and restarts Redo Apply around target datafile conversion. Use target-only offline conversion only with a supported Data Guard hybrid encryption policy.

## Safety

Test the complete workflow in a representative non-production environment. Validate the exact Oracle Database RU, OCI service, RAC/Grid Infrastructure topology, ASM or filesystem design, network and listener configuration, TDE setup, backup design, and organizational change controls before production execution.
