<#

.SYNOPSIS
PSAppDeployToolkit.Sleep - Provides sleep prevention functionality for PSAppDeployToolkit deployments.

.DESCRIPTION
This module provides sleep prevention functions to keep a device awake for the duration of a deployment.

It uses the Windows power availability request API (PowerCreateRequest/PowerSetRequest), which registers
the request against the current process and surfaces a human-readable reason in 'powercfg /requests'.

This module is imported by the Invoke-AppDeployToolkit.ps1 script which is used when installing or uninstalling an application.

.LINK
https://psappdeploytoolkit.com

#>

##*===============================================
##* MARK: MODULE GLOBAL SETUP
##*===============================================

# Set strict error handling across entire module.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 3

# Handle returned by PowerCreateRequest, and the request types currently set against it.
# These are the module's single source of truth for whether a request is outstanding.
$Script:ADTSleepRequest = [System.IntPtr]::Zero
$Script:ADTSleepRequestTypes = [System.Collections.Generic.List[System.Int32]]::new()

# POWER_REQUEST_TYPE values. Only the two this module needs are declared here.
$Script:ADTPowerRequestDisplayRequired = 0
$Script:ADTPowerRequestSystemRequired = 1


##*===============================================
##* MARK: PRIVATE FUNCTIONS
##*===============================================

function Initialize-ADTSleepNativeMethod
{
    <#
    .SYNOPSIS
        Ensures the native method definitions required by this module are available.

    .DESCRIPTION
        Compiles the PSADT.Sleep.NativeMethods type on first use only. Compilation is deferred until a
        caller actually needs it so that merely importing the module cannot fail on systems where
        on-the-fly C# compilation is unavailable.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Initialize-ADTSleepNativeMethod

        Defines the PSADT.Sleep.NativeMethods type if it is not already present.
    #>

    [CmdletBinding()]
    param
    (
    )

    # Nothing to do if the type is already present in this session.
    if ('PSADT.Sleep.NativeMethods' -as [System.Type])
    {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PSADT.Sleep
{
    public static class NativeMethods
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct POWER_REQUEST_CONTEXT
        {
            public uint Version;
            public uint Flags;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string SimpleReasonString;
        }

        public const uint POWER_REQUEST_CONTEXT_VERSION = 0;
        public const uint POWER_REQUEST_CONTEXT_SIMPLE_STRING = 0x1;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr PowerCreateRequest(ref POWER_REQUEST_CONTEXT Context);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PowerSetRequest(IntPtr PowerRequest, int RequestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PowerClearRequest(IntPtr PowerRequest, int RequestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);
    }
}
'@
}


##*===============================================
##* MARK: FUNCTION LISTINGS
##*===============================================

function Block-ADTSleep
{
    <#
    .SYNOPSIS
        Prevents the device from sleeping for the duration of the deployment.

    .DESCRIPTION
        Registers a power availability request against the current process so that Windows will not put
        the device to sleep while a deployment is running. The request is owned by the process, so it is
        released automatically if the process exits without calling Unblock-ADTSleep.

        Calling this function again to add the display request to an existing system request upgrades the
        outstanding request rather than failing.

    .PARAMETER KeepDisplayOn
        Additionally prevents the display from turning off. By default the display is allowed to sleep
        while the system is kept awake.

    .PARAMETER Reason
        The reason recorded against the power request. This is shown by 'powercfg /requests' and is only
        used when the request is first created.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Block-ADTSleep

        Prevents the device from sleeping, allowing the display to turn off as normal.

    .EXAMPLE
        Block-ADTSleep -KeepDisplayOn

        Prevents the device from sleeping and keeps the display on.

    .EXAMPLE
        Block-ADTSleep -Reason 'Contoso LOB app upgrade in progress.'

        Prevents the device from sleeping, recording a custom reason against the power request.

    .NOTES
        The request is released when Unblock-ADTSleep is called, when the module is removed, or when the
        owning process exits.

    .LINK
        https://psappdeploytoolkit.com
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$KeepDisplayOn,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$Reason = 'PSAppDeployToolkit: a deployment is in progress.'
    )

    begin
    {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                Initialize-ADTSleepNativeMethod
                $wasActive = $Script:ADTSleepRequest -ne [System.IntPtr]::Zero

                # Determine which request types this invocation needs.
                $required = $(
                    $Script:ADTPowerRequestSystemRequired
                    if ($KeepDisplayOn)
                    {
                        $Script:ADTPowerRequestDisplayRequired
                    }
                )

                # Create the underlying power request the first time we need one.
                if ($Script:ADTSleepRequest -eq [System.IntPtr]::Zero)
                {
                    $context = [PSADT.Sleep.NativeMethods+POWER_REQUEST_CONTEXT]::new()
                    $context.Version = [PSADT.Sleep.NativeMethods]::POWER_REQUEST_CONTEXT_VERSION
                    $context.Flags = [PSADT.Sleep.NativeMethods]::POWER_REQUEST_CONTEXT_SIMPLE_STRING
                    $context.SimpleReasonString = $Reason

                    # PowerCreateRequest returns INVALID_HANDLE_VALUE, not NULL, on failure.
                    $handle = [PSADT.Sleep.NativeMethods]::PowerCreateRequest([ref]$context)
                    if (($handle -eq [System.IntPtr]::Zero) -or ($handle -eq [System.IntPtr]::new(-1)))
                    {
                        throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error(), 'Failed to create the power availability request.')
                    }
                    $Script:ADTSleepRequest = $handle
                }

                # Apply only the request types that aren't already set.
                $applied = foreach ($type in $required)
                {
                    if ($Script:ADTSleepRequestTypes.Contains($type))
                    {
                        continue
                    }
                    if (![PSADT.Sleep.NativeMethods]::PowerSetRequest($Script:ADTSleepRequest, $type))
                    {
                        throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error(), "Failed to set power request type [$type].")
                    }
                    $Script:ADTSleepRequestTypes.Add($type)
                    $type
                }

                # Advise the caller if there was nothing left to do.
                if ($null -eq $applied)
                {
                    Write-ADTLogEntry -Message 'Sleep prevention is already active.' -Severity Warning
                    return
                }

                # One line per state change, and only mention the display when it's actually being held on.
                $displayNote = if ($Script:ADTSleepRequestTypes.Contains($Script:ADTPowerRequestDisplayRequired)) { ' (display kept on)' }
                Write-ADTLogEntry -Message "Sleep prevention $(if ($wasActive) { 'updated' } else { 'activated' })$displayNote."
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}

