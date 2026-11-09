# Define directory paths.
openssl_script_dir="$HOME/openssl/scripts"
certificate_authority_dir="$openssl_script_dir/certificate-authority"
intermediate_certificate_authority_dir="$openssl_script_dir/intermediate-certificate-authority"
certificate_dir="$openssl_script_dir/certificate"

alias new-tls-directory-setup="$openssl_script_dir/tls_directory_setup.sh"
alias openssl-migrate-tls="$openssl_script_dir/tls_directory_migrate.sh"
alias openssl-verify="$openssl_script_dir/verify_tls_certificates.sh"
alias openssl-status="$openssl_script_dir/tls_certificate_status.sh"
alias openssl-renew="$openssl_script_dir/renew_tls_certificates.sh"
alias openssl-revoke="$openssl_script_dir/revoke_tls_certificates.sh"

alias new-trusted-id="$certificate_authority_dir/trusted_id.sh"
alias new-root-ca="$certificate_authority_dir/root_ca.sh"

alias new-ca="$intermediate_certificate_authority_dir/ca.sh"

alias new-cert-localhost="$certificate_dir/cert_ecdsa_localhost.sh"

alias new-cert-server="$certificate_dir/cert_ecdsa_server.sh"
alias new-cert-rsa-server="$certificate_dir/cert_rsa_server.sh"

alias new-cert-client="$certificate_dir/cert_ecdsa_client.sh"
alias new-cert-rsa-client="$certificate_dir/cert_rsa_client.sh"

# Deprecated alias (old name). It still works and prints a warning.
alias new-ssl-directorie-setup="$openssl_script_dir/ssl_directory_setup.sh"
