; Installateur Windows d'AniPlay AI (Inno Setup 6)
;
;   iscc /DAppVersion=1.0.0 /DSourceDir=..\frontend\build\windows\x64\runner\Release ^
;        /DEdition=standard installer\aniplay.iss
;
; SourceDir doit contenir aniplay.exe (Flutter) et le dossier backend\ (PyInstaller + FFmpeg).
; Le script scripts\build_windows.ps1 prépare tout cela automatiquement.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\frontend\build\windows\x64\runner\Release"
#endif
#ifndef Edition
  #define Edition "standard"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define AppName "AniPlay AI"
#define AppExe "aniplay.exe"
#define ProgId "AniPlayAI.Video"

[Setup]
; Ne jamais changer AppId : il identifie l'application pour les mises à jour et la désinstallation
AppId={{6E1C2A57-8F3B-4D2E-9A41-AB12C0FFEE01}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=AniPlay AI
AppPublisherURL=https://github.com/ck526438-lgtm/aniplay-ai
AppSupportURL=https://github.com/ck526438-lgtm/aniplay-ai/issues
AppUpdatesURL=https://github.com/ck526438-lgtm/aniplay-ai/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Installation possible sans droits administrateur (dans le profil de l'utilisateur)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=AniPlay-AI-{#AppVersion}-{#Edition}-setup
SetupIconFile=..\frontend\assets\branding\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
LicenseFile=..\LICENSE
Compression=lzma2/max
SolidCompression=yes
LZMANumBlockThreads=4
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
french.AssocTask=Proposer AniPlay AI dans « Ouvrir avec » pour les vidéos (mkv, mp4, webm, avi…)
english.AssocTask=Add AniPlay AI to "Open with" for video files (mkv, mp4, webm, avi…)
french.AssocGroup=Intégration Windows :
english.AssocGroup=Windows integration:
french.LaunchApp=Lancer AniPlay AI
english.LaunchApp=Launch AniPlay AI
french.VideoFile=Vidéo AniPlay AI
english.VideoFile=AniPlay AI video

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "openwith"; Description: "{cm:AssocTask}"; GroupDescription: "{cm:AssocGroup}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Type de fichier « Vidéo AniPlay AI » + entrée « Ouvrir avec » (ne remplace pas le lecteur par défaut)
Root: HKA; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueData: "{cm:VideoFile}"; Flags: uninsdeletekey; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Flags: uninsdeletekey; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mkv"; ValueData: ""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mp4"; ValueData: ""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".webm"; ValueData: ""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".avi"; ValueData: ""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mov"; ValueData: ""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.m4v\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m4v"; ValueData: ""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.ts\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ts"; ValueData: ""; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\.m3u8\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: openwith
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m3u8"; ValueData: ""; Tasks: openwith

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Au cas où le moteur IA tournerait encore (application tuée brutalement)
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM aniplay-backend.exe"; Flags: runhidden; RunOnceId: "KillBackend"

[Code]
// Les caches (modèles IA, sous-titres) sont dans %LOCALAPPDATA%\AniPlay AI :
// on propose de les supprimer à la désinstallation.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{localappdata}\AniPlay AI');
    if DirExists(DataDir) and not UninstallSilent then
      if MsgBox('Supprimer aussi les données d''AniPlay AI (modèles IA téléchargés, sous-titres générés, journaux) ?' + #13#10 + DataDir,
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;
