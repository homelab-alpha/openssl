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

# Define directory paths.
print_section_header "Define directory paths"
ssl_dir="$HOME/ssl"
root_dir="$ssl_dir/root"
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
openssl ecparam -name secp384r1 -genkey -out "$root_dir/private/trusted-id.pem"

# Generate Certificate.
print_section_header "Generate Certificate"
openssl req -new -x509 -sha384 -config "$root_dir/trusted-id.cnf" -extensions v3_ca -key "$root_dir/private/trusted-id.pem" -days 10956 -out "$root_dir/certs/trusted-id.pem"

# Verify Certificate against itself.
print_section_header "Verify Certificate against itself"
openssl verify -CAfile "$root_dir/certs/trusted-id.pem" "$root_dir/certs/trusted-id.pem"

# Check Private Key.
print_section_header "Check Private Key"
openssl ecparam -in "$root_dir/private/trusted-id.pem" -text -noout

# Check Certificate.
print_section_header "Check Certificate"
openssl x509 -in "$root_dir/certs/trusted-id.pem" -text -noout

# Convert Certificate from .pem to .cert.
print_section_header "Convert from trusted-id.pem to"
cat "$root_dir/certs/trusted-id.pem" >"$root_dir/certs/trusted-id.crt"
echo -e "$(print_cyan "--> ")""trusted-id.crt"
