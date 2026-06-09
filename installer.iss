; Hermes Desktop + Hermes Agent 一键安装包
; 使用 Inno Setup 编译: iscc installer.iss

#define MyAppName "Hermes Desktop"
#define MyAppVersion "1.0.4"
#define MyAppPublisher "Nous Research"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Hermes Desktop
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer
OutputBaseFilename=HermesDesktop-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\hermes_desktop.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "installer\Languages\ChineseSimplified.isl"

[Files]
; Desktop 主程序
Source: "build\windows\x64\runner\Release\hermes_desktop.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Hermes Agent 包
Source: "dist\hermes.exe"; DestDir: "{app}\hermes"; Flags: ignoreversion

[Dirs]
Name: "{app}\hermes"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\hermes_desktop.exe"
Name: "{group}\{#MyAppName} (Hermes Gateway)"; Filename: "{app}\hermes\hermes.exe"; Parameters: "gateway run"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\hermes_desktop.exe"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // 安装后把 Hermes 路径加到环境变量
    SaveStringToFile(ExpandConstant('{app}\hermes\path.txt'), ExpandConstant('{app}\hermes'), False);
  end;
end;
