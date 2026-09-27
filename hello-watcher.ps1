# Disables the Windows Hello IR camera while the laptop lid is closed and re-enables it
# when the lid opens. Listens for the real lid switch (GUID_LIDSWITCH_STATE_CHANGE), so it
# works with or without an external monitor. Runs as SYSTEM via the "windows-clamshell" scheduled task.

$log = "$env:ProgramData\windows-clamshell\hello-watcher.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Log($m) { "$(Get-Date -Format s)  $m" | Add-Content $log }

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class LidWatcher : NativeWindow {
    [DllImport("user32.dll")]
    static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid powerSettingGuid, int flags);

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

$watcher = New-Object LidWatcher
$watcher.add_LidChanged({
    param([bool]$lidOpen)
    $cams = Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue | Where-Object FriendlyName -match '\bIR\b'
    foreach ($cam in $cams) {
        try {
            if ($lidOpen) { Enable-PnpDevice  -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction Stop }
            else          { Disable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction Stop }
            Log "lidOpen=$lidOpen -> $(if ($lidOpen) {'enabled'} else {'disabled'}) $($cam.FriendlyName)"
        } catch { Log "error: $_" }
    }
})
Log 'watcher started'
[System.Windows.Forms.Application]::Run()
