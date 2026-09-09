#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for PSAppDeployToolkit.Sleep.

.DESCRIPTION
    These tests exercise the module without requiring PSAppDeployToolkit to be installed. The PSADT
    functions the module depends on (Write-ADTLogEntry, Initialize-ADTFunction, Complete-ADTFunction
    and Invoke-ADTFunctionErrorHandler) are stubbed into the global scope, which is where a module
    resolves commands it cannot find locally.

    Run with: Invoke-Pester -Path .\tests\PSAppDeployToolkit.Sleep.Tests.ps1
#>

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The stubs and their backing log must live in the global scope, as that is where an imported module resolves commands it cannot find locally.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'The stubs deliberately mirror the real PSAppDeployToolkit parameter signatures; not every parameter is exercised.')]
param
(
)

BeforeAll {
    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'PSAppDeployToolkit.Sleep\PSAppDeployToolkit.Sleep.psm1'

    # Stub the PSADT functions the module calls, so the tests can run standalone. These must be defined
    # in the global scope: a module resolves unknown commands against global scope, not the caller's.
    $global:ADTSleepTestLog = [System.Collections.Generic.List[PSObject]]::new()

    function global:Write-ADTLogEntry
    {
        param ($Message, $Severity, $Source, $ScriptSection, [switch]$DebugMessage)
        $global:ADTSleepTestLog.Add([PSCustomObject]@{ Message = $Message; Severity = "$Severity"; IsDebug = [bool]$DebugMessage })
    }
    function global:Initialize-ADTFunction
    {
        param ($Cmdlet, $SessionState)
    }
    function global:Complete-ADTFunction
    {
        param ($Cmdlet)
    }
    function global:Invoke-ADTFunctionErrorHandler
    {
        param ($Cmdlet, $SessionState, $ErrorRecord)
        throw $ErrorRecord
    }

    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    Get-Module PSAppDeployToolkit.Sleep | Remove-Module -Force
    Remove-Item -Path function:global:Write-ADTLogEntry, function:global:Initialize-ADTFunction, function:global:Complete-ADTFunction, function:global:Invoke-ADTFunctionErrorHandler -ErrorAction SilentlyContinue
    Remove-Variable -Name ADTSleepTestLog -Scope Global -ErrorAction SilentlyContinue
}

Describe 'PSAppDeployToolkit.Sleep' {

    BeforeEach {
        $global:ADTSleepTestLog.Clear()
    }

    AfterEach {
        # Ensure no request leaks between tests.
        if ((Get-ADTSleepStatus).IsActive)
        {
            Unblock-ADTSleep
        }
    }

    Context 'Block-ADTSleep' {

        It 'reports inactive before any request is made' {
            $status = Get-ADTSleepStatus
            $status.IsActive | Should -BeFalse
            $status.SystemRequired | Should -BeFalse
            $status.DisplayRequired | Should -BeFalse
        }

        It 'activates a system request' {
            Block-ADTSleep
            $status = Get-ADTSleepStatus
            $status.IsActive | Should -BeTrue
            $status.SystemRequired | Should -BeTrue
            $status.DisplayRequired | Should -BeFalse
        }

        It 'activates a display request when -KeepDisplayOn is supplied' {
            Block-ADTSleep -KeepDisplayOn
            (Get-ADTSleepStatus).DisplayRequired | Should -BeTrue
        }

        It 'warns and does nothing when already active with the same request types' {
            Block-ADTSleep
            $global:ADTSleepTestLog.Clear()
            Block-ADTSleep
            ($global:ADTSleepTestLog | Where-Object { $_.Severity -eq 'Warning' }).Message | Should -Match 'already active'
        }

        It 'upgrades an existing request when -KeepDisplayOn is added later' {
            Block-ADTSleep
            (Get-ADTSleepStatus).DisplayRequired | Should -BeFalse
            Block-ADTSleep -KeepDisplayOn
            (Get-ADTSleepStatus).DisplayRequired | Should -BeTrue
        }

        It 'reports the owning process id' {
            Block-ADTSleep
            (Get-ADTSleepStatus).ProcessId | Should -Be $PID
        }
    }

    Context 'Unblock-ADTSleep' {

        It 'clears an active request' {
            Block-ADTSleep -KeepDisplayOn
            Unblock-ADTSleep
            $status = Get-ADTSleepStatus
            $status.IsActive | Should -BeFalse
            $status.SystemRequired | Should -BeFalse
            $status.DisplayRequired | Should -BeFalse
        }

        It 'warns rather than throwing when no request is active' {
            { Unblock-ADTSleep } | Should -Not -Throw
            ($global:ADTSleepTestLog | Where-Object { $_.Severity -eq 'Warning' }).Message | Should -Match 'not currently active'
        }

        It 'is safe to call twice in a row' {
            Block-ADTSleep
            Unblock-ADTSleep
            { Unblock-ADTSleep } | Should -Not -Throw
        }
    }

    Context 'Get-ADTSleepStatus' {

        It 'returns an object with the documented type name' {
            (Get-ADTSleepStatus).PSObject.TypeNames | Should -Contain 'PSADT.Sleep.SleepStatus'
        }

        It 'does not write to the log at normal verbosity' {
            $null = Get-ADTSleepStatus
            @($global:ADTSleepTestLog | Where-Object { -not $_.IsDebug }) | Should -BeNullOrEmpty
        }
    }

    Context 'Log verbosity' {

        It 'writes exactly one line per state change over a full cycle' {
            Block-ADTSleep
            Unblock-ADTSleep
            $lines = @($global:ADTSleepTestLog | Where-Object { -not $_.IsDebug })
            $lines.Count | Should -Be 2
            $lines[0].Message | Should -BeExactly 'Sleep prevention activated.'
            $lines[1].Message | Should -BeExactly 'Sleep prevention deactivated.'
        }

        It 'only mentions the display when the display is actually being held on' {
            Block-ADTSleep -KeepDisplayOn
            @($global:ADTSleepTestLog)[-1].Message | Should -BeExactly 'Sleep prevention activated (display kept on).'
        }

        It 'reports an upgrade rather than a second activation' {
            Block-ADTSleep
            $global:ADTSleepTestLog.Clear()
            Block-ADTSleep -KeepDisplayOn
            @($global:ADTSleepTestLog)[-1].Message | Should -BeExactly 'Sleep prevention updated (display kept on).'
        }
    }

    Context 'Module surface' {

        It 'exports exactly the three documented functions' {
            $exported = (Get-Module PSAppDeployToolkit.Sleep).ExportedFunctions.Keys | Sort-Object
            $exported | Should -Be @('Block-ADTSleep', 'Get-ADTSleepStatus', 'Unblock-ADTSleep')
        }

        It 'has help for every parameter on every exported function' {
            foreach ($name in (Get-Module PSAppDeployToolkit.Sleep).ExportedFunctions.Keys)
            {
                $help = Get-Help $name
                $documented = @($help.parameters.parameter.name)
                $declared = (Get-Command $name).Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }
                foreach ($parameter in $declared)
                {
                    $documented | Should -Contain $parameter -Because "$name -$parameter should be documented"
                }
            }
        }
    }
}
