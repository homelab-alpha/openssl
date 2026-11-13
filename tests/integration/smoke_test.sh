#!/bin/bash

# Script Name: smoke_test.sh
# Author: GJS (homelab-alpha)
# Date: 2026-11-13T10:00:00+01:00
# Version: 1.0.0

# Description:
# Integration test for the scripts in scripts/. It runs the whole flow in a
# temporary home directory: the directory setup, the three certificate
# authorities, one certificate of each kind, the verification, a revocation, a
# renewal, the status, and the installer. It never touches the real $HOME.

# Usage: ./tests/integration/smoke_test.sh [-v|--verbose] [-h|--help]
#
# Options:
#  -v, --verbose  Show the output of every command, not only of a failed one.
#  -h, --help     Show this help.

# Exit codes:
#  0  All checks passed.
#  1  One or more checks failed.
#  2  Wrong usage, or OpenSSL is not installed.

# Notes:
# - The test needs Bash, OpenSSL 1.1.1 or newer, and the GNU core utilities.
# - The private keys of the test are created in a temporary folder and removed
#   at the end.

set -Euo pipefail

repo_dir="$(dirname "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")")"
scripts_dir="$repo_dir/scripts"
verbose=false
passed=0
failed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -v | --verbose)
    verbose=true
    shift
    ;;
  -h | --help)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "[ERROR] Unknown option: $1" >&2
    exit 2
    ;;
  esac
done

command -v openssl >/dev/null 2>&1 || {
  echo "[ERROR] OpenSSL is not installed." >&2
  exit 2
}

# The whole test runs in a temporary home directory
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
export HOME="$test_root/home"
other_dir="$test_root/other"
log="$test_root/last.log"
blank_lines="$test_root/blank_lines"
mkdir -p "$HOME" "$other_dir"
printf '\n%.0s' {1..40} >"$blank_lines"
touch "$HOME/.bashrc"
tls="$HOME/tls"

# Test passphrases. They only protect keys in the temporary folder.
export TLS_TRUSTED_ID_PASSPHRASE="smoke-test-trusted-id"
export TLS_ROOT_CA_PASSPHRASE="smoke-test-root-ca"

# Run every script from another directory than $HOME: the scripts must not
# depend on the current directory.
cd "$other_dir" || exit 2

# Function to report the result of a check
report() {
  local status="$1" name="$2"
  if [[ "$status" == "pass" ]]; then
    passed=$((passed + 1))
    echo "[PASS] $name"
    [[ "$verbose" == "false" ]] || cat "$log"
  else
    failed=$((failed + 1))
    echo "[FAIL] $name"
    sed 's/^/       /' "$log"
  fi
}

# Function to run a command and expect an exit code
# Usage: expect <exit code> <name> <command> [arguments]
expect() {
  local want="$1" name="$2" got=0
  shift 2
  "$@" >"$log" 2>&1 <"$blank_lines" || got=$?
  if [[ "$got" -eq "$want" ]]; then
    report pass "$name"
  else
    echo "Expected exit code $want, got $got." >>"$log"
    report fail "$name"
  fi
}

# Function to check a condition
# Usage: check <name> <command> [arguments]
check() {
  local name="$1"
  shift
  if "$@" >"$log" 2>&1; then
    report pass "$name"
  else
    report fail "$name"
  fi
}

san_of() {
  openssl x509 -in "$tls/certs/certificates/$1.pem" -noout -ext subjectAltName | tail -n +2 | tr -d ' '
}

crl_number() {
  local value
  value=$(openssl crl -in "$tls/crl/ca_crl.pem" -noout -crlnumber)
  echo "$((16#${value#crlNumber=0x}))"
}

entries_of() {
  grep -c . "$1" || true
}

serial_of() {
  local value
  value=$(openssl x509 -in "$1" -noout -serial)
  echo "${value#serial=}"
}

mode_of() {
  stat -c %a "$1"
}

