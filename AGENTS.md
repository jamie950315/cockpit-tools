# Fork Maintenance Notes

This fork keeps three public branches with deliberately separate scopes:

- `xcode27patch`: only the Xcode 27 / Swift 6.4 static-library linker fix in `src-tauri/build.rs`.
- `cliproxy`: upstream mixed-model routing plus the sanitized five-account OAuth and CLIProxyAPI deployment guide.
- `main`: all changes from both branches.

Never commit Cockpit runtime stores, API keys, OAuth tokens, account IDs, auth files, generated model catalogs, build products, or local signing material.

Before publishing code changes, run the relevant frontend, Go, Rust, and macOS bundle checks described in the repository documentation. A model appearing in a catalog is not proof of correct routing; validate an official OAuth request and a namespaced CLIProxyAPI request independently in the target environment.
