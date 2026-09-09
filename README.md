# PSAppDeployToolkit.Sleep
[![CI](https://github.com/g0f/PSAppDeployToolkit.Sleep/actions/workflows/ci.yml/badge.svg)](https://github.com/g0f/PSAppDeployToolkit.Sleep/actions/workflows/ci.yml)

An extension to PSAppDeployToolkit that prevents Windows devices from sleeping during software deployments. I created this when we had end-of-life software that required immediate rollout with mandatory reboots — we couldn't disrupt production during work hours, so this let users just leave their PC on overnight and wake up to a completed installation.

## Installation

1. Download the module files:
   - `PSAppDeployToolkit.Sleep.psd1`
   - `PSAppDeployToolkit.Sleep.psm1`

2. Place them in a folder named `PSAppDeployToolkit.Sleep` within your PSADT script directory

3. The module will be automatically imported when your deployment script runs

## Usage

```powershell
# Start sleep prevention
Block-ADTSleep

# Your long-running deployment process here...
Show-ADTInstallationWelcome -CloseProcesses 'notepad' -CloseProcessesCountdown 18000  # 5 hours

# Stop sleep prevention when done
Unblock-ADTSleep
```

## Functions

### Block-ADTSleep

Prevents the device from sleeping.

```powershell
Block-ADTSleep [-KeepDisplayOn] [-Reason <String>]
```

| Parameter | Description |
| --- | --- |
| `-KeepDisplayOn` | Also prevents the display from turning off. By default the display is allowed to sleep while the device is kept awake. |
| `-Reason` | The reason recorded against the power request, shown by `powercfg /requests`. Defaults to `PSAppDeployToolkit: a deployment is in progress.` Only used when the request is first created. |

Calling `Block-ADTSleep` a second time to add `-KeepDisplayOn` upgrades the existing request rather than doing nothing.

### Unblock-ADTSleep

Restores normal power management behaviour.

```powershell
Unblock-ADTSleep
```

Safe to call when no request is active — it logs a warning rather than raising an error.

### Get-ADTSleepStatus

Returns the state of the request owned by this module.

```powershell
$status = Get-ADTSleepStatus
$status.IsActive         # $true if this module currently holds a power request
$status.ProcessId        # the process that owns the request
$status.SystemRequired   # $true if the device is being kept awake
$status.DisplayRequired  # $true if the display is being kept on
```

## Verification

To verify sleep prevention is active, run in an elevated command prompt:

```cmd
powercfg /requests
```

The request appears under `SYSTEM` (and `DISPLAY` when `-KeepDisplayOn` was used), attributed to the PowerShell process along with the reason string:

```
SYSTEM:
[PROCESS] \Device\HarddiskVolume3\...\powershell.exe
PSAppDeployToolkit: a deployment is in progress.
```

## Logging

The module writes one line per state change and nothing else. A complete deployment looks like this:

```
[Install] :: Module [PSAppDeployToolkit.Sleep] imported successfully.   PSAppDeployToolkit.Sleep.psm1
[Install] :: Sleep prevention activated.                               Block-ADTSleep
[Install] :: Sleep prevention deactivated.                             Unblock-ADTSleep
```

`Get-ADTSleepStatus` is a read rather than a state change, so it logs with `-DebugMessage` and stays out of the log unless the toolkit's `LogDebugMessage` config option is enabled. Warnings (`already active`, `not currently active`) and failures are always logged.

## Compatibility

- **Windows versions**: Windows 10, Windows 11, Windows Server 2016 and later
- **Architecture**: x86, x64, ARM64
- **PowerShell**: 5.1.14393 or later
- **PSADT**: 4.x (tested with 4.1.3 and 4.1.8)

## Technical details

The module uses the Windows power availability request API:

- `PowerCreateRequest` — creates a request object carrying a human-readable reason string
- `PowerSetRequest` with `PowerRequestSystemRequired` — prevents the device from sleeping
- `PowerSetRequest` with `PowerRequestDisplayRequired` — prevents the display from turning off (when `-KeepDisplayOn` is used)
- `PowerClearRequest` / `CloseHandle` — releases the request

### Request lifetime

The request is owned by the **process** running your PSADT script. It is released when:

- `Unblock-ADTSleep` is called;
- the module is removed with `Remove-Module`; or
- the process exits — Windows releases process-owned power requests automatically.

Calling `Unblock-ADTSleep` explicitly is still recommended, for clean logging and for immediate restoration of normal power management.

> **Note:** versions before 2.0.0 used `SetThreadExecutionState`, which binds the request to the *thread* that made the call rather than the process. That worked in practice only because the PowerShell console host reuses its pipeline thread. The current API is process-scoped, so it no longer depends on that behaviour.

## Licence

MIT — see [LICENSE](LICENSE).
