# Installs windows-clamshell:
#  1. Lid close action = "Do nothing" while plugged in (battery behaviour is left alone unless -OnBattery).
#  2. Windows Hello IR camera is disabled while the lid is closed (SYSTEM startup task).
# Works from a local clone or straight from the web:
#   irm https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main/install.ps1 | iex
param([switch]$OnBattery)

$repoRaw  = 'https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main'
$taskName = 'windows-clamshell'
$dest     = "$env:ProgramFiles\windows-clamshell"
$data     = "$env:ProgramData\windows-clamshell"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting administrator rights...'
    $flags = if ($OnBattery) { ' -OnBattery' } else { '' }
    $arg = if ($PSCommandPath) { "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$flags" }
           else { "-NoProfile -ExecutionPolicy Bypass -Command `"& ([scriptblock]::Create((irm $repoRaw/install.ps1)))$flags`"" }
    Start-Process powershell -Verb RunAs -Wait -ArgumentList $arg
    return
}

New-Item -ItemType Directory -Force $dest, $data | Out-Null

# --- 1. Don't sleep when the lid closes -------------------------------------------------
$SUB = '4f971e89-eebd-4455-a8de-9e59040e7347'   # SUB_BUTTONS
$LID = '5ca83367-6e45-459f-a27b-476b1d01c936'   # LIDACTION
$backup = "$data\lid-action-backup.txt"
if (-not (Test-Path $backup)) {
    # Save the original AC/DC values once so uninstall can restore them.
    $q = powercfg /qh SCHEME_CURRENT $SUB $LID
    $vals = $q | Select-String '0x[0-9a-fA-F]{8}' | ForEach-Object { [Convert]::ToInt32($_.Matches[0].Value, 16) }
    if ($vals.Count -ge 2) { "$($vals[-2]) $($vals[-1])" | Set-Content $backup }
}
powercfg /setacvalueindex SCHEME_CURRENT $SUB $LID 0
if ($OnBattery) { powercfg /setdcvalueindex SCHEME_CURRENT $SUB $LID 0 }
powercfg /setactive SCHEME_CURRENT
Write-Host "Lid close action set to 'Do nothing' when plugged in$(if ($OnBattery) {' and on battery'})."

# --- 2. Windows Hello IR camera off while lid is closed -----------------------------------
foreach ($old in 'LidHello', $taskName) {   # stop any previous version
    Stop-ScheduledTask -TaskName $old -ErrorAction SilentlyContinue
}
Unregister-ScheduledTask -TaskName 'LidHello' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramFiles\LidHello", "$env:ProgramData\LidHello" -Recurse -Force -ErrorAction SilentlyContinue

$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'hello-watcher.ps1' }
if ($local -and (Test-Path $local)) { Copy-Item $local $dest -Force }
else { Invoke-RestMethod "$repoRaw/hello-watcher.ps1" -OutFile "$dest\hello-watcher.ps1" }

$action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\hello-watcher.ps1`""
$trigger  = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

$cams = Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue | Where-Object FriendlyName -match '\bIR\b'
if ($cams) { Write-Host "Windows Hello watcher running. IR camera(s) managed: $($cams.FriendlyName -join ', ')" }
else { Write-Host 'Watcher installed, but no IR camera was found (no Camera-class device with "IR" in its name).' -ForegroundColor Yellow }
Write-Host "Done. Log: $data\hello-watcher.log" -ForegroundColor Green
if ($PSCommandPath) { Read-Host 'Press Enter to close' }
