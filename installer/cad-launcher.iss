; CAD 런처 설치 마법사 (Inno Setup) - "요즘 스타일"(WebView2, src-modern) 버전용
;
; 하는 일: CAD런처.exe(WebView2 버전) · catalog.json · lsp/ · tools/ · README.md 를
; 사용자가 고른 폴더에 설치하고, 시작 메뉴(+선택 시 바탕화면) 바로가기를 만든다.
; WebView2 런타임이 없으면 설치 중에 자동으로 깔아준다(필수 구성요소). 설치 중에
; 따로 받지 않고 설치 파일 안에 이미 들어있는 걸 쓰므로, 인터넷이 느리거나
; PowerShell 다운로드가 막힌 PC에서도 (이 설치 파일만 받았다면) 문제없이 된다.
; (MATX·PAVQ 는 런처에 통합되어 별도 외부 프로그램을 미리 설치할 필요가 없다.)
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
#define ModernDir "..\src-modern\build\"
#define ModernExe ModernDir + "CAD런처.exe"

[Setup]
AppId={{F3C1E6A2-6E6B-4B2C-9B7A-2B7C7E6B9C10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=hsb6582
; Program Files 에 설치 (AppData 에 exe 를 두면 보안 프로그램이 의심하기 쉬움).
; 런처가 실행 때마다 lsp/·catalog.json 을 받아 덮어쓰고 설정을 저장하므로,
; 아래 [Dirs] 에서 설치 폴더에 일반 사용자 쓰기 권한(users-modify)을 준다.
DefaultDirName={autopf}\CADLauncher
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

[Dirs]
; 관리자 권한 없이도 자동 업데이트·설정 저장이 되도록 설치 폴더에 쓰기 권한 부여 (하위 파일·폴더에 상속됨)
Name: "{app}"; Permissions: users-modify

[Files]
Source: "MicrosoftEdgeWebView2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#ModernExe}"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion
; WebView2Loader.dll 을 exe 옆에 두면 런처가 이 파일을 일반 방식으로 불러온다.
; 없으면 exe 안에 든 DLL을 메모리에서 직접 불러오는데, 이 방식은 보안 프로그램(Cortex XDR 등)이 의심한다.
Source: "{#ModernDir}WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}catalog.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}lsp\*"; DestDir: "{app}\lsp"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs createallsubdirs

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

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssInstall) and not IsWebView2Installed() then
    InstallWebView2();
end;
