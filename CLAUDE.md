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
```

The dev tooling needs the Node.js version in `engines` in `package.json`.

Linting has two parts. Pull requests run `npm run lint` (workflow
`lint_pull_request.yml`, script `.github/scripts/lint.sh`): Prettier, textlint
terminology, and merge conflict markers, with the same configuration as Super
Linter. Pushes to `main` run the full Super Linter (`.github/super_linter.env`,
workflow `super_linter.yml`), which adds actionlint, Gitleaks, Checkov, and the
other linters. For one file, `npx prettier --write <file>` uses the same
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
  localhost certificates), plus `ssl_directory_setup.sh`,
  `verify_ssl_certificates.sh`, and `ssl_dotfiles_installer.sh`. The
  configuration files are in `openssl.cnf/`.
- Script headers use `# Script Name:` and `# Description:`.
- `dotfiles/.bash_aliases` holds the aliases for the scripts and expects the
  repository in `~/openssl`.
- `examples/ssl-directory-structure/` holds example keys and certificates.
  Gitleaks reports them, so they are listed in `.gitleaksignore` with the path,
  the rule, and the line number. Update an entry when you change such a file.
- `ssl_dotfiles_installer.sh` removes the files that are only needed to develop
  the repository from the clone of the user, such as `.git` and `.github` (which
  holds the tooling, the branding, and the style guide). Keep that list in line
  with the repository.
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
- Update `CHANGELOG.md` under `[Unreleased]` for every change that alters
  behavior. Entries are imperative: `Add export command`.
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
