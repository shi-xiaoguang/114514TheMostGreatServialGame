param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [ValidateSet('data', 'interaction', 'ui', 'movement', 'all')][string]$Suite = 'data'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot '.godot/test-results'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable not found.' }

function Invoke-Check([string]$Name, [string[]]$EngineArguments, [string]$SummaryTag = '') {
    $logPath = Join-Path $logRoot ($Name + '.log')
    & $GodotPath --headless --path $projectRoot @EngineArguments 2>&1 | Out-File -LiteralPath $logPath -Encoding UTF8
    $engineExit = $LASTEXITCODE
    $lines = Get-Content -LiteralPath $logPath -Encoding UTF8
    # Windows certificate-store access is unrelated to these local, offline tests.
    $errors = @($lines | Where-Object {
        $_ -match '^(SCRIPT ERROR:|ERROR:|\[FAIL\])' -and
        $_ -notmatch '^ERROR: Failed to read the root certificate store\.?$'
    })
    if ($engineExit -ne 0 -or $errors.Count -gt 0) {
        $errors | Write-Output
        throw "$Name failed (exit $engineExit). See $logPath"
    }
    if ($SummaryTag) {
        $summary = @($lines | Where-Object {
            $_ -match ('^\[' + [regex]::Escape($SummaryTag) + '\].*PASS = [1-9][0-9]*.*FAIL = 0$')
        })
        if ($summary.Count -ne 1) { throw "$Name did not finish its assertions. See $logPath" }
        $summary | Write-Output
    } else {
        Write-Output "$Name completed (exit 0)."
    }
}

# Import first: a fresh clone has no global class cache or imported assets.
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
Write-Output "Suite '$Suite' passed. Logs: $logRoot"
