; Instalador de IndividualStreams, por anxo0
; Se compila en GitHub al publicar una version:
;   ISCC.exe /DMyVersion=1.1.2 /DDistDir=<carpeta dist de Vencord> /DCliPath=<VencordInstallerCli.exe> IndividualStreams.iss
; Las pantallas salen de diseno\index.html: tras cambiarlo, ejecuta diseno\construir.ps1.
; Para probarlo sin tocar Discord: /NODISCORD=1. Para que recorra las pantallas solo: /DEMO=1
;
; La ventana es una ventana de transmision de Discord sin bordes. Su fondo y sus textos fijos
; son imagenes; los botones, la casilla, el progreso y el cierre son piezas puestas encima.
; El asistente de Inno sigue funcionando debajo, escondido, para que Intro y Escape respondan.

#ifndef MyVersion
  #define MyVersion "0.0.0"
#endif
#ifndef DistDir
  #define DistDir "..\vencord\dist"
#endif
#ifndef CliPath
  #define CliPath "VencordInstallerCli.exe"
#endif
#include "piezas\posiciones.iss"

[Setup]
AppId={{6F2C1E8A-4B7D-4E31-9A55-2D8C3F1B7E40}
AppName=IndividualStreams
AppVersion={#MyVersion}
AppVerName=IndividualStreams {#MyVersion}
AppPublisher=anxo0
AppPublisherURL=https://github.com/anxo0/IndividualStreams
AppSupportURL=https://github.com/anxo0/IndividualStreams/issues
AppUpdatesURL=https://github.com/anxo0/IndividualStreams/releases
; Va a la carpeta normal de Vencord y no se registra en Windows: es un plugin, no una aplicacion
DefaultDirName={userappdata}\Vencord
UsePreviousAppDir=no
Uninstallable=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
OutputDir=salida
OutputBaseFilename=IndividualStreams-Installer-v{#MyVersion}
SetupIconFile=icono.ico
WizardStyle=modern dark
WizardBackColor=#000000
Compression=lzma2/max
SolidCompression=yes
CloseApplications=no
ShowLanguageDialog=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
SetupWindowTitle=Instalar IndividualStreams
StatusExtractFiles=Copiando archivos
StatusRunProgram=Terminando

[Files]
Source: "piezas\*.bmp"; Flags: dontcopy
Source: "{#CliPath}"; DestName: "VencordInstallerCli.exe"; Flags: dontcopy
Source: "{#DistDir}\patcher.js"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "{#DistDir}\preload.js"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "{#DistDir}\renderer.js"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "{#DistDir}\renderer.css"; DestDir: "{app}\dist"; Flags: ignoreversion
Source: "dist-package.json"; DestDir: "{app}\dist"; DestName: "package.json"; Flags: ignoreversion

[Run]
Filename: "{localappdata}\Discord\Update.exe"; Parameters: "--processStart Discord.exe"; Description: "Abrir Discord ahora"; Flags: postinstall nowait skipifsilent; Check: PuedeAbrirDiscord

[Code]
const
  // Colores de Inno en BGR
  ColorControles = $141211;  // #111214, la barra de controles
  ColorTinta = $FFFFFF;
  ColorSuave = $A39D9A;      // #9a9da3
  AnchoVentana = 760;
  AltoVentana = 440;
  AltoArrastre = 56;
  WM_NCHITTEST = $84;
  HTCLIENT = 1;
  HTCAPTION = 2;
  GWL_WNDPROC = -4;

type
  TPieza = record
    Normal, Encima: TBitmapImage;
    X, Y, W, H: Integer;
  end;

var
  Escala: String;
  Fondo, Avance, CasillaSi, CasillaNo: TBitmapImage;
  Instalar, Cancelar, CancelarInstalando, Terminar, Cerrar: TPieza;
  EstadoTexto, CifraTexto: TNewStaticText;
  ProcAnterior: LongInt;
  TemporizadorRaton, TemporizadorDemo: LongWord;

function SetWindowLong(Wnd: HWND; Index: Integer; NewLong: LongInt): LongInt;
  external 'SetWindowLongW@user32.dll stdcall';
function CallWindowProc(Proc: LongInt; Wnd: HWND; Msg: UINT; WParam, LParam: LongInt): LongInt;
  external 'CallWindowProcW@user32.dll stdcall';
function SetTimer(Wnd: HWND; Id, Elapse: LongWord; Func: LongWord): LongWord;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(Wnd: HWND; Id: LongWord): Boolean;
  external 'KillTimer@user32.dll stdcall';
function GetCursorPos(var Punto: TPoint): Boolean;
  external 'GetCursorPos@user32.dll stdcall';
function ScreenToClient(Wnd: HWND; var Punto: TPoint): Boolean;
  external 'ScreenToClient@user32.dll stdcall';
function GetSystemMetrics(Index: Integer): Integer;
  external 'GetSystemMetrics@user32.dll stdcall';
function DwmSetWindowAttribute(Wnd: HWND; Atributo: Integer; var Valor: Integer; Tamano: Integer): Integer;
  external 'DwmSetWindowAttribute@dwmapi.dll stdcall';

{ Modos de prueba }

function ModoDemo: Boolean;
begin
  Result := ExpandConstant('{param:DEMO|0}') = '1';
end;

function ModoPrueba: Boolean;
begin
  Result := ModoDemo or (ExpandConstant('{param:NODISCORD|0}') = '1');
end;

function PuedeAbrirDiscord: Boolean;
begin
  Result := (not ModoPrueba) and FileExists(ExpandConstant('{localappdata}\Discord\Update.exe'));
end;

function HayCasilla: Boolean;
begin
  Result := WizardForm.RunList.Items.Count > 0;
end;

{ Piezas }

function Imagen(const Nombre: String; X, Y, W, H: Integer): TBitmapImage;
var
  Archivo: String;
begin
  Archivo := Nombre + '-' + Escala + '.bmp';
  ExtractTemporaryFile(Archivo);
  Result := TBitmapImage.Create(WizardForm);
  Result.Parent := WizardForm;
  Result.SetBounds(ScaleX(X), ScaleY(Y), ScaleX(W), ScaleY(H));
  Result.Stretch := True;
  Result.Bitmap.LoadFromFile(ExpandConstant('{tmp}\') + Archivo);
end;

function Pieza(const Nombre: String; X, Y, W, H: Integer; AlPulsar: TNotifyEvent): TPieza;
begin
  Result.X := X; Result.Y := Y; Result.W := W; Result.H := H;
  Result.Normal := Imagen(Nombre, X, Y, W, H);
  Result.Encima := Imagen(Nombre + '-hover', X, Y, W, H);
  Result.Encima.Visible := False;
  Result.Normal.Cursor := crHand;
  Result.Encima.Cursor := crHand;
  Result.Normal.OnClick := AlPulsar;
  Result.Encima.OnClick := AlPulsar;
end;

procedure Mostrar(var P: TPieza; Visible: Boolean);
begin
  P.Normal.Visible := Visible;
  P.Encima.Visible := False;
end;

function Texto(X, Y, W, Tamano: Integer; Negrita: Boolean; Color: TColor): TNewStaticText;
begin
  Result := TNewStaticText.Create(WizardForm);
  Result.Parent := WizardForm;
  Result.AutoSize := False;
  Result.SetBounds(ScaleX(X), ScaleY(Y), ScaleX(W), ScaleY(24));
  Result.Font.Name := 'Segoe UI Variable Text';
  Result.Font.Size := Tamano;
  Result.Font.Color := Color;
  if Negrita then Result.Font.Style := [fsBold];
  Result.Color := ColorControles;
  Result.Caption := ' ';
end;

procedure PonerFondo(const Pantalla: String);
begin
  Fondo.Bitmap.LoadFromFile(ExpandConstant('{tmp}\fondo-') + Pantalla + '-' + Escala + '.bmp');
end;

{ Raton: Inno solo avisa de los clics, asi que un temporizador ligero sigue el cursor }

function Dentro(const P: TPieza; X, Y: Integer): Boolean;
begin
  Result := (X >= ScaleX(P.X)) and (X < ScaleX(P.X + P.W)) and (Y >= ScaleY(P.Y)) and (Y < ScaleY(P.Y + P.H));
end;

procedure Seguir(var P: TPieza; X, Y: Integer);
var
  Encima: Boolean;
begin
  if not (P.Normal.Visible or P.Encima.Visible) then Exit;
  Encima := Dentro(P, X, Y);
  if Encima <> P.Encima.Visible then
  begin
    P.Encima.Visible := Encima;
    P.Normal.Visible := not Encima;
  end;
end;

procedure AlMoverRaton(Wnd: HWND; Msg: UINT; Id: LongWord; Tiempo: DWORD);
var
  Punto: TPoint;
begin
  if TemporizadorRaton = 0 then Exit;
  if not GetCursorPos(Punto) then Exit;
  ScreenToClient(WizardForm.Handle, Punto);
  Seguir(Instalar, Punto.X, Punto.Y);
  Seguir(Cancelar, Punto.X, Punto.Y);
  Seguir(CancelarInstalando, Punto.X, Punto.Y);
  Seguir(Terminar, Punto.X, Punto.Y);
  Seguir(Cerrar, Punto.X, Punto.Y);
  // El paso de Discord avisa por la etiqueta de estado escondida
  if EstadoTexto.Visible and (WizardForm.StatusLabel.Caption <> '') then
    EstadoTexto.Caption := WizardForm.StatusLabel.Caption;
end;

{ Arrastre: la franja de arriba hace de barra de titulo }

function ProcVentana(Wnd: HWND; Msg: UINT; WParam, LParam: LongInt): LongInt;
var
  Punto: TPoint;
begin
  Result := CallWindowProc(ProcAnterior, Wnd, Msg, WParam, LParam);
  if (Msg = WM_NCHITTEST) and (Result = HTCLIENT) then
  begin
    Punto.X := LParam and $FFFF;
    Punto.Y := (LParam shr 16) and $FFFF;
    if Punto.X > $7FFF then Punto.X := Punto.X - $10000;
    if Punto.Y > $7FFF then Punto.Y := Punto.Y - $10000;
    ScreenToClient(Wnd, Punto);
    if (Punto.Y < ScaleY(AltoArrastre)) and not Dentro(Cerrar, Punto.X, Punto.Y) then
      Result := HTCAPTION;
  end;
end;

{ Los enganches se sueltan antes de cerrar la ventana: Windows los seguiria llamando }

procedure SoltarArrastre;
begin
  if ProcAnterior <> 0 then
  begin
    SetWindowLong(WizardForm.Handle, GWL_WNDPROC, ProcAnterior);
    ProcAnterior := 0;
  end;
end;

procedure Soltar;
begin
  if TemporizadorRaton <> 0 then KillTimer(0, TemporizadorRaton);
  if TemporizadorDemo <> 0 then KillTimer(0, TemporizadorDemo);
  TemporizadorRaton := 0;
  TemporizadorDemo := 0;
  SoltarArrastre;
end;

{ Acciones }

procedure Siguiente;
begin
  WizardForm.NextButton.OnClick(WizardForm.NextButton);
end;

procedure PulsarPrincipal(Sender: TObject);
begin
  if WizardForm.CurPageID = wpFinished then Soltar;
  Siguiente;
end;

procedure PulsarCancelar(Sender: TObject);
begin
  if WizardForm.CurPageID = wpFinished then PulsarPrincipal(Sender)
  else WizardForm.CancelButton.OnClick(WizardForm.CancelButton);
end;

procedure PulsarCasilla(Sender: TObject);
var
  Abrir: Boolean;
begin
  Abrir := not CasillaSi.Visible;
  if HayCasilla then WizardForm.RunList.Checked[0] := Abrir;
  CasillaSi.Visible := Abrir;
  CasillaNo.Visible := not Abrir;
end;

procedure AvanzarDemo(Wnd: HWND; Msg: UINT; Id: LongWord; Tiempo: DWORD);
begin
  if WizardForm.CurPageID <> wpInstalling then
    PulsarPrincipal(nil);
end;

{ Asistente }

procedure EsconderAsistente;
begin
  // Fuera de la vista pero vivos: siguen moviendo las paginas y respondiendo a Intro y Escape
  WizardForm.NextButton.Left := -ScaleX(2000);
  WizardForm.CancelButton.Left := -ScaleX(2000);
  WizardForm.BackButton.Left := -ScaleX(2000);
  WizardForm.OuterNotebook.Visible := False;
  WizardForm.Bevel.Visible := False;
end;

procedure InitializeWizard;
var
  Redondo: Integer;
begin
  if WizardSilent then Exit;
  if ScaleX(100) >= 175 then Escala := '200'
  else if ScaleX(100) >= 138 then Escala := '150'
  else if ScaleX(100) >= 113 then Escala := '125'
  else Escala := '100';

  WizardForm.BorderStyle := bsNone;
  WizardForm.ClientWidth := ScaleX(AnchoVentana);
  WizardForm.ClientHeight := ScaleY(AltoVentana);
  WizardForm.Left := (GetSystemMetrics(0) - WizardForm.Width) div 2;
  WizardForm.Top := (GetSystemMetrics(1) - WizardForm.Height) div 2;
  EsconderAsistente;

  ExtractTemporaryFile('fondo-instalando-' + Escala + '.bmp');
  ExtractTemporaryFile('fondo-listo-' + Escala + '.bmp');
  Fondo := Imagen('fondo-bienvenida', 0, 0, AnchoVentana, AltoVentana);

  Instalar := Pieza('instalar', {#InstalarX}, {#InstalarY}, {#InstalarW}, {#InstalarH}, @PulsarPrincipal);
  Cancelar := Pieza('cancelar', {#CancelarX}, {#CancelarY}, {#CancelarW}, {#CancelarH}, @PulsarCancelar);
  CancelarInstalando := Pieza('cancelar', {#CancelarInstalandoX}, {#CancelarInstalandoY}, {#CancelarInstalandoW}, {#CancelarInstalandoH}, @PulsarCancelar);
  Terminar := Pieza('terminar', {#TerminarX}, {#TerminarY}, {#TerminarW}, {#TerminarH}, @PulsarPrincipal);
  Cerrar := Pieza('cerrar', {#CerrarX}, {#CerrarY}, {#CerrarW}, {#CerrarH}, @PulsarCancelar);

  // Progreso: la linea de tiempo entera, de la que se ensena solo lo que lleve
  Avance := Imagen('avance', {#PistaX}, {#PistaY}, {#PistaW}, {#PistaH});
  Avance.Stretch := False;
  CifraTexto := Texto(40, 388, 56, 11, True, ColorTinta);
  EstadoTexto := Texto(96, 389, 420, 10, False, ColorSuave);

  CasillaSi := Imagen('casilla-si', {#CasillaX}, {#CasillaY}, {#CasillaW}, {#CasillaH});
  CasillaNo := Imagen('casilla-no', {#CasillaX}, {#CasillaY}, {#CasillaW}, {#CasillaH});
  CasillaSi.Cursor := crHand; CasillaNo.Cursor := crHand;
  CasillaSi.OnClick := @PulsarCasilla; CasillaNo.OnClick := @PulsarCasilla;

  // Esquinas redondeadas de Windows 11
  Redondo := 2;
  DwmSetWindowAttribute(WizardForm.Handle, 33, Redondo, 4);
  ProcAnterior := SetWindowLong(WizardForm.Handle, GWL_WNDPROC, CreateCallback(@ProcVentana));
  TemporizadorRaton := SetTimer(0, 0, 40, CreateCallback(@AlMoverRaton));
  if ModoDemo then
    TemporizadorDemo := SetTimer(0, 0, 3500, CreateCallback(@AvanzarDemo));
end;

procedure CurPageChanged(CurPageID: Integer);
var
  Bienvenida, Instalando, Listo: Boolean;
begin
  if WizardSilent then Exit;
  Bienvenida := CurPageID = wpWelcome;
  Instalando := CurPageID = wpInstalling;
  Listo := CurPageID = wpFinished;
  if Bienvenida then PonerFondo('bienvenida')
  else if Instalando then PonerFondo('instalando')
  else if Listo then PonerFondo('listo');

  Mostrar(Instalar, Bienvenida);
  Mostrar(Cancelar, Bienvenida);
  Mostrar(CancelarInstalando, Instalando);
  Avance.Visible := Instalando;
  EstadoTexto.Visible := Instalando;
  CifraTexto.Visible := Instalando;
  Mostrar(Terminar, Listo);
  CasillaSi.Visible := Listo and (not HayCasilla or WizardForm.RunList.Checked[0]);
  CasillaNo.Visible := Listo and HayCasilla and not WizardForm.RunList.Checked[0];
  Mostrar(Cerrar, True);
  // La ultima pantalla cierra la ventana: deja de arrastrar antes
  if Listo then SoltarArrastre;

  if Instalando then
  begin
    EstadoTexto.Caption := 'Copiando archivos';
    CifraTexto.Caption := '0 %';
    Avance.Width := 0;
  end;
  EsconderAsistente;
end;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  if (MaxProgress <= 0) or (Avance = nil) then Exit;
  Avance.Width := ScaleX({#PistaW}) * CurProgress div MaxProgress;
  CifraTexto.Caption := IntToStr(CurProgress * 100 div MaxProgress) + ' %';
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if WizardSilent then Exit;
  Confirm := False;
  Cancel := ModoDemo or (MsgBox('IndividualStreams no está instalado todavía. ¿Quieres salir?', mbConfirmation, MB_YESNO) = IDYES);
  if Cancel then Soltar;
end;

procedure DeinitializeSetup;
begin
  if TemporizadorRaton <> 0 then KillTimer(0, TemporizadorRaton);
  if TemporizadorDemo <> 0 then KillTimer(0, TemporizadorDemo);
  TemporizadorRaton := 0;
  TemporizadorDemo := 0;
end;

{ Discord }

procedure CerrarDiscord;
var
  Codigo: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Discord.exe', '', SW_HIDE, ewWaitUntilTerminated, Codigo);
  Sleep(1500);
end;

// Apunta Discord a la carpeta de Vencord, donde ya estan nuestros archivos.
// El instalador oficial de Vencord se usa desde la carpeta temporal y se borra al terminar.
function ParchearDiscord: Integer;
var
  Cli, Params: String;
begin
  ExtractTemporaryFile('VencordInstallerCli.exe');
  Cli := ExpandConstant('{tmp}\VencordInstallerCli.exe');
  Params := '/c set "VENCORD_USER_DATA_DIR=' + ExpandConstant('{app}') + '" && set "VENCORD_DEV_INSTALL=1" && "' + Cli + '" -install -branch stable';
  if not Exec(ExpandConstant('{cmd}'), Params, '', SW_HIDE, ewWaitUntilTerminated, Result) then
    Result := -1;
end;

// La v1.1.1 se instalaba como aplicacion en su propia carpeta: se quita su entrada y sus archivos.
// Su desinstalador con /NODISCORD=1 no toca Discord, que se parchea despues a la carpeta nueva.
procedure QuitarVersionAntigua;
var
  Desinstalador: String;
  Codigo: Integer;
begin
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{6F2C1E8A-4B7D-4E31-9A55-2D8C3F1B7E40}_is1', 'UninstallString', Desinstalador) then
    Exec(RemoveQuotes(Desinstalador), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NODISCORD=1', '', SW_HIDE, ewWaitUntilTerminated, Codigo);
end;

// Por si la entrada ya no estaba: la carpeta antigua solo se borra si es la de nuestro instalador
procedure BorrarCarpetaAntigua;
var
  Antigua: String;
begin
  Antigua := ExpandConstant('{userappdata}\IndividualStreams');
  if FileExists(Antigua + '\VencordInstallerCli.exe') and FileExists(Antigua + '\dist\patcher.js') then
    DelTree(Antigua, True, True, True);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if ModoPrueba then
    Exit;

  if CurStep = ssInstall then
  begin
    CerrarDiscord;
    QuitarVersionAntigua;
  end
  else if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Instalando el plugin en Discord';
    if ParchearDiscord <> 0 then
      SuppressibleMsgBox('No se ha podido instalar en Discord. Comprueba que tienes Discord instalado y vuelve a ejecutar el instalador.', mbError, MB_OK, IDOK)
    else
      BorrarCarpetaAntigua;
  end;
end;
