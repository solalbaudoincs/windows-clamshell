# windows-clamshell

Makes a Windows laptop work properly with the lid closed on an external monitor ("clamshell mode").

- **Closing the lid doesn't put the laptop to sleep** while it's plugged in.
- **Windows Hello face sign-in is turned off while the lid is closed.** Otherwise Windows keeps trying the IR camera behind the closed lid, and you wait for a face scan that can't work. With it off, Windows goes straight to your PIN (or an external Hello camera). Face sign-in comes back as soon as you open the lid.

## Install

In PowerShell, run:

```powershell
irm https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main/install.ps1 | iex
```

Or clone or download this repo and double-click `install.cmd`.

Either way, you'll get a UAC prompt, because turning a device on or off needs administrator rights.

By default, the laptop still sleeps when you close the lid on battery. To keep it awake on battery too, run `install.ps1 -OnBattery` from a local clone.

## Uninstall

```powershell
irm https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main/uninstall.ps1 | iex
```

Or double-click `uninstall.cmd`. Uninstalling turns the IR camera back on and restores your original lid close setting.

## How it works

**No sleep on lid close.** The installer sets the current power plan's *Lid close action* to *Do nothing*, using `powercfg`. Your previous values are saved to `C:\ProgramData\windows-clamshell\lid-action-backup.txt` so uninstall can put them back.

**Windows Hello.** A scheduled task named `windows-clamshell` starts `hello-watcher.ps1` at boot. It runs as SYSTEM, hidden. The script:

- registers for Windows' lid switch notification (`GUID_LIDSWITCH_STATE_CHANGE`), so it reacts to the real lid state, with or without an external monitor, and doesn't poll.
- disables every device in the Camera class with `IR` in its name when the lid closes, and enables them again when it opens. Your regular webcam is not touched.
- logs every change to `C:\ProgramData\windows-clamshell\hello-watcher.log`.

## Requirements

- Windows 10 or 11, with Windows PowerShell 5.1 (built in).
- For the Hello part: an IR camera whose name contains `IR`, for example `LGE IR-FHD Camera` or `Integrated IR Camera`. To check yours:

  ```powershell
  Get-PnpDevice -Class Camera | Select Status, FriendlyName
  ```

Tested on an LG gram 16Z90S running Windows 11 25H2.

## License

MIT
