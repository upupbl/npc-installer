$ErrorActionPreference = 'Stop'

$Version = if ($env:NPC_VERSION) { $env:NPC_VERSION } else { '0.26.10' }
$ReleaseBase = if ($env:NPC_RELEASE_BASE) { $env:NPC_RELEASE_BASE.TrimEnd('/') } else { 'https://dl.runsh.de/npc' }
$InstallDir = if ($env:NPC_INSTALL_DIR) { $env:NPC_INSTALL_DIR } else { 'C:\npc' }
$DefaultServer = if ($env:NPC_DEFAULT_SERVER) { $env:NPC_DEFAULT_SERVER } else { '23.141.12.66:8024' }
$Autostart = -not ($env:NPC_AUTOSTART -match '^(0|false|no|off)$')

$TimeoutSeconds = 0
if ($env:NPC_TIMEOUT) {
    if (-not [int]::TryParse($env:NPC_TIMEOUT, [ref]$TimeoutSeconds) -or $TimeoutSeconds -lt 0) {
        throw 'NPC_TIMEOUT must be a whole number of seconds (0 means no timeout).'
    }
}

$RequestedSshPort = 0
if ($env:NPC_SSH_PORT) {
    if (-not [int]::TryParse($env:NPC_SSH_PORT, [ref]$RequestedSshPort) -or $RequestedSshPort -lt 1 -or $RequestedSshPort -gt 65535) {
        throw 'NPC_SSH_PORT must be a port number from 1 to 65535.'
    }
}

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

function Get-UnixTimeSeconds {
    return [long]([DateTimeOffset]::UtcNow - [DateTimeOffset]'1970-01-01T00:00:00Z').TotalSeconds
}

function Get-NpcWindowsArchitecture {
    param([switch]$UseLegacyDetection)

    $architectureName = $null

    if (-not $UseLegacyDetection) {
        try {
            $runtimeArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
            if ($null -ne $runtimeArchitecture) {
                $architectureName = $runtimeArchitecture.ToString()
            }
        }
        catch {
            $architectureName = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($architectureName)) {
        $architectureName = if ($env:PROCESSOR_ARCHITEW6432) {
            $env:PROCESSOR_ARCHITEW6432
        }
        elseif ($env:PROCESSOR_ARCHITECTURE) {
            $env:PROCESSOR_ARCHITECTURE
        }
        elseif ([Environment]::Is64BitOperatingSystem) {
            'AMD64'
        }
        else {
            'x86'
        }
    }

    switch ($architectureName.Trim().ToUpperInvariant()) {
        'X64' { return 'X64' }
        'AMD64' { return 'X64' }
        'X86' { return 'X86' }
        default { return $architectureName }
    }
}

function Ensure-SshFirewallRule {
    param([Parameter(Mandatory = $true)][int]$Port)

    $ruleName = if ($Port -eq 22) { 'OpenSSH-Server-In-TCP' } else { "NPC-OpenSSH-In-TCP-$Port" }
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
                -LocalPort $Port | Out-Null
            Write-Host "[SSH] Firewall rule created for TCP/$Port."
        }
        elseif ($rule.Enabled -ne 'True') {
            Enable-NetFirewallRule -Name $ruleName | Out-Null
            Write-Host "[SSH] Firewall rule enabled for TCP/$Port."
        }
        else {
            Write-Host "[SSH] Firewall rule for TCP/$Port already exists."
        }
        return
    }

    Write-Host "[SSH] NetSecurity cmdlets unavailable; using netsh for TCP/$Port."
    & netsh advfirewall firewall add rule name="NPC OpenSSH Server TCP $Port" dir=in action=allow protocol=TCP localport=$Port | Out-Null
}

function Get-SshListeningPorts {
    $ports = @()

    try {
        $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction Stop
        if ($serviceInfo.ProcessId -gt 0 -and (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
            $ports = @(Get-NetTCPConnection -State Listen -OwningProcess $serviceInfo.ProcessId -ErrorAction Stop |
                Select-Object -ExpandProperty LocalPort -Unique)
        }
    }
    catch {
        $ports = @()
    }

    if ($ports.Count -eq 0) {
        $configPath = Join-Path $env:ProgramData 'ssh\sshd_config'
        if (Test-Path $configPath) {
            $ports = @(Get-Content $configPath -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_ -match '^\s*Port\s+(\d+)\s*(?:#.*)?$') {
                    [int]$Matches[1]
                }
            } | Select-Object -Unique)
        }
    }

    if ($ports.Count -eq 0) {
        $ports = @(22)
    }

    return $ports
}

