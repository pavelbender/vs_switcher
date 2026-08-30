[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$appDirectory = Join-Path $env:LOCALAPPDATA 'VSCodeAccountLauncher'
$configPath = Join-Path $appDirectory 'config.json'
$logPath = Join-Path $appDirectory 'launcher.log'
$logLineLimit = 10000

function Write-LauncherLog {
    param([string]$Message)
    try {
        New-Item -ItemType Directory -Path $appDirectory -Force | Out-Null
        $line = "{0:yyyy-MM-dd HH:mm:ss.fff} | {1}" -f (Get-Date), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
        $lines = @(Get-Content -LiteralPath $logPath -Encoding UTF8)
        if ($lines.Count -gt $logLineLimit) {
            $lines | Select-Object -Last $logLineLimit | Set-Content -LiteralPath $logPath -Encoding UTF8
        }
    } catch { }
}

function Read-RequiredDirectory {
    param([string]$Prompt)
    while ($true) {
        $value = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($value)) { Write-Host 'Enter an existing folder path.' -ForegroundColor Yellow; continue }
        try {
            $resolved = (Resolve-Path -LiteralPath $value -ErrorAction Stop).Path
            if ((Get-Item -LiteralPath $resolved).PSIsContainer) { return $resolved }
        } catch { }
        Write-Host "Folder does not exist: $value" -ForegroundColor Yellow
    }
}

$openRouterModel = '~openai/gpt-latest'

function New-OpenRouterRoot {
    param([string]$Path)
    $codexHome = Join-Path $env:USERPROFILE '.codex-openrouter'
    [PSCustomObject]@{
        name = 'OpenRouter'; path = $Path; account = 'OpenRouter API key'
        codexHome = $codexHome
        userDataDir = (Join-Path $env:LOCALAPPDATA 'VSCode-OpenRouter')
        extensionsDir = (Join-Path $env:USERPROFILE '.vscode\extensions')
        provider = 'openrouter'
        model = $openRouterModel
        apiKeyEnv = 'OPENROUTER_API_KEY'
        apiKeyFile = (Join-Path $codexHome 'openrouter.key')
    }
}

function New-DefaultConfig {
    Clear-Host
    Write-Host 'VS Code launcher setup' -ForegroundColor Cyan
    Write-Host 'Enter the parent projects folder. work and personal are detected automatically.'
    $projectsDirectory = Read-RequiredDirectory 'Projects folder (for example C:\Projects)'
    $workDirectory = Join-Path $projectsDirectory 'work'
    $personalDirectory = Join-Path $projectsDirectory 'personal'
    if (-not (Test-Path -LiteralPath $workDirectory -PathType Container)) { $workDirectory = Read-RequiredDirectory 'Work projects folder' }
    if (-not (Test-Path -LiteralPath $personalDirectory -PathType Container)) { $personalDirectory = Read-RequiredDirectory 'Personal projects folder' }
    [PSCustomObject]@{
        roots = @(
            [PSCustomObject]@{
                name = 'Work'; path = $workDirectory; account = 'Work Codex account'
                codexHome = (Join-Path $env:USERPROFILE '.codex-work')
                userDataDir = (Join-Path $env:LOCALAPPDATA 'VSCode-Work')
                extensionsDir = (Join-Path $env:USERPROFILE '.vscode\extensions')
            }
            [PSCustomObject]@{
                name = 'Personal'; path = $personalDirectory; account = 'Personal Codex account'
                codexHome = (Join-Path $env:USERPROFILE '.codex-personal')
                userDataDir = (Join-Path $env:LOCALAPPDATA 'VSCode-Personal')
                extensionsDir = (Join-Path $env:USERPROFILE '.vscode\extensions')
            }
            (New-OpenRouterRoot -Path $projectsDirectory)
        )
    }
}