echo "=== Directory setup ==="
expect 0 "setup creates the directory structure" bash "$scripts_dir/tls_directory_setup.sh"
check "private folder has mode 700" test "$(mode_of "$tls/private")" = "700"
check "every authority has its own database" test -f "$tls/db/trusted_id/index.txt" -a -f "$tls/db/root_ca/index.txt"
check "crlnumber starts at 1000" test "$(cat "$tls/db/crlnumber")" = "1000"
echo "# local change" >>"$tls/openssl.cnf/cert.cnf"
serial_before=$(cat "$tls/db/serial")
expect 0 "setup runs a second time" bash "$scripts_dir/tls_directory_setup.sh"
check "second run keeps a changed configuration file" grep -q "# local change" "$tls/openssl.cnf/cert.cnf"
check "second run keeps the serial file" test "$(cat "$tls/db/serial")" = "$serial_before"
expect 0 "setup --update-config replaces the file" bash "$scripts_dir/tls_directory_setup.sh" --update-config
check "--update-config restores the repository file" cmp -s "$repo_dir/openssl.cnf/cert.cnf" "$tls/openssl.cnf/cert.cnf"
check "--update-config saves the old file" bash -c "ls '$tls'/openssl.cnf/cert.cnf.bak-* >/dev/null"
chmod 755 "$tls/private"
expect 0 "setup warns about a wider mode" bash "$scripts_dir/tls_directory_setup.sh"
check "setup does not change the mode by itself" test "$(mode_of "$tls/private")" = "755"
expect 0 "setup --fix-permissions" bash "$scripts_dir/tls_directory_setup.sh" --fix-permissions
check "--fix-permissions sets mode 700" test "$(mode_of "$tls/private")" = "700"
expect 2 "setup rejects an unknown option" bash "$scripts_dir/tls_directory_setup.sh" --unknown

echo "=== Certificate authorities ==="
expect 0 "trusted identity is created" bash "$scripts_dir/certificate-authority/trusted_id.sh"
check "trusted identity key is encrypted" grep -q "ENCRYPTED" "$tls/private/root/trusted_id.pem"
check "trusted identity key has mode 600" test "$(mode_of "$tls/private/root/trusted_id.pem")" = "600"
expect 0 "root CA is created" bash "$scripts_dir/certificate-authority/root_ca.sh"
check "root CA key is encrypted" grep -q "ENCRYPTED" "$tls/private/root/root_ca.pem"
expect 0 "intermediate CA is created" bash "$scripts_dir/intermediate-certificate-authority/ca.sh"
check "intermediate CA key is not encrypted" bash -c "! grep -q ENCRYPTED '$tls/private/intermediate/ca.pem'"
check "root CA is in the database of the trusted identity" test "$(entries_of "$tls/db/trusted_id/index.txt")" = "1"
check "intermediate CA is in the database of the root CA" test "$(entries_of "$tls/db/root_ca/index.txt")" = "1"
check "no authority is in the database of the certificates" test "$(entries_of "$tls/db/index.txt")" = "0"
expect 2 "intermediate CA is not overwritten without --replace" \
  bash "$scripts_dir/intermediate-certificate-authority/ca.sh"
expect 2 "root CA is not overwritten without --replace" bash "$scripts_dir/certificate-authority/root_ca.sh"
expect 2 "trusted identity is not overwritten without --replace" \
  bash "$scripts_dir/certificate-authority/trusted_id.sh"

echo "=== Certificates ==="
expect 0 "ECDSA server certificate" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn app.example.test --ip 192.168.1.10, 192.168.1.11
check "ECDSA server names" test "$(san_of app.example.test)" = \
  "DNS:app.example.test,DNS:www.app.example.test,IPAddress:192.168.1.10,IPAddress:192.168.1.11"
check "server key has mode 600" test "$(mode_of "$tls/private/certificates/app.example.test.key")" = "600"
check "HAProxy bundle has mode 600" test "$(mode_of "$tls/certs/certificates/app.example.test_haproxy.pem")" = "600"
expect 0 "RSA server certificate" bash "$scripts_dir/certificate/cert_rsa_server.sh" --fqdn rsa.example.test
expect 0 "wildcard server certificate" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" --fqdn '*.wild.example.test'
check "wildcard names" test "$(san_of '*.wild.example.test')" = "DNS:*.wild.example.test,DNS:wild.example.test"
expect 0 "ECDSA client certificate" bash "$scripts_dir/certificate/cert_ecdsa_client.sh" --fqdn client.example.test
check "client names" test "$(san_of client.example.test)" = "DNS:client.example.test"
check "client has no HAProxy bundle" test ! -e "$tls/certs/certificates/client.example.test_haproxy.pem"
expect 0 "RSA client certificate with --www" bash "$scripts_dir/certificate/cert_rsa_client.sh" \
  --fqdn rsaclient.example.test --www
