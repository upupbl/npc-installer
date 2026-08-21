# NPS NPC Auto Installer

Automatically detects the platform/architecture, downloads NPS v0.26.10 NPC, installs it, asks for NPS connection information, and starts NPC in the background.

## Linux / NAS

Recommended for NAS/embedded systems:

```sh
sh -c "$(curl -kfsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
```

If Bash is available:

```bash
bash -c "$(curl --insecure -fsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
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

NPC is started in the background using `setsid`, `nohup`, or BusyBox `nohup` when available. Logs are written to `npc.log` in the installation directory.

### Linux non-interactive mode

You can provide connection information without prompts:

```sh
NPC_SERVER='23.141.12.66:8024' NPC_VKEY='YOUR_VKEY' sh -c "$(curl -kfsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
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
```

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
- then ask for the NPS server and VKey and start `C:\npc\npc.exe` in the background.

Because OpenSSH Server installation changes Windows services and firewall settings, the default Windows installer must be run from an Administrator PowerShell window.

Supported Windows NPC architectures:

- 64-bit x86 -> windows_amd64_client.tar.gz
- 32-bit x86 -> windows_386_client.tar.gz

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
https://dl.runsh.de/npc/v0.26.10/windows_amd64_client.tar.gz
https://dl.runsh.de/npc/v0.26.10/windows_386_client.tar.gz
```

You can temporarily override the mirror without editing the scripts.

Linux example:

```sh
NPC_RELEASE_BASE='https://another.example.com/npc' sh -c "$(curl -kfsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
```

Windows example:

```powershell
$env:NPC_RELEASE_BASE='https://another.example.com/npc'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

Do not commit real VKeys to a public repository.
