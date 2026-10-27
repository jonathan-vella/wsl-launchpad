# Microsoft Defender on Windows 11 with WSL

This page gives guidance only. WSL Launchpad does not change Defender, firewall,
or Intune settings. The guidance has not been tested with Azure Linux 4, which
is in preview. On a managed device, follow your organization's policy and ask
your administrator before changing settings.

## Personal devices

1. Keep Microsoft Defender Antivirus real-time protection, cloud-delivered
   protection, and tamper protection on. Do not turn them off to speed up builds.
2. Keep Windows and WSL current: Windows Update, then `wsl --update`.
3. Before changing antivirus settings to address slow builds, check the
   [project storage and toolchain guidance](../README.md#where-to-keep-projects).
4. Do not add exclusions by default. If a measured slowdown remains, limit any
   justified exclusion to one build or cache folder. Never exclude the entire
   `%LOCALAPPDATA%\Packages` distro store, `wsl.exe`, or a drive.
5. Leave Windows Firewall on. With Windows 11 22H2 and WSL 2.0.9 or later,
   Windows Firewall rules apply to WSL automatically.
6. Treat files as untrusted regardless of whether Defender has scanned them;
   a clean scan is not a guarantee that a file is safe to run.
7. Never commit tokens. Use the sign-in steps in the README and keep secrets
   out of project files.

## Organization-managed devices

- The Defender for Endpoint plug-in gives security teams visibility into WSL 2
  distros. Microsoft lists WSL 2.0.7.0 or later and a device onboarded to
  Defender for Endpoint Plan 2 as prerequisites.
- The plug-in does not support ARM64 devices, multi-session Windows, or custom
  kernels. Visibility is not guaranteed with custom kernels. It provides
  visibility, not antimalware, threat and vulnerability management, or response
  commands for the WSL logical device. A distro can take up to 30 minutes to
  appear in the Defender portal.
- Admins can use Intune to control WSL settings, including custom-kernel use.
  Do not work around your organization's policy; ask your administrator.
- Check plug-in health with `healthcheck.exe` in
  `%ProgramFiles%\Microsoft Defender for Endpoint plug-in for WSL\tools`.

## Sources

- [Defender for Endpoint plug-in for WSL](https://learn.microsoft.com/defender-endpoint/mde-plugin-wsl)
- [WSL enterprise setup](https://learn.microsoft.com/windows/wsl/enterprise)
- [Manage WSL with Intune](https://learn.microsoft.com/windows/wsl/intune)

Microsoft Learn documents the plug-in requirements and firewall behavior above.
The personal-device checklist is general security guidance. Check Microsoft's
current documentation and your organization's policy for current requirements.
