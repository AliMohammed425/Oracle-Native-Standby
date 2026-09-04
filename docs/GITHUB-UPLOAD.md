# GitHub Upload Guide

Review first:

```bash
bin/oracle-native-standby-validate
git status
git diff
```

Initialize and commit:

```bash
git init
git branch -M main
git add .
git status
git commit -m "Initial release: Oracle-Native-Standby v34"
```

Create an empty GitHub repository, then:

```bash
git remote add origin <repository-url>
git push -u origin main
```

Recommended topics: `oracle`, `rman`, `data-guard`, `oci`, `database-migration`, `standby`.

Never publish production passwords, keys, wallets, backups, sensitive logs, or secret-bearing response files.
