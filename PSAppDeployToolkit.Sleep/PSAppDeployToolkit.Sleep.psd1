#
# Module manifest for module 'PSAppDeployToolkit.Sleep'
#
# Generated on: 2025-09-08
#

@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'PSAppDeployToolkit.Sleep.psm1'

    # Version number of this module.
    ModuleVersion = '2.0.0'

    # Supported PSEditions
    # CompatiblePSEditions = @()

    # ID used to uniquely identify this module
    GUID = '41f8489f-8270-4993-b926-5140a631d00f'

    # Author of this module
    Author = 'Simon Enbom'

    # Company or vendor of this module
    CompanyName = 'enbom.eu'

    # Copyright statement for this module
    Copyright = '(c) 2025 Simon Enbom. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Sleep prevention functionality for PSAppDeployToolkit deployments. Keeps a device awake for the duration of a deployment using the Windows power availability request API.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1.14393.0'

    # Name of the Windows PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the Windows PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = '4.7.2.0'

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    #CLRVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ ModuleName = 'PSAppDeployToolkit'; GUID = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.0' }
    )

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @('Block-ADTSleep', 'Unblock-ADTSleep', 'Get-ADTSleepStatus')

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    FileList = @(
        'PSAppDeployToolkit.Sleep.psd1',
        'PSAppDeployToolkit.Sleep.psm1'
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('PSAppDeployToolkit', 'PSADT', 'Sleep', 'Power', 'Deployment', 'Intune', 'MECM', 'Windows')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/g0f/PSAppDeployToolkit.Sleep/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/g0f/PSAppDeployToolkit.Sleep/'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
## 2.0.0

### Breaking changes
- Removed the `-WriteLog` parameter from all functions. Logging now follows the standard PowerShell
  common parameters, consistent with PSAppDeployToolkit v4.
- `Get-ADTSleepStatus` no longer returns a `VerificationCommand` property. It now returns
  `SystemRequired` and `DisplayRequired` instead.

### Changed
- Replaced `SetThreadExecutionState` with the `PowerCreateRequest`/`PowerSetRequest` API. The request is
  now owned by the process rather than a single thread, and a reason string is shown in
  `powercfg /requests`.
- All functions now follow the PSAppDeployToolkit v4 extension template.
- Reduced log output to one line per state change. `Get-ADTSleepStatus` is a read, so it now logs with
  `-DebugMessage` and is silent unless debug logging is enabled. `Block-ADTSleep` only mentions the
  display when the display is actually being held on.

### Fixed
- Native API failures are now detected and raised instead of being silently reported as success.
- `Block-ADTSleep -KeepDisplayOn` now upgrades an existing request instead of doing nothing.
- Corrected the `.PARAMETER KeepDisplaOn` typo that hid the parameter's help.

### Added
- `-Reason` parameter on `Block-ADTSleep`.
- Pester tests.
'@

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}
