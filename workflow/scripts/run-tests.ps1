#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$GodotPath,
    [ValidateSet('data', 'interaction', 'ui', 'movement', 'all')][string]$Suite = 'all',
    [string]$LogRoot,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 120
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

$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $gameRoot ".godot/test-results/$runId"
} else {
    $LogRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogRoot)
}
if (Test-Path -LiteralPath $LogRoot) { throw "Evidence directory already exists; choose a new -LogRoot: $LogRoot" }
New-Item -ItemType Directory -Path (Split-Path -Parent $LogRoot) -Force | Out-Null
# No -Force: never merge this run into existing evidence, including a concurrent run.
New-Item -ItemType Directory -Path $LogRoot | Out-Null

$gitHead = $null
$gitStatus = @()
if (Get-Command git -ErrorAction SilentlyContinue) {
    $headOutput = & git -C $repositoryRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $gitHead = ($headOutput | Out-String).Trim()
        $gitStatus = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=normal 2>$null)
    }
}
$checks = [Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    schema_version = 1
    run_id = $runId
    started_at_utc = [DateTime]::UtcNow.ToString('o')
    finished_at_utc = $null
    status = 'running'
    suite = $Suite
    timeout_seconds_per_process = $TimeoutSeconds
    repository_root = $repositoryRoot
    game_path = $gameRoot
    test_entry = $PSCommandPath
    godot_executable = $GodotPath
    engine_version = $null
    git_head = $gitHead
    git_worktree_status = $gitStatus
    assertion_pass_count = 0
    assertion_fail_count = 0
    checks = $checks
    failure = $null
}
$summaryPath = Join-Path $LogRoot 'summary.json'

function Save-Summary {
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

function Invoke-EngineProcess([string]$Name, [string[]]$EngineArguments) {
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $GodotPath
    $process.StartInfo.WorkingDirectory = $gameRoot
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($argument in $EngineArguments) { $process.StartInfo.ArgumentList.Add($argument) }

    $result = [ordered]@{
        name = $Name
        arguments = $EngineArguments
        started_at_utc = [DateTime]::UtcNow.ToString('o')
        duration_seconds = 0
        exit_code = $null
        timed_out = $false
        status = 'failed'
        log = "$Name.log"
        stdout_log = "$Name.stdout.log"
        stderr_log = "$Name.stderr.log"
        assertion_pass_count = 0
        assertion_fail_count = 0
        error_lines = @()
        failure = $null
    }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $stdout = ''
    $stderr = ''
    try {
        if (-not $process.Start()) { throw 'Godot process did not start.' }
        # Drain both pipes concurrently, so large test output cannot deadlock WaitForExit.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.timed_out = $true
            $process.Kill($true)
            if (-not $process.WaitForExit(5000)) { throw 'Timed-out process could not be terminated.' }
        }
        $result.exit_code = $process.ExitCode
        if (-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)) { throw 'Godot output streams did not close.' }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
    } catch {
        $result.failure = $_.Exception.Message
    } finally {
        $watch.Stop()
        $result.duration_seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        $process.Dispose()
        [IO.File]::WriteAllText((Join-Path $LogRoot $result.stdout_log), $stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $LogRoot $result.stderr_log), $stderr, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $LogRoot $result.log), ($stdout + $stderr), [Text.UTF8Encoding]::new($false))
    }
    return [pscustomobject]$result
}

