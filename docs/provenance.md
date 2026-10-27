# Provenance

The WSL bootstrap comes from the public
[`jonathan-vella/the-ultimate-csa-toolkit`](https://github.com/jonathan-vella/the-ultimate-csa-toolkit)
repository. Its source is under `.devcontainer/wsl/` at revision
[`3906eba2dc13180afbd757ccfd3c46255478b8a7`](https://github.com/jonathan-vella/the-ultimate-csa-toolkit/commit/3906eba2dc13180afbd757ccfd3c46255478b8a7).
Launchpad includes the bootstrap, provisioning, and isolated regression tests
without the personal-dotfiles integration. The dotfiles installer and tests
were adapted from source supplied for this task. Launchpad includes only
neutral include and override hooks. It contains no personal configuration, Git
identity, VS Code settings, or private-repository URL. The `LICENSE` file
retains the MIT license notice.

Launchpad does not include the full dev-container stack, its image
configuration, or unrelated toolkit functionality.
