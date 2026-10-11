#Requires -Version 7.2
[CmdletBinding()]
param([string]$GodotPath = '')

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workflowRoot = Join-Path $repoRoot 'workflow'
$skillsRoot = Join-Path $workflowRoot 'skills'
$pythonCommand = Get-Command python -ErrorAction Stop

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'game/project.godot') -PathType Leaf)) {
    throw 'Run this script from a complete Robinson checkout: game/project.godot is missing.'
}

# Validate both destinations before generating files or creating either link.
$linkPaths = @('.agents/skills', '.codebuddy/skills')
foreach ($relativePath in $linkPaths) {
    $linkPath = Join-Path $repoRoot $relativePath
    $parentPath = Split-Path -Parent $linkPath
    if (Test-Path -LiteralPath $parentPath) {
        $parent = Get-Item -LiteralPath $parentPath -Force
        if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to write through a linked configuration directory: $parentPath"
        }
    }
    $existing = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        if (-not ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Existing skill directory is not managed by this setup; preserve it and resolve the conflict: $linkPath"
        }
        $resolvedTarget = $existing.ResolveLinkTarget($true)
        if ($null -eq $resolvedTarget -or $resolvedTarget.FullName -ne $skillsRoot) {
            throw "Skill link points elsewhere. Preserve or remove that link explicitly before setup: $linkPath"
        }
    }
}

if ($GodotPath) {
    $GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'GodotPath must be an executable file.' }
}

& $pythonCommand.Source (Join-Path $PSScriptRoot 'generate-skills.py')
if ($LASTEXITCODE -ne 0) { throw 'Skill adapter generation failed.' }

foreach ($relativePath in $linkPaths) {
    $linkPath = Join-Path $repoRoot $relativePath
    if ($null -eq (Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $linkPath) -Force | Out-Null
        if ($IsWindows) {
            New-Item -ItemType Junction -Path $linkPath -Target $skillsRoot | Out-Null
        } else {
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $skillsRoot | Out-Null
        }
    }
    Write-Output "$relativePath -> workflow/skills"
}

if ($GodotPath) {
    $settingsPath = Join-Path $workflowRoot 'local-settings.json'
    $settings = @{}
    if (Test-Path -LiteralPath $settingsPath) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    }
    $settings['godot_path'] = $GodotPath
    $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
    Write-Output 'Saved the Godot executable location in ignored workflow/local-settings.json.'
}

& $pythonCommand.Source (Join-Path $PSScriptRoot 'validate-workspace.py') --require-native-links
if ($LASTEXITCODE -ne 0) { throw 'Workspace validation failed; inspect the report above.' }
Write-Output 'Setup complete. Start a new Codex or CodeBuddy session to refresh its skill catalog.'
