# NPS NPC Auto Installer

Automatically detects the platform/architecture and downloads the matching NPS v0.26.10 NPC client.

## Linux / NAS one-line install

```bash
bash -c "$(curl --insecure -fsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
```

For embedded NAS systems without Bash, use:

```sh
sh -c "$(curl -kfsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
```

Supported Linux architectures include:

- x86_64 / amd64 -> linux_amd64_client.tar.gz
- i386 / i686 -> linux_386_client.tar.gz
- aarch64 / arm64 -> linux_arm64_client.tar.gz
- armv7l -> linux_arm_v7_client.tar.gz
- armv6 / armv5
- mips / mipsle / mips64 / mips64le

The installer extracts in `/tmp` but executes the final binary from `/usr/local/npc` (root) or `$HOME/.local/npc` (non-root), avoiding common NAS `/tmp noexec` problems.

## Windows one-line install

Run PowerShell as Administrator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex"
```

Supported Windows architectures:

- 64-bit x86 -> windows_amd64_client.tar.gz
- 32-bit x86 -> windows_386_client.tar.gz

## Change download mirror later

The default download base is:

```text
https://github.com/ehang-io/nps/releases/download
```

Linux example:

```bash
NPC_RELEASE_BASE="https://your-mirror.example.com/nps/releases/download" sh -c "$(curl -kfsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
```

Windows example:

```powershell
$env:NPC_RELEASE_BASE='https://your-mirror.example.com/nps/releases/download'; irm https://raw.githubusercontent.com/upupbl/npc-installer/main/install.ps1 | iex
```

## Start NPC

Linux:

```bash
/usr/local/npc/npc -server=SERVER_IP:8024 -vkey=YOUR_VKEY -type=tcp
```

Windows:

```powershell
C:\npc\npc.exe -server=SERVER_IP:8024 -vkey=YOUR_VKEY -type=tcp
```

Do not commit real VKeys to a public repository.
