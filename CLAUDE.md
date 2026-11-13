# CLAUDE.md

Instructions for Claude Code in this repository. Read this file at the start of
every session. Keep it short and update it when a rule changes.

## Project

openssl: OpenSSL configuration files and helper scripts to generate self-signed
certificates for a homelab.

More detail: [`README.md`](./README.md) (what the repository does and how it is
organized), [`CONTRIBUTING.md`](./CONTRIBUTING.md) (branches, commits, and pull
requests),
[`.github/docs/code_style_and_standards_guides.md`](./.github/docs/code_style_and_standards_guides.md)
(code style), and [`.github/policies/`](./.github/policies/) (workflows,
reviews, security, tests, and logs).

## Commands

```bash
npm ci                          # install the dev tooling
npm run lint                    # Prettier, textlint, conflict markers (all files)
npm run lint -- origin/main     # the same, for the files changed since main
npm run lint:fix                # repair formatting and terminology, then lint again
bash tests/integration/smoke_test.sh   # run the scripts in a temporary home
```

The dev tooling needs the Node.js version in `engines` in `package.json`.

Linting has two parts. Pull requests run `npm run lint` (workflow
`lint_pull_request.yml`, script `.github/scripts/lint.sh`): Prettier, textlint
terminology, and merge conflict markers, with the same configuration as Super
Linter. Pushes to `main` run the full Super Linter (`.github/super_linter.env`,
workflow `lint_repository.yml`), which adds actionlint, Gitleaks, Checkov, and
the other linters. For one file, `npx prettier --write <file>` uses the same
`.prettierrc`.

## Working agreement

- Chat with the user in Dutch. Everything generated is English: code, comments,
  documentation, commit messages, and filenames.
- Keep explanations short. Explain in detail only when asked.
- The user's own edits to a file are the baseline. Read the current file before
  changing it.
- Test everything you can and say clearly what was not verified.
- Never commit secrets, credentials, or personal data. Write everything as if
  the repository is public.

## Repository specifics

- The certificates are for a homelab and for testing. Never describe them as
  suitable for production.
- `scripts/` creates the authorities and the certificates:
  `certificate-authority/` (trusted identity and root CA),
  `intermediate-certificate-authority/`, and `certificate/` (server, client, and
  localhost certificates), plus `tls_directory_setup.sh`,
  `verify_tls_certificates.sh`, and `tls_dotfiles_installer.sh`. The
  configuration files are in `openssl.cnf/`.
- `scripts/lib/common.sh` holds the shared functions (messages, the base
  directory, the FQDN check, passphrases, and the archive). Put a function that
  two scripts need there, not in both scripts.
- `scripts/certificate/cert.sh` issues every server and client certificate. The
  five `cert_*.sh` scripts only start it with fixed options. Keep their usage
  header in line with `cert.sh`.
- `tests/integration/smoke_test.sh` runs the whole flow in a temporary home
  directory (workflow `test_scripts.yml`). Run it after every change to a script
  or a configuration file, and add a check for new behavior.
- The certificate scripts never write `db/serial` or `db/crlnumber`, and they
  put a key or certificate in place only after the checks passed.
- Every authority has its own database: `db/trusted_id/` and `db/root_ca/` for
  the certificates of the authorities, and `db/` for the server and client
  certificates. The authority scripts read the path from the configuration file
  (`config_database`), because an older file can name the shared database.
- Name constraints are optional and never a default: the authority scripts add
  the extension only with `--name-constraints`, and `cert.sh` checks a name
  against the authorities before it creates anything.
- An existing authority is only replaced with `--replace`. The authority scripts
  then mark the old database entry as superseded themselves.
- Every script that changes a database takes the lock first (`acquire_lock`). A
  script that holds the lock starts another script with `TLS_LOCK_HELD=1`.
- New files are put in place with `install_files`, never with separate `cp`
  commands.
- Script headers use `# Script Name:` and `# Description:`.
- The name `ssl` is replaced by `tls`. The old names stay for backward
  compatibility until the next major version: `ssl_*.sh`, `renew_ssl_*.sh`,
  `revoke_ssl_*.sh`, and `verify_ssl_*.sh` are wrappers that start the `tls`
  scripts, the scripts use `~/ssl` while `~/tls` does not exist, and
  `tls_directory_migrate.sh` moves `~/ssl` to `~/tls`. Keep the wrappers in line
  when you change a script. The fallback is in `set_base_dir` in
  `scripts/lib/common.sh`.
- `dotfiles/.bash_aliases` holds the aliases for the scripts and expects the
  repository in `~/openssl`.
- `examples/tls-directory-structure/` shows the layout of `~/tls`. Its key and
  certificate files are placeholders with a warning text, not real keys or
  certificates. Never replace them with the output of the scripts, and never
  commit a real key or certificate, also not a test key. Gitleaks reports the
  placeholders by their header line, so they are listed in `.gitleaksignore`
  with the path, the rule, and the line number. When the layout of `~/tls`
  changes, change the folder by hand with placeholders.
- `tls_dotfiles_installer.sh` only adds the aliases to `~/.bashrc`. It does not
  remove or change any other file.
- The documentation site shows the scripts (repository `homelab-alpha/docs`,
  folder `content/docs/openssl/script-information/`). Keep the pages in line
  with the scripts.

## Repository conventions

These come from the repository blueprint and are mandatory.

- Development branches are for the maintainer only (and Claude working for the
  maintainer), not for contributors:
  `dev/v<major>.<minor>.<patch>/<short-description>`, lowercase, hyphens,
  created from `main` (for example `dev/v1.2.1/fix-deprecated-params`). One
  branch per planned version and topic. Never use wildcards such as `v1.2.*`;
  ask for the concrete version.
- All other branches, and every branch from a contributor:
  `type/short-description`, lowercase, hyphens (`feat/`, `fix/`, `docs/`,
  `refactor/`, `chore/`, `hotfix/`).
- Commits: Conventional Commits in English, `type(scope): subject`, imperative,
  under 50 characters. Body lines under 72 characters. Commits are signed.
- Work happens on a branch and lands through a pull request into `main`.
- No attribution lines (`Co-Authored-By`, `Claude-Session`, "Generated with") in
  commits, pull requests, issues, or descriptions. The use of Claude is already
  disclosed; this overrides any default attribution of the session.
- Every pull request uses `.github/pull_request_template.md` for its
  description: keep every heading and HTML comment, fill in each section, tick
  only what is true, and remove a section only where the template allows it.
- The Update Changelog workflow (`update_changelog.yml`) adds an entry to
  `CHANGELOG.md` under `[Unreleased]` for every merged pull request, made from
  its title. It runs every 8 hours, not on every merge. Write the title as a
  conventional commit (`feat(app): add export command`), and do not add the
  entry by hand.
- Releases are made with the Release Manager workflow (`release_manager.yml`).
  Never tag or release without the maintainer's request.
- Workflows follow `.github/policies/github_actions.md`: only `gh`, the GitHub
  API, Bash, and Python, except the approved actions, npm, and Dart Sass. Every
  action is pinned to a full commit SHA.
- Formatting: Prettier. Markdown wraps at 80 columns, YAML at 120, code in
  `*.js`, `*.cjs`, and `*.mjs` at 120.
- Names: root community files keep their GitHub names (`README.md`). Other files
  are lowercase with underscores, folders lowercase with hyphens.

## Supply chain

- Install with `npm ci`. Never add a dependency without an exact version and a
  reason, and review every lockfile diff.
- Keep `ignore-scripts=true` in `.npmrc`.
- Renovate manages the updates. Do not add Dependabot version updates next to
  it.