function Invoke-Check([string]$Name, [string[]]$EngineArguments, [string]$SummaryTag = '') {
    $result = Invoke-EngineProcess $Name (@('--headless', '--path', $gameRoot) + $EngineArguments)
    $checks.Add($result)
    $lines = @(Get-Content -LiteralPath (Join-Path $LogRoot $result.log) -Encoding UTF8)
    # Windows certificate-store access is unrelated to these local, offline tests.
    $result.error_lines = @($lines | Where-Object {
        $_ -match '^(SCRIPT ERROR:|ERROR:|\[FAIL\])' -and
        $_ -notmatch '^ERROR: Failed to read the root certificate store\.?$'
    })
    if ($result.failure -or $result.timed_out -or $result.exit_code -ne 0 -or $result.error_lines.Count -gt 0) {
        if (-not $result.failure) { $result.failure = "Exit $($result.exit_code); timed out: $($result.timed_out); error lines: $($result.error_lines.Count)." }
        throw "$Name failed. $($result.failure) See $(Join-Path $LogRoot $result.log)"
    }
    if ($SummaryTag) {
        $pattern = '^\[' + [regex]::Escape($SummaryTag) + '\].*PASS = ([0-9]+).*FAIL = ([0-9]+)$'
        $matchesFound = @($lines | ForEach-Object { if ($_ -match $pattern) { [regex]::Match($_, $pattern) } })
        if ($matchesFound.Count -ne 1) { throw "$Name did not finish its assertions. See $(Join-Path $LogRoot $result.log)" }
        $result.assertion_pass_count = [int]$matchesFound[0].Groups[1].Value
        $result.assertion_fail_count = [int]$matchesFound[0].Groups[2].Value
        $summary.assertion_pass_count += $result.assertion_pass_count
        $summary.assertion_fail_count += $result.assertion_fail_count
        if ($result.assertion_pass_count -lt 1 -or $result.assertion_fail_count -ne 0) {
            throw "$Name assertion summary failed. See $(Join-Path $LogRoot $result.log)"
        }
        Write-Output $matchesFound[0].Value
    } else {
        Write-Output "$Name completed (exit 0)."
    }
    $result.status = 'passed'
    Save-Summary
}

Save-Summary
try {
    $version = Invoke-EngineProcess 'engine-version' @('--version')
    $checks.Add($version)
    if ($version.failure -or $version.timed_out -or $version.exit_code -ne 0) {
        throw "Cannot read Godot version. See $(Join-Path $LogRoot $version.log)"
    }
    $summary.engine_version = (Get-Content -LiteralPath (Join-Path $LogRoot $version.stdout_log) -Raw -Encoding UTF8).Trim()
    $version.status = 'passed'
    Save-Summary

    # A fresh clone needs imports and the global class cache before tests run.
    Invoke-Check 'import' @('--editor', '--import', '--quit')
    if ($Suite -in @('data', 'all')) {
        Invoke-Check 'items' @('--script', 'res://tests/test_item_definition.gd', '--quit-after', '1800') 'ITEM-01'
        Invoke-Check 'inventory' @('--script', 'res://tests/test_inventory.gd', '--quit-after', '1800') 'INVENTORY-01'
    }
    if ($Suite -in @('interaction', 'all')) {
        Invoke-Check 'interaction' @('res://tests/interaction_test.tscn', '--fixed-fps', '60', '--quit-after', '1800') 'INTERACTION-01'
    }
    if ($Suite -in @('ui', 'all')) {
        Invoke-Check 'ui' @('res://tests/ui_test.tscn', '--fixed-fps', '60', '--quit-after', '1800') 'UI-01'
    }
    if ($Suite -in @('movement', 'all')) {
        Invoke-Check 'movement' @('res://tests/movement_test.tscn', '--fixed-fps', '60', '--quit-after', '1800') 'MOVEMENT-BASELINE'
    }
    if ($Suite -eq 'all') {
        Invoke-Check 'main-smoke' @('--fixed-fps', '60', '--quit-after', '240')
        Invoke-Check 'world-smoke' @('res://scenes/world.tscn', '--fixed-fps', '60', '--quit-after', '120')
    }
    $summary.status = 'passed'
} catch {
    $summary.status = 'failed'
    $summary.failure = $_.Exception.Message
    Write-Host $summary.failure -ForegroundColor Red
} finally {
    $summary.finished_at_utc = [DateTime]::UtcNow.ToString('o')
    Save-Summary
}
Write-Output "Suite '$Suite': $($summary.status). Evidence: $LogRoot"
if ($summary.status -ne 'passed') { exit 1 }
