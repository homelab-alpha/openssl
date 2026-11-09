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
   5. [Development](#development)
   6. [Project Structure](#project-structure)
   7. [CI/CD and Automation](#cicd-and-automation)
      1. [Workflows](#workflows)
      2. [Linting](#linting)
      3. [Dependency Management](#dependency-management)
   8. [Policies and Standards](#policies-and-standards)
   9. [Working with Claude](#working-with-claude)
   10. [Known Issues](#known-issues)
       1. [Currently Being Addressed](#currently-being-addressed)
   11. [Contributing](#contributing)
   12. [Support](#support)
   13. [Security](#security)
   14. [Roadmap](#roadmap)
   15. [License](#license)

  </p>
</details>

## Description

**openssl** generates self-signed certificates for a homelab. It holds OpenSSL
configuration files and Bash scripts that create a root certificate authority,
an intermediate certificate authority, and ECDSA and RSA server, client, and
localhost certificates, and that verify the result.

> [!WARNING]
>
> The certificates are meant for a homelab environment, primarily for testing
> purposes. Do not use them in production.

> [!WARNING]
>
> This repository is being updated for OpenSSL 4.x, so parts of it may not work
> as expected. Check the output before you rely on it.

More documentation is on the
[Homelab-Alpha documentation site](https://homelab-alpha.nl/openssl/).

## Features

- **Certificate authorities** — Scripts for a trusted identity, a root CA, and
  an intermediate CA.
- **Certificates** — ECDSA and RSA certificates for servers and clients, and an
  ECDSA certificate for localhost with an HAProxy bundle. The server and client
  scripts also run without questions with `--fqdn` (and `--ip` for servers).
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
  `examples/ssl-directory-structure/`.

### Scripts

| Script                                             | Purpose                                                                                         | Alias                      |
| :------------------------------------------------- | :---------------------------------------------------------------------------------------------- | :------------------------- |
| `scripts/ssl_directory_setup.sh`                   | Sets up the directory structure for certificate management and the OpenSSL configuration files. | `new-ssl-directorie-setup` |
| `scripts/certificate-authority/trusted_id.sh`      | Creates the trusted root certificate (ECDSA) with verification and format conversion.           | `new-trusted-id`           |
| `scripts/certificate-authority/root_ca.sh`         | Creates the root certificate authority (ECDSA) and its CA chain bundle.                         | `new-root-ca`              |
| `scripts/intermediate-certificate-authority/ca.sh` | Creates the intermediate certificate authority and its CA chain bundle.                         | `new-ca`                   |
| `scripts/certificate/cert_ecdsa_localhost.sh`      | Issues an ECDSA certificate for localhost, with a bundle for HAProxy.                           | `new-cert-localhost`       |
| `scripts/certificate/cert_ecdsa_server.sh`         | Issues an ECDSA server certificate.                                                             | `new-cert-server`          |
| `scripts/certificate/cert_rsa_server.sh`           | Issues an RSA server certificate.                                                               | `new-cert-rsa-server`      |
| `scripts/certificate/cert_ecdsa_client.sh`         | Issues an ECDSA client certificate.                                                             | `new-cert-client`          |
| `scripts/certificate/cert_rsa_client.sh`           | Issues an RSA client certificate.                                                               | `new-cert-rsa-client`      |
| `scripts/verify_ssl_certificates.sh`               | Verifies certificates against their chain of trust.                                             | `openssl-verify`           |
| `scripts/ssl_certificate_status.sh`                | Reports the expiry date and the days left of all certificates. Read only.                       | `openssl-status`           |
| `scripts/renew_ssl_certificates.sh`                | Renews server and client certificates before they expire.                                       | `openssl-renew`            |
| `scripts/revoke_ssl_certificates.sh`               | Revokes a server or client certificate and generates a CRL.                                     | `openssl-revoke`           |
| `scripts/ssl_dotfiles_installer.sh`                | Adds the aliases to `~/.bashrc` when they are not there yet.                                    | —                          |

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
./scripts/ssl_dotfiles_installer.sh
```

The installer adds the aliases to `~/.bashrc`. Open a new shell, run
`new-ssl-directorie-setup` to create the directory structure, and then use the
other aliases to create the authorities and certificates. Each script describes
its usage in its header.

## Monitoring and Renewal

The leaf certificates are valid for 366 days. Two scripts help you keep them
valid. The certificates are for a homelab and for testing, not for production.

### Check the expiry

`openssl-status` lists every certificate under `~/ssl/certs`, including the
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
openssl-renew --dry-run www.example.test       # show the plan and exit
openssl-renew www.example.test                 # show the plan and ask first
openssl-renew --all --within 30 --yes          # renew everything that expires within 30 days
openssl-renew --reuse-key www.example.test     # keep the private key
```

For every renewal the script:

- archives the old key, certificate, and bundles in
  `~/ssl/archive/<fqdn>/<date>/` first, and never deletes anything;
- issues the new certificate with the same names, and rebuilds the chain bundle
  and the HAProxy bundle (mode 600);
- verifies the chain, the key, and the names, and restores the old files when a
  check fails;
- marks the old entry in `~/ssl/db/index.txt` as revoked with the reason
  `superseded`, because `openssl ca` cannot hold two valid entries with the same
  name. This is a database marking only. Run `openssl-revoke --crl-only`
  afterwards to put it in the CRL;
- runs the executable files in `~/ssl/hooks.d/`.

Good to know:

- CA certificates (trusted identity, root, and intermediate) are not renewed.
  The scripts warn when one expires soon.
- Only the names that the certificate scripts create are supported (the FQDN,
  `www.<fqdn>`, and one IPv4 address). A certificate with other names is
  refused.
- The CA private keys are not encrypted. A renewal that runs unattended can
  therefore read the intermediate CA key. Protect `~/ssl/private`.
- Exit codes: `0` success or nothing to renew, `1` a renewal, check, or hook
  failed, and `2` wrong usage or a pre-flight error (nothing was changed).

### Hooks

After a successful renewal, every executable file in `~/ssl/hooks.d/` runs with
the arguments `<fqdn> <certificate> <chain_bundle> <key> <haproxy_bundle>`. The
HAProxy bundle is empty for client certificates. A file that is not executable
is skipped. The example hook is executable in the repository, so copy it with
`install -m 644` to keep it disabled until you run `chmod +x`:

```bash
mkdir -p ~/ssl/hooks.d
install -m 644 ~/openssl/examples/hooks.d/reload_haproxy.sh ~/ssl/hooks.d/
chmod +x ~/ssl/hooks.d/reload_haproxy.sh
```

### Schedule

Nothing is installed automatically. Pick one of these examples.

A systemd user timer, in `~/.config/systemd/user/`:

```ini
# ssl-certificate-renewal.service
[Unit]
Description=Renew homelab certificates that expire soon

[Service]
Type=oneshot
WorkingDirectory=%h
ExecStart=%h/openssl/scripts/renew_ssl_certificates.sh --all --within 30 --yes
ExecStartPost=%h/openssl/scripts/ssl_certificate_status.sh --quiet
```

```ini
# ssl-certificate-renewal.timer
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
systemctl --user enable --now ssl-certificate-renewal.timer
loginctl enable-linger "$USER"   # run the timer when you are not logged in
```

The service fails when a renewal fails, or when the status check still finds a
certificate (for example an authority) that expires soon.

Or a cron job (`crontab -e`):

```cron
17 3 * * * cd "$HOME" && "$HOME/openssl/scripts/renew_ssl_certificates.sh" --all --within 30 --yes && "$HOME/openssl/scripts/ssl_certificate_status.sh" --quiet
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
(`~/ssl/db/index.txt`) and generates a new Certificate Revocation List (CRL) in
`~/ssl/crl/ca_crl.pem`, signed by the intermediate CA. The script verifies the
CRL with the CA chain before it replaces the previous CRL.

```bash
openssl-revoke --dry-run www.example.test                     # show the plan and exit
openssl-revoke www.example.test                               # show the plan and ask first
openssl-revoke --reason keyCompromise --yes www.example.test  # no questions
openssl-revoke --no-crl www.example.test                      # revoke, but skip the CRL
openssl-revoke --crl-only                                     # only generate a new CRL
```

The reason is one of `unspecified` (default), `keyCompromise`,
`affiliationChanged`, `superseded`, and `cessationOfOperation`. The script saves
a copy of `index.txt` in `~/ssl/archive/_database/` before it changes the
database.

Good to know:

- No file is deleted. The key, the certificate, and the bundles stay where they
  are, so stop using them yourself.
- A revoked certificate shows as `REVOKED` in `openssl-status`, and does not
  count for its exit code. `openssl-renew` refuses it. Issue a new certificate
  with the certificate scripts instead.
- CA certificates (trusted identity, root, and intermediate) are not revoked.
- The certificates have no CRL distribution point. Clients do not find the CRL
  by themselves. Install `ca_crl.pem` where it is used, for example in the
  configuration of HAProxy or nginx.
- A CRL is valid for 30 days. Generate a new one with
  `openssl-revoke --crl-only` before it expires, for example with a cron job or
  a timer. The renewal script marks the old entry of a renewed certificate as
  `superseded`. Run `--crl-only` afterwards to put those entries in the CRL.
- Exit codes: `0` success, `1` a revocation, the CRL, or a check failed, and `2`
  wrong usage or a pre-flight error (nothing was changed).

Check a certificate against the CRL:

```bash
openssl verify -crl_check -CAfile ~/ssl/certs/intermediate/ca_chain_bundle.pem \
  -CRLfile ~/ssl/crl/ca_crl.pem ~/ssl/certs/certificates/www.example.test.crt
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
│   │   ├── unreproducible_issues.yml           # Unreproducible issue management
│   │   └── update_changelog.yml                # Changelog entry for merged pull requests
│   ├── CODEOWNERS                              # Code ownership definitions
│   ├── labels.yml                              # Repository label definitions
│   ├── pull_request_template.md                # Pull request template
│   ├── renovate.json                           # Renovate dependency automation
│   └── super_linter.env                        # Super Linter environment configuration
├── dotfiles/                                   # Bash aliases for the scripts
│   └── .bash_aliases                           # Aliases for the SSL scripts
├── examples/                                   # Example scripts and usage demonstrations
│   ├── hooks.d/                                # Example hooks for the renewal script
│   │   └── reload_haproxy.sh                   # Example hook that reloads HAProxy (disabled by default)
│   └── ssl-directory-structure/                # Example directory structure for certificate management (52 files)
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
│   │   ├── cert_ecdsa_client.sh                # Issues an ECDSA client certificate
│   │   ├── cert_ecdsa_localhost.sh             # Issues an ECDSA certificate for localhost, with a bundle for HAProxy
│   │   ├── cert_ecdsa_server.sh                # Issues an ECDSA server certificate
│   │   ├── cert_rsa_client.sh                  # Issues an RSA client certificate
│   │   └── cert_rsa_server.sh                  # Issues an RSA server certificate
│   ├── intermediate-certificate-authority/     # Intermediate CA script
│   │   └── ca.sh                               # Creates the intermediate certificate authority and its CA chain bundle
│   ├── renew_ssl_certificates.sh               # Renews server and client certificates before they expire
│   ├── revoke_ssl_certificates.sh              # Revokes a server or client certificate and generates a CRL
│   ├── ssl_certificate_status.sh               # Reports the expiry date and the days left of all certificates
│   ├── ssl_directory_setup.sh                  # Sets up the directory structure for certificate management and the OpenSSL configuration files
│   ├── ssl_dotfiles_installer.sh               # Adds the aliases to `~/.bashrc` when they are not there yet
│   └── verify_ssl_certificates.sh              # Verifies certificates against their chain of trust
├── .editorconfig                               # Editor settings (indent, line endings)
├── .gitignore                                  # Git ignore rules
├── .gitleaksignore                             # Gitleaks secret scanning allowlist
├── .npmrc                                      # npm supply-chain hardening
├── .pre-commit-config.yaml                     # Local pre-commit hooks (mirrors CI)
├── .prettierignore                             # Files excluded from Prettier formatting
├── .prettierrc                                 # Prettier configuration file
├── AI_CONTRIBUTION_POLICY.md                   # Rules for contributions made with AI assistance
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
prioritizes security updates. Renovate does not automerge: a maintainer reviews
every update. Renovate also keeps a dependency dashboard issue.

## Policies and Standards

The repository includes internal policies that define how the project operates.
These are documented in `.github/policies/` and in root-level files:

| Document                                                                                               | Purpose                                              |
| :----------------------------------------------------------------------------------------------------- | :--------------------------------------------------- |
| [`.github/policies/github_actions.md`](./.github/policies/github_actions.md)                           | Workflow structure, security, and logging standards  |
| [`.github/policies/labels.md`](./.github/policies/labels.md)                                           | Label naming, color strategy, and usage rules        |
| [`.github/policies/logs.md`](./.github/policies/logs.md)                                               | Logging conventions for workflows and scripts        |
| [`.github/policies/review_process.md`](./.github/policies/review_process.md)                           | Code review stages, criteria, and merge strategy     |
| [`.github/policies/security.md`](./.github/policies/security.md)                                       | Security scanning and vulnerability management       |
| [`.github/policies/tests.md`](./.github/policies/tests.md)                                             | Testing standards, structure, and conventions        |
| [`.github/docs/code_style_and_standards_guides.md`](./.github/docs/code_style_and_standards_guides.md) | Coding style guidelines and Prettier configuration   |
| [`AI_CONTRIBUTION_POLICY.md`](./AI_CONTRIBUTION_POLICY.md)                                             | Rules for contributions made with AI assistance      |
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
[AI_CONTRIBUTION_POLICY.md](./AI_CONTRIBUTION_POLICY.md).

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
