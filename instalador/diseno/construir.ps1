# Dibuja las pantallas del instalador en instalador\diseno\png (se guardan en el repositorio)
# y las convierte a BMP para Inno Setup. Necesita Node 22+ y Microsoft Edge.
# Ejecutalo cada vez que cambies diseno\index.html.
$ErrorActionPreference = "Stop"
$aqui = $PSScriptRoot
$png = Join-Path $aqui "png"
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "Falta Microsoft Edge para dibujar el instalador" }

if (Test-Path $png) { Get-ChildItem $png -File | Remove-Item -Force }
node (Join-Path $aqui "piezas.mjs") $edge $png
if ($LASTEXITCODE -ne 0) { throw "No se han podido dibujar las piezas" }
$perfil = Join-Path $aqui "perfil-edge"
if (Test-Path $perfil) { Remove-Item $perfil -Recurse -Force }

& (Join-Path $aqui "convertir.ps1")