function Unblock-ADTSleep
{
    <#
    .SYNOPSIS
        Releases the power availability request created by Block-ADTSleep.

    .DESCRIPTION
        Clears every power request type set by Block-ADTSleep and releases the underlying handle,
        restoring the device's normal power management behaviour.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Unblock-ADTSleep

        Restores normal power management behaviour.

    .NOTES
        Safe to call when sleep prevention is not active; a warning is logged and no error is raised.

    .LINK
        https://psappdeploytoolkit.com
    #>

    [CmdletBinding()]
    param
    (
    )

    begin
    {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                if ($Script:ADTSleepRequest -eq [System.IntPtr]::Zero)
                {
                    Write-ADTLogEntry -Message 'Sleep prevention is not currently active.' -Severity Warning
                    return
                }

                try
                {
                    # Only clear types we actually set; clearing an unset type fails with ERROR_NOT_SUPPORTED.
                    foreach ($type in $Script:ADTSleepRequestTypes.ToArray())
                    {
                        if (![PSADT.Sleep.NativeMethods]::PowerClearRequest($Script:ADTSleepRequest, $type))
                        {
                            throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error(), "Failed to clear power request type [$type].")
                        }
                        [System.Void]$Script:ADTSleepRequestTypes.Remove($type)
                    }
                }
                finally
                {
                    # Never leak the handle, but only release it once every type has been cleared.
                    if ($Script:ADTSleepRequestTypes.Count -eq 0)
                    {
                        [System.Void][PSADT.Sleep.NativeMethods]::CloseHandle($Script:ADTSleepRequest)
                        $Script:ADTSleepRequest = [System.IntPtr]::Zero
                    }
                }

                Write-ADTLogEntry -Message 'Sleep prevention deactivated.'
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}

function Get-ADTSleepStatus
{
    <#
    .SYNOPSIS
        Gets the state of the power availability request owned by this module.

    .DESCRIPTION
        Returns whether this module currently holds a power availability request, and which request types
        are set against it.

    .INPUTS
        None

        You cannot pipe objects to this function.

    .OUTPUTS
        PSADT.Sleep.SleepStatus

        Returns an object with the following properties:
        - IsActive: whether this module currently holds a power availability request.
        - ProcessId: the process that owns the request.
        - SystemRequired: whether the device is being kept awake.
        - DisplayRequired: whether the display is being kept on.

    .EXAMPLE
        Get-ADTSleepStatus

        Returns the current sleep prevention state.

    .NOTES
        This reflects only the requests made by this module. To see every power request on the device,
        run 'powercfg /requests' from an elevated prompt.

    .LINK
        https://psappdeploytoolkit.com
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
    )

    begin
    {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process
    {
        try
        {
            try
            {
                $status = [PSCustomObject]@{
                    PSTypeName = 'PSADT.Sleep.SleepStatus'
                    IsActive = $Script:ADTSleepRequest -ne [System.IntPtr]::Zero
                    ProcessId = $PID
                    SystemRequired = $Script:ADTSleepRequestTypes.Contains($Script:ADTPowerRequestSystemRequired)
                    DisplayRequired = $Script:ADTSleepRequestTypes.Contains($Script:ADTPowerRequestDisplayRequired)
                }

                # This is a read, not a state change, so it stays out of the log unless debug logging is on.
                Write-ADTLogEntry -Message "Sleep prevention status: $(if ($status.IsActive) { 'active' } else { 'inactive' })." -DebugMessage
                return $status
            }
            catch
            {
                # Re-writing the ErrorRecord with Write-Error ensures the correct PositionMessage is used.
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            # Process the caught error, log it and throw depending on the specified ErrorAction.
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        # Finalize function.
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}


##*===============================================
##* MARK: SCRIPT BODY
##*===============================================

# Release any outstanding power request if the module is removed mid-session.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($Script:ADTSleepRequest -ne [System.IntPtr]::Zero)
    {
        foreach ($type in $Script:ADTSleepRequestTypes.ToArray())
        {
            [System.Void][PSADT.Sleep.NativeMethods]::PowerClearRequest($Script:ADTSleepRequest, $type)
        }
        [System.Void][PSADT.Sleep.NativeMethods]::CloseHandle($Script:ADTSleepRequest)
        $Script:ADTSleepRequest = [System.IntPtr]::Zero
        $Script:ADTSleepRequestTypes.Clear()
    }
}

# Export only the public functions, keeping the manifest as the single source of truth. Without this,
# importing the .psm1 directly would also expose this module's private helpers.
Export-ModuleMember -Function (Import-PowerShellDataFile -LiteralPath "$PSScriptRoot\PSAppDeployToolkit.Sleep.psd1").FunctionsToExport

# Announce successful importation of module.
Write-ADTLogEntry -Message "Module [$($MyInvocation.MyCommand.ScriptBlock.Module.Name)] imported successfully." -ScriptSection Initialization
