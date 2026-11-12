# Convierte las pantallas dibujadas (diseno\png) en los BMP que usa Inno Setup (instalador\piezas).
# No necesita Edge: GitHub lo ejecuta antes de compilar el instalador.
$ErrorActionPreference = "Stop"
$aqui = $PSScriptRoot
$png = Join-Path $aqui "png"
$piezas = Join-Path (Split-Path $aqui) "piezas"

Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $piezas | Out-Null
Get-ChildItem $piezas -File | Remove-Item -Force
foreach ($archivo in Get-ChildItem (Join-Path $png "*.png")) {
    $imagen = [System.Drawing.Image]::FromFile($archivo.FullName)
    $bmp = New-Object System.Drawing.Bitmap $imagen.Width, $imagen.Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Black)
    $g.DrawImage($imagen, 0, 0, $imagen.Width, $imagen.Height)
    $g.Dispose()
    $bmp.Save((Join-Path $piezas ($archivo.BaseName + ".bmp")), [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose(); $imagen.Dispose()
}
Copy-Item (Join-Path $png "posiciones.iss") (Join-Path $piezas "posiciones.iss") -Force
"Piezas listas: $((Get-ChildItem $piezas -Filter *.bmp).Count)"
