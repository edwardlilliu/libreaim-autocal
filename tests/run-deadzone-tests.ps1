param([string]$Godot = 'godot')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testDataRoot = Join-Path $repoRoot '.godot\deadzone-test-profile'
New-Item -ItemType Directory -Force $testDataRoot | Out-Null
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = $testDataRoot
    & $Godot --headless --path $repoRoot --import
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    foreach ($phase in @('gameplay', 'reload')) {
        $testLog = Join-Path $testDataRoot "deadzone-$phase.log"
        $engineArgs = @('--headless', '--path', $repoRoot, '--script', 'res://tests/deadzone_gameplay_test.gd', '--quit-after', '1000', '--log-file', $testLog)
        if ($phase -eq 'reload') { $engineArgs += @('--', '--verify-reload') }
        & $Godot @engineArgs
        $engineExitCode = $LASTEXITCODE
        $logText = Get-Content -LiteralPath $testLog -Raw
        $resultPattern = if ($phase -eq 'reload') { 'DEADZONE RELOAD TESTS: \d+ checks, 0 failures' } else { 'DEADZONE TESTS: \d+ checks, 0 failures' }
        if ($engineExitCode -ne 0 -or $logText -notmatch $resultPattern -or $logText -match 'SCRIPT ERROR|FAIL:') {
            throw "Deadzone $phase tests did not pass. Read $testLog"
        }
    }
} finally {
    $env:APPDATA = $previousAppData
}
