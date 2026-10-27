# WSL performance cheat sheet

Azure Linux 4 is a preview. These workflow recommendations have not been
measured on this distribution.

## Put the working files with the tools

- **Linux tools, Git, builds, and dependencies in WSL:** keep the project under
  `~/src` in the WSL filesystem.
- **Windows-native tools and builds:** keep the project in a Windows folder,
  such as `C:\repos`.
- Avoid building Linux projects from `/mnt/c`. Microsoft recommends using the
  filesystem of the environment running the tools for best performance.
- If you need to build the same project in both environments, use separate
  checkouts. Keep generated dependencies and build outputs (for example
  `node_modules`, `.venv`, `bin`, and `obj`) with their matching toolchain.

If WSL opens under `/mnt/c`, move to your Linux workspace before cloning or
building:

```bash
mkdir -p ~/src
cd ~/src
```

To browse Linux files from Windows, run `explorer.exe .` from the WSL project
or open `\\wsl$\AzureLinux-4` in File Explorer. This does not change which
filesystem the tools use.

## Keep the editor and toolchain aligned

Install VS Code on Windows with the WSL extension. Run `code .` from the WSL
project directory and check that VS Code connects to `AzureLinux-4`. Run
language, build, and debug extensions in WSL when they use Linux tools. Keep
editor UI extensions on Windows.

## Don't trade security for speed

- Keep Defender protections enabled; do not disable real-time protection or
  add broad exclusions as a performance workaround.
- If builds remain slow, check the project location and tool environment first.
  Read [`defender.md`](defender.md) before considering an exclusion.
- Change WSL resource or networking settings only after identifying a
  bottleneck. Compare the same workload in the same environment before and
  after each change.

## References

- [Microsoft: file storage and performance across file systems](https://learn.microsoft.com/en-us/windows/wsl/filesystems#file-storage-and-performance-across-file-systems)
- [Microsoft: get started with VS Code and WSL](https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-vscode)
- [Launchpad Defender guidance](defender.md)
