# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add a brand guide and branding files in `.github/branding/` (logo, icons,
  favicon, and social preview), and show the logo at the top of `README.md`
- Add the `badges.yml` workflow and `.github/scripts/generate_badges.py` to render the
  README badges, including Super Linter and CodeQL, as SVG files on the `badges`
  branch

### Changed

- Move the repository tooling (`lint.sh`, `generate_badges.py`, `setup_gpg.sh`,
  and `verify_signatures.sh`) from `scripts/` to `.github/scripts/`, the
  branding from `assets/branding/` to `.github/branding/`, and the code style
  guide from `docs/` to `.github/docs/`. `scripts/` keeps the certificate
  scripts
- Add a 20 px protective border to the logo SVGs and show the logo in
  `README.md` at a fixed height of 100 px
- Update the badges only after Lint Repository and CodeQL ran and passed for the
  same commit: remove the `push` trigger from `badges.yml` and add the
  `check-workflows` job
- Remove the `docs`, `assets`, and `scripts/generate_badges.py` entries from the
  removal list of `ssl_dotfiles_installer.sh` (version 2.7.0): those files now
  live in `.github`, which the installer removes as a whole
- Replace the `img.shields.io` badges in `README.md` with the self-hosted
  badges
- Explain in `.github/super_linter.env` when to enable PowerShell validation
- Explain in `codeql.yml` when to add a language
- Ignore `notes.md`, `super_linter.log`, and Python cache files in `.gitignore`
- Replace the deprecated `deny-licenses` option in `dependency_review.yml` with
  an `allow-licenses` list of permissive licenses and CC BY-NC-SA 4.0, so GPL
  and LGPL stay blocked
- Check development dependencies too in `dependency_review.yml`, by setting
  `fail-on-scopes` to `runtime, development`