function Get-LauncherConfig {
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($config.roots -and @($config.roots).Count -ge 2) {
                $roots = @($config.roots)
                if (-not ($roots | Where-Object { $_.provider -eq 'openrouter' })) {
                    $parentDirectory = Split-Path -Path $roots[0].path -Parent
                    if ([string]::IsNullOrWhiteSpace($parentDirectory)) { $parentDirectory = $roots[0].path }
                    $config.roots = @($roots + (New-OpenRouterRoot -Path $parentDirectory))
                    $config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8
                    Write-LauncherLog "OpenRouter context added to $configPath"
                }
                Write-LauncherLog "Configuration loaded from $configPath"
                return $config
            }
        } catch { Write-LauncherLog "Configuration read failed: $($_.Exception.Message)" }
    }
    $config = New-DefaultConfig
    New-Item -ItemType Directory -Path $appDirectory -Force | Out-Null
    $config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-LauncherLog "Configuration created at $configPath"
    $config
}

$codexSeedFiles = @('config.toml', 'AGENTS.md', 'RTK.md')
$codexSubdirectories = @('log', 'sessions', 'attachments', 'tmp')

# Layout from https://openrouter.ai/docs/cookbook/coding-agents/codex-cli
$openRouterConfigTemplate = @'
model_provider = "openrouter"
model_reasoning_effort = "high"
model = "{0}"

[model_providers.openrouter]
name = "openrouter"
base_url = "https://openrouter.ai/api/v1"

[model_providers.openrouter.auth]
command = "powershell"
args = ["-NoProfile", "-Command", "Write-Output $env:{1}"]
'@

function Get-RootApiKey {
    param([object]$Root)
    if ([string]::IsNullOrWhiteSpace($Root.apiKeyEnv)) { return $null }
    if ($Root.apiKeyFile -and (Test-Path -LiteralPath $Root.apiKeyFile -PathType Leaf)) {
        $key = (Get-Content -LiteralPath $Root.apiKeyFile -Raw -Encoding UTF8).Trim()
        if ($key) { return $key }
    }
    $inherited = [Environment]::GetEnvironmentVariable($Root.apiKeyEnv)
    if ($inherited) { return $inherited.Trim() }
    $null
}

function Initialize-CodexHome {
    param([object]$Root)
    $codexHome = $Root.codexHome
    if ([string]::IsNullOrWhiteSpace($codexHome)) {
        $script:LastLaunchError = "Context $($Root.name) has no codexHome value in $configPath"
        Write-LauncherLog $script:LastLaunchError
        return $false
    }
    try {
        $script:CodexHomeCreated = -not (Test-Path -LiteralPath $codexHome -PathType Container)
        New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
        foreach ($name in $codexSubdirectories) {
            New-Item -ItemType Directory -Path (Join-Path $codexHome $name) -Force | Out-Null
        }
        if ($script:CodexHomeCreated) {
            Write-LauncherLog "Codex home created: $codexHome"
            $defaultCodexHome = Join-Path $env:USERPROFILE '.codex'
            $seedFiles = $codexSeedFiles
            if ($Root.provider -eq 'openrouter') {
                $seedFiles = @($codexSeedFiles | Where-Object { $_ -ne 'config.toml' })
                $model = if ($Root.model) { $Root.model } else { $openRouterModel }
                $keyVariable = if ($Root.apiKeyEnv) { $Root.apiKeyEnv } else { 'OPENROUTER_API_KEY' }
                Set-Content -LiteralPath (Join-Path $codexHome 'config.toml') -Value ($openRouterConfigTemplate -f $model, $keyVariable) -Encoding UTF8
                Write-LauncherLog "OpenRouter config.toml written to $codexHome"
            }
            if ($defaultCodexHome -ne $codexHome) {
                foreach ($name in $seedFiles) {
                    $source = Join-Path $defaultCodexHome $name
                    $destination = Join-Path $codexHome $name
                    if ((Test-Path -LiteralPath $source -PathType Leaf) -and -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
                        Copy-Item -LiteralPath $source -Destination $destination -Force
                        Write-LauncherLog "Codex home seeded with $name from $defaultCodexHome"
                    }
                }
            }
        }
        New-Item -ItemType Directory -Path $Root.userDataDir -Force | Out-Null
        if ($Root.apiKeyEnv) {
            $script:CodexApiKey = Get-RootApiKey -Root $Root
            $script:CodexSignedIn = [bool]$script:CodexApiKey
        } else {
            $script:CodexSignedIn = Test-Path -LiteralPath (Join-Path $codexHome 'auth.json') -PathType Leaf
        }
        return $true
    } catch {
        $script:LastLaunchError = "Failed to prepare CODEX_HOME ${codexHome}: $($_.Exception.Message)"
        Write-LauncherLog $script:LastLaunchError
        return $false
    }
}

