[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceDirectory = $PSScriptRoot
$installDirectory = Join-Path $env:LOCALAPPDATA 'VSCodeAccountLauncher'

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'vs-switcher.ps1') -Destination (Join-Path $installDirectory 'vs-switcher.ps1') -Force

$existingCommand = Get-Command c.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
$launcherDirectory = if ($existingCommand -and $existingCommand.Source) { Split-Path -Path $existingCommand.Source -Parent } else { $installDirectory }
$launcherPath = Join-Path $launcherDirectory 'c.cmd'

if ($existingCommand -and ((Resolve-Path -LiteralPath $existingCommand.Source).Path -ne (Resolve-Path -LiteralPath $launcherPath).Path)) {
    throw 'The existing c command is not a c.cmd file and cannot be replaced safely.'
}

@"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$installDirectory\vs-switcher.ps1"
"@ | Set-Content -LiteralPath $launcherPath -Encoding Ascii

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @($userPath -split ';' | Where-Object { $_ })
if ($pathEntries -notcontains $installDirectory) {
    [Environment]::SetEnvironmentVariable('Path', (($pathEntries + $installDirectory) -join ';'), 'User')
}

Write-Host "Installation complete. Command installed at: $launcherPath" -ForegroundColor Green
Write-Host 'Open a new PowerShell window and run: c' -ForegroundColor Green