- chore: adopt the blueprint template as the repository standard [3dbe881](https://github.com/homelab-alpha/openssl/commit/3dbe88126f82c7bec49b73010e9085164db4236d) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(deps): comment on the pull request only when the dependency review fails [884f2dd](https://github.com/homelab-alpha/openssl/commit/884f2dd12427f9082d19b20c2f1a13dba7d7031d) by [@homelab-alpha](https://github.com/homelab-alpha)
- docs: add CLAUDE.md with the project rules for Claude Code [e09b4de](https://github.com/homelab-alpha/openssl/commit/e09b4de6a8a7ca7bc09732913f91f397d9f98040) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(repo): adopt the current blueprint standard [3e36ac3](https://github.com/homelab-alpha/openssl/commit/3e36ac33176b0b6ef1d620ee05f23893da91914a) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(scripts): remove assets in the installer [eb3ee72](https://github.com/homelab-alpha/openssl/commit/eb3ee72960901931a41b02065301533e06301cf5) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(repo): sync the latest blueprint updates [210da04](https://github.com/homelab-alpha/openssl/commit/210da04f6d93539fdeb542b3870d4cd8a3bd69c0) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(scripts): trim the installer removal list [7eddbce](https://github.com/homelab-alpha/openssl/commit/7eddbce86344decbeeed0be953c93473b602b10d) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(workflows): replace deny-licenses with allow-licenses [4a252ba](https://github.com/homelab-alpha/openssl/commit/4a252babc50653697818e6042e783cd828506fa5) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(blueprint): sync with the blueprint [03c26da](https://github.com/homelab-alpha/openssl/commit/03c26da61df31d67b1f8a37a2da5e10eed271268) by [@homelab-alpha](https://github.com/homelab-alpha)
- ci(workflows): request a reviewer on bot PRs [571d21b](https://github.com/homelab-alpha/openssl/commit/571d21b5fc7cdcec4821dfabcc452ad42ddfe06c) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(github): sync Hugo and Dart Sass rules [f94ef14](https://github.com/homelab-alpha/openssl/commit/f94ef14e86b537542c7b65e49fab8e43603a5a27) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(github): sync runners, Renovate, and linters [8f598b2](https://github.com/homelab-alpha/openssl/commit/8f598b2952f5ae86a1910f39439adcc50d7ca319) by [@homelab-alpha](https://github.com/homelab-alpha)
- ci(workflows): run workflows for bots [038ae2d](https://github.com/homelab-alpha/openssl/commit/038ae2d0db2312a79920081f98fa44b56354234e) by [@homelab-alpha](https://github.com/homelab-alpha)
- ci(workflows): allow BlueOak-1.0.0 license [6a3a989](https://github.com/homelab-alpha/openssl/commit/6a3a989186f3b96567f8e29bf7db0a6778803446) by [@homelab-alpha](https://github.com/homelab-alpha)
- chore(labels): add dependency update labels [0f01004](https://github.com/homelab-alpha/openssl/commit/0f010040f2a4ee1e021323759d545843d61bfccf) by [@homelab-alpha](https://github.com/homelab-alpha)
- docs(readme): reword the maintenance warning [3d65895](https://github.com/homelab-alpha/openssl/commit/3d658957f1bffd04c4dd101f4b1e7887f84cd4ff) by [@homelab-alpha](https://github.com/homelab-alpha)

### Deprecated

### Removed

### Fixed

- Fix the link to the documentation site in `README.md`, which pointed to
  `homelab-alpha.nl/docs/openssl/` instead of `homelab-alpha.nl/openssl/`
- Fix the GitHub link in `NOTICE`, which pointed to `github.com/openssl`
  instead of `github.com/homelab-alpha`
- Fix the table of contents link of `CONTRIBUTING.md` to its first heading
- fix(renovate): fix invalid automergeType and vulnerability rule [f041929](https://github.com/homelab-alpha/openssl/commit/f041929d7e6522c050f1a2b4f9faea787596ad40) by [@homelab-alpha](https://github.com/homelab-alpha)
- fix(labels): skip unchanged labels and retry failed writes [f86d8d3](https://github.com/homelab-alpha/openssl/commit/f86d8d348d59598e2983f485e73a20eda8064ee4) by [@homelab-alpha](https://github.com/homelab-alpha)
- fix(docs): fix the TOC link to the first heading [206df6c](https://github.com/homelab-alpha/openssl/commit/206df6cb0d53c9b3138aef02537e13b7abaf1be7) by [@homelab-alpha](https://github.com/homelab-alpha)
- fix(docs): fix the documentation site link [697c67b](https://github.com/homelab-alpha/openssl/commit/697c67b3f77396649ed80947fa003ff431a17a59) by [@homelab-alpha](https://github.com/homelab-alpha)
- fix(changelog): remove the date from Unreleased [6c75240](https://github.com/homelab-alpha/openssl/commit/6c7524002fd4bc24c0767ee0ceeef6f4dbbb13ad) by [@homelab-alpha](https://github.com/homelab-alpha)
- fix(scripts): restore pull_request_body.py logic [1c5d608](https://github.com/homelab-alpha/openssl/commit/1c5d6083e24bb87def267a93c3ba6ad0e0bcf357) by [@homelab-alpha](https://github.com/homelab-alpha)
- fix(changelog): remove the Unreleased link [98976b1](https://github.com/homelab-alpha/openssl/commit/98976b1c2c43a3b319c52edb67875fb40330fea3) by [@homelab-alpha](https://github.com/homelab-alpha)
- fix(openssl): align configs with OpenSSL 4.x [6bd5392](https://github.com/homelab-alpha/openssl/commit/6bd53925b28edd5019311a3cf3a89efee2e72a8c) by [@homelab-alpha](https://github.com/homelab-alpha)

### Security

- Override the transitive dev dependencies `glob` (14.0.3) and `minimatch`
  (11.0.3) to fix Dependabot alerts, which textlint pulls in
