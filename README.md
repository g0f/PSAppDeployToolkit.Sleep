
# PSAppDeployToolkit.Sleep

An extension to PSAppDeployToolkit that prevents Windows systems from sleeping during software deployments. I created this when we had end-of-life software that required immediate rollout with mandatory reboots - couldn't disrupt production during work hours, so this let users just leave their PC on overnight and wake up to a completed installation.

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
Prevents the system from going to sleep.

```powershell
Block-ADTSleep [-WriteLog <Boolean>] [-KeepDisplayOn]
```

### Unblock-ADTSleep
Restores normal power management behavior.

```powershell
Unblock-ADTSleep [-WriteLog <Boolean>]
```

### Get-ADTSleepStatus
Returns current sleep prevention status.

```powershell
$status = Get-ADTSleepStatus
Write-Host "Sleep blocked: $($status.IsActive)"
Write-Host "Process ID: $($status.ProcessId)"
```

## Verification

To verify sleep prevention is active, run in an elevated command prompt:

```cmd
powercfg /requests
```

You should see your PowerShell process listed under "EXECUTION" requests.

## Compatibility

- **Windows Versions**:  10, 11 (In theory XP, Vista, 7, and 8 aswell, but untested)
- **Architecture**: x86, x64
- **PowerShell**: 5.1+
- **PSADT**: 4.x (tested with 4.1.3)

## Technical Details

The module uses the Windows `SetThreadExecutionState` API with these flags:
- `ES_CONTINUOUS` - Maintains state until explicitly cleared
- `ES_SYSTEM_REQUIRED` - Prevents system sleep
- `ES_DISPLAY_REQUIRED` - Prevents display sleep (when KeepDisplayOn is used)

 ### Process-Bound Termination
  Sleep prevention is tied to the PowerShell process running your PSADT script. When the deployment completes and the process ends, Windows automatically clears the sleep prevention state - no manual cleanup required. However, calling Unblock-ADTSleep explicitly is still recommended for clean logging and immediate restoration of normal power management.
