# Define directory paths.
openssl_script_dir="$HOME/openssl/scripts"
certificate_authority_dir="$openssl_script_dir/certificate-authority"
intermediate_certificate_authority_dir="$openssl_script_dir/intermediate-certificate-authority"
certificate_dir="$openssl_script_dir/certificate"

alias new-ssl-directorie-setup="$openssl_script_dir/ssl_directory_setup.sh"
alias openssl-verify="$openssl_script_dir/verify_ssl_certificates.sh"

alias new-trusted-id="$certificate_authority_dir/trusted-id.sh"
alias new-root-ca="$certificate_authority_dir/root_ca.sh"

alias new-ca="$intermediate_certificate_authority_dir/ca.sh"

alias new-cert-localhost="$certificate_dir/cert_ecdsa_localhost.sh"

alias new-cert-server="$certificate_dir/cert_ecdsa_server.sh"
alias new-cert-rsa-server="$certificate_dir/cert_rsa_server.sh"

alias new-cert-client="$certificate_dir/cert_ecdsa_client.sh"
alias new-cert-rsa-client="$certificate_dir/cert_rsa_client.sh"
