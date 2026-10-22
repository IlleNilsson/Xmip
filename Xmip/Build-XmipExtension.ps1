#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    The VS Code extension built without Node.js: its TypeScript shell
    compiled by TypeScript's native compiler and packaged as a VSIX by
    PowerShell, for Build-XmipService -Extension and the landing.

.DESCRIPTION
    The owner, 2026-10-22, on the extension's build: *Do it*, and Node.js is
    never installed on his machine (ADR-0014, amendment 2026-10-22). So:

    - The packages the shell compiles against and runs with — the language
      client and what it needs, and the type declarations of VS Code and
      Node's API — are restored from the extension's package-lock.json: each
      tarball fetched from where the lock says it was resolved and refused
      unless its digest is the lock's integrity, then unpacked under
      extension/node_modules. The linter and the test runner are not
      restored; they run in the CI alone.
    - The shell and its webview are compiled by the native compiler that
      prerequisite.toml's [archive.typescript] names (Install-XmipArchive).
    - The VSIX is a zip: extension.vsixmanifest, [Content_Types].xml, and
      extension/ holding package.json, the README, the license, the compiled
      out/ without its tests, media/ and the runtime packages.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipExtensionPackage {
    <#
        .SYNOPSIS
            The packages of the extension's lock its build needs: the runtime
            dependencies and the type declarations, with every package each
            depends on, by the lock's path for it.

        .PARAMETER Lock
            package-lock.json, as ConvertFrom-Json read it.

        .PARAMETER Runtime
            The runtime dependencies alone, what the VSIX carries.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lock,

        [Parameter(Mandatory = $false)]
        [switch] $Runtime
    )

    [hashtable] $packages = $Lock['packages']
    [hashtable] $top = $packages['']
    [string[]] $wanted = @($top['dependencies'].Keys)

    if (-not $Runtime) {
        $wanted += @($top['devDependencies'].Keys | Where-Object { $_ -like '@types/*' })
    }

    $found = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $wanted | ForEach-Object { $queue.Enqueue("node_modules/$_") }

    while ($queue.Count -gt 0) {
        [string] $at = $queue.Dequeue()

        if (-not $found.Add($at)) {
            continue
        }

        [hashtable] $entry = $packages[$at]

        if ($null -eq $entry) {
            throw "package-lock.json holds no $at; restore the lock in the CI."
        }

        [string[]] $needs = @()

        if ($entry.Contains('dependencies')) {
            $needs = @($entry['dependencies'].Keys)
        }

        foreach ($name in $needs) {
            # A nested copy wins over the top one, as Node resolves it.
            [string] $nested = "$at/node_modules/$name"
            [string] $next = "node_modules/$name"

            if ($packages.Contains($nested)) {
                $next = $nested
            }

            $queue.Enqueue($next)
        }
    }

    return [string[]] @($found | Sort-Object)
}


function Restore-XmipExtensionPackage {
    <#
        .SYNOPSIS
            Fetches and unpacks under node_modules every package the build
            needs that is not there at the lock's version, each refused
            unless its digest is the lock's integrity.

        .PARAMETER Extension
            The extension's directory, holding package-lock.json.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Extension
    )

    [hashtable] $lock = Get-Content -LiteralPath (Join-Path $Extension 'package-lock.json') -Raw |
        ConvertFrom-Json -AsHashtable

    foreach ($at in Get-XmipExtensionPackage -Lock $lock) {
        [hashtable] $entry = $lock['packages'][$at]
        [string] $into = Join-Path -Path $Extension -ChildPath $at
        [string] $held = Join-Path -Path $into -ChildPath 'package.json'

        if (Test-Path -LiteralPath $held) {
            [string] $version = (Get-Content -LiteralPath $held -Raw | ConvertFrom-Json).version

            if ($version -eq $entry['version']) {
                continue
            }
        }

        [string] $tarball = [System.IO.Path]::GetTempFileName()

        try {
            Invoke-WebRequest -Uri $entry['resolved'] -OutFile $tarball
            [string] $algorithm, [string] $expected = $entry['integrity'] -split '-', 2
            [byte[]] $bytes = [System.IO.File]::ReadAllBytes($tarball)
            [byte[]] $hash = switch ($algorithm) {
                'sha512' { [System.Security.Cryptography.SHA512]::HashData($bytes) }
                'sha1' { [System.Security.Cryptography.SHA1]::HashData($bytes) }
                default { throw "REFUSED: $at states integrity of $algorithm, which is not read." }
            }

            if ([Convert]::ToBase64String($hash) -ne $expected) {
                throw ("REFUSED: $($entry['resolved']) is not the package the lock states; " +
                    'nothing was unpacked.')
            }

            Remove-Item -LiteralPath $into -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $into -Force | Out-Null
            & tar -xzf $tarball -C $into --strip-components=1

            if ($LASTEXITCODE -ne 0) {
                throw "tar could not unpack $at (exit $LASTEXITCODE)."
            }
        }
        finally {
            Remove-Item -LiteralPath $tarball -Force -ErrorAction SilentlyContinue
        }
    }
}


