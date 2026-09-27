# Installs windows-clamshell: copies clamshell-watcher.ps1 to Program Files and registers
# a SYSTEM startup task that runs it. See README.md for what the watcher does.
# Works from a local clone or straight from the web:
#   irm https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main/install.ps1 | iex

$repoRaw  = 'https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main'
$taskName = 'windows-clamshell'
$dest     = "$env:ProgramFiles\windows-clamshell"
$data     = "$env:ProgramData\windows-clamshell"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting administrator rights...'
    $arg = if ($PSCommandPath) { "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" }
           else { "-NoProfile -ExecutionPolicy Bypass -Command `"irm $repoRaw/install.ps1 | iex`"" }
    Start-Process powershell -Verb RunAs -Wait -ArgumentList $arg
    return
}

New-Item -ItemType Directory -Force $dest, $data | Out-Null

# Save the original lid close action once so uninstall can restore it.
$backup = "$data\lid-action-backup.txt"
if (-not (Test-Path $backup)) {
    $q = powercfg /qh SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936
    $vals = $q | Select-String '0x[0-9a-fA-F]{8}' | ForEach-Object { [Convert]::ToInt32($_.Matches[0].Value, 16) }
    if ($vals.Count -ge 2) { "$($vals[-2]) $($vals[-1])" | Set-Content $backup }
}

# Stop and clean up any previous version (including the old LidHello name).
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName 'LidHello' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'LidHello' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramFiles\LidHello", "$env:ProgramData\LidHello", "$dest\hello-watcher.ps1" -Recurse -Force -ErrorAction SilentlyContinue

$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'clamshell-watcher.ps1' }
if ($local -and (Test-Path $local)) { Copy-Item $local $dest -Force }
else { Invoke-RestMethod "$repoRaw/clamshell-watcher.ps1" -OutFile "$dest\clamshell-watcher.ps1" }

$action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\clamshell-watcher.ps1`""
$trigger  = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

$cams = Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue | Where-Object FriendlyName -match '\bIR\b'
if ($cams) { Write-Host "IR camera(s) managed: $($cams.FriendlyName -join ', ')" }
else { Write-Host 'No IR camera found (no Camera-class device with "IR" in its name); the Windows Hello part will do nothing.' -ForegroundColor Yellow }
Write-Host "windows-clamshell installed and running. Log: $data\clamshell.log" -ForegroundColor Green
if ($PSCommandPath) { Read-Host 'Press Enter to close' }
