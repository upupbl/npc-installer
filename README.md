# NPS NPC Auto Installer

Automatically detects the platform/architecture, downloads NPS v0.26.10 NPC, installs it, asks for NPS connection information, and starts NPC in the background. Linux/NAS, macOS, and Windows clients are supported.

## Linux / NAS

Recommended for NAS/embedded systems:

```sh
sh -c "$(curl -kfsSL https://dl.runsh.de/npc/install.sh)"
```

If Bash is available:

```bash
bash -c "$(curl --insecure -fsSL https://dl.runsh.de/npc/install.sh)"
```

After installation the script asks:

```text
NPS server [23.141.12.66:8024]:
VKey:
```

Press Enter at the server prompt to use the default server. VKey is not stored in this public repository.

Supported Linux architectures:

- x86_64 / amd64 -> linux_amd64_client.tar.gz
- i386 / i686 -> linux_386_client.tar.gz
- aarch64 / arm64 -> linux_arm64_client.tar.gz
- armv7l -> linux_arm_v7_client.tar.gz
- armv6 / armv5
- mips / mipsle / mips64 / mips64le

The installer extracts in `/tmp`, but runs the final binary from a writable executable directory such as `/usr/local/npc`, `/opt/npc`, `$HOME/.local/npc`, or `$HOME/npc`. This avoids common NAS `/tmp noexec` problems.
Updates are staged and atomically moved into place so an already-running binary does not cause a `Text file busy` failure or make the install directory change unexpectedly.

When run as root on a systemd host, the installer creates and enables `npc.service`. On macOS, running as root creates the `de.runsh.npc` LaunchDaemon. The saved startup configuration is readable only by root. If root or the native service manager is unavailable, NPC falls back to the previous detached background mode and prints a warning. Logs are written to `npc.log` in the installation directory.

Temporary sessions save an absolute expiry time. Restarting the computer resumes a still-valid connection but does not reset or extend its lifetime.

### Linux non-interactive mode

You can provide connection information without prompts:

```sh
NPC_SERVER='23.141.12.66:8024' NPC_VKEY='YOUR_VKEY' sh -c "$(curl -kfsSL https://dl.runsh.de/npc/install.sh)"
```

Optional variables:

```text
NPC_VERSION
NPC_RELEASE_BASE
NPC_INSTALL_DIR
NPC_DEFAULT_SERVER
NPC_SERVER
NPC_VKEY
NPC_TYPE
NPC_TIMEOUT        # seconds; 0 or unset means no automatic stop
NPC_SSH_PORT       # local SSH target port; defaults to 22
NPC_REPLACE_EXISTING # 1 (default) stops an old npc before starting; 0 keeps it running
NPC_AUTOSTART       # 1 (default) enables native boot startup; 0 uses background mode
```

When a generated Linux command is run again, the installer replaces an existing
`npc` connection by default. It sends `TERM`, waits up to 10 seconds, and only
then uses `KILL` if necessary. If a service or another watchdog immediately
restarts the old process, the installer stops with an error instead of launching
a second client. Set `NPC_REPLACE_EXISTING=0` to retain the old connection.

Temporary 24-hour session using a non-default local SSH port:

```sh
NPC_SERVER='23.141.12.66:8024' NPC_VKEY='YOUR_VKEY' NPC_TIMEOUT='86400' NPC_SSH_PORT='2222' sh -c "$(curl -kfsSL https://dl.runsh.de/npc/install.sh)"
```

## macOS

Enable **System Settings > General > Sharing > Remote Login** first, then run the same POSIX shell installer:

```sh
NPC_SERVER='23.141.12.66:8024' NPC_VKEY='YOUR_VKEY' NPC_TIMEOUT='86400' NPC_SSH_PORT='22' sh -c "$(curl -kfsSL https://dl.runsh.de/npc/install.sh)"
```

Supported macOS configurations:

- Intel Mac (`x86_64`) -> `darwin_amd64_client.tar.gz`
- Apple Silicon (`arm64`) -> the same Intel package through Rosetta 2

NPS v0.26.10 does not publish a native Darwin arm64 client. On Apple Silicon,
the installer verifies Rosetta 2 before downloading NPC and prints the official
`softwareupdate --install-rosetta --agree-to-license` command when it is missing.
The installer also verifies that the configured local SSH port is accepting
connections before it starts NPC.
If the default `dl.runsh.de` mirror does not contain the Darwin archive, the
installer automatically falls back to the official `ehang-io/nps` GitHub Release.

