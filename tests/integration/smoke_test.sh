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
expect 2 "root CA is not overwritten while unique_subject is yes" bash "$scripts_dir/certificate-authority/root_ca.sh"
expect 2 "trusted identity is not overwritten while unique_subject is yes" \
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

echo "=== Verification ==="
expect 0 "verify passes for a server certificate" bash "$scripts_dir/verify_tls_certificates.sh" app.example.test
expect 0 "verify passes for a client certificate" bash "$scripts_dir/verify_tls_certificates.sh" client.example.test
expect 0 "verify passes for the intermediate CA" bash "$scripts_dir/verify_tls_certificates.sh" ca.pem
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=BOOK" \
  -keyout "$test_root/rogue.key" -out "$tls/certs/certificates/BOOK.pem" >/dev/null 2>&1
cp "$tls/certs/certificates/BOOK.pem" "$tls/certs/certificates/BOOK_chain_bundle.pem"
expect 1 "verify fails for a certificate from another issuer" bash "$scripts_dir/verify_tls_certificates.sh" BOOK
rm -f "$tls/certs/certificates/BOOK.pem" "$tls/certs/certificates/BOOK_chain_bundle.pem"
expect 1 "verify fails for an unknown certificate" bash "$scripts_dir/verify_tls_certificates.sh" missing.example.test
expect 2 "verify rejects an unknown option" bash "$scripts_dir/verify_tls_certificates.sh" --unknown

echo "=== Revocation and CRL ==="
expect 0 "revoke a certificate" bash "$scripts_dir/revoke_tls_certificates.sh" --yes rsa.example.test
first_crl=$(crl_number)
expect 0 "new certificate after a revocation" bash "$scripts_dir/certificate/cert_rsa_server.sh" --fqdn rsa.example.test
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
