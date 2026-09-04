# Oracle-Native-Standby — How To Use

## 1. Prepare the package

```bash
chmod 750 bin/oracle-native-standby bin/oracle-native-standby-validate
chmod 600 conf/oracle-native-standby.drv
bin/oracle-native-standby-validate
```

## 2. Configure inputs

Edit `conf/oracle-native-standby.drv` or start the interactive wizard:

```bash
bin/oracle-native-standby
```

The configuration covers source and target database identities, hosts, Oracle homes, services, listener ports, storage, TDE wallets, RAC settings, backup staging, and operator access policy.

The main menu follows the required build order: target placeholder creation, primary database preparation, and physical standby build on the target. Each phase can run in the foreground or background.

Target TDE tablespace encryption provides two guarded modes: `TARGET_ONLINE_AFTER_SWITCHOVER` for a target that is already primary and open read-write, and `TARGET_OFFLINE_AFTER_BUILD` for mounted target-standby datafile encryption. The source database is never encrypted by these functions.

## 3. Review the plan

```bash
bin/oracle-native-standby task-list
bin/oracle-native-standby plan
bin/oracle-native-standby -d conf/oracle-native-standby.drv driver-validate conf/oracle-native-standby.drv
```

## 4. Validate access and prerequisites

```bash
bin/oracle-native-standby -d conf/oracle-native-standby.drv access-check
bin/oracle-native-standby -d conf/oracle-native-standby.drv preflight
bin/oracle-native-standby -d conf/oracle-native-standby.drv precheck
```

## 5. Execute

Run all tasks in the background:

```bash
bin/oracle-native-standby -d conf/oracle-native-standby.drv all --background
```

Run selected tasks or production steps:

```bash
bin/oracle-native-standby -d conf/oracle-native-standby.drv tasks 1-10 --foreground
bin/oracle-native-standby -d conf/oracle-native-standby.drv steps 005,010,070 --background
```

Every registered process is independently available in interactive and non-interactive modes. Select **INDIVIDUAL PROCESSES** from the main menu, or use:

```bash
bin/oracle-native-standby process-list
bin/oracle-native-standby -d conf/oracle-native-standby.drv process 10 --foreground
bin/oracle-native-standby -d conf/oracle-native-standby.drv process 19 --background
bin/oracle-native-standby -d conf/oracle-native-standby.drv processes 1-10 --foreground
bin/oracle-native-standby -d conf/oracle-native-standby.drv processes 1,4,7 --background
```

## 6. Monitor and resume

```bash
bin/oracle-native-standby jobs
bin/oracle-native-standby status <job-id>
bin/oracle-native-standby logs <job-id>
bin/oracle-native-standby wait <job-id>
bin/oracle-native-standby failed-from <job-id> --background
```

## 7. Validate Data Guard

```bash
bin/oracle-native-standby -d conf/oracle-native-standby.drv dg-validate
bin/oracle-native-standby -d conf/oracle-native-standby.drv sync
```

Production execution requires approved change controls, verified backups, tested recovery procedures, validated TDE and password-file handling, and confirmed source-to-target connectivity.
