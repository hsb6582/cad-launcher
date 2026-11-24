; CAD 런처 설치 마법사 (Inno Setup) - "요즘 스타일"(WebView2, src-modern) 버전용
;
; 하는 일: CAD런처.exe(WebView2 버전) · catalog.json · lsp/ · tools/ · README.md 를
; 사용자가 고른 폴더에 설치하고, 시작 메뉴(+선택 시 바탕화면) 바로가기를 만든다.
; WebView2 런타임이 없으면 설치 중에 자동으로 깔아준다(필수 구성요소). 설치 중에
; 따로 받지 않고 설치 파일 안에 이미 들어있는 걸 쓰므로, 인터넷이 느리거나
; PowerShell 다운로드가 막힌 PC에서도 (이 설치 파일만 받았다면) 문제없이 된다.
; "외부 프로그램 미리 설치"를 선택하면 tools/PAVQ-Tools.zip 을 C:\MATX-Tools 에
; 미리 풀어둔다 (MATX는 런처에 통합되어 별도 프로그램이 필요 없음).
; 안 풀리면 설치 뒤 런처 안의 '외부 프로그램 설치' 버튼으로도 똑같이 설치할 수
; 있으니, 이 옵션은 선택 사항으로 둔다.
;
; 빌드: 보통은 .github/workflows/build-installer.yml 이 GitHub Actions(Windows)에서
; src-modern 을 직접 빌드한 뒤 Inno Setup으로 컴파일해서 CAD런처-설치.exe 를 만들어준다.
; 로컬에서 직접 만들려면:
;   cd src-modern && go build -ldflags "-H windowsgui -s -w" -o build\CAD런처.exe .
;   그다음 Inno Setup(https://jrsoftware.org/isinfo.php) 설치 후
;   ISCC installer\cad-launcher.iss  (리포지토리 루트에서 실행)
; 결과물은 installer\output\CAD런처-설치.exe

#define MyAppName "CAD 런처"
#define MyAppVersion "1.0"
#define MyAppExeName "CAD런처.exe"
#define RepoRoot "..\"
#define ModernExe "..\src-modern\build\CAD런처.exe"

[Setup]
AppId={{F3C1E6A2-6E6B-4B2C-9B7A-2B7C7E6B9C10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=hsb6582
; 사용자 폴더에 설치: 런처가 실행 때마다 lsp/·catalog.json 을 받아 덮어쓰고 설정을 저장하므로
; 관리자 권한 없이 쓸 수 있는 곳이어야 한다 (Program Files 에 두면 업데이트가 조용히 실패함).
DefaultDirName={localappdata}\CADLauncher
PrivilegesRequired=lowest
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir=output
OutputBaseFilename=CAD런처-설치
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면에 바로가기 만들기"; GroupDescription: "추가 아이콘:"
Name: "exttools"; Description: "외부 프로그램(PAVQ 보조 프로그램)도 지금 같이 설치 (C:\MATX-Tools) - 나중에 런처 안에서도 설치할 수 있음"; GroupDescription: "추가 구성요소:"; Flags: unchecked

[Files]
Source: "MicrosoftEdgeWebView2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#ModernExe}"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion
Source: "{#RepoRoot}catalog.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}lsp\*"; DestDir: "{app}\lsp"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}tools\PAVQ-Tools.zip"; DestDir: "{tmp}"; Flags: deleteafterinstall; Tasks: exttools

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "설치 후 바로 실행"; Flags: nowait postinstall skipifsilent

[Code]
// 요즘 스타일(WebView2) 버전은 Microsoft Edge WebView2 런타임이 필요하다.
// 레지스트리에 설치 기록이 있는지 확인하고, 없으면 설치 중에 자동으로 받아서 깐다.
const
  WebView2ClientId = 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

function IsWebView2Installed(): Boolean;
var
  Version: String;
begin
  Result :=
    RegQueryStringValue(HKLM64, WebView2ClientId, 'pv', Version) or
    RegQueryStringValue(HKLM32, WebView2ClientId, 'pv', Version) or
    RegQueryStringValue(HKCU, WebView2ClientId, 'pv', Version);
end;

// 설치 파일 안에 이미 들어있는 부트스트래퍼를 그대로 실행한다 (따로 받지 않음).
// 이 부트스트래퍼 자체는 작지만, 실제 런타임은 실행될 때 인터넷에서 받으므로
// 그 순간엔 인터넷이 필요하다. 실패해도 설치 자체는 계속 진행된다 - 나중에
// 수동으로 WebView2 Runtime을 설치하면 된다 (https://developer.microsoft.com/microsoft-edge/webview2/).
procedure InstallWebView2();
var
  BootstrapFile: String;
  ResultCode: Integer;
begin
  BootstrapFile := ExpandConstant('{tmp}\MicrosoftEdgeWebView2Setup.exe');
  if FileExists(BootstrapFile) then
  begin
    WizardForm.StatusLabel.Caption := 'Microsoft Edge WebView2 런타임을 설치하는 중...';
    Exec(BootstrapFile, '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

// Shell.Application COM 객체로 압축을 푼다 (추가 unzip 도구 없이, Windows 기본 기능만 사용).
// 이 방식은 설치 파일 용량을 늘리지 않지만, 아주 드물게 환경에 따라 느리거나 안 될 수 있다.
// 그런 경우에도 설치 자체는 계속 진행되고, 런처를 실행한 뒤 '외부 프로그램 설치' 버튼으로
// 같은 결과를 얻을 수 있으니 실패해도 치명적이지 않다.
procedure ExtractZip(ZipPath, TargetPath: string);
var
  Shell, ZipFile, TargetFolder: Variant;
begin
  if not DirExists(TargetPath) then
    ForceDirectories(TargetPath);
  try
    Shell := CreateOleObject('Shell.Application');
    ZipFile := Shell.NameSpace(ZipPath);
    TargetFolder := Shell.NameSpace(TargetPath);
    if (not VarIsNull(ZipFile)) and (not VarIsNull(TargetFolder)) then
      TargetFolder.CopyHere(ZipFile.Items, 4 + 16 + 1024); // 조용히, 확인 없이, 오류창 없이
  except
    // 실패해도 설치는 계속 진행 (런처 안의 '외부 프로그램 설치'로 나중에 가능)
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssInstall) and not IsWebView2Installed() then
    InstallWebView2();
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('exttools') then
  begin
    ExtractZip(ExpandConstant('{tmp}\PAVQ-Tools.zip'), 'C:\MATX-Tools');
  end;
end;