function Resolve-SshPort {
    $detectedPorts = @(Get-SshListeningPorts)

    if ($RequestedSshPort -gt 0) {
        if ($InstallSsh -and $detectedPorts -notcontains $RequestedSshPort) {
            $detectedText = $detectedPorts -join ', '
            throw "NPC_SSH_PORT is $RequestedSshPort, but sshd is listening on: $detectedText. Use the actual SSH port."
        }
        return $RequestedSshPort
    }

    return [int]$detectedPorts[0]
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

    $service = Get-Service sshd
    Write-Host '[SSH] OpenSSH Server is ready.'
    Write-Host "[SSH] Service status: $($service.Status)"
    Write-Host '[SSH] Startup type: Automatic'
}

function Install-NpcStartupTask {
    param(
        [Parameter(Mandatory = $true)][string]$NpcPath,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$VKey,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][string]$InstallDir
    )

    if (-not (Test-IsAdministrator)) {
        throw 'Administrator privileges are required to enable NPC startup.'
    }

    $expiresAt = if ($TimeoutSeconds -gt 0) {
        (Get-UnixTimeSeconds) + $TimeoutSeconds
    }
    else { 0 }
    $configPath = Join-Path $InstallDir 'npc-startup.json'
    $runnerPath = Join-Path $InstallDir 'npc-startup.ps1'
    $logOut = Join-Path $InstallDir 'npc.log'
    $logErr = Join-Path $InstallDir 'npc-error.log'

    & icacls.exe $InstallDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not restrict access to $InstallDir" }

    [ordered]@{
        NpcPath = $NpcPath
        Server = $Server
        VKey = $VKey
        Type = $Type
        ExpiresAtUnix = $expiresAt
        LogOut = $logOut
        LogErr = $logErr
    } | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8

    $runnerContent = @'
$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'npc-startup.json'
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$now = [long]([DateTimeOffset]::UtcNow - [DateTimeOffset]'1970-01-01T00:00:00Z').TotalSeconds
$expiresAt = [long]$config.ExpiresAtUnix
if ($expiresAt -gt 0 -and $now -ge $expiresAt) { exit 0 }

