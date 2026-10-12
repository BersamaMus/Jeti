; Jeti's Windows installer (Inno Setup). Build it with build_installer.ps1,
; which builds the app first and passes in the version from pubspec.yaml.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Identifies Jeti to Windows across versions, so updates replace it. Never
; change it (lib\services\apps_controller.dart has it too, as jetiAppId).
AppId={{36B8D607-D548-4D10-88B8-9527F9C574D1}
AppName=Jeti
AppVersion={#AppVersion}
AppVerName=Jeti {#AppVersion}
AppPublisher=BersamaMus
AppPublisherURL=https://bersamamus.com
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\Jeti
DefaultGroupName=Jeti
DisableProgramGroupPage=yes
; Installs for just this user without asking for admin, unless they choose
; everyone. Jeti then installs the apps the same way.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\build\installer
OutputBaseFilename=Jeti-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\jeti.exe
UninstallDisplayName=Jeti
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
; Closes a running Jeti before updating it.
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Everything the release build needs beside jeti.exe: Flutter, the plugins'
; DLLs and the app's data folder.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Jeti"; Filename: "{app}\jeti.exe"
Name: "{autodesktop}\Jeti"; Filename: "{app}\jeti.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\jeti.exe"; Description: "{cm:LaunchProgram,Jeti}"; Flags: nowait postinstall skipifsilent
; When Jeti updates itself it runs this silently with /RELAUNCH=1, and closes;
; this opens the new one.
Filename: "{app}\jeti.exe"; Flags: nowait; Check: IsRelaunch

[Code]
function IsRelaunch: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;
