$ErrorActionPreference = 'Stop'

$Version = if ($env:NPC_VERSION) { $env:NPC_VERSION } else { '0.26.10' }
$ReleaseBase = if ($env:NPC_RELEASE_BASE) { $env:NPC_RELEASE_BASE.TrimEnd('/') } else { 'https://github.com/ehang-io/nps/releases/download' }
$InstallDir = if ($env:NPC_INSTALL_DIR) { $env:NPC_INSTALL_DIR } else { 'C:\npc' }
$DefaultServer = if ($env:NPC_DEFAULT_SERVER) { $env:NPC_DEFAULT_SERVER } else { '23.141.12.66:8024' }

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