check "client names with --www" test "$(san_of rsaclient.example.test)" = \
  "DNS:rsaclient.example.test,DNS:www.rsaclient.example.test"
expect 0 "localhost certificate" bash "$scripts_dir/certificate/cert_ecdsa_localhost.sh" --non-interactive
check "localhost names" test "$(san_of localhost)" = "DNS:localhost,DNS:*.localhost,IPAddress:127.0.0.1"
check "crlnumber is not changed by the certificate scripts" test "$(cat "$tls/db/crlnumber")" = "1000"

echo "=== Input validation ==="
key_before=$(sha256sum "$tls/private/certificates/app.example.test.pem")
expect 2 "existing certificate is refused while unique_subject is yes" \
  bash "$scripts_dir/certificate/cert_ecdsa_server.sh" --fqdn app.example.test
check "refused run keeps the existing key" test "$(sha256sum "$tls/private/certificates/app.example.test.pem")" = "$key_before"
expect 2 "path in --fqdn is refused" bash "$scripts_dir/certificate/cert_ecdsa_client.sh" --fqdn ../../../evil
printf '../../../evil\n' >"$test_root/answer"
expect 2 "path in the interactive FQDN is refused" bash -c \
  "bash '$scripts_dir/certificate/cert_ecdsa_client.sh' <'$test_root/answer'"
expect 2 "empty interactive FQDN is refused" bash "$scripts_dir/certificate/cert_ecdsa_client.sh"
expect 2 "comma in --fqdn is refused" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" --fqdn 'a.test,DNS:b.test'
expect 2 "wildcard in the middle is refused" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" --fqdn 'a.*.test'
expect 2 "invalid IPv4 address is refused" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn ip.example.test --ip 192.168.1.256
expect 2 "--ip is refused for a client" bash "$scripts_dir/certificate/cert_ecdsa_client.sh" \
  --fqdn ip.example.test --ip 192.168.1.1
# A failure after the key was generated must not leave or change a key
mv "$tls/newcerts" "$tls/newcerts.moved"
expect 1 "failed issuance exits with an error" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn atomic.example.test
mv "$tls/newcerts.moved" "$tls/newcerts"
check "failed issuance leaves no key" test ! -e "$tls/private/certificates/atomic.example.test.pem"
check "failed issuance leaves no certificate" test ! -e "$tls/certs/certificates/atomic.example.test.pem"
check "no file was written outside the tls folder" bash -c "! find '$HOME' -name 'evil*' | grep -q ."
check "no key without a name was written" test ! -e "$tls/private/certificates/.pem"
check "no temporary folder is left" bash -c "! find '$tls' -maxdepth 1 -name '.cert.*' | grep -q ."

# A failure after the certificate was issued: a wrapper makes openssl verify fail
mkdir -p "$test_root/shim"
real_openssl=$(command -v openssl)
# shellcheck disable=SC2016
printf '#!/bin/bash\n[[ "$1" != "verify" ]] || exit 1\nexec "%s" "$@"\n' "$real_openssl" >"$test_root/shim/openssl"
chmod +x "$test_root/shim/openssl"
expect 1 "failure after the certificate was issued" env PATH="$test_root/shim:$PATH" \
  bash "$scripts_dir/certificate/cert_ecdsa_client.sh" --fqdn late.example.test
check "late failure leaves no key" test ! -e "$tls/private/certificates/late.example.test.pem"
check "late failure leaves no staged file" bash -c "! find '$tls' -name '*.new.*' | grep -q ."
check "late failure revokes the unused entry" bash -c \
  "grep 'CN=late.example.test' '$tls/db/index.txt' | grep -q '^R' && ! grep 'CN=late.example.test' '$tls/db/index.txt' | grep -q '^V'"
expect 0 "next run after a late failure is not blocked" bash "$scripts_dir/certificate/cert_ecdsa_client.sh" \
  --fqdn late.example.test

# Without --fqdn the script asks for the FQDN only, and the Common Name follows it
expect 0 "interactive mode" bash -c "printf 'asked.example.test\n\nother.example.test\n' | bash '$scripts_dir/certificate/cert_ecdsa_server.sh'"
check "interactive mode sets the Common Name to the FQDN" bash -c \
  "openssl x509 -in '$tls/certs/certificates/asked.example.test.pem' -noout -subject | grep -q 'CN *= *asked.example.test$'"