function Get-Directories {
    param([string]$Path)
    @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue | Sort-Object -Property Name)
}

function Start-VSCode {
    param([string]$Path, [object]$Root)
    $script:LastLaunchError = $null
    $script:CodexHomeCreated = $false
    $script:CodexSignedIn = $true
    $script:CodexApiKey = $null
    if (-not (Initialize-CodexHome -Root $Root)) { return $false }
    $codeCommand = Get-Command code.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $codeCommand) {
        $script:LastLaunchError = 'The code.cmd command was not found.'
        Write-LauncherLog $script:LastLaunchError
        return $false
    }
    $previousCodexHome = $env:CODEX_HOME
    $apiKeyVariable = $Root.apiKeyEnv
    $previousApiKey = if ($apiKeyVariable) { [Environment]::GetEnvironmentVariable($apiKeyVariable) } else { $null }
    try {
        $env:CODEX_HOME = $Root.codexHome
        if ($apiKeyVariable -and $script:CodexApiKey) {
            Set-Item -LiteralPath "env:$apiKeyVariable" -Value $script:CodexApiKey
            Write-LauncherLog "$apiKeyVariable set for context $($Root.name)"
        }
        Write-LauncherLog "Launching: context=$($Root.name); path=$Path; code=$($codeCommand.Source); CODEX_HOME=$($Root.codexHome); userDataDir=$($Root.userDataDir)"
        $output = & $codeCommand.Source --reuse-window --user-data-dir $Root.userDataDir --extensions-dir $Root.extensionsDir $Path 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in @($output)) { Write-LauncherLog "code output: $line" }
        Write-LauncherLog "code exit: $exitCode; path=$Path"
        if ($exitCode -ne 0) {
            $script:LastLaunchError = "VS Code CLI exited with code $exitCode. See $logPath"
            return $false
        }
    } catch {
        $script:LastLaunchError = $_.Exception.Message
        Write-LauncherLog "Launch exception: $script:LastLaunchError"
        return $false
    } finally {
        $env:CODEX_HOME = $previousCodexHome
        if ($apiKeyVariable) { Set-Item -LiteralPath "env:$apiKeyVariable" -Value $previousApiKey }
    }
    $true
}

function Write-Menu {
    param([object]$Root, [string]$CurrentPath, [System.IO.DirectoryInfo[]]$Items, [int]$SelectedIndex, [bool]$AtRootMenu, [object[]]$Roots)
    Clear-Host
    Write-Host 'VS Code project launcher' -ForegroundColor Cyan
    Write-Host ("Codex account: {0} | Context: {1}" -f $Root.account, $Root.name) -ForegroundColor Green
    Write-Host ("Path: {0}" -f $CurrentPath) -ForegroundColor DarkGray
    Write-Host 'Up/Down: select | Right: enter folder | Left: back | Enter: open in VS Code | Esc: quit' -ForegroundColor DarkGray
    Write-Host ''
    if ($AtRootMenu) {
        for ($index = 0; $index -lt $Roots.Count; $index++) {
            $prefix = if ($index -eq $SelectedIndex) { '>' } else { ' ' }
            $color = if ($index -eq $SelectedIndex) { 'Black' } else { 'White' }
            $background = if ($index -eq $SelectedIndex) { 'Cyan' } else { 'Black' }
            Write-Host ("{0} {1,-10} {2}" -f $prefix, $Roots[$index].name, $Roots[$index].path) -ForegroundColor $color -BackgroundColor $background
        }
        return
    }
    if ($Items.Count -eq 0) { Write-Host '  No child folders.' -ForegroundColor DarkYellow; return }
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $prefix = if ($index -eq $SelectedIndex) { '>' } else { ' ' }
        $color = if ($index -eq $SelectedIndex) { 'Black' } else { 'White' }
        $background = if ($index -eq $SelectedIndex) { 'Cyan' } else { 'Black' }
        Write-Host ("{0} {1}" -f $prefix, $Items[$index].Name) -ForegroundColor $color -BackgroundColor $background
    }
}

