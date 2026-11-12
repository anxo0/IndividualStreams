@echo off
setlocal
title Instalador de IndividualStreams

if not defined REPO set "REPO=https://github.com/anxo0/IndividualStreams.git"
if not defined PLUGIN_REPO set "PLUGIN_REPO=%USERPROFILE%\IndividualStreams"
if not defined VENCORD_DEST set "VENCORD_DEST=%USERPROFILE%\VencordIndividualStreams"

echo.
echo  === Instalador de IndividualStreams (por anxo0) ===
echo.

set "FALTA="

where git >nul 2>nul
if errorlevel 1 (
    echo  Instalando Git...
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
    set "FALTA=1"
)

where node >nul 2>nul
if errorlevel 1 (
    echo  Instalando Node.js...
    winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
    set "FALTA=1"
)

if defined FALTA (
    echo.
    echo  Se han instalado programas necesarios.
    echo  CIERRA esta ventana y vuelve a hacer doble clic en instalar.bat
    goto :fin
)

where pnpm >nul 2>nul
if errorlevel 1 (
    echo  Instalando pnpm...
    call npm install -g pnpm
    if errorlevel 1 goto :error
)

echo  Descargando la ultima version del plugin...
if exist "%PLUGIN_REPO%\.git" (
    git -C "%PLUGIN_REPO%" fetch --depth 1 origin
    if not errorlevel 1 git -C "%PLUGIN_REPO%" reset --hard FETCH_HEAD
) else (
    git clone --depth 1 "%REPO%" "%PLUGIN_REPO%"
)

set "PLUGIN=%PLUGIN_REPO%\individualStreams"
if not exist "%PLUGIN%\index.tsx" (
    echo  No se ha podido descargar. Uso la copia que viene junto a este archivo.
    set "PLUGIN=%~dp0individualStreams"
)
if not exist "%PLUGIN%\index.tsx" (
    echo  ERROR: no encuentro el plugin.
    goto :error
)

if exist "%VENCORD_DEST%\.git" (
    echo  Actualizando Vencord...
    git -C "%VENCORD_DEST%" fetch --depth 1 origin
    if not errorlevel 1 git -C "%VENCORD_DEST%" reset --hard FETCH_HEAD
) else (
    echo  Descargando Vencord...
    git clone --depth 1 https://github.com/Vendicated/Vencord.git "%VENCORD_DEST%"
)
if errorlevel 1 goto :error

echo  Copiando el plugin...
if exist "%VENCORD_DEST%\src\userplugins\individualStreams" rmdir /S /Q "%VENCORD_DEST%\src\userplugins\individualStreams"
xcopy /E /I /Y "%PLUGIN%" "%VENCORD_DEST%\src\userplugins\individualStreams" >nul
if errorlevel 1 goto :error

cd /d "%VENCORD_DEST%"

echo  Instalando dependencias (puede tardar un par de minutos)...
call pnpm install --frozen-lockfile
if errorlevel 1 goto :error

echo  Compilando...
call pnpm build
if errorlevel 1 goto :error

if defined SOLO_COMPILAR (
    echo  Compilado. No se toca Discord.
    goto :fin
)

echo.
echo  Ahora se va a cerrar Discord para instalar el plugin.
pause

taskkill /F /IM Discord.exe >nul 2>nul

node scripts\runInstaller.mjs -- --install -branch stable
if errorlevel 1 goto :error

node -e "const fs=require('fs');const p=process.env.APPDATA+'/Vencord/settings/settings.json';if(fs.existsSync(p)){const s=JSON.parse(fs.readFileSync(p,'utf8'));s.plugins=s.plugins||{};s.plugins.IndividualStreams=Object.assign({},s.plugins.IndividualStreams,{enabled:true});fs.writeFileSync(p,JSON.stringify(s,null,4));}"

if exist "%LOCALAPPDATA%\Discord\Update.exe" start "" "%LOCALAPPDATA%\Discord\Update.exe" --processStart Discord.exe

echo.
echo  LISTO. Discord se esta abriendo.
echo  Si el plugin no sale activado: Ajustes, Vencord, Plugins, IndividualStreams.
echo  Para actualizar en el futuro, vuelve a ejecutar este archivo.
echo  No borres la carpeta %VENCORD_DEST%
goto :fin

:error
echo.
echo  Algo ha fallado. Haz una captura de esta ventana y enviasela a anxo0.

:fin
echo.
pause
endlocal