expect 2 "interactive mode refuses a second certificate for the FQDN" bash -c \
  "printf 'asked.example.test\n\n' | bash '$scripts_dir/certificate/cert_ecdsa_server.sh'"

# Scripts that run at the same time must not lose a database entry
entries_before=$(entries_of "$tls/db/index.txt")
for n in 1 2 3 4; do
  bash "$scripts_dir/certificate/cert_ecdsa_client.sh" --fqdn "parallel$n.example.test" >/dev/null 2>&1 &
done
wait
check "parallel runs keep every database entry" test "$(entries_of "$tls/db/index.txt")" = "$((entries_before + 4))"
check "parallel runs create every certificate" bash -c \
  "ls '$tls'/certs/certificates/parallel[1-4].example.test.pem | wc -l | grep -qx 4"
flock "$tls/.renew.lock" sleep 3 &
sleep 0.5
expect 2 "revocation stops while another script holds the lock" bash "$scripts_dir/revoke_tls_certificates.sh" --crl-only
wait

echo "=== Verification ==="
expect 0 "verify passes for a server certificate" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
expect 0 "verify passes for a client certificate" bash "$scripts_dir/verify_tls_certificates.sh" client.example.test
expect 0 "verify passes for the intermediate CA" bash "$scripts_dir/verify_tls_certificates.sh" ca.pem
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=BOOK" \
  -keyout "$test_root/rogue.key" -out "$tls/certs/certificates/BOOK.pem" >/dev/null 2>&1
cp "$tls/certs/certificates/BOOK.pem" "$tls/certs/certificates/BOOK_chain_bundle.pem"
expect 1 "verify fails for a certificate from another issuer" bash "$scripts_dir/verify_tls_certificates.sh" BOOK
rm -f "$tls/certs/certificates/BOOK.pem" "$tls/certs/certificates/BOOK_chain_bundle.pem"
cp -p "$tls/certs/certificates/app.example.test_chain_bundle.pem" "$test_root/bundle.keep"
cp "$tls/certs/certificates/app.example.test.pem" "$tls/certs/certificates/app.example.test_chain_bundle.pem"
expect 1 "verify fails for a bundle without the chain" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
cp -p "$test_root/bundle.keep" "$tls/certs/certificates/app.example.test_chain_bundle.pem"
cp -p "$tls/certs/certificates/app.example.test_haproxy.pem" "$test_root/haproxy.keep"
cat "$tls/certs/certificates/app.example.test_chain_bundle.pem" "$tls/private/certificates/client.example.test.pem" \
  >"$tls/certs/certificates/app.example.test_haproxy.pem"
expect 1 "verify fails for a HAProxy bundle with another key" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
cp -p "$test_root/haproxy.keep" "$tls/certs/certificates/app.example.test_haproxy.pem"
expect 0 "verify passes after the bundles are restored" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
expect 1 "verify fails for an unknown certificate" bash "$scripts_dir/verify_tls_certificates.sh" missing.example.test
expect 2 "verify rejects an unknown option" bash "$scripts_dir/verify_tls_certificates.sh" --unknown

echo "=== Revocation and CRL ==="
expect 0 "revoke a certificate" bash "$scripts_dir/revoke_tls_certificates.sh" --yes rsa.example.test
first_crl=$(crl_number)
expect 2 "--reuse-key refuses a key of another type" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn rsa.example.test --reuse-key
check "--reuse-key names the key type" bash -c \
  "bash '$scripts_dir/certificate/cert_ecdsa_server.sh' --fqdn rsa.example.test --reuse-key 2>&1 | grep -q 'is not an ECDSA key'"
rsa_key_before=$(sha256sum "$tls/private/certificates/rsa.example.test.pem")
expect 0 "new certificate after a revocation, with the same key" bash "$scripts_dir/certificate/cert_rsa_server.sh" \
  --fqdn rsa.example.test --reuse-key
check "--reuse-key keeps the key" test "$(sha256sum "$tls/private/certificates/rsa.example.test.pem")" = "$rsa_key_before"
expect 0 "generate a second CRL" bash "$scripts_dir/revoke_tls_certificates.sh" --crl-only
check "CRL number increases" test "$(crl_number)" -gt "$first_crl"

