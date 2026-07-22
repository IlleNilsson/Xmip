@{
    RootModule = 'Xmip-Git.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'f3e02f62-e272-46ee-8fcb-aeb8266b78c3'
    Author = 'IlleNilsson'
    CompanyName = 'Xmip'
    Copyright = '(c) IlleNilsson. All rights reserved.'
    Description = 'Manifest-driven Git operations across the Xmip repository set.'

    PowerShellVersion = '7.6.3'
    CompatiblePSEditions = @('Core')

    FunctionsToExport = @('Xmip-Git')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Xmip', 'Git', 'Repositories', 'CrossPlatform')
            ProjectUri = 'https://github.com/IlleNilsson/Xmip'
        }
    }
}
