#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$gameRoot = Join-Path $repositoryRoot 'game'

if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = $env:GODOT_PATH }
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $settingsPath = Join-Path $repositoryRoot 'workflow/local-settings.json'
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.PSObject.Properties.Name -contains 'godot_path') { $GodotPath = $settings.godot_path }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot executable not found. Set -GodotPath, GODOT_PATH, or workflow/local-settings.json godot_path.'
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'project.godot') -PathType Leaf)) {
    throw "Godot project not found: $gameRoot"
}

# Start-Process joins its argument array; quote the project path explicitly for spaces.
$engineArguments = @('--path', ('"' + $gameRoot + '"'))
if (-not $Run) { $engineArguments += '--editor' }
$startOptions = @{
    FilePath = $GodotPath
    ArgumentList = $engineArguments
    WorkingDirectory = $gameRoot
    PassThru = $true
}
# This command is the user's interactive editor/game entry; tests run hidden separately.
if ($IsWindows) { $startOptions['WindowStyle'] = 'Normal' }
$process = Start-Process @startOptions
$mode = if ($Run) { 'game' } else { 'editor' }
Write-Output "Started Godot $mode for $gameRoot (process $($process.Id))."