echo "=== Renewal ==="
serial_before=$(openssl x509 -in "$tls/certs/certificates/app.example.test.pem" -noout -serial)
san_before=$(san_of app.example.test)
expect 0 "renew a server certificate" bash "$scripts_dir/renew_tls_certificates.sh" --yes app.example.test
check "renewal issues a new serial number" test \
  "$(openssl x509 -in "$tls/certs/certificates/app.example.test.pem" -noout -serial)" != "$serial_before"
check "renewal keeps the names" test "$(san_of app.example.test)" = "$san_before"
expect 0 "renew a client certificate with www" bash "$scripts_dir/renew_tls_certificates.sh" --yes rsaclient.example.test
expect 0 "renew localhost with the same key" bash "$scripts_dir/renew_tls_certificates.sh" --yes --reuse-key localhost
expect 0 "renew --all --dry-run" bash "$scripts_dir/renew_tls_certificates.sh" --all --within 400 --dry-run
check "unique_subject is yes after the renewals" grep -q "unique_subject = yes" "$tls/db/index.txt.attr"
expect 0 "verify passes after the renewal" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
expect 0 "status reports no problem" bash "$scripts_dir/tls_certificate_status.sh"

echo "=== Shared database of an older version ==="
# Put the entries of the authorities back in the shared database, as an older
# version wrote them, and let the setup move them.
leaf_entries=$(entries_of "$tls/db/index.txt")
root_serial=$(serial_of "$tls/certs/root/root_ca.pem")
ca_serial=$(serial_of "$tls/certs/intermediate/ca.pem")
cat "$tls/db/trusted_id/index.txt" "$tls/db/root_ca/index.txt" >>"$tls/db/index.txt"
: >"$tls/db/trusted_id/index.txt"
: >"$tls/db/root_ca/index.txt"
mv "$tls/newcerts/trusted_id/$root_serial.pem" "$tls/newcerts/root_ca/$ca_serial.pem" "$tls/newcerts/"
expect 0 "setup moves the entries of the authorities" bash "$scripts_dir/tls_directory_setup.sh"
check "root CA entry is moved" grep -q "$root_serial" "$tls/db/trusted_id/index.txt"
check "intermediate CA entry is moved" grep -q "$ca_serial" "$tls/db/root_ca/index.txt"
check "certificate entries are kept" test "$(entries_of "$tls/db/index.txt")" = "$leaf_entries"
check "certificate copies are moved" test -f "$tls/newcerts/trusted_id/$root_serial.pem" -a \
  -f "$tls/newcerts/root_ca/$ca_serial.pem"
check "a copy of the database is saved" bash -c "ls '$tls'/archive/_database/index.txt.* >/dev/null"
expect 0 "setup moves nothing a second time" bash "$scripts_dir/tls_directory_setup.sh"
check "entries are moved once" test "$(entries_of "$tls/db/trusted_id/index.txt")" = "1"
expect 0 "root CA database is readable for openssl" openssl ca -config "$tls/openssl.cnf/ca.cnf" -updatedb \
  -passin env:TLS_ROOT_CA_PASSPHRASE
expect 0 "verify passes after the move" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test

