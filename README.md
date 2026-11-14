<!-- markdownlint-disable MD041 -->

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/branding/logo_dark.svg" />
    <img src=".github/branding/logo_light.svg" alt="openssl" height="100" />
  </picture>
</p>

[![Super Linter](https://github.com/homelab-alpha/openssl/raw/badges/super_linter.svg)](https://github.com/homelab-alpha/openssl/actions/workflows/lint_repository.yml)
[![CodeQL](https://github.com/homelab-alpha/openssl/raw/badges/codeql.svg)](https://github.com/homelab-alpha/openssl/actions/workflows/codeql.yml)
[![Last commit](https://github.com/homelab-alpha/openssl/raw/badges/last_commit.svg)](https://github.com/homelab-alpha/openssl/commits/main/)
[![Repo size](https://github.com/homelab-alpha/openssl/raw/badges/repo_size.svg)](https://github.com/homelab-alpha/openssl/tree/main)
[![Changelog](https://github.com/homelab-alpha/openssl/raw/badges/changelog.svg)](https://github.com/homelab-alpha/openssl/blob/main/CHANGELOG.md)
[![Contributor Covenant](https://github.com/homelab-alpha/openssl/raw/badges/contributor_covenant.svg)](https://github.com/homelab-alpha/openssl/blob/main/CODE_OF_CONDUCT.md)
[![Conventional Commits](https://github.com/homelab-alpha/openssl/raw/badges/conventional_commits.svg)](https://conventionalcommits.org)
[![Semantic Versioning](https://github.com/homelab-alpha/openssl/raw/badges/semver.svg)](https://semver.org/spec/v2.0.0.html)
[![License](https://github.com/homelab-alpha/openssl/raw/badges/license.svg)](https://github.com/homelab-alpha/openssl/blob/main/LICENSE)

# OpenSSL

OpenSSL configuration files and helper scripts to generate self-signed
certificates for a homelab.

<details>
  <summary>Table of Contents (click to expand)</summary>
  <p>

1. [OpenSSL](#openssl)
   1. [Description](#description)
   2. [Features](#features)
      1. [Scripts](#scripts)
      2. [Configuration files](#configuration-files)
   3. [Project Status](#project-status)
   4. [Getting Started](#getting-started)
      1. [Requirements](#requirements)
      2. [Installation](#installation)
      3. [Passphrases of the authority keys](#passphrases-of-the-authority-keys)
      4. [Replace an authority](#replace-an-authority)
      5. [Name constraints (optional)](#name-constraints-optional)
      6. [Upgrading from an older version](#upgrading-from-an-older-version)
   5. [Migrating from ssl to tls](#migrating-from-ssl-to-tls)
   6. [Monitoring and Renewal](#monitoring-and-renewal)
      1. [Check the expiry](#check-the-expiry)
      2. [Renew certificates](#renew-certificates)
      3. [Hooks](#hooks)
      4. [Schedule](#schedule)
      5. [Check the served certificate](#check-the-served-certificate)
   7. [Revoke Certificates](#revoke-certificates)
      1. [Revoke an authority](#revoke-an-authority)
   8. [Development](#development)
   9. [Project Structure](#project-structure)
   10. [CI/CD and Automation](#cicd-and-automation)
       1. [Workflows](#workflows)
       2. [Linting](#linting)
       3. [Dependency Management](#dependency-management)
   11. [Policies and Standards](#policies-and-standards)
   12. [Working with Claude](#working-with-claude)
   13. [Known Issues](#known-issues)
       1. [Currently Being Addressed](#currently-being-addressed)
   14. [Contributing](#contributing)
   15. [Support](#support)
   16. [Security](#security)
   17. [Roadmap](#roadmap)
   18. [License](#license)

  </p>
</details>

## Description

**openssl** generates self-signed certificates for a homelab. It holds OpenSSL
configuration files and Bash scripts that create a root certificate authority,
an intermediate certificate authority, and ECDSA and RSA server, client, and
localhost certificates, and that verify, monitor, renew, and revoke them.

> [!WARNING]
>
> The certificates are meant for a homelab environment, primarily for testing
> purposes. Do not use them in production.

More documentation is on the
[Homelab-Alpha documentation site](https://homelab-alpha.nl/openssl/).

## Features

- **Certificate authorities** — Scripts for a trusted identity, a root CA, and
  an intermediate CA.
- **Certificates** — ECDSA and RSA certificates for servers and clients, and an
  ECDSA certificate for localhost with an HAProxy bundle. The server and client
  scripts also run without questions with `--fqdn` (and `--ip` for servers, with
  one or more IPv4 addresses separated by commas, such as
  `--ip 192.168.0.1,192.168.0.2` or `--ip 192.168.0.1, 192.168.0.2`). A server
  certificate covers the FQDN and `www.<fqdn>`. For a wildcard FQDN such as
  `'*.example.test'`, it covers the wildcard and `example.test` itself.
- **Verification** — A script that checks certificates against their chain of
  trust.
- **Monitoring and renewal** — A script that reports the expiry of all
  certificates, and a script that renews server and client certificates before
  they expire. See [Monitoring and Renewal](#monitoring-and-renewal).
- **Revocation** — A script that revokes a server or client certificate and
  generates a Certificate Revocation List (CRL). See
  [Revoke Certificates](#revoke-certificates).
- **Aliases** — A set of Bash aliases for every script in
  `dotfiles/.bash_aliases`.
- **Example** — An example directory structure in
  `examples/tls-directory-structure/`.

### Scripts

| Script                                             | Purpose                                                                                         | Alias                     |
| :------------------------------------------------- | :---------------------------------------------------------------------------------------------- | :------------------------ |
| `scripts/tls_directory_setup.sh`                   | Sets up the directory structure for certificate management and the OpenSSL configuration files. | `new-tls-directory-setup` |
| `scripts/certificate-authority/trusted_id.sh`      | Creates the trusted root certificate (ECDSA) with verification and format conversion.           | `new-trusted-id`          |
| `scripts/certificate-authority/root_ca.sh`         | Creates the root certificate authority (ECDSA) and its CA chain bundle.                         | `new-root-ca`             |
| `scripts/intermediate-certificate-authority/ca.sh` | Creates the intermediate certificate authority and its CA chain bundle.                         | `new-ca`                  |
| `scripts/certificate/cert.sh`                      | Issues a server or client certificate (ECDSA or RSA). The five scripts below start it.          | —                         |
| `scripts/certificate/cert_ecdsa_localhost.sh`      | Issues an ECDSA certificate for localhost, with a bundle for HAProxy.                           | `new-cert-localhost`      |
| `scripts/certificate/cert_ecdsa_server.sh`         | Issues an ECDSA server certificate.                                                             | `new-cert-server`         |
| `scripts/certificate/cert_rsa_server.sh`           | Issues an RSA server certificate.                                                               | `new-cert-rsa-server`     |
| `scripts/certificate/cert_ecdsa_client.sh`         | Issues an ECDSA client certificate.                                                             | `new-cert-client`         |
| `scripts/certificate/cert_rsa_client.sh`           | Issues an RSA client certificate.                                                               | `new-cert-rsa-client`     |
| `scripts/verify_tls_certificates.sh`               | Verifies certificates against their chain of trust.                                             | `openssl-verify`          |
| `scripts/tls_certificate_status.sh`                | Reports the expiry date and the days left of all certificates. Read only.                       | `openssl-status`          |
| `scripts/renew_tls_certificates.sh`                | Renews server and client certificates before they expire.                                       | `openssl-renew`           |
| `scripts/revoke_tls_certificates.sh`               | Revokes a certificate or an authority and generates a CRL.                                      | `openssl-revoke`          |
| `scripts/tls_directory_migrate.sh`                 | Moves the old directory `~/ssl` to `~/tls` and leaves a link behind.                            | `openssl-migrate-tls`     |
| `scripts/tls_dotfiles_installer.sh`                | Adds the aliases to `~/.bashrc` when they are not there yet.                                    | —                         |
| `scripts/lib/common.sh`                            | Shared functions. The other scripts load it; it is not a program.                               | —                         |

### Configuration files

| File                         | Purpose                                                  |
| :--------------------------- | :------------------------------------------------------- |
| `openssl.cnf/trusted_id.cnf` | Configuration for the trusted identity                   |
| `openssl.cnf/root_ca.cnf`    | Configuration for the root certificate authority         |
| `openssl.cnf/ca.cnf`         | Configuration for the intermediate certificate authority |
| `openssl.cnf/cert.cnf`       | Configuration for the certificates                       |

## Project Status

> [!NOTE]
>
> **Status:** Maintained
>
> The repository is maintained and updated through pull requests and automated
> dependency updates. Planned work is listed in [ROADMAP.md](./ROADMAP.md).

## Getting Started

### Requirements

A Linux system with Bash and OpenSSL.

### Installation

The aliases expect the repository in `~/openssl`:

```bash
git clone https://github.com/homelab-alpha/openssl.git ~/openssl
cd ~/openssl
chmod +x scripts/*.sh scripts/*/*.sh
./scripts/tls_dotfiles_installer.sh
```

The installer adds the aliases to `~/.bashrc`. Open a new shell, run
`new-tls-directory-setup` to create the directory structure, and then use the
other aliases to create the authorities and certificates. Each script describes
its usage in its header, and shows it with `--help`.

`new-tls-directory-setup` is safe to run again: it creates what is missing and
keeps every file that exists. To replace the configuration files in
`~/tls/openssl.cnf` with the files of the repository, run
`new-tls-directory-setup --update-config`. Each replaced file is saved first as
`<name>.cnf.bak-<date>`.

### Passphrases of the authority keys

`new-trusted-id` and `new-root-ca` encrypt the private key with a passphrase
(AES-256). The scripts ask for it, or read it from the environment variables
`TLS_TRUSTED_ID_PASSPHRASE` and `TLS_ROOT_CA_PASSPHRASE`. Keep the passphrases:
without them the keys cannot sign a new authority. Use `--no-passphrase` to
create a key that is not encrypted.

The key of the intermediate CA is not encrypted, because the certificate scripts
and the renewal use it at every run. Use `new-ca --passphrase` to encrypt it.
The scripts then ask for the passphrase, or read it from `TLS_CA_PASSPHRASE`; an
unattended renewal needs that variable. Protect `~/tls/private`.

### Replace an authority

An existing authority is never changed by accident. To create one again, for
example before the intermediate CA expires, use `--replace`:

```bash
new-ca --replace          # shows a warning and asks first
new-ca --replace --yes    # no questions
```

`new-root-ca` and `new-trusted-id` have the same options. The script copies the
old key and certificate to `~/tls/archive/_ca/` first, issues the new
certificate, and marks the old database entry as superseded.

The authorities and certificates below a replaced authority must be created
again: after a new root CA run `new-ca --replace`, and after a new intermediate
CA run `openssl-renew --all --within 400 --yes` to issue every certificate
again.

### Name constraints (optional)

By default an authority can sign a certificate for every name. A device that
trusts your trusted identity then also trusts a certificate for any other
domain, when someone gets hold of an authority key. The option
`--name-constraints` limits the names that an authority, and every authority
below it, can sign for. It is not set by default.

```bash
new-root-ca --name-constraints "DNS:example.test, DNS:localhost, IP:192.168.0.0/16, IP:127.0.0.0/8"
new-ca      --name-constraints "DNS:example.test, DNS:localhost, IP:192.168.0.0/16, IP:127.0.0.0/8"
```

- A space after a comma is allowed.
- `DNS:<domain>` permits the domain and its subdomains. `IP:<network>/<prefix>`
  permits an IPv4 network.
- A type that is not in the list is not limited. Name both the DNS names and the
  IP networks.
- Add `DNS:localhost` and `IP:127.0.0.0/8` when you use `new-cert-localhost`.
- The certificate scripts refuse a name outside the list before they create
  anything. Clients refuse such a certificate too.
- The list is part of the certificate of the authority. To change it, create the
  authority again, and then the authorities and certificates below it.
- `new-trusted-id` has the same option. Not every client applies the limit of a
  certificate in its trust store, so also set it for the root CA.

### Upgrading from an older version

- The configuration files now use `$ENV::HOME`, so the scripts work from every
  directory. Files that were copied to `~/tls/openssl.cnf` earlier keep working.
  Run `new-tls-directory-setup --update-config` to get the new files.
- The certificate scripts no longer write `db/serial` and `db/crlnumber`. Serial
  numbers are random, and the CRL number now increases with every CRL.
- Every authority has its own database: `~/tls/db/trusted_id/` (the root CA),
  `~/tls/db/root_ca/` (the intermediate CA), and `~/tls/db/` (the certificates).
  Older versions used `~/tls/db/` for all three. An existing setup keeps working
  with its old configuration files. `new-tls-directory-setup --update-config`
  moves the entries of the root CA and the intermediate CA to their own
  database, after a copy of `index.txt` in `~/tls/archive/_database/`.
- Existing authority keys stay as they are. Only a new trusted identity or root
  CA gets a passphrase.
- A client certificate holds only its FQDN. Use `--www` to add `www.<fqdn>`. The
  renewal keeps the names of an existing certificate.
- `openssl-verify` exits with `1` when a check fails. It also checks that every
  bundle holds a complete chain, and that the key in a HAProxy bundle belongs to
  the certificate.
- An existing authority is only created again with `--replace`. Editing
  `index.txt.attr` by hand is no longer needed.
- The Common Name is always the FQDN. Without `--fqdn` the certificate scripts
  ask for the FQDN only.
- A client certificate no longer has the extended key usage `emailProtection`.
- `--reuse-key` refuses a key of another type than the script creates.
- `openssl-status` also shows a revoked root CA or intermediate CA as `REVOKED`,
  and the certificate scripts refuse to use a revoked intermediate CA.
- The certificate scripts, the renewal, and the revocation share one lock, so
  two scripts cannot change a database at the same time.
- `new-tls-directory-setup` warns when `~/tls/private` has a wider mode
  than 700. Use `--fix-permissions` to change it.
- The installer no longer removes files from the clone.

## Migrating from ssl to tls

SSL is the old name of the protocol; TLS replaced it. The directory, the
scripts, and the aliases are renamed to match. The old names keep working, so
nothing breaks when you update an existing installation.

| Old                                  | New                                  |
| :----------------------------------- | :----------------------------------- |
| `~/ssl`                              | `~/tls`                              |
| `scripts/ssl_directory_setup.sh`     | `scripts/tls_directory_setup.sh`     |
| `scripts/ssl_certificate_status.sh`  | `scripts/tls_certificate_status.sh`  |
| `scripts/renew_ssl_certificates.sh`  | `scripts/renew_tls_certificates.sh`  |
| `scripts/revoke_ssl_certificates.sh` | `scripts/revoke_tls_certificates.sh` |
| `scripts/verify_ssl_certificates.sh` | `scripts/verify_tls_certificates.sh` |
| `scripts/ssl_dotfiles_installer.sh`  | `scripts/tls_dotfiles_installer.sh`  |
| `new-ssl-directorie-setup`           | `new-tls-directory-setup`            |

What keeps working until you migrate:

- The scripts use `~/ssl` while `~/tls` does not exist, and print a warning on
  `stderr`.
- The old script names start the new scripts and print a deprecation warning.
  The old alias `new-ssl-directorie-setup` does the same.
- `new-tls-directory-setup` refuses to create a second, empty `~/tls` while
  `~/ssl` exists.

To move to `~/tls`, run the migration once. It moves `~/ssl` to `~/tls`, leaves
a link `~/ssl` that points to `tls` (so old paths keep working), and changes the
path in `~/tls/openssl.cnf/*.cnf`. Every changed file is saved first as
`<name>.cnf.pre-tls`. No certificate, key, or database file changes.

```bash
openssl-migrate-tls --dry-run   # show what would happen
openssl-migrate-tls             # move the directory
```

The migration stops when both `~/ssl` and `~/tls` exist as directories, and when
a renewal or revocation is running. Update your own cron jobs, systemd units,
hooks, and HAProxy or nginx configuration to `~/tls` when you can, and remove
the link `~/ssl` when nothing uses it. The old script names and the old alias
are removed in a future major version.

## Monitoring and Renewal

The leaf certificates are valid for 366 days. Two scripts help you keep them
valid. The certificates are for a homelab and for testing, not for production.

### Check the expiry

`openssl-status` lists every certificate under `~/tls/certs`, including the
authorities, sorted by the days left. It never changes a file.

```bash
openssl-status                  # the full list
openssl-status --warn-days 45   # warn 45 days ahead for server and client certificates
openssl-status --quiet          # print only what needs attention (for cron or a timer)
```

Server and client certificates warn 30 days ahead by default, and the
authorities warn 180 days ahead (`--ca-warn-days`). The exit code tells what
happened:

| Exit code | Meaning                                                            |
| :-------- | :----------------------------------------------------------------- |
| `0`       | Every certificate is valid for longer than its threshold.          |
| `1`       | At least one certificate expires within its threshold.             |
| `2`       | At least one certificate has expired.                              |
| `3`       | An error occurred, for example an unreadable certificate. It wins. |

### Renew certificates

`openssl-renew` renews server and client certificates. It detects RSA or ECDSA
and server or client from the existing certificate, and it calls the matching
certificate script without questions.

```bash
openssl-renew --dry-run example.test       # show the plan and exit
openssl-renew example.test                 # show the plan and ask first
openssl-renew --all --within 30 --yes          # renew everything that expires within 30 days
openssl-renew --reuse-key example.test     # keep the private key
```

For every renewal the script:

- archives the old key, certificate, and bundles in
  `~/tls/archive/<fqdn>/<date>/` first, and never deletes anything;
- issues the new certificate with the same names, and rebuilds the chain bundle
  and the HAProxy bundle (mode 600);
- verifies the chain, the key, and the names, and restores the old files when a
  check fails;
- marks the old entry in `~/tls/db/index.txt` as revoked with the reason
  `superseded`, because `openssl ca` cannot hold two valid entries with the same
  name. This is a database marking only. Run `openssl-revoke --crl-only`
  afterwards to put it in the CRL;
- runs the executable files in `~/tls/hooks.d/`.

Good to know:

- CA certificates (trusted identity, root, and intermediate) are not renewed.
  The scripts warn when one expires soon. Create a new one with `--replace`.
- Only the names that the certificate scripts create are supported (the FQDN,
  `www.<fqdn>`, and IPv4 addresses). For a wildcard FQDN such as
  `*.example.test`, the domain itself (`example.test`) replaces `www.<fqdn>`. A
  certificate with other names is refused.
- The private key of the intermediate CA is not encrypted by default. A renewal
  that runs unattended can therefore read it. Protect `~/tls/private`.
- Exit codes: `0` success or nothing to renew, `1` a renewal, check, or hook
  failed, and `2` wrong usage or a pre-flight error (nothing was changed).

### Hooks

After a successful renewal, every executable file in `~/tls/hooks.d/` runs with
the arguments `<fqdn> <certificate> <chain_bundle> <key> <haproxy_bundle>`. The
HAProxy bundle is empty for client certificates. A file that is not executable
is skipped. The example hook is executable in the repository, so copy it with
`install -m 644` to keep it disabled until you run `chmod +x`:

```bash
mkdir -p ~/tls/hooks.d
install -m 644 ~/openssl/examples/hooks.d/reload_haproxy.sh ~/tls/hooks.d/
chmod +x ~/tls/hooks.d/reload_haproxy.sh
```

### Schedule

Nothing is installed automatically. Pick one of these examples.

A systemd user timer, in `~/.config/systemd/user/`:

```ini
# tls-certificate-renewal.service
[Unit]
Description=Renew homelab certificates that expire soon

[Service]
Type=oneshot
WorkingDirectory=%h
ExecStart=%h/openssl/scripts/renew_tls_certificates.sh --all --within 30 --yes
ExecStartPost=%h/openssl/scripts/tls_certificate_status.sh --quiet
```

```ini
# tls-certificate-renewal.timer
[Unit]
Description=Daily check of the homelab certificates

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now tls-certificate-renewal.timer
loginctl enable-linger "$USER"   # run the timer when you are not logged in
```

The service fails when a renewal fails, or when the status check still finds a
certificate (for example an authority) that expires soon.

Or a cron job (`crontab -e`):

```cron
17 3 * * * cd "$HOME" && "$HOME/openssl/scripts/renew_tls_certificates.sh" --all --within 30 --yes && "$HOME/openssl/scripts/tls_certificate_status.sh" --quiet
```

### Check the served certificate

The files can be fine while a service still serves the old certificate, for
example because it was not reloaded. Check what the service really serves:

```bash
echo | openssl s_client -connect host.example.test:443 -servername host.example.test 2>/dev/null \
  | openssl x509 -noout -enddate

# Exit code 1 when the served certificate expires within 30 days
echo | openssl s_client -connect host.example.test:443 -servername host.example.test 2>/dev/null \
  | openssl x509 -noout -checkend "$((30 * 86400))"
```

## Revoke Certificates

`openssl-revoke` revokes a server or client certificate, for example after a
private key leaked. It marks the certificate as revoked in the CA database
(`~/tls/db/index.txt`) and generates a new Certificate Revocation List (CRL) in
`~/tls/crl/ca_crl.pem`, signed by the intermediate CA. The script verifies the
CRL with the CA chain before it replaces the previous CRL.

```bash
openssl-revoke --dry-run example.test                     # show the plan and exit
openssl-revoke example.test                               # show the plan and ask first
openssl-revoke --reason keyCompromise --yes example.test  # no questions
openssl-revoke --no-crl example.test                      # revoke, but skip the CRL
openssl-revoke --crl-only                                 # only generate a new CRL
```

The reason is one of `unspecified` (default), `keyCompromise`,
`affiliationChanged`, `superseded`, and `cessationOfOperation`. The script saves
a copy of `index.txt` in `~/tls/archive/_database/` before it changes the
database.

Good to know:

- No file is deleted. The key, the certificate, and the bundles stay where they
  are, so stop using them yourself.
- A revoked certificate shows as `REVOKED` in `openssl-status`, and does not
  count for its exit code. `openssl-renew` refuses it. Issue a new certificate
  with the certificate scripts instead.
- When the key that signs is encrypted, the script asks for the passphrase, or
  reads it from `TLS_CA_PASSPHRASE`, `TLS_ROOT_CA_PASSPHRASE`, or
  `TLS_TRUSTED_ID_PASSPHRASE`.
- The certificates have no CRL distribution point. Clients do not find the CRL
  by themselves. Install `ca_crl.pem` where it is used, for example in the
  configuration of HAProxy or nginx.
- A CRL is valid for 30 days. Generate a new one with
  `openssl-revoke --crl-only` before it expires, for example with a cron job or
  a timer. The renewal script marks the old entry of a renewed certificate as
  `superseded`. Run `--crl-only` afterwards to put those entries in the CRL.
- Exit codes: `0` success, `1` a revocation, the CRL, or a check failed, and `2`
  wrong usage or a pre-flight error (nothing was changed).

### Revoke an authority

With `--authority` the script revokes the certificate of an authority, in the
database of the authority that signed it, and generates the CRL of that signer:

| Option                | Revokes             | Signed by            | CRL                            |
| :-------------------- | :------------------ | :------------------- | :----------------------------- |
| `--authority ca`      | the intermediate CA | the root CA          | `~/tls/crl/root_crl.pem`       |
| `--authority root_ca` | the root CA         | the trusted identity | `~/tls/crl/trusted_id_crl.pem` |

```bash
openssl-revoke --dry-run --authority ca               # show the plan and exit
openssl-revoke --reason caCompromise --authority ca   # revoke the intermediate CA
openssl-revoke --crl-only --authority ca              # only generate the CRL of the root CA
```

Clients that use the CRL then refuse every certificate below the revoked
authority. Create the authority again with `--replace`, and then the
certificates below it. The CRL of the root CA is valid for 90 days, and the CRL
of the trusted identity for 365 days. The trusted identity signs itself and
cannot be revoked: remove it from the trust stores instead.

Check a certificate against the CRL:

```bash
openssl verify -crl_check -CAfile ~/tls/certs/intermediate/ca_chain_bundle.pem \
  -CRLfile ~/tls/crl/ca_crl.pem ~/tls/certs/certificates/example.test.crt
```

## Development

Set up the dev tooling on any computer. It needs Node.js 24 (see `engines` in
`package.json`):

```bash
git clone https://github.com/homelab-alpha/openssl.git
cd openssl
npm ci
npm run lint
```

Linting has two parts. Every pull request runs `npm run lint` (Prettier,
textlint terminology, and merge conflict markers on the changed files), which
you can also run locally. `npm run lint:fix` repairs formatting and terminology
for you. Every push to `main` runs the full Super Linter, which you can run
locally with Docker:

```bash
docker run --rm -e RUN_LOCAL=true -e USE_FIND_ALGORITHM=true \
  -e VALIDATE_ALL_CODEBASE=true --env-file .github/super_linter.env \
  -v "$PWD":/tmp/lint ghcr.io/super-linter/super-linter:v9.0.0
```

For quick formatting of a single file, `npx prettier --write <file>` uses the
same `.prettierrc`.

The certificate scripts have an integration test. It runs the whole flow (the
setup, the authorities, one certificate of each kind, verification, revocation,
and renewal) in a temporary home directory, and never touches your own `~/tls`.
Every pull request runs it (`test_scripts.yml`). Run it locally with:

```bash
bash tests/integration/smoke_test.sh
```

## Project Structure

```treeview
openssl/
├── .claude/                                    # Claude Code project settings
│   └── settings.json                           # Shared permissions for Claude Code
├── .github/                                    # GitHub-specific configuration and automation
│   ├── DISCUSSION_TEMPLATE/                    # GitHub Discussions templates
│   │   ├── announcements.yml                   # Template for announcements
│   │   ├── feature-request.yml                 # Template for feature requests
│   │   ├── feedback.yml                        # Template for feedback
│   │   ├── help-support.yml                    # Template for help and support
│   │   └── q-a.yml                             # Template for Q&A
│   ├── ISSUE_TEMPLATE/                         # GitHub issue templates
│   │   ├── bug_report.yml                      # Template for bug reports
│   │   ├── config.yml                          # Issue template configuration
│   │   ├── i18n_issue.yml                      # Template for translation & localization
│   │   └── security_report.yml                 # Template for security issues
│   ├── branding/                               # Brand guide, logo, icons, and social preview
│   │   ├── brand_guide.md                      # Brand guide
│   │   ├── favicon.svg                         # Favicon
│   │   ├── icon_dark.svg                       # App icon (dark tile)
│   │   ├── icon_light.svg                      # App icon (light tile)
│   │   ├── logo_dark.svg                       # Logo (dark backgrounds)
│   │   ├── logo_light.svg                      # Logo (light backgrounds)
│   │   ├── logo_tagline_dark.svg               # Logo with slogan (dark)
│   │   ├── logo_tagline_light.svg              # Logo with slogan (light)
│   │   ├── mark_dark.svg                       # Mark (dark backgrounds)
│   │   ├── mark_light.svg                      # Mark (light backgrounds)
│   │   ├── social_preview.png                  # GitHub social preview (1280x640)
│   │   └── social_preview.svg                  # Source of the social preview
│   ├── docs/                                   # Repository style guide (not project docs)
│   │   ├── code_style_and_standards_guides.md  # Coding standards and style guidelines
│   │   └── .placeholder                        # Placeholder for empty folder
│   ├── linters/                                # Configuration files for Super Linter
│   │   ├── .checkov.yaml                       # Infrastructure-as-code security rules
│   │   ├── .gitleaks.toml                      # Gitleaks secret scanning configuration
│   │   ├── .markdown-lint.yml                  # Markdown linting rules
│   │   ├── .powershell-psscriptanalyzer.psd1   # PowerShell static analysis rules
│   │   ├── .textlintrc                         # Text/grammar linting configuration
│   │   ├── .yaml-lint.yml                      # YAML linting rules
│   │   └── actionlint.yml                      # GitHub Actions workflow linting rules
│   ├── policies/                               # Internal policies and documentation
│   │   ├── ai_contribution_policy.md           # AI contribution policy (ENG-AI-001)
│   │   ├── github_actions.md                   # Workflow standards (ENG-CI-001)
│   │   ├── labels.md                           # Label color strategy and rules
│   │   ├── logs.md                             # Logging policies and practices
│   │   ├── review_process.md                   # Code review process
│   │   ├── security.md                         # Security policy
│   │   └── tests.md                            # Testing policy
│   ├── scripts/                                # Repository tooling (not project code)
│   │   ├── generate_badges.py                  # Renders the README badges as SVG files
│   │   ├── lint.sh                             # Local lint (Prettier, textlint, conflict markers)
│   │   ├── pull_request_body.py                # Builds a pull request description from the template
│   │   ├── setup_signing.sh                    # Configures API or GPG signing for Git operations
│   │   └── verify_signatures.sh                # Verifies commit and tag signatures
│   ├── workflows/                              # GitHub Actions workflows
│   │   ├── badges.yml                          # Self-hosted README badges
│   │   ├── cleanup_actions.yml                 # Cache and run cleanup
│   │   ├── codeql.yml                          # CodeQL security analysis
│   │   ├── contributors.yml                    # Contributors list generator
│   │   ├── dependency_review.yml               # Dependency review
│   │   ├── issues.yml                          # Issue automation
│   │   ├── lint_pull_request.yml               # npm linting for pull requests
│   │   ├── lint_repository.yml                 # Super Linter
│   │   ├── merge_conflicts.yml                 # Merge conflict detection
│   │   ├── milestone_manager.yml               # Milestone automation
│   │   ├── pull_request.yml                    # Pull request automation
│   │   ├── release_manager.yml                 # Release automation
│   │   ├── signing_test.yml                    # Test API-based commit and tag signing
│   │   ├── stale_issues_and_pull_requests.yml  # Stale issue management
│   │   ├── sync_labels.yml                     # Label synchronization
│   │   ├── test_scripts.yml                    # Integration test of the certificate scripts
│   │   ├── unreproducible_issues.yml           # Unreproducible issue management
│   │   └── update_changelog.yml                # Changelog entry for merged pull requests
│   ├── CODEOWNERS                              # Code ownership definitions
│   ├── labels.yml                              # Repository label definitions
│   ├── pull_request_template.md                # Pull request template
│   ├── renovate.json                           # Renovate dependency automation
│   └── super_linter.env                        # Super Linter environment configuration
├── dotfiles/                                   # Bash aliases for the scripts
│   └── .bash_aliases                           # Aliases for the TLS scripts
├── examples/                                   # Example scripts and usage demonstrations
│   ├── hooks.d/                                # Example hooks for the renewal script
│   │   └── reload_haproxy.sh                   # Example hook that reloads HAProxy (disabled by default)
│   └── tls-directory-structure/                # Example directory structure for certificate management (71 files)
├── openssl.cnf/                                # OpenSSL configuration files
│   ├── ca.cnf                                  # Intermediate certificate authority configuration
│   ├── cert.cnf                                # Certificate configuration
│   ├── root_ca.cnf                             # Root certificate authority configuration
│   └── trusted_id.cnf                          # Trusted identity configuration
├── scripts/                                    # Utility and automation shell scripts
│   ├── certificate-authority/                  # Trusted identity and root CA scripts
│   │   ├── root_ca.sh                          # Creates the root certificate authority (ECDSA) and its CA chain bundle
│   │   └── trusted_id.sh                       # Creates the trusted root certificate (ECDSA) with verification and format conversion
│   ├── certificate/                            # Server, client, and localhost certificate scripts
│   │   ├── cert.sh                             # Issues a server or client certificate (ECDSA or RSA)
│   │   ├── cert_ecdsa_client.sh                # Issues an ECDSA client certificate
│   │   ├── cert_ecdsa_localhost.sh             # Issues an ECDSA certificate for localhost, with a bundle for HAProxy
│   │   ├── cert_ecdsa_server.sh                # Issues an ECDSA server certificate
│   │   ├── cert_rsa_client.sh                  # Issues an RSA client certificate
│   │   └── cert_rsa_server.sh                  # Issues an RSA server certificate
│   ├── intermediate-certificate-authority/     # Intermediate CA script
│   │   └── ca.sh                               # Creates the intermediate certificate authority and its CA chain bundle
│   ├── lib/                                    # Shared functions
│   │   └── common.sh                           # Functions that the other scripts load
│   ├── renew_ssl_certificates.sh               # Deprecated: starts renew_tls_certificates.sh
│   ├── renew_tls_certificates.sh               # Renews server and client certificates before they expire
│   ├── revoke_ssl_certificates.sh              # Deprecated: starts revoke_tls_certificates.sh
│   ├── revoke_tls_certificates.sh              # Revokes a server or client certificate and generates a CRL
│   ├── ssl_certificate_status.sh               # Deprecated: starts tls_certificate_status.sh
│   ├── ssl_directory_setup.sh                  # Deprecated: starts tls_directory_setup.sh
│   ├── ssl_dotfiles_installer.sh               # Deprecated: starts tls_dotfiles_installer.sh
│   ├── tls_certificate_status.sh               # Reports the expiry date and the days left of all certificates
│   ├── tls_directory_migrate.sh                # Moves the old directory ~/ssl to ~/tls and leaves a link behind
│   ├── tls_directory_setup.sh                  # Sets up the directory structure for certificate management and the OpenSSL configuration files
│   ├── tls_dotfiles_installer.sh               # Adds the aliases to `~/.bashrc` when they are not there yet
│   ├── verify_ssl_certificates.sh              # Deprecated: starts verify_tls_certificates.sh
│   └── verify_tls_certificates.sh              # Verifies certificates against their chain of trust
├── tests/                                      # Tests
│   └── integration/                            # Integration tests
│       └── smoke_test.sh                       # Runs the whole flow in a temporary home directory
├── .editorconfig                               # Editor settings (indent, line endings)
├── .gitignore                                  # Git ignore rules
├── .gitleaksignore                             # Gitleaks secret scanning allowlist
├── .npmrc                                      # npm supply-chain hardening
├── .pre-commit-config.yaml                     # Local pre-commit hooks (mirrors CI)
├── .prettierignore                             # Files excluded from Prettier formatting
├── .prettierrc                                 # Prettier configuration file
├── CHANGELOG.md                                # Project change history
├── CLAUDE.md                                   # Project rules for Claude Code
├── CODE_OF_CONDUCT.md                          # Contributor Covenant Code of Conduct
├── CONTRIBUTING.md                             # Contribution guidelines
├── CONTRIBUTORS.md                             # Auto-generated contributors list
├── GOVERNANCE.md                               # Project governance model
├── LICENSE                                     # Creative Commons BY-NC-SA 4.0 license
├── MAINTAINERS.md                              # Project maintainer list and process
├── NOTICE                                      # Attribution and license notice
├── package-lock.json                           # Locked versions of the dev tooling
├── package.json                                # Dev tooling (Prettier, textlint) and lint scripts
├── README.md                                   # Primary repository documentation
├── ROADMAP.md                                  # Planned features and milestones
├── SECURITY.md                                 # Security policy and reporting guidelines
├── SUPPORT.md                                  # Support channels and response times
└── TERMS_OF_SERVICE.md                         # Terms of service
```

## CI/CD and Automation

The repository includes a set of GitHub Actions workflows that run automatically
on push, pull request, and scheduled triggers.

### Workflows

| Workflow                             | Trigger                      | Purpose                                                       |
| :----------------------------------- | :--------------------------- | :------------------------------------------------------------ |
| `badges.yml`                         | Workflow run, daily, manual  | Renders the README badges to the `badges` branch              |
| `cleanup_actions.yml`                | Weekly schedule, manual      | Cleans up old workflow runs and Actions caches                |
| `codeql.yml`                         | Push, PR, weekly, manual     | CodeQL static analysis for security vulnerabilities           |
| `contributors.yml`                   | Push to `main`, manual       | Auto-generates `CONTRIBUTORS.md`                              |
| `dependency_review.yml`              | PR, manual                   | Reviews dependency changes for known vulnerabilities          |
| `issues.yml`                         | Issue events, manual         | Automates issue labeling and triage                           |
| `lint_pull_request.yml`              | PR, manual                   | Runs `npm run lint` on the changed files                      |
| `lint_repository.yml`                | Push to `main`, manual       | Runs Super Linter across the codebase                         |
| `merge_conflicts.yml`                | Push, PR                     | Detects merge conflicts in open pull requests                 |
| `milestone_manager.yml`              | Manual                       | Automates milestone creation and lifecycle                    |
| `pull_request.yml`                   | PR events, reviews, manual   | Pull request automation and validation                        |
| `release_manager.yml`                | Manual                       | Automates GitHub Releases                                     |
| `signing_test.yml`                   | Manual                       | Tests API-based commit and tag signing                        |
| `stale_issues_and_pull_requests.yml` | Daily schedule, manual       | Marks and closes stale issues and pull requests               |
| `sync_labels.yml`                    | Push, manual                 | Synchronizes repository labels from `.github/labels.yml`      |
| `test_scripts.yml`                   | PR, manual                   | Runs the integration test of the certificate scripts          |
| `unreproducible_issues.yml`          | Issue events, weekly, manual | Manages issues that cannot be reproduced                      |
| `update_changelog.yml`               | Every 8 hours, manual        | Adds an entry to `CHANGELOG.md` for every merged pull request |

All workflows follow the standards documented in
[`.github/policies/github_actions.md`](./.github/policies/github_actions.md),
including actions pinned to a commit SHA, concurrency controls, timeout limits,
and structured job summaries.

The README badges are not fetched from a third-party service. `badges.yml`
renders them with `.github/scripts/generate_badges.py` (Python standard library
only) and publishes the SVG files to the `badges` branch, which the README links
to through `github.com/<owner>/<repo>/raw/badges/`, which also works in a
private repository for signed-in viewers with access. The Super Linter and
CodeQL badges show the latest finished run on the default branch: passing or
failing. A workflow that exists but is turned off shows disabled. A workflow
that does not exist gets an empty badge, a transparent image, so the README
shows nothing and no broken image. Remove its badge line from this README when
you no longer need it. A cancelled or skipped run is ignored, and a workflow
without a finished run shows unknown. The workflow does not start on a push: it
starts when Lint Repository or CodeQL finishes, whatever the result (the
`workflow_run` trigger lists their names, so update it when you rename them),
and once a day. It creates the branch on its first run. The badges follow the
colors in [`.github/branding/brand_guide.md`](./.github/branding/brand_guide.md)
and switch to a dark variant with the system theme.

### Linting

Pull requests are linted with `npm run lint` (`.github/scripts/lint.sh`), which
uses Prettier, textlint, and a merge conflict marker check with the
configuration files below. Pushes to `main` run
[Super Linter](https://github.com/super-linter/super-linter), configured through
`.github/super_linter.env`. The following linters are enabled: Bash, Bash Exec,
Checkov, ENV, GitHub Actions (actionlint), Gitleaks, Git merge conflict markers,
JSON (Prettier), Markdown (Prettier), Natural Language (textlint), Pre-commit,
Renovate, and YAML (Prettier).

Super Linter reads its configuration files from `.github/linters/`: the rules
for Checkov, Gitleaks, textlint, actionlint, and PowerShell. The same folder
holds the rules for markdownlint and yamllint, which only the local pre-commit
hooks use.

### Dependency Management

Dependency updates are managed by [Renovate](https://github.com/apps/renovate).
The configuration in `.github/renovate.json` pins GitHub Actions to commit SHAs
and npm packages to exact versions, pins container images and pre-commit hooks
to digests or commit SHAs, waits 7 days before it proposes a new release, and
prioritizes security updates. Renovate groups updates by kind. Renovate
automerges patch, pin, and digest updates of GitHub Actions, pre-commit hooks,
and npm dev dependencies once the checks pass. A maintainer reviews every other
update. Pull Request Automation does not put the pull requests of Renovate back
to draft, because a draft cannot automerge. Renovate also keeps a dependency
dashboard issue.

## Policies and Standards

The repository includes internal policies that define how the project operates.
These are documented in `.github/policies/` and in root-level files:

| Document                                                                                               | Purpose                                              |
| :----------------------------------------------------------------------------------------------------- | :--------------------------------------------------- |
| [`.github/policies/ai_contribution_policy.md`](./.github/policies/ai_contribution_policy.md)           | Rules for AI-assisted contributions and code agents  |
| [`.github/policies/github_actions.md`](./.github/policies/github_actions.md)                           | Workflow structure, security, and logging standards  |
| [`.github/policies/labels.md`](./.github/policies/labels.md)                                           | Label naming, color strategy, and usage rules        |
| [`.github/policies/logs.md`](./.github/policies/logs.md)                                               | Logging conventions for workflows and scripts        |
| [`.github/policies/review_process.md`](./.github/policies/review_process.md)                           | Code review stages, criteria, and merge strategy     |
| [`.github/policies/security.md`](./.github/policies/security.md)                                       | Security scanning and vulnerability management       |
| [`.github/policies/tests.md`](./.github/policies/tests.md)                                             | Testing standards, structure, and conventions        |
| [`.github/docs/code_style_and_standards_guides.md`](./.github/docs/code_style_and_standards_guides.md) | Coding style guidelines and Prettier configuration   |
| [`GOVERNANCE.md`](./GOVERNANCE.md)                                                                     | Project governance model and decision-making process |
| [`MAINTAINERS.md`](./MAINTAINERS.md)                                                                   | Maintainer roles, responsibilities, and current list |
| [`TERMS_OF_SERVICE.md`](./TERMS_OF_SERVICE.md)                                                         | Terms of use for the repository                      |

## Working with Claude

Project rules and conventions for Claude Code live in
[`CLAUDE.md`](./CLAUDE.md). The shared settings are in
[`.claude/settings.json`](./.claude/settings.json). The code style guide is in
[`.github/docs/code_style_and_standards_guides.md`](./.github/docs/code_style_and_standards_guides.md),
so a session on any computer follows the same rules.

## Known Issues

The maintainers strive to provide a seamless experience. Below are any known
bugs, limitations, or issues you might encounter. This section is updated
regularly.

### Currently Being Addressed

No known issues at this time.

If you discover a bug or experience an issue not listed here, please
[open an issue on GitHub](https://github.com/homelab-alpha/openssl/issues/new/choose).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for
contribution guidelines, branch naming conventions, commit message format, and
the review process. AI-assisted contributions follow
[ai_contribution_policy.md](./.github/policies/ai_contribution_policy.md).

## Support

For setup questions, troubleshooting, and general help, see
[SUPPORT.md](./SUPPORT.md).

## Security

To report a security vulnerability, please follow the process described in
[SECURITY.md](./SECURITY.md). Do **not** report security issues via public
GitHub issues or discussions.

## Roadmap

Planned features, milestones, and the long-term direction of the project are
documented in [ROADMAP.md](./ROADMAP.md).

## License

This project is licensed under the **Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International License** (CC BY-NC-SA
4.0). See the [LICENSE](./LICENSE) and [NOTICE](./NOTICE) files for the full
license text and attribution requirements.
