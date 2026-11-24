; CAD 런처 설치 마법사 (Inno Setup)
;
; 하는 일: CAD런처.exe · catalog.json · lsp/ · tools/ · README.md 를
; 사용자가 고른 폴더에 설치하고, 시작 메뉴(+선택 시 바탕화면) 바로가기를 만든다.
; "외부 프로그램 미리 설치"를 선택하면 tools/PAVQ-Tools.zip 을 C:\MATX-Tools 에
; 미리 풀어둔다 (MATX는 이제 런처에 통합되어 별도 프로그램이 필요 없음).
; 안 풀리면 설치 뒤 런처 안의 '외부 프로그램 설치' 버튼으로도 똑같이 설치할 수
; 있으니, 이 옵션은 선택 사항으로 둔다.
;
; 빌드: 보통은 .github/workflows/build-installer.yml 이 GitHub Actions(Windows)에서
; 자동으로 컴파일해서 CAD런처-설치.exe 를 만들어준다.
; 로컬에서 직접 만들려면 Inno Setup(https://jrsoftware.org/isinfo.php) 설치 후
;   ISCC installer\cad-launcher.iss
; (리포지토리 루트에서 실행. 결과물은 installer\output\CAD런처-설치.exe)

#define MyAppName "CAD 런처"
#define MyAppVersion "1.0"
#define MyAppExeName "CAD런처.exe"
#define RepoRoot "..\"

[Setup]
AppId={{F3C1E6A2-6E6B-4B2C-9B7A-2B7C7E6B9C10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=hsb6582
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
; 자재내역.xlsx 등 내부 파일 이름에 한글이 들어가므로 UTF-8 로 패키징
[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면에 바로가기 만들기"; GroupDescription: "추가 아이콘:"
Name: "exttools"; Description: "외부 프로그램(PAVQ 보조 프로그램)도 지금 같이 설치 (C:\MATX-Tools) - 나중에 런처 안에서도 설치할 수 있음"; GroupDescription: "추가 구성요소:"; Flags: unchecked

[Files]
Source: "{#RepoRoot}CAD런처.exe"; DestDir: "{app}"; Flags: ignoreversion
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
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('exttools') then
  begin
    ExtractZip(ExpandConstant('{tmp}\PAVQ-Tools.zip'), 'C:\MATX-Tools');
  end;
end;
