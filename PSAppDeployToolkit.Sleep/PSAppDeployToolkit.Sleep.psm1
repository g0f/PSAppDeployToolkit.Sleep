<#

.SYNOPSIS
PSAppDeployToolkit.Sleep - Provides sleep prevention functionality for PSAppDeployToolkit deployments.

.DESCRIPTION
This module provides sleep prevention functions to prevent systems from going to sleep.
It uses Windows API SetThreadExecutionState with zero external dependencies.

This module is imported by the Invoke-AppDeployToolkit.ps1 script which is used when installing or uninstalling an application.

#>

##*===============================================
##* MARK: MODULE GLOBAL SETUP
##*===============================================

# Set strict error handling across entire module.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Global variable to track sleep prevention state
$Script:ADTSleepBlocked = $false

##*===============================================
##* MARK: FUNCTION LISTINGS
##*===============================================

function Block-ADTSleep {
    <#
    .SYNOPSIS
        Activates sleep prevention for the current process.
    
    .DESCRIPTION
        Prevents the system from entering sleep mode during deployment processes.
        Uses Windows SetThreadExecutionState API with ES_CONTINUOUS, ES_SYSTEM_REQUIRED, 
        and ES_AWAYMODE_REQUIRED flags.
    
    .PARAMETER WriteLog
        Write function activity to the log file. Default is: $true.
    
    .EXAMPLE
        Block-ADTSleep
        Activates sleep prevention with default logging.
    
    .EXAMPLE  
        Block-ADTSleep -WriteLog $false
        Activates sleep prevention without writing to log.
    
    .NOTES
        - Sleep prevention will automatically end when the PowerShell process terminates
        - Can be manually stopped using Unblock-ADTSleep
        - Status can be verified with: powercfg /requests
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$WriteLog = $true
    )
    
    Begin {
        ## Get the name of this function and write header
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        
        if ($WriteLog) {
            Write-ADTLogEntry -Message "Function Start: ${CmdletName}" -Severity 1 -Source ${CmdletName}
        }
    }
    Process {
        try {
            # Check if sleep prevention is already active
            if ($Script:ADTSleepBlocked) {
                if ($WriteLog) {
                    Write-ADTLogEntry -Message "Sleep prevention is already active." -Severity 2 -Source ${CmdletName}
                }
                return
            }
            
            if ($WriteLog) {
                Write-ADTLogEntry -Message "Activating sleep prevention to prevent system sleep during deployment..." -Severity 1 -Source ${CmdletName}
            }
            
            # Define the Windows API SetThreadExecutionState function
            Add-Type -MemberDefinition '[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)] public static extern void SetThreadExecutionState(uint esFlags);' -Name System -Namespace Win32 -ErrorAction SilentlyContinue
            
            # Set execution state flags:
            # ES_CONTINUOUS (0x80000000) = 2147483648 - Informs system that state should remain in effect until next call
            # ES_SYSTEM_REQUIRED (0x00000001) = 1 - Forces system to be in working state by resetting system idle timer
            # ES_DISPLAY_REQUIRED (0x00000002) = 2 - Forces display to be on by resetting display idle timer
            
            if ($KeepDisplayOn) {
                # Keep both system and display active
                # ES_CONTINUOUS + ES_SYSTEM_REQUIRED + ES_DISPLAY_REQUIRED = 2147483648 + 1 + 2 = 2147483651
                $executionState = 2147483651
                if ($WriteLog) {
                    Write-ADTLogEntry -Message "Preventing system sleep and keeping display on..." -Severity 1 -Source ${CmdletName}
                }
            } else {
                # Keep system active, allow display to turn off
                # ES_CONTINUOUS + ES_SYSTEM_REQUIRED = 2147483648 + 1 = 2147483649
                $executionState = 2147483649
                if ($WriteLog) {
                    Write-ADTLogEntry -Message "Preventing system sleep, allowing display to turn off..." -Severity 1 -Source ${CmdletName}
                }
            }
            
            # Call the Windows API to prevent sleep
            [Win32.System]::SetThreadExecutionState($executionState)
            
            # Update tracking variable
            $Script:ADTSleepBlocked = $true
            
            if ($WriteLog) {
                Write-ADTLogEntry -Message "Sleep prevention activated successfully. System will not sleep until deployment completes." -Severity 1 -Source ${CmdletName}
                Write-ADTLogEntry -Message "Note: Sleep prevention status can be verified with command: powercfg /requests" -Severity 1 -Source ${CmdletName}
            }
        }
        catch {
            if ($WriteLog) {
                Write-ADTLogEntry -Message "Failed to activate sleep prevention. Error: $($_.Exception.Message)" -Severity 3 -Source ${CmdletName}
            }
            Write-ADTLogEntry -Message "Failed to activate sleep prevention. Error: $($_.Exception.Message)" -Severity 3 -Source ${CmdletName} -WriteHost $false
            throw "Failed to activate sleep prevention: $($_.Exception.Message)"
        }
    }
    End {
        if ($WriteLog) {
            Write-ADTLogEntry -Message "Function End: ${CmdletName}" -Severity 1 -Source ${CmdletName}
        }
    }
}

