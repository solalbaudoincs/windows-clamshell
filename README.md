# windows-clamshell

Makes a Windows laptop work properly with the lid closed on an external monitor ("clamshell mode"). It's what macOS does out of the box.

- **Closing the lid only keeps the laptop awake when it's docked.** With an external monitor connected, closing the lid does nothing. Without one, closing the lid puts the laptop to sleep, as usual. If you unplug the monitor while the lid is already closed, the laptop hibernates.
- **Windows Hello face sign-in is turned off while the lid is closed.** Otherwise Windows keeps trying the IR camera behind the closed lid, and you wait for a face scan that can't work. With it off, Windows goes straight to your PIN (or an external Hello camera). Face sign-in comes back as soon as you open the lid.
- **The power mode follows where you are:**

  | Situation | Power mode |
  |---|---|
  | Docked | Best performance |
  | Undocked, plugged in | Balanced |
  | Undocked, on battery | Best power efficiency |

  The mode only changes when you dock, undock or plug in, so if you pick a different mode yourself, it stays until the next change.

## Install

In PowerShell, run:

```powershell
irm https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main/install.ps1 | iex
```

Or clone or download this repo and double-click `install.cmd`.

Either way, you'll get a UAC prompt, because turning a device on or off needs administrator rights.

## Uninstall

```powershell
irm https://raw.githubusercontent.com/solalbaudoincs/windows-clamshell/main/uninstall.ps1 | iex
```

Or double-click `uninstall.cmd`. Uninstalling turns the IR camera back on and restores your original lid close setting. The power mode stays as it was last set.

## How it works

A scheduled task named `windows-clamshell` starts `clamshell-watcher.ps1` at boot. It runs as SYSTEM, hidden, and every change it makes is logged to `C:\ProgramData\windows-clamshell\clamshell.log`.

- **Lid:** the watcher registers for Windows' lid switch notification (`GUID_LIDSWITCH_STATE_CHANGE`). When the lid closes, it disables every device in the Camera class with `IR` in its name, and it enables them again when the lid opens. Your regular webcam is not touched.
- **Docking:** every 3 seconds, the watcher checks which monitors are connected. Any monitor other than the built-in panel counts as docked. When that changes, it sets the power plan's *Lid close action* to *Do nothing* (docked) or *Sleep* (undocked), and switches the power mode.
- **Unplugging with the lid closed:** Windows only applies the lid action at the moment the lid closes, so the watcher handles this case itself. After about 9 seconds without an external monitor, it hibernates. Hibernate is used because Modern Standby sleep can't be started from a background service.

Your original lid close action is saved to `C:\ProgramData\windows-clamshell\lid-action-backup.txt` so uninstall can put it back.

## Caveats

- Some monitors disconnect when they go into standby. With one of those, the laptop can hibernate when the monitor sleeps while the lid is closed.
- The Windows Hello part needs an IR camera whose name contains `IR`, for example `LGE IR-FHD Camera` or `Integrated IR Camera`. To check yours:

  ```powershell
  Get-PnpDevice -Class Camera | Select Status, FriendlyName
  ```

## Requirements

Windows 10 or 11, with Windows PowerShell 5.1 (built in). Power modes need Windows 11 or a recent Windows 10.

Tested on an LG gram 16Z90S running Windows 11 25H2.

## License

MIT
