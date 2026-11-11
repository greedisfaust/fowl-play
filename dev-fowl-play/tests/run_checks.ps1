param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path ([IO.Path]::GetTempPath()) ('fowl-play-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logPath | Out-Null

function Start-Check([string]$Name, [string]$Arguments) {
    $checkProcess = Start-Process -FilePath $GodotPath -ArgumentList "--headless --path `"$projectPath`" $Arguments" `
        -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logPath "$Name.log") `
        -RedirectStandardError (Join-Path $logPath "$Name.err") -PassThru
    # Retain the native handle so Windows PowerShell keeps the exit status.
    $null = $checkProcess.Handle
    return $checkProcess
}

function Complete-Check([Diagnostics.Process]$Process, [string]$Name) {
    if (-not $Process.WaitForExit(30000)) {
        $Process.Kill()
        throw "$Name exceeded 30 seconds. Logs: $logPath"
    }
    $Process.WaitForExit()
    $output = (Get-Content (Join-Path $logPath "$Name.log"), (Join-Path $logPath "$Name.err")) -join "`n"
    Write-Output $output
    # Godot may return zero even when a script fails to parse.
    if ($Process.ExitCode -ne 0 -or $output -match '(?m)(SCRIPT ERROR:|ERROR:)') {
        throw "$Name failed. Logs: $logPath"
    }
}

$import = Start-Check 'import' '--editor --import --quit'
Complete-Check $import 'import'
$rules = Start-Check 'rules' 'res://tests/test_cluckjack.tscn'
Complete-Check $rules 'rules'
$poker = Start-Check 'poker' 'res://tests/test_poker.tscn'
Complete-Check $poker 'poker'
$pokerTable = Start-Check 'poker-table' 'res://tests/test_poker_table.tscn'
Complete-Check $pokerTable 'poker-table'
$house = Start-Check 'house' 'res://tests/test_house.tscn'
Complete-Check $house 'house'
$smoke = Start-Check 'smoke' '--quit-after 120'
Complete-Check $smoke 'smoke'
$hostCheck = Start-Check 'host' 'res://tests/test_cluckjack_network.tscn -- --host'
$clientCheck = Start-Check 'client' 'res://tests/test_cluckjack_network.tscn -- --client'
# Always collect both owned processes before reporting failure.
$networkErrors = @()
foreach ($entry in @(@{ Process = $hostCheck; Name = 'host' }, @{ Process = $clientCheck; Name = 'client' })) {
    try { Complete-Check $entry.Process $entry.Name } catch { $networkErrors += $_ }
}
if ($networkErrors.Count) { throw ($networkErrors -join "`n") }
$physicsHost = Start-Check 'physics-host' 'res://tests/test_house_network.tscn -- --host'
$physicsClient = Start-Check 'physics-client' 'res://tests/test_house_network.tscn -- --client'
$physicsErrors = @()
foreach ($entry in @(@{ Process = $physicsHost; Name = 'physics-host' }, @{ Process = $physicsClient; Name = 'physics-client' })) {
    try { Complete-Check $entry.Process $entry.Name } catch { $physicsErrors += $_ }
}
if ($physicsErrors.Count) { throw ($physicsErrors -join "`n") }
Write-Output "All checks passed. Logs: $logPath"