function Start-Launcher {
    Write-LauncherLog 'Launcher started'
    $config = Get-LauncherConfig
    $roots = @($config.roots)
    $rootIndex = 0; $selectedIndex = 0; $atRootMenu = $true; $currentPath = $null; $currentRoot = $roots[$rootIndex]
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            if ($atRootMenu) {
                $currentRoot = $roots[$rootIndex]
                Write-Menu -Root $currentRoot -CurrentPath $currentRoot.path -Items @() -SelectedIndex $rootIndex -AtRootMenu $true -Roots $roots
            } else {
                $items = Get-Directories -Path $currentPath
                if ($selectedIndex -ge $items.Count) { $selectedIndex = [Math]::Max(0, $items.Count - 1) }
                Write-Menu -Root $currentRoot -CurrentPath $currentPath -Items $items -SelectedIndex $selectedIndex -AtRootMenu $false -Roots $roots
            }
            $key = [Console]::ReadKey($true).Key
            Write-LauncherLog "Key: $key; atRootMenu=$atRootMenu; currentPath=$currentPath"
            switch ($key) {
                'Escape' { return }
                'UpArrow' { if ($atRootMenu) { $rootIndex = ($rootIndex - 1 + $roots.Count) % $roots.Count } elseif ($items.Count) { $selectedIndex = ($selectedIndex - 1 + $items.Count) % $items.Count } }
                'DownArrow' { if ($atRootMenu) { $rootIndex = ($rootIndex + 1) % $roots.Count } elseif ($items.Count) { $selectedIndex = ($selectedIndex + 1) % $items.Count } }
                'RightArrow' {
                    if ($atRootMenu) { $currentRoot = $roots[$rootIndex]; $currentPath = $currentRoot.path; $selectedIndex = 0; $atRootMenu = $false }
                    elseif ($items.Count) { $currentPath = $items[$selectedIndex].FullName; $selectedIndex = 0 }
                }
                'LeftArrow' {
                    if (-not $atRootMenu) {
                        if ($currentPath -eq $currentRoot.path) { $atRootMenu = $true; $selectedIndex = $rootIndex }
                        else { $currentPath = Split-Path -Path $currentPath -Parent; $selectedIndex = 0 }
                    }
                }
                'Enter' {
                    $pathToOpen = if ($atRootMenu) { $roots[$rootIndex].path } elseif ($items.Count) { $items[$selectedIndex].FullName } else { $currentPath }
                    $rootForOpen = if ($atRootMenu) { $roots[$rootIndex] } else { $currentRoot }
                    Clear-Host
                    Write-Host "Opening: $pathToOpen" -ForegroundColor Cyan
                    if (-not (Start-VSCode -Path $pathToOpen -Root $rootForOpen)) {
                        $message = if ($script:LastLaunchError) { $script:LastLaunchError } else { 'The code command was not found. In VS Code run: Shell Command: Install code command in PATH.' }
                        Write-Host $message -ForegroundColor Yellow
                        [Console]::ReadKey($true) | Out-Null
                    } else {
                        $hints = @()
                        if ($script:CodexHomeCreated) {
                            $hints += "Created the Codex home for $($rootForOpen.name): $($rootForOpen.codexHome)"
                            $hints += 'If a window for this context was already open, run Developer: Reload Window so Codex picks up CODEX_HOME.'
                        }
                        if (-not $script:CodexSignedIn) {
                            if ($rootForOpen.apiKeyEnv) {
                                $hints += "No $($rootForOpen.apiKeyEnv) value found. Write the key as a single line in $($rootForOpen.apiKeyFile), or set the environment variable, then open this context again."
                            } else {
                                $hints += "No auth.json in $($rootForOpen.codexHome). Sign in to the $($rootForOpen.account) from the Codex panel in the new window."
                            }
                        }
                        if ($hints.Count) {
                            foreach ($hint in $hints) { Write-Host $hint -ForegroundColor Yellow }
                            Write-Host 'Press any key to continue.' -ForegroundColor DarkGray
                            [Console]::ReadKey($true) | Out-Null
                        }
                    }
                }
            }
        }
    } finally { Write-LauncherLog 'Launcher stopped'; [Console]::CursorVisible = $true; Clear-Host }
}

Start-Launcher