function Invoke-XmipExtensionCompile {
    <#
        .SYNOPSIS
            Compiles the shell and its webview with TypeScript's native
            compiler; REFUSED, naming how to get it, where it is absent.

        .PARAMETER Root
            The estate root.

        .PARAMETER Extension
            The extension's directory.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Extension
    )

    $tsc = Get-XmipArchiveTool -Root $Root -Name 'typescript'

    if (-not $tsc.Present) {
        throw ("REFUSED: TypeScript's native compiler $($tsc.Version) is not at " +
            "$($tsc.Executable): Install-XmipPrerequisite -Install -IncludeOptional")
    }

    foreach ($project in @($Extension, (Join-Path -Path $Extension -ChildPath 'webview'))) {
        & $tsc.Executable -p $project 2>&1 | Out-Host

        if ($LASTEXITCODE -ne 0) {
            throw "FAILED: tsc -p $project exited $LASTEXITCODE."
        }
    }
}


function New-XmipExtensionPackage {
    <#
        .SYNOPSIS
            Writes the VSIX of a compiled extension: a zip of its manifests
            and extension/, built by PowerShell. Returns its path.

        .PARAMETER Extension
            The extension's directory, compiled.

        .PARAMETER License
            The license file the package carries.

        .PARAMETER Into
            The directory the VSIX is written to.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Extension,

        [Parameter(Mandatory = $true)]
        [string] $License,

        [Parameter(Mandatory = $true)]
        [string] $Into
    )

    $package = Get-Content -LiteralPath (Join-Path $Extension 'package.json') -Raw |
        ConvertFrom-Json
    [hashtable] $lock = Get-Content -LiteralPath (Join-Path $Extension 'package-lock.json') -Raw |
        ConvertFrom-Json -AsHashtable
    [string] $stage = Join-Path ([System.IO.Path]::GetTempPath()) "xmip-vsix-$([guid]::NewGuid())"
    [string] $content = Join-Path -Path $stage -ChildPath 'extension'

    try {
        New-Item -ItemType Directory -Path $content -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Extension 'package.json') -Destination $content
        Copy-Item -LiteralPath (Join-Path $Extension 'README.md') -Destination $content
        Copy-Item -LiteralPath $License -Destination (Join-Path $content 'LICENSE.txt')
        Copy-Item -LiteralPath (Join-Path $Extension 'media') -Destination $content -Recurse
        Copy-Item -LiteralPath (Join-Path $Extension 'out') -Destination $content -Recurse
        [string] $tests = Join-Path -Path $content -ChildPath 'out/test'
        Remove-Item -LiteralPath $tests -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $content -Recurse -File -Filter '*.map' | Remove-Item

        foreach ($at in Get-XmipExtensionPackage -Lock $lock -Runtime) {
            [string] $to = Join-Path -Path $content -ChildPath $at
            New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $Extension $at) -Destination $to -Recurse
        }

        [string] $manifest = Get-XmipExtensionManifest -Package $package
        [string] $written = Join-Path -Path $stage -ChildPath 'extension.vsixmanifest'
        Set-Content -LiteralPath $written -Value $manifest -Encoding utf8NoBOM
        [System.IO.FileInfo[]] $files = @(Get-ChildItem -LiteralPath $stage -Recurse -File)
        [string[]] $kinds = @($files | Where-Object Extension -ne '' |
                ForEach-Object { $_.Extension.ToLowerInvariant() } | Sort-Object -Unique)
        [string[]] $bare = @($files | Where-Object Extension -eq '' | ForEach-Object {
                '/' + [System.IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
            })
        [string] $types = Get-XmipExtensionContentType -Extension $kinds -Part $bare
        [string] $typed = Join-Path -Path $stage -ChildPath '[Content_Types].xml'
        Set-Content -LiteralPath $typed -Value $types -Encoding utf8NoBOM

        New-Item -ItemType Directory -Path $Into -Force | Out-Null
        [string] $file = "$($package.name)-$($package.version).vsix"
        [string] $vsix = Join-Path -Path $Into -ChildPath $file
        Remove-Item -LiteralPath $vsix -Force -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $vsix)

        return $vsix
    }
    finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}


