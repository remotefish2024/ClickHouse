#!/usr/bin/env bash
# Tags: no-fasttest, no-parallel, no-replicated-database
# Tag no-replicated-database: https://s3.amazonaws.com/clickhouse-test-reports/65277/43e9a7ba4bbf7f20145531b384a31304895b55bc/stateless_tests__release__old_analyzer__s3__databasereplicated__[1_2].html and https://github.com/ClickHouse/ClickHouse/blob/011c694117845500c82f9563c65930429979982f/tests/queries/0_stateless/01175_distributed_ddl_output_mode_long.sh#L4

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

ssh_key="-----BEGIN OPENSSH PRIVATE KEY-----
         b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
         QyNTUxOQAAACAc6mt3bktHHukGJM1IJKPVtFMe4u3d8T6LHha8J4WOGAAAAJApc2djKXNn
         YwAAAAtzc2gtZWQyNTUxOQAAACAc6mt3bktHHukGJM1IJKPVtFMe4u3d8T6LHha8J4WOGA
         AAAEAk15S5L7j85LvmAivo2J8lo44OR/tLILBO1Wb2//mFwBzqa3duS0ce6QYkzUgko9W0
         Ux7i7d3xPoseFrwnhY4YAAAADWFydGh1ckBhcnRodXI=
         -----END OPENSSH PRIVATE KEY-----"

function test_login_no_pwd
{
  ${CLICKHOUSE_CLIENT} --user $1 --query "select 1"
}

function test_login_pwd
{
  ${CLICKHOUSE_CLIENT} --user $1 --password $2 --query "select 1"
}

function test_login_pwd_expect_error
{
  test_login_pwd "$1" "$2" 2>&1 | grep -m1 -o 'AUTHENTICATION_FAILED'
}

function test
{
  user="u01_03174"

  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "DROP USER IF EXISTS ${user} $1"

  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "CREATE USER ${user} $1 IDENTIFIED WITH plaintext_password BY '1'"

  echo "Basic authentication after user creation"
  test_login_pwd ${user} '1'

  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "ALTER USER ${user} $1 IDENTIFIED WITH plaintext_password BY '2'"

  echo "Changed password, old password should not work"
  test_login_pwd_expect_error ${user} '1'

  echo "New password should work"
  test_login_pwd ${user} '2'

  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "ALTER USER ${user} $1 ADD IDENTIFIED WITH plaintext_password BY '3', plaintext_password BY '4'"

  echo "Two new passwords were added, should both work"
  test_login_pwd ${user} '3'

  test_login_pwd ${user} '4'

  ssh_pub_key="AAAAC3NzaC1lZDI1NTE5AAAAIBzqa3duS0ce6QYkzUgko9W0Ux7i7d3xPoseFrwnhY4Y"

  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "ALTER USER ${user} $1 ADD IDENTIFIED WITH ssh_key BY KEY '${ssh_pub_key}' TYPE 'ssh-ed25519'"

  echo ${ssh_key} > ssh_key

  echo "Authenticating with ssh key"
  ${CLICKHOUSE_CLIENT} --user ${user} --ssh-key-file 'ssh_key' --ssh-key-passphrase "" --query "SELECT 1"

  echo "Altering credentials and keeping only bcrypt_password"
  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "ALTER USER ${user} $1 IDENTIFIED WITH bcrypt_password BY '5'"

  echo "Asserting SSH does not work anymore"
  ${CLICKHOUSE_CLIENT} --user ${user} --ssh-key-file 'ssh_key' --ssh-key-passphrase "" --query "SELECT 1" 2>&1 | grep -m1 -o 'AUTHENTICATION_FAILED'

  echo "Asserting bcrypt_password works"
  test_login_pwd ${user} '5'

  echo "Adding new bcrypt_password"
  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "ALTER USER ${user} $1 ADD IDENTIFIED WITH bcrypt_password BY '6'"

  echo "Both current authentication methods should work"
  test_login_pwd ${user} '5'
  test_login_pwd ${user} '6'

  echo "Reset authentication methods to new"
  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "ALTER USER ${user} $1 RESET AUTHENTICATION METHODS TO NEW"

  echo "Only the latest should work, below should fail"
  test_login_pwd_expect_error ${user} '5'

  echo "Should work"
  test_login_pwd ${user} '6'

  echo "Replacing existing authentication methods in favor of no_password, should succeed"
  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "ALTER USER ${user} $1 IDENTIFIED WITH no_password"
  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "SHOW CREATE USER ${user}"

  echo "Trying to auth with no pwd, should succeed"
  test_login_no_pwd ${user}

  ${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}" -d "DROP USER IF EXISTS ${user}"
}

test ""

echo "On cluster tests"

test "ON CLUSTER test_shard_localhost"
