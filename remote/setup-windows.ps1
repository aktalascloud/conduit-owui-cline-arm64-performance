param(
    [Parameter(Mandatory=$true)][string]$HostAddress,
    [string]$ClineCli = (Join-Path $env:LOCALAPPDATA 'Cline Desktop AVX1 RU\cline-cli.exe'),
    [string]$ClineConfig = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cline-avx1'),
    [string]$Workspace = ([Environment]::GetFolderPath('UserProfile')),
    [string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'ConduitClineRemote'),
    [string]$ListenAddress = '127.0.0.1',
    [int]$SshPort = 2222,
    [switch]$InstallStartup,
    [switch]$Start
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stateRoot = [IO.Path]::GetFullPath($StateDirectory)
if ($stateRoot.StartsWith($repositoryRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $stateRoot -eq $repositoryRoot) {
    throw 'Keep private configuration outside the public checkout.'
}
if (-not (Test-Path -LiteralPath $ClineCli -PathType Leaf)) { throw 'Installed Cline CLI not found.' }
if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { throw 'Project folder not found.' }
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $stateRoot /inheritance:r /grant:r ('*' + $sid + ':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Private folder ACL could not be restricted.' }
$venv = Join-Path $stateRoot 'venv'
if (-not (Test-Path -LiteralPath (Join-Path $venv 'Scripts\python.exe'))) {
    if (Get-Command py.exe -ErrorAction SilentlyContinue) { & py.exe -3 -m venv $venv }
    else { & python.exe -m venv $venv }
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.12 or later is required.' }
}
$python = Join-Path $venv 'Scripts\python.exe'
& $python -m pip install --disable-pip-version-check --upgrade 'pip>=26.2'
if ($LASTEXITCODE -ne 0) { throw 'Secure pip bootstrap failed.' }
& $python -m pip install --disable-pip-version-check -r (Join-Path $PSScriptRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Gateway dependency installation failed.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'cline_gateway.py') -Destination $stateRoot
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-gateway.ps1') -Destination $stateRoot
$initializer = @'
import json,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from cline_gateway import prepare,client_profile,validate_config
root=Path(sys.argv[1])
config=prepare(root,Path(sys.argv[2]),Path(sys.argv[3]),Path(sys.argv[4]),bind_host=sys.argv[6],ssh_port=int(sys.argv[7]))
config.update(bind_host=sys.argv[6],ssh_port=int(sys.argv[7]))
validate_config(config)
(root/'server.json').write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
profile=client_profile(config,sys.argv[5]);profile['projectPath']=sys.argv[3]
(root/'connection.json').write_text(json.dumps(profile,indent=2)+'\n',encoding='utf-8')
'@
$initializer | & $python -B -X utf8 - $stateRoot $ClineCli $Workspace $ClineConfig $HostAddress $ListenAddress $SshPort
if ($LASTEXITCODE -ne 0) { throw 'Private profile initialization failed.' }
if ($InstallStartup) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Conduit Cline Remote.lnk'))
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $stateRoot 'start-gateway.ps1') + '"'
    $shortcut.WorkingDirectory = $stateRoot
    $shortcut.WindowStyle = 7
    $shortcut.Save()
}
if ($Start) { & (Join-Path $stateRoot 'start-gateway.ps1') }
Write-Output ('Private phone connection document: ' + (Join-Path $stateRoot 'connection.json'))
Write-Output 'Do not publish this document. Add a scoped firewall rule and router forwarding only when intentionally using public SSH.'