## Windows

Run PowerShell as Administrator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex"
```

The Windows installer now also installs and configures OpenSSH Server by default. It will:

- skip the OpenSSH package download if the `sshd` service already exists;
- otherwise download `https://dl.runsh.de/ssh/OpenSSH-Win64.zip`;
- install OpenSSH under `C:\OpenSSH-Win64`;
- set `sshd` to start automatically;
- start the `sshd` service;
- create/enable a Windows Firewall inbound rule for TCP port 22;
- then ask for the NPS server and VKey, create the `NPS NPC Client` startup task, and run `C:\npc\npc.exe` as `SYSTEM`.

The task stores the connection settings in `C:\npc\npc-startup.json`; the NPC install directory and its contents are restricted to `SYSTEM` and Administrators. Temporary sessions retain their original absolute expiry across reboots.

Because OpenSSH Server installation changes Windows services and firewall settings, the default Windows installer must be run from an Administrator PowerShell window.

Supported Windows NPC architectures:

- 64-bit x86 -> windows_amd64_client.tar.gz
- 32-bit x86 -> windows_386_client.tar.gz

Architecture detection uses `RuntimeInformation.OSArchitecture` when available
and automatically falls back to legacy Windows environment/runtime checks on
older Windows PowerShell and .NET Framework installations.

The default bundled OpenSSH download is the Win64 package. On 32-bit Windows, either provide a compatible SSH ZIP with `NPC_SSH_ZIP_URL` or skip SSH installation.

### Skip OpenSSH installation

If you only want to install NPC:

```powershell
$env:NPC_INSTALL_SSH='0'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

### Override the OpenSSH ZIP source

```powershell
$env:NPC_SSH_ZIP_URL='https://example.com/OpenSSH-Win64.zip'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

You can also override the OpenSSH install directory with `NPC_SSH_INSTALL_DIR`.

### Windows non-interactive mode

```powershell
$env:NPC_SERVER='23.141.12.66:8024'; $env:NPC_VKEY='YOUR_VKEY'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

Temporary 24-hour session using the detected/default SSH port:

```powershell
$env:NPC_SERVER='23.141.12.66:8024'; $env:NPC_VKEY='YOUR_VKEY'; $env:NPC_TIMEOUT='86400'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

If OpenSSH already listens on a non-default port, provide it explicitly. The installer validates the requested port against the running `sshd` service before starting NPC:

```powershell
$env:NPC_SERVER='23.141.12.66:8024'; $env:NPC_VKEY='YOUR_VKEY'; $env:NPC_TIMEOUT='86400'; $env:NPC_SSH_PORT='2222'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

Logs are written to:

```text
C:\npc\npc.log
C:\npc\npc-error.log
```

Windows-specific optional variables:

```text
NPC_INSTALL_SSH
NPC_SSH_ZIP_URL
NPC_SSH_INSTALL_DIR
NPC_TIMEOUT
NPC_SSH_PORT
NPC_AUTOSTART
```

## Package mirror

The default package source is:

```text
https://dl.runsh.de/npc
```

The installer builds package URLs as:

```text
https://dl.runsh.de/npc/v0.26.10/<package-name>
```

Examples:

```text
https://dl.runsh.de/npc/v0.26.10/linux_amd64_client.tar.gz
https://dl.runsh.de/npc/v0.26.10/linux_arm64_client.tar.gz
https://dl.runsh.de/npc/v0.26.10/linux_arm_v7_client.tar.gz
https://dl.runsh.de/npc/v0.26.10/darwin_amd64_client.tar.gz
https://dl.runsh.de/npc/v0.26.10/windows_amd64_client.tar.gz
https://dl.runsh.de/npc/v0.26.10/windows_386_client.tar.gz
```

You can temporarily override the mirror without editing the scripts.

Linux/macOS example:

```sh
NPC_RELEASE_BASE='https://another.example.com/npc' sh -c "$(curl -kfsSL https://dl.runsh.de/npc/install.sh)"
```

Windows example:

```powershell
$env:NPC_RELEASE_BASE='https://another.example.com/npc'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

Do not commit real VKeys to a public repository.
