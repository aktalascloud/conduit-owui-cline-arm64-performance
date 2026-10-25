$ErrorActionPreference = 'Stop'
$stateRoot = $PSScriptRoot
$python = Join-Path $stateRoot 'venv\Scripts\pythonw.exe'
$script = Join-Path $stateRoot 'cline_gateway.py'
$config = Join-Path $stateRoot 'server.json'
if (-not (Test-Path -LiteralPath $python) -or -not (Test-Path -LiteralPath $config)) {
    throw 'Run setup-windows.ps1 first.'
}
$running = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^pythonw?\.exe$' -and
    $_.CommandLine -like ('*' + $script + '*') -and
    $_.CommandLine -like ('*' + $config + '*')
})
if ($running.Count -gt 0) { exit 0 }
$command = '"' + $python + '" -B -X utf8 "' + $script + '" --config "' + $config + '"'
$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine = $command
    CurrentDirectory = $stateRoot
}
if ($result.ReturnValue -ne 0) { throw 'Independent gateway launch failed.' }
