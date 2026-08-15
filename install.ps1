$ErrorActionPreference = 'Stop'

$Version = if ($env:NPC_VERSION) { $env:NPC_VERSION } else { '0.26.10' }
$ReleaseBase = if ($env:NPC_RELEASE_BASE) { $env:NPC_RELEASE_BASE.TrimEnd('/') } else { 'https://github.com/ehang-io/nps/releases/download' }
$InstallDir = if ($env:NPC_INSTALL_DIR) { $env:NPC_INSTALL_DIR } else { 'C:\npc' }

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
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host "  $installed -server=SERVER_IP:PORT -vkey=YOUR_VKEY -type=tcp"
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
