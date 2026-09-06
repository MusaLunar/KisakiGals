; KisakiGals 安装包脚本（Inno Setup 6）
; 用 ISCC.exe 编译：iscc /DPortable="<便携版zip>" install_script.iss 或直接编译

#define MyAppName "KisakiGals"
#define MyAppVersion "0.9.0-beta"
#define MyAppPublisher "MusaLunar"
#define MyAppURL "https://github.com/MusaLunar/KisakiGals"
#define MyAppExeName "kisakigals.exe"
#define SrcDir "E:\Programming\KisakiGals\build\windows\x64\runner\Release"

[Setup]
AppId={{8A1C4F2E-3D5B-4C6A-9E7F-KisakiGals001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=KisakiGals-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SrcDir}\kisakigals.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
