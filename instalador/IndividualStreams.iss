; Instalador de IndividualStreams, por anxo0
; Se compila en GitHub al publicar una version:
;   ISCC.exe /DMyVersion=1.1.0 /DDistDir=<carpeta dist de Vencord> /DCliPath=<VencordInstallerCli.exe> IndividualStreams.iss

#ifndef MyVersion
  #define MyVersion "0.0.0"
#endif
#ifndef DistDir
  #define DistDir "..\vencord\dist"
#endif
#ifndef CliPath
  #define CliPath "VencordInstallerCli.exe"
#endif

[Setup]
AppId={{6F2C1E8A-4B7D-4E31-9A55-2D8C3F1B7E40}
AppName=IndividualStreams
AppVersion={#MyVersion}
AppVerName=IndividualStreams {#MyVersion}
AppPublisher=anxo0
AppPublisherURL=https://github.com/anxo0/IndividualStreams
AppSupportURL=https://github.com/anxo0/IndividualStreams/issues
AppUpdatesURL=https://github.com/anxo0/IndividualStreams/releases
DefaultDirName={userappdata}\IndividualStreams
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputDir=salida
OutputBaseFilename=IndividualStreams-Installer-v{#MyVersion}
SetupIconFile=icono.ico
UninstallDisplayIcon={app}\icono.ico
UninstallDisplayName=IndividualStreams
WizardStyle=modern dynamic
WizardImageFile=lateral_1.bmp,lateral_2.bmp
WizardSmallImageFile=pequena_1.bmp,pequena_2.bmp
WizardImageBackColor=#000000
Compression=lzma2/max
SolidCompression=yes
CloseApplications=no
ShowLanguageDialog=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
WelcomeLabel1=IndividualStreams
WelcomeLabel2=Abre cada transmisión de Discord en su propia ventana, para poner una en cada pantalla.%n%nDiscord se cerrará durante la instalación y se volverá a abrir al terminar. Tus ajustes y plugins de Vencord se conservan.
FinishedHeadingLabel=Listo
FinishedLabelNoIcons=IndividualStreams ya está en tu Discord.%n%nPara usarlo, en una llamada pulsa el botón con el 1 junto a "Abrir en ventana", o haz clic derecho en una transmisión y elige "Abrir individual".%n%nSe actualiza solo desde Discord.
FinishedLabel=IndividualStreams ya está en tu Discord.%n%nPara usarlo, en una llamada pulsa el botón con el 1 junto a "Abrir en ventana", o haz clic derecho en una transmisión y elige "Abrir individual".%n%nSe actualiza solo desde Discord.
ConfirmUninstall=¿Quieres quitar IndividualStreams?%n%nDiscord se cerrará y se quedará con Vencord normal, sin este plugin.

[Files]
Source: "{#DistDir}\patcher.js"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "{#DistDir}\preload.js"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "{#DistDir}\renderer.js"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "{#DistDir}\renderer.css"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "dist-package.json"; DestDir: "{app}\dist"; DestName: "package.json"; Flags: ignoreversion
Source: "{#CliPath}"; DestDir: "{app}"; DestName: "VencordInstallerCli.exe"; Flags: ignoreversion
Source: "icono.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[UninstallDelete]
; Archivos que el actualizador de Vencord pueda haber reescrito
Type: filesandordirs; Name: "{app}\dist"

[Run]
Filename: "{localappdata}\Discord\Update.exe"; Parameters: "--processStart Discord.exe"; Description: "Abrir Discord"; Flags: postinstall nowait skipifsilent; Check: PuedeAbrirDiscord

[Code]
// /NODISCORD=1 instala los archivos sin cerrar ni parchear Discord (para pruebas)
function ModoPrueba: Boolean;
begin
  Result := ExpandConstant('{param:NODISCORD|0}') = '1';
end;

function PuedeAbrirDiscord: Boolean;
begin
  Result := (not ModoPrueba) and FileExists(ExpandConstant('{localappdata}\Discord\Update.exe'));
end;

procedure CerrarDiscord;
var
  Codigo: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Discord.exe', '', SW_HIDE, ewWaitUntilTerminated, Codigo);
  Sleep(1500);
end;

// Con ConPlugin = True apunta Discord a nuestros archivos; si no, instala el Vencord oficial
function EjecutarVencord(ConPlugin: Boolean; Argumentos: String): Integer;
var
  Cli, Params: String;
begin
  Cli := ExpandConstant('{app}\VencordInstallerCli.exe');
  Params := '/c ';
  if ConPlugin then
    Params := Params + 'set "VENCORD_USER_DATA_DIR=' + ExpandConstant('{app}') + '" && set "VENCORD_DEV_INSTALL=1" && ';
  Params := Params + '"' + Cli + '" ' + Argumentos;
  if not Exec(ExpandConstant('{cmd}'), Params, '', SW_HIDE, ewWaitUntilTerminated, Result) then
    Result := -1;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if ModoPrueba then
    Exit;

  if CurStep = ssInstall then
    CerrarDiscord
  else if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Instalando el plugin en Discord...';
    if EjecutarVencord(True, '-install -branch stable') <> 0 then
      SuppressibleMsgBox('No se ha podido instalar en Discord. Comprueba que tienes Discord instalado y vuelve a ejecutar el instalador.', mbError, MB_OK, IDOK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep <> usUninstall) or ModoPrueba then
    Exit;

  CerrarDiscord;
  // Deja Vencord normal; si no se puede descargar, quita el mod para que Discord no se rompa
  if EjecutarVencord(False, '-install -branch stable') <> 0 then
    EjecutarVencord(False, '-uninstall -branch stable');
end;
