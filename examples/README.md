# Examples

This folder shows what the scripts create. It is documentation, not a working
setup.

> [!NOTE]
>
> The key and certificate files in `tls-directory-structure/` are placeholders.
> They hold a warning text, not a real key or certificate, so they cannot be
> used. Create your own authorities and certificates with the scripts in
> `scripts/`.

| Folder                     | Content                                                 |
| :------------------------- | :------------------------------------------------------ |
| `hooks.d/`                 | Example hook for `renew_tls_certificates.sh`.           |
| `tls-directory-structure/` | Example of the directory `~/tls` after the scripts ran. |

The folder shows the layout that the current scripts create: the directory
setup, the three authorities, a certificate for `localhost`, and a server
certificate for `example.com`. Every authority has its own database
(`db/trusted_id/` and `db/root_ca/`). The configuration files in `openssl.cnf/`
are copies of the files of this repository.
