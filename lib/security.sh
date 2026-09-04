#!/usr/bin/env bash
set -euo pipefail

passwordfile_prepare(){
  require_var SOURCE_SYS_PASSWORD
  require_var TARGET_SYS_PASSWORD
  [[ "$SOURCE_SYS_PASSWORD" == "$TARGET_SYS_PASSWORD" ]] || die "SYS password must match for primary/auxiliary connectivity."

  local platform="${RESOLVED_OCI_PLATFORM:-${OCI_TARGET_PLATFORM:-AUTO}}"
  if [[ "$platform" == "BASE_DB_SERVICE_DBCLI" ]]; then
    require_var TARGET_ADMIN_PASSWORD
    [[ "$TARGET_ADMIN_PASSWORD" == "$SOURCE_SYS_PASSWORD" ]] || die "For OCI Base DB Service instance-only creation, TARGET_ADMIN_PASSWORD must match the primary admin/SYS password for this workflow."
    echo "Base DB Service placeholder owns password-file creation; matching credential validated."
    return 0
  fi

  ssh "$TARGET_OS_USER@$TARGET_HOST" "command -v expect >/dev/null 2>&1" || die "expect is required on generic target for unattended ORAPWD prompting."
  local td; td="$(mktemp -d /tmp/ons_orapwd.XXXXXX)"; trap 'rm -rf "$td"' RETURN
  printf '%s' "$TARGET_SYS_PASSWORD" > "$td/secret"; chmod 600 "$td/secret"
  cat > "$td/run.expect" <<'EXP'
set timeout 120
set fh [open "/tmp/ons_orapwd.secret" r]
set pw [string trimright [read $fh] "\r\n"]
close $fh
set cmd $env(ONS_ORAPWD_CMD)
eval spawn $cmd
expect {
  -re {(?i)password.*:} { send -- "$pw\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
EXP
  chmod 600 "$td/run.expect"
  scp -q "$td/secret" "$TARGET_OS_USER@$TARGET_HOST:/tmp/ons_orapwd.secret"
  scp -q "$td/run.expect" "$TARGET_OS_USER@$TARGET_HOST:/tmp/ons_orapwd.expect"
  ssh "$TARGET_OS_USER@$TARGET_HOST" "set -e; export ORACLE_HOME='$TARGET_ORACLE_HOME'; export ORACLE_SID='$TARGET_SID'; export PATH=\$ORACLE_HOME/bin:\$PATH; umask 077; export ONS_ORAPWD_CMD=\"\$ORACLE_HOME/bin/orapwd FILE=\$ORACLE_HOME/dbs/orapw$TARGET_SID FORCE=Y FORMAT=12.2 SYS=Y\"; expect /tmp/ons_orapwd.expect; rc=\$?; rm -f /tmp/ons_orapwd.secret /tmp/ons_orapwd.expect; test -s \$ORACLE_HOME/dbs/orapw'$TARGET_SID'; exit \$rc"
}

tde_detect(){
  local out
  out="$(remote_sql "$SOURCE_HOST" "$SOURCE_OS_USER" "$SOURCE_ORACLE_HOME" "$SOURCE_SID" <<'SQL'
set pages 0 feedback off heading off verify off echo off
select case when exists (select 1 from v$encrypted_tablespaces) then 'TDE_ENABLED' else 'TDE_NOT_ENABLED' end from dual;
exit
SQL
)"
  TDE_STATUS="$(printf '%s\n' "$out" | tr -d '\r ' | grep -E 'TDE_(ENABLED|NOT_ENABLED)' | tail -1)"
  export TDE_STATUS
  echo "$TDE_STATUS"
}

tde_prepare(){
  tde_detect
  if [[ "$TDE_STATUS" == "TDE_NOT_ENABLED" ]]; then
    echo "TDE is not enabled; keystore staging is not required."
    return 0
  fi
  require_var SOURCE_TDE_WALLET_PATH
  require_var TARGET_TDE_WALLET_PATH
  [[ "$SOURCE_TDE_WALLET_PATH" == "$TARGET_TDE_WALLET_PATH" ]] || die "Automatic TDE handling requires the same absolute keystore path on source and target so inherited wallet configuration remains valid."
  ssh "$SOURCE_OS_USER@$SOURCE_HOST" "test -d '$SOURCE_TDE_WALLET_PATH'; test -s '$SOURCE_TDE_WALLET_PATH/ewallet.p12' -o -s '$SOURCE_TDE_WALLET_PATH/cwallet.sso'"
  ssh "$TARGET_OS_USER@$TARGET_HOST" "mkdir -p '$TARGET_TDE_WALLET_PATH'; chmod 700 '$TARGET_TDE_WALLET_PATH'"
  local td; td="$(mktemp -d /tmp/ons_wallet.XXXXXX)"; trap 'rm -rf "$td"' RETURN
  scp -q "$SOURCE_OS_USER@$SOURCE_HOST:$SOURCE_TDE_WALLET_PATH/ewallet.p12" "$td/" 2>/dev/null || true
  scp -q "$SOURCE_OS_USER@$SOURCE_HOST:$SOURCE_TDE_WALLET_PATH/cwallet.sso" "$td/" 2>/dev/null || true
  compgen -G "$td/*" >/dev/null || die "No TDE keystore files could be staged."
  scp -q "$td"/* "$TARGET_OS_USER@$TARGET_HOST:$TARGET_TDE_WALLET_PATH/"
  ssh "$TARGET_OS_USER@$TARGET_HOST" "chmod 600 '$TARGET_TDE_WALLET_PATH'/*; ls -l '$TARGET_TDE_WALLET_PATH'"
}

tde_tablespace_status(){
  remote_sql "$TARGET_HOST" "$TARGET_OS_USER" "$TARGET_ORACLE_HOME" "$TARGET_SID" <<SQL
set lines 220 pages 200 feedback off verify off
${TDE_ENCRYPT_CONTAINER:+alter session set container="$TDE_ENCRYPT_CONTAINER";}
column tablespace_name format a35
column encrypted format a10
select t.tablespace_name,
       case when e.tablespace_name is not null then 'YES' else 'NO' end encrypted
from dba_tablespaces t
left join v\$encrypted_tablespaces e on e.ts# = t.ts#
where t.contents = 'PERMANENT'
  and t.tablespace_name not in ('SYSTEM','SYSAUX')
order by t.tablespace_name;
exit
SQL
}

tde_encrypt_tablespaces(){
  [[ "${TDE_ENCRYPTION_MODE:-NONE}" == "TARGET_ONLINE_AFTER_SWITCHOVER" ]] || {
    echo "Target online encryption is not selected."
    return 0
  }
  local algorithm="${TDE_ENCRYPT_ALGORITHM:-AES256}"
  [[ "$algorithm" =~ ^AES(128|192|256)$ ]] || die "TDE_ENCRYPT_ALGORITHM must be AES128, AES192, or AES256."

  local state
  state="$(remote_sql "$TARGET_HOST" "$TARGET_OS_USER" "$TARGET_ORACLE_HOME" "$TARGET_SID" <<'SQL'
set pages 0 feedback off heading off verify off
select database_role || ':' || open_mode from v$database;
exit
SQL
)"
  grep -q 'PRIMARY:READ WRITE' <<<"$state" || die "Target online encryption requires target role PRIMARY and open mode READ WRITE. Current state: $state"
  echo "Encrypting unencrypted permanent user tablespaces on the target using $algorithm."
  remote_sql "$TARGET_HOST" "$TARGET_OS_USER" "$TARGET_ORACLE_HOME" "$TARGET_SID" <<SQL
set serveroutput on size unlimited feedback on verify off
whenever sqlerror exit failure rollback
${TDE_ENCRYPT_CONTAINER:+alter session set container="$TDE_ENCRYPT_CONTAINER";}
declare
  l_count number := 0;
begin
  for r in (
    select t.tablespace_name
    from dba_tablespaces t
    where t.contents = 'PERMANENT'
      and t.status = 'ONLINE'
      and t.bigfile in ('YES','NO')
      and t.tablespace_name not in ('SYSTEM','SYSAUX')
      and not exists (
        select 1 from v\$encrypted_tablespaces e where e.ts# = t.ts#
      )
  ) loop
    dbms_output.put_line('Encrypting tablespace: ' || r.tablespace_name);
    execute immediate 'alter tablespace ' || dbms_assert.enquote_name(r.tablespace_name, false) ||
                      ' encryption online using ''$algorithm'' encrypt';
    l_count := l_count + 1;
  end loop;
  dbms_output.put_line('Tablespaces encrypted: ' || l_count);
end;
/
exit
SQL
  echo "Post-encryption status:"
  tde_tablespace_status
}

tde_encrypt_standby_offline(){
  [[ "${TDE_ENCRYPTION_MODE:-NONE}" == "TARGET_OFFLINE_AFTER_BUILD" ]] || {
    echo "Offline post-build standby encryption is not selected."
    return 0
  }
  local algorithm="${TDE_ENCRYPT_ALGORITHM:-AES256}" rc=0
  [[ "$algorithm" =~ ^AES(128|192|256)$ ]] || die "TDE_ENCRYPT_ALGORITHM must be AES128, AES192, or AES256."
  echo "Stopping Redo Apply and encrypting eligible standby datafiles while mounted."
  set +e
  remote_sql "$TARGET_HOST" "$TARGET_OS_USER" "$TARGET_ORACLE_HOME" "$TARGET_SID" <<SQL
set serveroutput on size unlimited feedback on verify off
whenever sqlerror exit failure rollback
alter database recover managed standby database cancel;
declare
  l_count number := 0;
begin
  for r in (
    select d.file_name
    from dba_data_files d
    join dba_tablespaces t on t.tablespace_name = d.tablespace_name
    where t.contents = 'PERMANENT'
      and t.tablespace_name not in ('SYSTEM','SYSAUX')
      and not exists (select 1 from v\$encrypted_tablespaces e where e.ts# = t.ts#)
  ) loop
    dbms_output.put_line('Encrypting standby datafile: ' || r.file_name);
    execute immediate 'alter database datafile ' || dbms_assert.enquote_literal(r.file_name) ||
                      ' encrypt using ''$algorithm''';
    l_count := l_count + 1;
  end loop;
  dbms_output.put_line('Standby datafiles encrypted: ' || l_count);
end;
/
exit
SQL
  rc=$?
  set -e
  remote_sql "$TARGET_HOST" "$TARGET_OS_USER" "$TARGET_ORACLE_HOME" "$TARGET_SID" <<'SQL'
whenever sqlerror exit failure rollback
alter database recover managed standby database using current logfile disconnect from session;
exit
SQL
  [[ $rc -eq 0 ]] || die "Offline standby encryption failed; Redo Apply restart was attempted. Review the alert log."
  echo "Target standby conversion completed. Validate the supported hybrid TABLESPACE_ENCRYPTION policy before cutover."
}