function Unblock-ADTSleep {
    <#
    .SYNOPSIS
        Deactivates sleep prevention and restores normal power management.
    
    .DESCRIPTION
        Restores the system's normal power management behavior by clearing the 
        execution state flags set by Block-ADTSleep.
    
    .PARAMETER WriteLog
        Write function activity to the log file. Default is: $true.
    
    .EXAMPLE
        Unblock-ADTSleep
        Deactivates sleep prevention with default logging.
    
    .EXAMPLE
        Unblock-ADTSleep -WriteLog $false  
        Deactivates sleep prevention without writing to log.
    
    .NOTES
        - Should be called at the end of deployment processes that used Block-ADTSleep
        - Sleep prevention will also automatically end when PowerShell process terminates
        - Safe to call multiple times (will not cause errors if sleep prevention is not active)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$WriteLog = $true
    )
    
    Begin {
        ## Get the name of this function and write header
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        
        if ($WriteLog) {
            Write-ADTLogEntry -Message "Function Start: ${CmdletName}" -Severity 1 -Source ${CmdletName}
        }
    }
    Process {
        try {
            # Check if sleep prevention is active
            if (-not $Script:ADTSleepBlocked) {
                if ($WriteLog) {
                    Write-ADTLogEntry -Message "Sleep prevention is not currently active." -Severity 2 -Source ${CmdletName}
                }
                return
            }
            
            if ($WriteLog) {
                Write-ADTLogEntry -Message "Deactivating sleep prevention and restoring normal power management..." -Severity 1 -Source ${CmdletName}
            }
            
            # Ensure the Windows API type is available (may already be loaded from Start function)
            Add-Type -MemberDefinition '[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)] public static extern void SetThreadExecutionState(uint esFlags);' -Name System -Namespace Win32 -ErrorAction SilentlyContinue
            
            # Clear execution state by calling with ES_CONTINUOUS only
            # ES_CONTINUOUS (0x80000000) = 2147483648 - This clears previous settings and restores normal behavior
            $executionState = 2147483648
            
            # Call the Windows API to restore normal power management
            [Win32.System]::SetThreadExecutionState($executionState)
            
            # Update tracking variable
            $Script:ADTSleepBlocked = $false
            
            if ($WriteLog) {
                Write-ADTLogEntry -Message "Sleep prevention deactivated successfully. Normal power management restored." -Severity 1 -Source ${CmdletName}
            }
        }
        catch {
            if ($WriteLog) {
                Write-ADTLogEntry -Message "Failed to deactivate sleep prevention. Error: $($_.Exception.Message)" -Severity 3 -Source ${CmdletName}
            }
            Write-ADTLogEntry -Message "Failed to deactivate sleep prevention. Error: $($_.Exception.Message)" -Severity 3 -Source ${CmdletName} -WriteHost $false
            throw "Failed to deactivate sleep prevention: $($_.Exception.Message)"
        }
    }
    End {
        if ($WriteLog) {
            Write-ADTLogEntry -Message "Function End: ${CmdletName}" -Severity 1 -Source ${CmdletName}
        }
    }
}

function Get-ADTSleepStatus {
    <#
    .SYNOPSIS
        Gets the current status of sleep prevention.
    
    .DESCRIPTION
        Returns information about whether sleep prevention is currently active
        and provides instructions for verifying system power requests.
    
    .PARAMETER WriteLog
        Write function activity to the log file. Default is: $true.
    
    .EXAMPLE
        Get-ADTSleepStatus
        Returns the current sleep prevention status.
    
    .OUTPUTS
        PSCustomObject with properties:
        - IsActive: Boolean indicating if sleep prevention is active
        - ProcessId: Current PowerShell process ID
        - VerificationCommand: Command to verify power requests in system
    
    .NOTES
        Use 'powercfg /requests' in an elevated command prompt to see all active power requests
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$WriteLog = $true
    )
    
    Begin {
        ## Get the name of this function and write header
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        
        if ($WriteLog) {
            Write-ADTLogEntry -Message "Function Start: ${CmdletName}" -Severity 1 -Source ${CmdletName}
        }
    }
    Process {
        try {
            $status = [PSCustomObject]@{
                IsActive = $Script:ADTSleepBlocked
                ProcessId = $PID
                VerificationCommand = "powercfg /requests"
            }
            
            if ($WriteLog) {
                $statusMessage = if ($status.IsActive) { "Sleep prevention is ACTIVE" } else { "Sleep prevention is INACTIVE" }
                Write-ADTLogEntry -Message "$statusMessage for process ID $($status.ProcessId)" -Severity 1 -Source ${CmdletName}
                Write-ADTLogEntry -Message "To verify system power requests, run: $($status.VerificationCommand)" -Severity 1 -Source ${CmdletName}
            }
            
            return $status
        }
        catch {
            if ($WriteLog) {
                Write-ADTLogEntry -Message "Failed to get sleep prevention status. Error: $($_.Exception.Message)" -Severity 3 -Source ${CmdletName}
            }
            throw "Failed to get sleep prevention status: $($_.Exception.Message)"
        }
    }
    End {
        if ($WriteLog) {
            Write-ADTLogEntry -Message "Function End: ${CmdletName}" -Severity 1 -Source ${CmdletName}
        }
    }
}

##*===============================================
##* MARK: SCRIPT BODY
##*===============================================

# Announce successful importation of module.
Write-ADTLogEntry -Message "Module [$($MyInvocation.MyCommand.ScriptBlock.Module.Name)] imported successfully." -ScriptSection Initialization