echo "=== Configuration files from before version 0.2.0 ==="
for file in "$tls"/openssl.cnf/*.cnf; do
  # shellcheck disable=SC2016
  sed -i -e 's#\$ENV::HOME/tls#$HOME/tls#g' -e '1i HOME = .' "$file"
done
expect 0 "certificate with an old configuration file" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn legacy.example.test

echo "=== Name constraints ==="
# A second home directory with authorities that have name constraints
first_home="$HOME"
export HOME="$test_root/home_constraints"
mkdir -p "$HOME"
limited="$HOME/tls"
expect 0 "setup for the name constraints" bash "$scripts_dir/tls_directory_setup.sh"
expect 2 "invalid name constraints are refused" bash "$scripts_dir/certificate-authority/trusted_id.sh" \
  --name-constraints "example.test"
check "refused option creates no key" test ! -e "$limited/private/root/trusted_id.pem"
expect 0 "trusted identity with name constraints" bash "$scripts_dir/certificate-authority/trusted_id.sh" \
  --name-constraints "DNS:test,DNS:localhost,IP:0.0.0.0/0"
expect 0 "root CA with name constraints" bash "$scripts_dir/certificate-authority/root_ca.sh" \
  --name-constraints DNS:example.test, DNS:lab.test, DNS:localhost --name-constraints "IP:192.168.0.0/16, IP:127.0.0.0/8"
check "a list with spaces and without quotes is read in full" bash -c \
  "openssl x509 -in '$limited/certs/root/root_ca.pem' -noout -text | grep -A8 'Name Constraints' | grep -c 'DNS:\|IP:' | grep -qx 5"
expect 0 "intermediate CA with name constraints" bash "$scripts_dir/intermediate-certificate-authority/ca.sh" \
  --name-constraints "DNS:example.test, DNS:localhost, IP:192.168.1.77/16, IP:127.0.0.0/8"
check "intermediate CA holds the critical extension" bash -c \
  "openssl x509 -in '$limited/certs/intermediate/ca.pem' -noout -text | grep -q 'Name Constraints: critical'"
check "the network address is normalized" bash -c \
  "openssl x509 -in '$limited/certs/intermediate/ca.pem' -noout -text | grep -q 'IP:192.168.0.0/255.255.0.0'"
check "the configuration file is not changed" cmp -s "$repo_dir/openssl.cnf/ca.cnf" "$limited/openssl.cnf/ca.cnf"
expect 0 "certificate for a permitted name" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn app.example.test --ip 192.168.1.10
expect 0 "wildcard certificate for a permitted name" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn '*.wild.example.test'
expect 0 "localhost certificate with name constraints" bash "$scripts_dir/certificate/cert_ecdsa_localhost.sh" \
  --non-interactive
expect 2 "name outside the intermediate CA is refused" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn app.lab.test
expect 2 "name outside every authority is refused" bash "$scripts_dir/certificate/cert_ecdsa_client.sh" \
  --fqdn app.other.test
expect 2 "name that only ends with a permitted name is refused" bash "$scripts_dir/certificate/cert_ecdsa_client.sh" \
  --fqdn notexample.test
expect 2 "IP address outside the networks is refused" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn ip.example.test --ip 10.0.0.1
check "refused names leave no key" bash -c "! ls '$limited'/private/certificates/ | grep -Eq 'lab|other|notexample|ip\.'"
check "refused names leave no database entry" bash -c "! grep -Eq 'lab|other|notexample|ip\.' '$limited/db/index.txt'"
expect 0 "verify passes with name constraints" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
expect 0 "renewal with name constraints" bash "$scripts_dir/renew_tls_certificates.sh" --yes app.example.test
# OpenSSL itself refuses a name outside the constraints, also without the check of the script
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes -subj "/CN=app.other.test" \
  -keyout "$test_root/outside.key" -out "$test_root/outside.csr" >/dev/null 2>&1
printf 'subjectAltName = DNS:app.other.test\n' >"$test_root/outside.ext"
openssl ca -config "$limited/openssl.cnf/cert.cnf" -rand_serial -notext -batch -in "$test_root/outside.csr" \
  -out "$test_root/outside.pem" -extfile "$test_root/outside.ext" >/dev/null 2>&1
expect 2 "openssl verify refuses a name outside the constraints" openssl verify \
  -CAfile "$limited/certs/intermediate/ca_chain_bundle.pem" "$test_root/outside.pem"

echo "=== Replace and revoke an authority ==="
count_status() {
  awk -F'\t' -v s="$1" '$1 == s' "$2" | grep -c . || true
}
expect 0 "CRL of the root CA" bash "$scripts_dir/revoke_tls_certificates.sh" --crl-only --authority ca
check "CRL of the root CA verifies" openssl crl -in "$limited/crl/root_crl.pem" -noout \
  -CAfile "$limited/certs/root/root_ca_chain_bundle.pem"
expect 0 "CRL of the trusted identity" bash "$scripts_dir/revoke_tls_certificates.sh" --crl-only --authority root_ca
check "CRL of the trusted identity verifies" openssl crl -in "$limited/crl/trusted_id_crl.pem" -noout \
  -CAfile "$limited/certs/root/trusted_id.pem"
expect 2 "caCompromise needs --authority" bash "$scripts_dir/revoke_tls_certificates.sh" --yes \
  --reason caCompromise app.example.test
old_ca_serial=$(serial_of "$limited/certs/intermediate/ca.pem")
expect 1 "replacing an authority asks for confirmation" bash "$scripts_dir/intermediate-certificate-authority/ca.sh" --replace
check "a refused replacement changes nothing" test "$(serial_of "$limited/certs/intermediate/ca.pem")" = "$old_ca_serial"
expect 0 "intermediate CA is replaced" bash "$scripts_dir/intermediate-certificate-authority/ca.sh" --replace --yes
check "the old intermediate CA is superseded" test "$(count_status R "$limited/db/root_ca/index.txt")" = "1"
check "the new intermediate CA is the only valid entry" test "$(count_status V "$limited/db/root_ca/index.txt")" = "1"
check "unique_subject is yes after the replacement" grep -q "unique_subject = yes" "$limited/db/root_ca/index.txt.attr"
check "the old intermediate CA is in the archive" bash -c "ls '$limited'/archive/_ca/ca/*/certs/intermediate/ca.pem >/dev/null"
expect 0 "database of the root CA loads after the replacement" openssl ca -config "$limited/openssl.cnf/ca.cnf" \
  -updatedb -passin env:TLS_ROOT_CA_PASSPHRASE
