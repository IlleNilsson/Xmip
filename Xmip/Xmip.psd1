#
# Module manifest for Xmip.
#
# This is where the dependency and the version floor belong: PowerShell enforces
# both at import, before a single line of the module runs. ADR-0021 says a floor
# is a refusal rather than a preference, and RequiredModules and
# PowerShellVersion are how that is stated to the runtime rather than to a
# reader.
#

@{
    RootModule           = 'Xmip.psm1'
    ModuleVersion        = '1.15.0'
    GUID                 = 'a4f1e6c2-9b73-4d58-8e21-5c7a3f0d94b6'
    Author               = 'Ilian Nilsson'
    CompanyName          = 'Xmip'
    Copyright            = 'Copyright (c) Ilian Nilsson. Licensed AGPL-3.0-or-later.'

    Description          = 'Tooling for the Xmip estate: prerequisites, GitHub reconciliation and local repositories.'

    # ADR-0021: current platforms only. Core edition, 7.6.5 or later.
    PowerShellVersion    = '7.6.5'
    CompatiblePSEditions = @('Core')

    # Two modules from the gallery, both declared in prerequisite.toml:
    #
    #   PSToml     reads architecture.toml and prerequisite.toml. PowerShell has
    #              no built-in TOML parser.
    #   posh-git   reads git state as objects. Ahead and behind counts are not
    #              in `git status --porcelain`, so Get-XmipStatus would
    #              otherwise answer a narrower question than the prompt does.
    #
    # Deliberately not RequiredModules: that would make both hard import-time
    # dependencies, and Install-XmipPrerequisite exists precisely to be runnable
    # on a machine that does not have them yet. Each is imported at the point it
    # is actually needed, and says how to get it when it is missing.
    RequiredModules      = @()

    FunctionsToExport    = @(
        'Install-XmipModule'
        'Install-XmipPrerequisite'
        'Sync-XmipEstate'
        'Sync-XmipRepository'
        'Get-XmipManifest'
        'Get-XmipRepositoryRoot'
        'Test-XmipManifest'
        'Expand-XmipEstate'
        'Publish-XmipChange'
        'Publish-XmipPin'
        'Get-XmipStatus'
        'Get-XmipDecisionRecord'
        'New-XmipDecisionIndex'
    )

    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('xmip-git', 'xgit')

    PrivateData = @{
        PSData = @{
            Tags         = @('xmip', 'integration', 'estate', 'devops')
            LicenseUri   = 'https://www.gnu.org/licenses/agpl-3.0.html'
            ProjectUri   = 'https://github.com/IlleNilsson/Xmip'
            ReleaseNotes = 'See docs/decisions for the record of what changed and why.'
        }
    }
}
