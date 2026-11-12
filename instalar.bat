@echo off
title Instalador de IndividualStreams
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = [IO.File]::ReadAllText('%~f0'); Invoke-Expression $s.Substring($s.LastIndexOf('#INICIO' + '_POWERSHELL#'))"
echo.
pause
exit /b

#INICIO_POWERSHELL#
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = if ($env:IS_REPO) { $env:IS_REPO } else { "anxo0/IndividualStreams" }
$dest = if ($env:IS_DEST) { $env:IS_DEST } else { Join-Path $env:APPDATA "IndividualStreams" }
$dist = Join-Path $dest "dist"
$headers = @{ "User-Agent" = "IndividualStreams-Instalador" }

Write-Host ""
Write-Host " === Instalador de IndividualStreams (por anxo0) ==="
Write-Host ""

try {
    Write-Host " Descargando la ultima version..."
    New-Item -ItemType Directory -Force $dist | Out-Null
    $release = Invoke-RestMethod -Headers $headers "https://api.github.com/repos/$repo/releases/latest"

    foreach ($name in "patcher.js", "preload.js", "renderer.js", "renderer.css") {
        $asset = $release.assets | Where-Object { $_.name -eq $name }
        if (-not $asset) { throw "La version publicada no tiene el archivo $name" }
        Invoke-WebRequest -UseBasicParsing -Headers $headers $asset.browser_download_url -OutFile (Join-Path $dist $name)
    }
    [IO.File]::WriteAllText((Join-Path $dist "package.json"), "{}")
    Write-Host " Version descargada: $($release.name)"

    if ($env:IS_SOLO_DESCARGAR) {
        Write-Host " Descargado. No se toca Discord."
        return
    }

    Write-Host " Descargando el instalador oficial de Vencord..."
    $cli = Join-Path $dest "VencordInstallerCli.exe"
    Invoke-WebRequest -UseBasicParsing -Headers $headers "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe" -OutFile $cli

    Write-Host ""
    Write-Host " Ahora se va a cerrar Discord para instalar el plugin."
    Read-Host " Pulsa Enter para continuar" | Out-Null

    Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2

    $env:VENCORD_USER_DATA_DIR = $dest
    $env:VENCORD_DEV_INSTALL = "1"
    & $cli --install -branch stable
    if ($LASTEXITCODE -ne 0) { throw "El instalador de Vencord ha fallado" }

    $updater = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
    if (Test-Path $updater) { Start-Process $updater -ArgumentList "--processStart", "Discord.exe" }

    Write-Host ""
    Write-Host " LISTO. Discord se esta abriendo con IndividualStreams activado."
    Write-Host " A partir de ahora se actualiza solo desde Discord."
    Write-Host " No borres la carpeta $dest"
}
catch {
    Write-Host ""
    Write-Host " Algo ha fallado: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host " Haz una captura de esta ventana y enviasela a anxo0."
}