expect 0 "certificate from the new intermediate CA" bash "$scripts_dir/certificate/cert_ecdsa_server.sh" \
  --fqdn fresh.example.test
expect 0 "verify passes for the new intermediate CA" bash "$scripts_dir/verify_tls_certificates.sh" fresh.example.test
expect 0 "renewal moves a certificate to the new intermediate CA" bash "$scripts_dir/renew_tls_certificates.sh" \
  --yes app.example.test
expect 0 "verify passes for the renewed certificate" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
expect 0 "revoke the intermediate CA (dry run)" bash "$scripts_dir/revoke_tls_certificates.sh" --dry-run --authority ca
check "dry run revokes nothing" test "$(count_status V "$limited/db/root_ca/index.txt")" = "1"
expect 0 "revoke the intermediate CA" bash "$scripts_dir/revoke_tls_certificates.sh" --yes --authority ca \
  --reason caCompromise
check "no valid intermediate CA is left in the database" test "$(count_status V "$limited/db/root_ca/index.txt")" = "0"
check "CRL of the root CA lists both certificates" bash -c \
  "openssl crl -in '$limited/crl/root_crl.pem' -noout -text | grep -c 'Serial Number:' | grep -qx 2"
check "CRL of the root CA has the reason" bash -c \
  "openssl crl -in '$limited/crl/root_crl.pem' -noout -text | grep -q 'CA Compromise'"
check "status shows the revoked intermediate CA" bash -c \
  "bash '$scripts_dir/tls_certificate_status.sh' | grep 'intermediate' | grep -q REVOKED"
expect 2 "a revoked intermediate CA does not issue" bash "$scripts_dir/certificate/cert_ecdsa_client.sh" \
  --fqdn afterrevoke.example.test
expect 2 "an authority is not revoked twice" bash "$scripts_dir/revoke_tls_certificates.sh" --yes --authority ca
check "the database of the certificates is not touched" bash -c "! grep -q 'HA E1' '$limited/db/index.txt'"
expect 0 "root CA is replaced" bash "$scripts_dir/certificate-authority/root_ca.sh" --replace --yes
check "the old root CA is superseded" test "$(count_status R "$limited/db/trusted_id/index.txt")" = "1"
check "the new root CA is the only valid entry" test "$(count_status V "$limited/db/trusted_id/index.txt")" = "1"
expect 0 "trusted identity is replaced" bash "$scripts_dir/certificate-authority/trusted_id.sh" --replace --yes
check "the old trusted identity is in the archive" bash -c \
  "ls '$limited'/archive/_ca/trusted_id/*/certs/root/trusted_id.pem >/dev/null"
check "no temporary folder or staged file is left" bash -c \
  "! find '$limited' \\( -name '.ca.*' -o -name '.root_ca.*' -o -name '.trusted_id.*' -o -name '*.new.*' \\) | grep -q ."
export HOME="$first_home"

echo "=== Old script names ==="
expect 0 "ssl_certificate_status.sh starts the new script" bash "$scripts_dir/ssl_certificate_status.sh"

echo "=== Installer ==="
expect 0 "installer adds the aliases" bash "$scripts_dir/tls_dotfiles_installer.sh"
expect 0 "installer runs a second time" bash "$scripts_dir/tls_dotfiles_installer.sh"
check "aliases are added once" test "$(grep -c 'dotfiles/.bash_aliases" ]; then' "$HOME/.bashrc")" = "1"

echo
echo "Passed: $passed. Failed: $failed."
[[ "$failed" -eq 0 ]] || exit 1
exit 0
