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

After installation it asks for the NPS server and VKey, then starts `C:\npc\npc.exe` in the background.

Supported Windows architectures:

- 64-bit x86 -> windows_amd64_client.tar.gz
- 32-bit x86 -> windows_386_client.tar.gz

### Windows non-interactive mode

```powershell
$env:NPC_SERVER='23.141.12.66:8024'; $env:NPC_VKEY='YOUR_VKEY'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

Logs are written to:

```text
C:\npc\npc.log
C:\npc\npc-error.log
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
