#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Test-XmipPlaygroundBinary {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [string] $Path
    )

    [string] $actual = try { $Process.Path } catch { '' }

    if ([string]::IsNullOrWhiteSpace($actual)) { return $false }

    return [IO.Path]::GetFullPath($actual) -ieq [IO.Path]::GetFullPath($Path)
}
