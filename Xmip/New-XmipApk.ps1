#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The phone host's package (ADR-0014, amendment 2026-10-22): the APK a
    person side-loads onto an Android phone, made by Build-XmipService
    -Remote Android -Package apk after the runtime's two Android libraries.

    Style: doc/governance/powershell-style.md
#>

function Assert-XmipPhonePackage {
    <#
        .SYNOPSIS
            Throws REFUSED, in words, for a package -Remote does not make:
            only apk, and only with Android among the platforms; and for an
            -Address with no APK to follow it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Remote,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Package,

        [Parameter(Mandatory = $false)]
        [string] $Address = ''
    )

    if ($Address -and $Package -notcontains 'apk') {
        throw ('REFUSED: -Address is the node the APK follows: ' +
            '-Remote Android -Package apk -Address.')
    }

    foreach ($kind in $Package) {
        if ($kind -ne 'apk') {
            throw "REFUSED: -Package $kind is a site's; -Remote makes apk alone."
        }

        if ($Remote -notcontains 'Android') {
            throw 'REFUSED: -Package apk is the Android phone host: -Remote Android -Package apk.'
        }
    }
}


function Find-XmipAndroidJdk {
    <#
        .SYNOPSIS
            The Java Development Kit the .NET for Android build runs its tools
            with, Microsoft's OpenJDK 21; empty when this machine has none.

        .DESCRIPTION
            Named to the build as JavaSdkDirectory, never through JAVA_HOME,
            which names the Java Event binding's JDK 27 (prerequisite.toml,
            android-jdk and java; the owner, 2026-11-09). The newest
            %ProgramFiles%\Microsoft\jdk-21* on Windows, the newest
            /usr/lib/jvm/msopenjdk-21* or java-21-openjdk* elsewhere; the
            first with bin/java wins.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [string[]] $pattern = if ($IsWindows) {
        @(Join-Path -Path $env:ProgramFiles -ChildPath 'Microsoft/jdk-21*')
    }
    else {
        @('/usr/lib/jvm/msopenjdk-21*', '/usr/lib/jvm/java-21-openjdk*')
    }

    [string] $java = if ($IsWindows) { 'bin/java.exe' } else { 'bin/java' }

    foreach ($each in $pattern) {
        [string] $found = Get-Item -Path $each -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path -Path $_.FullName -ChildPath $java) } |
            Sort-Object -Property Name -Descending |
            Select-Object -First 1 -ExpandProperty FullName

        if ($found) {
            return $found
        }
    }

    return ''
}


function New-XmipApk {
    <#
        .SYNOPSIS
            Publishes the phone host, Xmip.Operations, for net11.0-android,
            Release, as one APK holding the runtime's two Android libraries
            the remote build made, and copies it under
            .local-work/package/<version>. Returns Kind and Path.

        .DESCRIPTION
            No signing key is named, so the build signs with the Android
            SDK's debug key, made once per user: an APK a person side-loads,
            never one a store takes (ADR-0014, amendment 2026-10-22).

            With Address, the document the APK ships is the shipped one with
            that node's Address written in, beside the stage, so the source
            is never edited.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $false)]
        [string] $Address = ''
    )

    $cargo = Read-XmipToml -Path (Join-Path $Root 'Cargo.toml')
    $crate = Get-TomlValue -Node $cargo -Name 'package'
    [string] $version = Get-TomlValue -Node $crate -Name 'version'
    [string] $output = Join-Path (Get-XmipEstateLayout -Root $Root).Package $version
    [string] $stage = Join-Path $output 'android'
    [string] $project = Join-Path $Root 'module/core/operation/gui/src/Xmip.Operations'

    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }

    [string] $jdk = Find-XmipAndroidJdk

    if (-not $jdk) {
        throw ('FAILED: no OpenJDK 21 for the .NET for Android build; install the ' +
            'android-jdk prerequisite (Install-XmipPrerequisite).')
    }

    [string[]] $argument = @(
        'publish', $project, '--framework', 'net11.0-android', '--configuration', 'Release'
        '--output', $stage, '-p:AndroidPackageFormat=apk', "-p:JavaSdkDirectory=$jdk"
    )

    if ($Address) {
        [string] $shipped = Join-Path $project 'Resources/Raw/gui.toml'
        [string] $document = Join-Path $output 'android-gui.toml'
        $null = New-Item -ItemType Directory -Path $output -Force
        [string] $text = Get-Content -LiteralPath $shipped -Raw
        [string] $line = "Address = `"$Address`""
        [regex] $named = '(?m)^#?\s*Address\s*=.*$'

        if (-not $named.IsMatch($text)) {
            throw "FAILED: $shipped says nowhere where its Address goes."
        }

        Set-Content -LiteralPath $document -Value $named.Replace($text, $line, 1) -NoNewline
        $argument += "-p:XmipPhoneDocument=$document"
    }
    if (-not (Invoke-XmipTool -Tool dotnet -Argument $argument -Prefix '    dotnet| ').Passed) {
        throw "FAILED: dotnet publish of $project for Android."
    }

    $signed = @(Get-ChildItem -LiteralPath $stage -Filter '*-Signed.apk' -File)

    if ($signed.Count -ne 1) {
        throw "FAILED: dotnet publish of $project left $($signed.Count) signed APKs in $stage."
    }

    [string] $apk = Join-Path $output "xmip-operations-$version-android.apk"
    Copy-Item -LiteralPath $signed[0].FullName -Destination $apk -Force
    Write-XmipStep -Message "OK: apk $apk"

    return [pscustomobject] @{ Kind = 'apk'; Path = $apk }
}