# Uninstalls windows-clamshell: removes the Hello watcher, re-enables the IR camera,
# and restores the original lid close action.

$taskName = 'windows-clamshell'
$data     = "$env:ProgramData\windows-clamshell"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting administrator rights...'
    $arg = if ($PSCommandPath) { "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" }
           else { "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main/uninstall.ps1 | iex`"" }
    Start-Process powershell -Verb RunAs -Wait -ArgumentList $arg
    return
}

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue | Where-Object FriendlyName -match '\bIR\b' |
    ForEach-Object { Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue }
Write-Host 'Windows Hello watcher removed, IR camera re-enabled.'

$backup = "$data\lid-action-backup.txt"
if (Test-Path $backup) {
    $ac, $dc = (Get-Content $backup).Split(' ')
    $SUB = '4f971e89-eebd-4455-a8de-9e59040e7347'; $LID = '5ca83367-6e45-459f-a27b-476b1d01c936'
    powercfg /setacvalueindex SCHEME_CURRENT $SUB $LID $ac
    powercfg /setdcvalueindex SCHEME_CURRENT $SUB $LID $dc
    powercfg /setactive SCHEME_CURRENT
    Write-Host 'Original lid close action restored.'
}

Remove-Item "$env:ProgramFiles\windows-clamshell", $data -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'windows-clamshell uninstalled.' -ForegroundColor Green
if ($PSCommandPath) { Read-Host 'Press Enter to close' }
