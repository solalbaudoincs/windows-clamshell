# windows-clamshell watcher. Runs as SYSTEM via the "windows-clamshell" scheduled task.
#
#  - Lid closed  -> Windows Hello IR camera disabled; lid open -> re-enabled.
#  - Docked (external monitor connected) -> lid close does nothing; undocked -> lid close sleeps.
#  - Monitor unplugged while the lid is closed -> hibernate (Modern Standby can't be entered from a service).
#  - Power mode: docked -> Best performance; undocked -> Balanced on AC, Best power efficiency on battery.
#    Applied only when docking or power source changes, so manual changes stick until then.

$log = "$env:ProgramData\windows-clamshell\clamshell.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Log($m) { "$(Get-Date -Format s)  $m" | Add-Content $log }

$SUB_BUTTONS = '4f971e89-eebd-4455-a8de-9e59040e7347'
$LIDACTION   = '5ca83367-6e45-459f-a27b-476b1d01c936'
$Mode = @{
    Efficiency  = [guid]'961cc777-2547-4f9d-8174-7d86181b8a7a'
    Balanced    = [guid]'00000000-0000-0000-0000-000000000000'
    Performance = [guid]'ded574b5-45a0-4f42-8737-46345c09c238'
}
# Video output technologies that mean "built-in panel": INTERNAL, DISPLAYPORT_EMBEDDED, UDI_EMBEDDED
$internalVot = @(0x80000000, 11, 13)

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class LidWatcher : NativeWindow {
    [DllImport("user32.dll")]
    static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid powerSettingGuid, int flags);
    [DllImport("powrprof.dll")]
    public static extern uint PowerSetActiveOverlayScheme(Guid overlay);

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct POWERBROADCAST_SETTING { public Guid PowerSetting; public uint DataLength; public byte Data; }

    static Guid LidSwitch = new Guid("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3");
    const int WM_POWERBROADCAST = 0x218, PBT_POWERSETTINGCHANGE = 0x8013;

    public event Action<bool> LidChanged;

    public LidWatcher() {
        CreateHandle(new CreateParams());
        // Windows immediately sends the current lid state after registering.
        RegisterPowerSettingNotification(Handle, ref LidSwitch, 0);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_POWERBROADCAST && (int)m.WParam == PBT_POWERSETTINGCHANGE) {
            var s = (POWERBROADCAST_SETTING)Marshal.PtrToStructure(m.LParam, typeof(POWERBROADCAST_SETTING));
            if (s.PowerSetting == LidSwitch && LidChanged != null) LidChanged(s.Data != 0);
        }
        base.WndProc(ref m);
    }
}
'@

$state = @{ LidOpen = $null; Docked = $null; OnAC = $null; HibernateIn = 0 }

# --- Windows Hello: IR camera follows the lid --------------------------------------------
$watcher = New-Object LidWatcher
$watcher.add_LidChanged({
    param([bool]$lidOpen)
    $state.LidOpen = $lidOpen
    $cams = Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue | Where-Object FriendlyName -match '\bIR\b'
    foreach ($cam in $cams) {
        try {
            if ($lidOpen) { Enable-PnpDevice  -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction Stop }
            else          { Disable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction Stop }
            Log "lid $(if ($lidOpen) {'open -> enabled'} else {'closed -> disabled'}) $($cam.FriendlyName)"
        } catch { Log "error: $_" }
    }
})

# --- Docking: lid action, power mode, hibernate on unplug ---------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({
    # WMI occasionally returns nothing; treat that as "unknown" rather than "undocked".
    $monitors = @(Get-CimInstance -Namespace root\wmi WmiMonitorConnectionParams -ErrorAction SilentlyContinue)
    if ($monitors.Count -eq 0) { return }
    $docked = @($monitors | Where-Object { [uint32]$_.VideoOutputTechnology -notin $internalVot }).Count -gt 0
    $onAC   = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -ne 'Offline'

    if ($docked -ne $state.Docked) {
        $action = if ($docked) { 0 } else { 1 }   # 0 = do nothing, 1 = sleep
        powercfg /setacvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION $action
        powercfg /setdcvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION $action
        powercfg /setactive SCHEME_CURRENT
        Log "$(if ($docked) {'docked -> lid close does nothing'} else {'undocked -> lid close sleeps'})"

        # Unplugged the monitor with the lid shut: nothing is using the laptop any more.
        if (-not $docked -and $state.Docked -and $state.LidOpen -eq $false) { $state.HibernateIn = 3 }
    }

    # Wait a few ticks in case the monitor was only blinking, then hibernate.
    if ($state.HibernateIn) {
        if ($docked -or $state.LidOpen) { $state.HibernateIn = 0 }
        elseif (--$state.HibernateIn -eq 0) {
            Log 'monitor unplugged with lid closed -> hibernate'
            shutdown.exe /h
        }
    }

    if ($docked -ne $state.Docked -or $onAC -ne $state.OnAC) {
        $name = if ($docked) { 'Performance' } elseif ($onAC) { 'Balanced' } else { 'Efficiency' }
        [void][LidWatcher]::PowerSetActiveOverlayScheme($Mode[$name])
        Log "docked=$docked onAC=$onAC -> power mode $name"
    }
    $state.Docked = $docked
    $state.OnAC   = $onAC
})
$timer.Start()

Log 'watcher started'
[System.Windows.Forms.Application]::Run()
