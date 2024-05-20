#!/bin/bash

# Function to print text in cyan color
print_cyan() {
  echo -e "\e[36m$1\e[0m" # \e[36m sets text color to cyan, \e[0m resets it
}

# Function to generate a random hex value.
generate_random_hex() {
  openssl rand -hex 16
}

# Function to print section headers.
print_section_header() {
  echo ""
  echo ""
  echo -e "$(print_cyan "=== $1 === ")"
}

# Certificate information.
file_name=localhost
fqdn=localhost
ipv4=", IP:127.0.0.1"

# Define directory paths.
print_section_header "Define directory paths"
ssl_dir="$HOME/ssl"
certificates_dir="$ssl_dir/certificates"
intermediate_dir="$ssl_dir/intermediate"

# Renew db serial numbers.
print_section_header "Renew db serial numbers"
for dir in "$ssl_dir/root/db" "$intermediate_dir/db" "$ssl_dir/tsa/db"; do
  generate_random_hex >"$dir/serial"
done
generate_random_hex >"$ssl_dir/root/db/crlnumber"
generate_random_hex >"$intermediate_dir/db/crlnumber"

# Generate ECDSA key.
print_section_header "Generate ECDSA key"
openssl ecparam -name secp384r1 -genkey -out "$certificates_dir/private/${file_name}.pem"

# Generate Certificate Signing Request (CSR).
print_section_header "Generate Certificate Signing Request (CSR)"
openssl req -new -sha384 -config "$certificates_dir/cert.cnf" -key "$certificates_dir/private/${file_name}.pem" -out "$certificates_dir/csr/${file_name}.pem"

# Creating an extfile with all the alternative names
print_section_header "Create an extfile with all the alternative names"
{
  echo "subjectAltName = DNS:${fqdn}, DNS:*.${fqdn}${ipv4}"
  echo "basicConstraints = critical, CA:FALSE"
  echo "keyUsage = critical, digitalSignature"
  echo "extendedKeyUsage = serverAuth"
  echo "nsCertType = server"
  echo "nsComment = OpenSSL Generated Server Certificate"
} >>"$certificates_dir/extfile/${file_name}.cnf"

# Generate Certificate.
print_section_header "Generate Certificate"
openssl ca -config "$certificates_dir/cert.cnf" -notext -batch -in "$certificates_dir/csr/${file_name}.pem" -out "$certificates_dir/certs/${file_name}.pem" -extfile "$certificates_dir/extfile/${file_name}.cnf"

# Create Certificate Chain Bundle.
print_section_header "Create Certificate Chain Bundle"
cat "$certificates_dir/certs/${file_name}.pem" "$intermediate_dir/certs/ca_chain_bundle.pem" >"$certificates_dir/certs/${file_name}_chain_bundle.pem"

# Create Certificate Chain Bundle for HAProxy.
print_section_header "Create Certificate Chain Bundle for HAProxy"
cat "$certificates_dir/certs/${file_name}_chain_bundle.pem" "$certificates_dir/private/${file_name}.pem" >"$certificates_dir/certs/${file_name}_haproxy.pem"
chmod 600 "$certificates_dir/certs/${file_name}_haproxy.pem"

# Verify Certificate against the Certificate Chain Bundle.
print_section_header "Verify ${file_name} certificate against the ${file_name} certificate chain Bundle"
openssl verify -CAfile "$certificates_dir/certs/${file_name}_chain_bundle.pem" "$certificates_dir/certs/${file_name}.pem"

# Verify Certificate against the Intermediate Certificate Authority Chain Bundle.
print_section_header "Verify ${file_name} Certificate against the Intermediate Certificate Authority Chain Bundle"
openssl verify -CAfile "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${file_name}.pem"

# Verify Certificate Chain Bundle against the Intermediate Certificate Authority Chain Bundle.
print_section_header "Verify ${file_name} Certificate Chain Bundle against the Intermediate Certificate Authority Chain Bundle"
openssl verify -CAfile "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${file_name}_chain_bundle.pem"

# Verify HAProxy Certificate Chain Bundle against the Intermediate Certificate Authority Chain Bundle.
print_section_header "Verify HAProxy Certificate Chain Bundle against the Intermediate Certificate Authority Chain Bundle"
openssl verify -CAfile "$intermediate_dir/certs/ca_chain_bundle.pem" "$certificates_dir/certs/${file_name}_haproxy.pem"

# Check Private Key.
print_section_header "Check Private Key"
openssl ecparam -in "$certificates_dir/private/${file_name}.pem" -text -noout

# Check Certificate Signing Request (CSR).
print_section_header "Check Certificate Signing Request (CSR)"
openssl req -text -noout -verify -in "$certificates_dir/csr/${file_name}.pem"

# Check Certificate.
print_section_header "Check Certificate"
openssl x509 -in "$certificates_dir/certs/${file_name}.pem" -text -noout

# Check Certificate Chain Bundle.
print_section_header "Check Certificate Chain Bundle"
openssl x509 -in "$certificates_dir/certs/${file_name}_chain_bundle.pem" -text -noout

# Convert Certificate from .pem to .crt and .key.
print_section_header "Convert Certificate from ${fqdn}.pem to"
cat "$certificates_dir/certs/${file_name}.pem" >"$certificates_dir/certs/${file_name}.crt"
cat "$certificates_dir/certs/${file_name}_chain_bundle.pem" >"$certificates_dir/certs/${file_name}_chain_bundle.crt"
cat "$certificates_dir/private/${file_name}.pem" >"$certificates_dir/private/${file_name}.key"
chmod 600 "$certificates_dir/private/${file_name}.key"
echo -e "$(print_cyan "--> ")""${fqdn}.crt"
echo -e "$(print_cyan "--> ")""${fqdn}_chain_bundle.crt"
echo -e "$(print_cyan "--> ")""${fqdn}.key"
