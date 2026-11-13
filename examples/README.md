# Examples

This folder shows what the scripts create. It is documentation, not a working
setup.

> [!WARNING]
>
> The private keys in `tls-directory-structure/` are public: everyone can read
> them in this repository. Never install the example certificates in a trust
> store, and never use the example keys or certificates for a service. Create
> your own authorities with the scripts in `scripts/`.

| Folder                     | Content                                                 |
| :------------------------- | :------------------------------------------------------ |
| `hooks.d/`                 | Example hook for `renew_tls_certificates.sh`.           |
| `tls-directory-structure/` | Example of the directory `~/tls` after the scripts ran. |

The example files were made with an earlier version of the scripts. The current
scripts create the same structure, with some differences: the configuration
files use `$ENV::HOME`, and the keys of the trusted identity and the root CA are
encrypted with a passphrase.
