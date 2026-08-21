$ErrorActionPreference = 'Stop'

$Version = if ($env:NPC_VERSION) { $env:NPC_VERSION } else { '0.26.10' }
$ReleaseBase = if ($env:NPC_RELEASE_BASE) { $env:NPC_RELEASE_BASE.TrimEnd('/') } else { 'https://dl.runsh.de/npc' }
$InstallDir = if ($env:NPC_INSTALL_DIR) { $env:NPC_INSTALL_DIR } else { 'C:\npc' }
$DefaultServer = if ($env:NPC_DEFAULT_SERVER) { $env:NPC_DEFAULT_SERVER } else { '23.141.12.66:8024' }

# OpenSSH Server is installed by default on Windows.
# Set NPC_INSTALL_SSH=0 to skip it.
$InstallSsh = -not ($env:NPC_INSTALL_SSH -match '^(0|false|no|off)$')
$SshZipUrl = if ($env:NPC_SSH_ZIP_URL) { $env:NPC_SSH_ZIP_URL } else { 'https://dl.runsh.de/ssh/OpenSSH-Win64.zip' }
$SshInstallDir = if ($env:NPC_SSH_INSTALL_DIR) { $env:NPC_SSH_INSTALL_DIR } else { 'C:\OpenSSH-Win64' }

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-SshFirewallRule {
    $ruleName = 'OpenSSH-Server-In-TCP'
    $getFirewallRule = Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue
    $newFirewallRule = Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue

    if ($getFirewallRule -and $newFirewallRule) {
        $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if (-not $rule) {
            New-NetFirewallRule `
                -Name $ruleName `
                -DisplayName 'OpenSSH SSH Server (sshd)' `
                -Enabled True `
                -Direction Inbound `
                -Protocol TCP `
                -Action Allow `
                -LocalPort 22 | Out-Null
            Write-Host '[SSH] Firewall rule created for TCP/22.'
        }
        elseif ($rule.Enabled -ne 'True') {
            Enable-NetFirewallRule -Name $ruleName | Out-Null
            Write-Host '[SSH] Firewall rule enabled for TCP/22.'
        }
        else {
            Write-Host '[SSH] Firewall rule for TCP/22 already exists.'
        }
        return
    }

    Write-Host '[SSH] NetSecurity cmdlets unavailable; using netsh for TCP/22.'
    & netsh advfirewall firewall add rule name='OpenSSH SSH Server (sshd)' dir=in action=allow protocol=TCP localport=22 | Out-Null
}

function Install-OpenSshServer {
    if (-not $InstallSsh) {
        Write-Host '[SSH] Skipped because NPC_INSTALL_SSH disables SSH installation.'
        return
    }

    if (-not (Test-IsAdministrator)) {
        throw 'Administrator privileges are required to install and start OpenSSH Server. Re-run PowerShell as Administrator, or set NPC_INSTALL_SSH=0 to skip SSH.'
    }

    $service = Get-Service sshd -ErrorAction SilentlyContinue

    if (-not $service) {
        if (-not [Environment]::Is64BitOperatingSystem -and -not $env:NPC_SSH_ZIP_URL) {
            throw 'The default OpenSSH package is Win64, but this Windows installation is 32-bit. Set NPC_SSH_ZIP_URL to a compatible package or NPC_INSTALL_SSH=0.'
        }

        $sshTmp = Join-Path $env:TEMP ('openssh-install-' + [guid]::NewGuid().ToString('N'))
        $sshArchive = Join-Path $sshTmp 'OpenSSH.zip'
        $sshExtract = Join-Path $sshTmp 'extract'

        New-Item -ItemType Directory -Path $sshExtract -Force | Out-Null

        try {
            Write-Host '[SSH] sshd service not found. Installing OpenSSH Server...'
            Write-Host "[SSH] Download: $SshZipUrl"

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $SshZipUrl -OutFile $sshArchive

            Write-Host '[SSH] Extracting package...'
            Expand-Archive -Path $sshArchive -DestinationPath $sshExtract -Force

            $installer = Get-ChildItem -Path $sshExtract -Filter 'install-sshd.ps1' -File -Recurse | Select-Object -First 1
            if (-not $installer) {
                throw 'install-sshd.ps1 was not found after extracting the OpenSSH package.'
            }

            $sourceDir = $installer.Directory.FullName
            New-Item -ItemType Directory -Path $SshInstallDir -Force | Out-Null
            Get-ChildItem -LiteralPath $sourceDir -Force | Copy-Item -Destination $SshInstallDir -Recurse -Force

            $targetInstaller = Join-Path $SshInstallDir 'install-sshd.ps1'
            if (-not (Test-Path $targetInstaller)) {
                throw "OpenSSH installer was not copied to $targetInstaller"
            }

            Write-Host "[SSH] Install directory: $SshInstallDir"
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetInstaller
            if ($LASTEXITCODE -ne 0) {
                throw "install-sshd.ps1 exited with code $LASTEXITCODE"
            }
        }
        finally {
            Remove-Item $sshTmp -Recurse -Force -ErrorAction SilentlyContinue
        }

        $service = Get-Service sshd -ErrorAction SilentlyContinue
        if (-not $service) {
            throw 'OpenSSH installer completed, but the sshd service was not found.'
        }
    }
    else {
        Write-Host '[SSH] sshd service already exists. Package installation skipped.'
    }

    Set-Service sshd -StartupType Automatic

    $service = Get-Service sshd
    if ($service.Status -ne 'Running') {
        Start-Service sshd
    }

    Ensure-SshFirewallRule

    $service = Get-Service sshd
    Write-Host '[SSH] OpenSSH Server is ready.'
    Write-Host "[SSH] Service status: $($service.Status)"
    Write-Host '[SSH] Startup type: Automatic'
    Write-Host '[SSH] Listening port: TCP/22'
}

if ($InstallSsh -and -not (Test-IsAdministrator)) {
    throw 'This installer now installs OpenSSH Server by default and must be run from an Administrator PowerShell window. Set NPC_INSTALL_SSH=0 if SSH is not needed.'
}

$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($arch) {
    'X64' { $pkg = 'windows_amd64_client.tar.gz' }
    'X86' { $pkg = 'windows_386_client.tar.gz' }
    default { throw "Unsupported Windows architecture: $arch. NPS v0.26.10 release used by this installer supports Windows x86/x64 here." }
}

$url = "$ReleaseBase/v$Version/$pkg"
$tmp = Join-Path $env:TEMP ("npc-install-" + [guid]::NewGuid().ToString('N'))
$archive = Join-Path $tmp $pkg

New-Item -ItemType Directory -Path $tmp -Force | Out-Null
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

try {
    Write-Host "[NPC] Windows architecture: $arch"
    Write-Host "[NPC] Package: $pkg"
    Write-Host "[NPC] Version: $Version"
    Write-Host "[NPC] Download: $url"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tar) { throw 'tar.exe is required. Use Windows 10/11 or install tar/7-Zip and extract manually.' }

    & tar.exe -xzf $archive -C $tmp
    $npc = Join-Path $tmp 'npc.exe'
    if (-not (Test-Path $npc)) { throw 'npc.exe was not found after extraction.' }

    Copy-Item $npc (Join-Path $InstallDir 'npc.exe') -Force
    $installed = Join-Path $InstallDir 'npc.exe'

    Write-Host "[NPC] Installed successfully: $installed"
    & $installed -version
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Install-OpenSshServer

$Server = $env:NPC_SERVER
if ([string]::IsNullOrWhiteSpace($Server)) {
    $inputServer = Read-Host "NPS server [$DefaultServer]"
    $Server = if ([string]::IsNullOrWhiteSpace($inputServer)) { $DefaultServer } else { $inputServer.Trim() }
}

$VKey = $env:NPC_VKEY
if ([string]::IsNullOrWhiteSpace($VKey)) {
    $secure = Read-Host 'VKey' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $VKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

$Type = if ($env:NPC_TYPE) { $env:NPC_TYPE } else { 'tcp' }

if ([string]::IsNullOrWhiteSpace($VKey)) {
    Write-Host ''
    Write-Host '[NPC] Installation finished. VKey was not supplied, so NPC was not started.'
    Write-Host 'Run manually:'
    Write-Host "  $installed -server=$Server -vkey=YOUR_VKEY -type=$Type"
    exit 0
}

$existing = Get-Process -Name npc -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host '[NPC] An npc.exe process is already running. Installation completed; no second process was started.'
    $existing | ForEach-Object { Write-Host "[NPC] PID: $($_.Id)" }
    exit 0
}

$logOut = Join-Path $InstallDir 'npc.log'
$logErr = Join-Path $InstallDir 'npc-error.log'
Remove-Item $logOut, $logErr -Force -ErrorAction SilentlyContinue

$args = @("-server=$Server", "-vkey=$VKey", "-type=$Type")
$proc = Start-Process -FilePath $installed -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $logOut -RedirectStandardError $logErr
Start-Sleep -Seconds 2

if (-not $proc.HasExited) {
    Write-Host '[NPC] Started successfully in background.'
    Write-Host "[NPC] PID: $($proc.Id)"
    Write-Host "[NPC] Server: $Server"
    Write-Host "[NPC] Log: $logOut"
    if (Test-Path $logOut) { Get-Content $logOut -Tail 10 -ErrorAction SilentlyContinue }
    if (Test-Path $logErr) { Get-Content $logErr -Tail 10 -ErrorAction SilentlyContinue }
}
else {
    Write-Host '[NPC] Process exited shortly after start.'
    if (Test-Path $logOut) { Get-Content $logOut -ErrorAction SilentlyContinue }
    if (Test-Path $logErr) { Get-Content $logErr -ErrorAction SilentlyContinue }
    throw "npc.exe exited with code $($proc.ExitCode)"
}