function Get-XmipExtensionManifest {
    <#
        .SYNOPSIS
            extension.vsixmanifest, from package.json: what VS Code reads of
            a VSIX before it unpacks it.

        .PARAMETER Package
            package.json, as ConvertFrom-Json read it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Package
    )

    [string] $description = [System.Security.SecurityElement]::Escape($Package.description)
    [string] $categories = $Package.categories -join ','

    return @"
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0"
    xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"
    xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="$($Package.name)" Version="$($Package.version)"
        Publisher="$($Package.publisher)" />
    <DisplayName>$($Package.displayName)</DisplayName>
    <Description xml:space="preserve">$description</Description>
    <Categories>$categories</Categories>
    <GalleryFlags>Public</GalleryFlags>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="$($Package.engines.vscode)" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="workspace" />
      <Property Id="Microsoft.VisualStudio.Services.Links.Source"
          Value="$($Package.repository.url)" />
    </Properties>
    <License>extension/LICENSE.txt</License>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json"
        Addressable="true" />
    <Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md"
        Addressable="true" />
    <Asset Type="Microsoft.VisualStudio.Services.Content.License" Path="extension/LICENSE.txt"
        Addressable="true" />
  </Assets>
</PackageManifest>
"@
}


function Get-XmipExtensionContentType {
    <#
        .SYNOPSIS
            [Content_Types].xml: the media type of each file extension the
            VSIX holds, as the Open Packaging Conventions ask of a zip.

        .PARAMETER Extension
            The file extensions present, with their dot.

        .PARAMETER Part
            The files that have none, by their path in the zip: each is
            given its type by name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Extension,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Part = @()
    )

    [hashtable] $type = @{
        '.json' = 'application/json'; '.js' = 'application/javascript'
        '.md' = 'text/markdown'; '.txt' = 'text/plain'; '.css' = 'text/css'
        '.vsixmanifest' = 'text/xml'; '.xml' = 'text/xml'; '.svg' = 'image/svg+xml'
        '.png' = 'image/png'; '.ts' = 'text/plain'
    }
    [string[]] $named = foreach ($bare in $Part) {
        [string] $escaped = [System.Security.SecurityElement]::Escape($bare)
        "  <Override PartName=`"$escaped`" ContentType=`"application/octet-stream`" />"
    }
    [string[]] $lines = foreach ($kind in $Extension) {
        [string] $said = 'application/octet-stream'

        if ($type.ContainsKey($kind)) {
            $said = $type[$kind]
        }

        "  <Default Extension=`"$kind`" ContentType=`"$said`" />"
    }

    return (@(
            '<?xml version="1.0" encoding="utf-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        ) + $lines + $named + '</Types>') -join "`n"
}
