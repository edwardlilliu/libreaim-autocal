param([string]$Godot = 'godot')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testDataRoot = Join-Path $repoRoot '.godot\sensitivity-test-profile'
New-Item -ItemType Directory -Force $testDataRoot | Out-Null
$previousAppData = $env:APPDATA
try {
    # Keep synthetic profiles and scores separate from the player's real saves.
    $env:APPDATA = $testDataRoot
    & $Godot --headless --path $repoRoot --import
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    $testLog = Join-Path $testDataRoot 'sensitivity-tests.log'
    & $Godot --headless --path $repoRoot --script res://tests/sensitivity_calibration_test.gd --quit-after 1000 --log-file $testLog
    $engineExitCode = $LASTEXITCODE
    $logText = Get-Content -LiteralPath $testLog -Raw
    if ($engineExitCode -ne 0 -or $logText -notmatch 'SENSITIVITY TESTS: \d+ checks, 0 failures' -or $logText -match 'SCRIPT ERROR|FAIL:') {
        throw "Sensitivity tests did not pass. Read $testLog"
    }
} finally {
    $env:APPDATA = $previousAppData
}