$arguments = @("-server=$($config.Server)", "-vkey=$($config.VKey)", "-type=$($config.Type)")
$process = Start-Process -FilePath $config.NpcPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $config.LogOut -RedirectStandardError $config.LogErr
$timedOut = $false
if ($expiresAt -gt 0) {
    $remainingMilliseconds = [int][Math]::Max(1, [Math]::Min([int]::MaxValue, ($expiresAt - $now) * 1000))
    if (-not $process.WaitForExit($remainingMilliseconds)) {
        $timedOut = $true
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
    }
}
else {
    $process.WaitForExit()
}
if ($timedOut) { exit 0 }
if ($process.ExitCode -eq 0 -and ($expiresAt -eq 0 -or [long]([DateTimeOffset]::UtcNow - [DateTimeOffset]'1970-01-01T00:00:00Z').TotalSeconds -lt $expiresAt)) { exit 1 }
exit $process.ExitCode
'@
    Set-Content -Path $runnerPath -Value $runnerContent -Encoding UTF8

    $taskName = 'NPS NPC Client'
    $powerShellArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$runnerPath`""
    if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $powerShellArguments
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
        Start-ScheduledTask -TaskName $taskName
    }
    else {
        $taskCommand = "powershell.exe $powerShellArguments"
        & schtasks.exe /Create /TN $taskName /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $taskCommand /F | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the NPC startup task.' }
        & schtasks.exe /Run /TN $taskName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not start the NPC startup task.' }
    }

    return $expiresAt
}

if (($InstallSsh -or $Autostart) -and -not (Test-IsAdministrator)) {
    throw 'Administrator PowerShell is required for OpenSSH installation or NPC startup. Set NPC_INSTALL_SSH=0 and NPC_AUTOSTART=0 only if both features are not needed.'
}

$arch = Get-NpcWindowsArchitecture
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

    if ($Autostart) {
        if (Get-Command Stop-ScheduledTask -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName 'NPS NPC Client' -ErrorAction SilentlyContinue
        }
        else {
            & schtasks.exe /End /TN 'NPS NPC Client' 2>$null | Out-Null
        }
        $oldNpcProcesses = @(Get-Process -Name npc -ErrorAction SilentlyContinue)
        $oldNpcProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        $oldNpcProcesses | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    }

    Copy-Item $npc (Join-Path $InstallDir 'npc.exe') -Force
    $installed = Join-Path $InstallDir 'npc.exe'

    Write-Host "[NPC] Installed successfully: $installed"
    & $installed -version
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Install-OpenSshServer

$SshPort = Resolve-SshPort
if ($InstallSsh) {
    Ensure-SshFirewallRule -Port $SshPort
}
Write-Host "[SSH] Listening port used for the NPS target: TCP/$SshPort"

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

if ($Autostart) {
    $expiresAt = Install-NpcStartupTask -NpcPath $installed -Server $Server -VKey $VKey -Type $Type -TimeoutSeconds $TimeoutSeconds -InstallDir $InstallDir
    Start-Sleep -Seconds 2
    $started = Get-Process -Name npc -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $started -and ($expiresAt -eq 0 -or (Get-UnixTimeSeconds) -lt $expiresAt)) {
        throw 'The NPC startup task was created, but npc.exe did not remain running. Check npc-error.log and Task Scheduler.'
    }
    Write-Host '[NPC] Started by Task Scheduler and enabled at boot.'
    if ($started) { Write-Host "[NPC] PID: $($started.Id)" }
    Write-Host '[NPC] Startup task: NPS NPC Client'
    Write-Host "[NPC] Server: $Server"
    Write-Host "[NPC] Local SSH target: 127.0.0.1:$SshPort"
    Write-Host "[NPC] Log: $(Join-Path $InstallDir 'npc.log')"
    if ($TimeoutSeconds -gt 0) {
        Write-Host "[NPC] Absolute expiry: $expiresAt (Unix time); reboot does not reset it."
    }
    else {
        Write-Host '[NPC] Automatic stop: disabled'
    }
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
    Write-Host "[NPC] Local SSH target: 127.0.0.1:$SshPort"
    Write-Host "[NPC] Log: $logOut"

    if ($TimeoutSeconds -gt 0) {
        $watchdogPath = Join-Path $InstallDir 'npc-timeout-watchdog.ps1'
        $watchdogLog = Join-Path $InstallDir 'npc-watchdog.log'
        $watchdogContent = @'
param(
    [Parameter(Mandatory = $true)][int]$TargetProcessId,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)][string]$ExpectedPath,
    [Parameter(Mandatory = $true)][string]$LogPath
)

Start-Sleep -Seconds $TimeoutSeconds

try {
    $target = Get-Process -Id $TargetProcessId -ErrorAction Stop
}
catch {
    exit 0
}

try {
    $actualPath = $target.Path
}
catch {
    $actualPath = $null
}

if ($actualPath -and -not $actualPath.Equals($ExpectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    exit 0
}

Add-Content -Path $LogPath -Value "$(Get-Date -Format o) [NPC] Session timeout reached; stopping PID $TargetProcessId."
Stop-Process -Id $TargetProcessId -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Stop-Process -Id $TargetProcessId -Force -ErrorAction SilentlyContinue
'@
        Set-Content -Path $watchdogPath -Value $watchdogContent -Encoding UTF8

        $watchdogArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$watchdogPath`" -TargetProcessId $($proc.Id) -TimeoutSeconds $TimeoutSeconds -ExpectedPath `"$installed`" -LogPath `"$watchdogLog`""
        Start-Process -FilePath 'powershell.exe' -ArgumentList $watchdogArgs -WindowStyle Hidden | Out-Null

        Write-Host "[NPC] Automatic stop: $TimeoutSeconds seconds"
        Write-Host "[NPC] Watchdog log: $watchdogLog"
    }
    else {
        Write-Host '[NPC] Automatic stop: disabled'
    }

    if (Test-Path $logOut) { Get-Content $logOut -Tail 10 -ErrorAction SilentlyContinue }
    if (Test-Path $logErr) { Get-Content $logErr -Tail 10 -ErrorAction SilentlyContinue }
}
else {
    Write-Host '[NPC] Process exited shortly after start.'
    if (Test-Path $logOut) { Get-Content $logOut -ErrorAction SilentlyContinue }
    if (Test-Path $logErr) { Get-Content $logErr -ErrorAction SilentlyContinue }
    throw "npc.exe exited with code $($proc.ExitCode)"
}
