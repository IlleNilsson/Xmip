#requires -Version 7.7.0

<#
.SYNOPSIS
    Prepares the overview's transfer data, collects regenerated narration, or
    validates the story against its voice tracks.

.DESCRIPTION
    The editorial source is story.toml; audio/timing.toml holds each section's
    voice track and its sentence timing. Every mode first refuses a story and a
    timing whose numbers of sections differ, and a project source a section
    cites that is not a file of the repository.

    With no switch, the working area .ai-interaction/presentation is made ready
    to render: build/story.json, the story as JSON transfer data; the host
    images under output/brand-presenters; and for each section whose narration
    its voice track says word for word, the track and its timing as
    build/overview-narration-<n>.wav and .json, n counted from zero. A section
    whose narration changed has its build track removed and is named, so it is
    narrated again; a track is never reused for words it does not say.

    -CollectNarration takes the narration generated into build/, each section's
    track and its timing, refuses one whose words differ from its section or
    whose track is missing, and only then copies the tracks into audio/ as
    scene-<nn>.wav and writes audio/timing.toml.

    -Validate says OK when every section's track says its narration and is
    there, and refuses the first that does not.

    JSON is transfer here; the tracked sources are TOML. TOML is read through
    the estate module's one reader, Read-XmipToml.

.PARAMETER Validate
    Check the story, its sources and its voice tracks; change nothing.

.PARAMETER CollectNarration
    Collect regenerated narration and timing from the working area into
    audio/.

.EXAMPLE
    ./asset/brand/presentation/tools/prepare.ps1 -Validate

.EXAMPLE
    ./asset/brand/presentation/tools/prepare.ps1

.EXAMPLE
    ./asset/brand/presentation/tools/prepare.ps1 -CollectNarration
#>
[CmdletBinding(DefaultParameterSetName = 'Prepare')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Validate')]
    [switch] $Validate,

    [Parameter(Mandatory = $true, ParameterSetName = 'Collect')]
    [switch] $CollectNarration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[string] $script:Material = Split-Path -Parent $PSScriptRoot
[string] $script:Root = (Resolve-Path -LiteralPath (Join-Path $script:Material '../../..')).Path
[string] $script:Work = Join-Path $script:Root '.ai-interaction/presentation'
[System.Text.Encoding] $script:Utf8 = [System.Text.UTF8Encoding]::new($false)

function Read-PresentationToml {
    # The estate's one TOML reader, in the module's own scope.
    param([string] $Path)

    $module = Get-Module -Name Xmip | Select-Object -First 1

    if ($null -eq $module) {
        $module = Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -PassThru 3>$null
    }

    return (& $module { param($File) Read-XmipToml -Path $File } $Path)
}

function Get-PresentationStory {
    # The story's sections and the timing's scenes, refused where they do not
    # pair or a cited source is not there.
    $story = Read-PresentationToml -Path (Join-Path $script:Material 'story.toml')
    $timing = Read-PresentationToml -Path (Join-Path $script:Material 'audio/timing.toml')
    [object[]] $sections = @($story['section'])
    [object[]] $scenes = @($timing['scene'])

    if ($sections.Count -ne $scenes.Count) {
        throw 'REFUSED. Story and audio timing must have the same number of sections.'
    }

    foreach ($section in $sections) {
        foreach ($source in @($section['sources'])) {
            if (-not (Test-Path -LiteralPath (Join-Path $script:Root $source) -PathType Leaf)) {
                throw "REFUSED. Missing project source: $source"
            }
        }
    }

    return [pscustomobject]@{ Sections = $sections; Scenes = $scenes }
}

function Test-PresentationNarration {
    # Whether the captions say the section's narration word for word.
    param($Section, [object[]] $Caption)

    [string] $said = (@($Caption | ForEach-Object { ([string] $_['text']).Trim() })) -join ' '

    return $said -ceq [string] $Section['narration']
}

function ConvertTo-PresentationJson {
    # JSON transfer data, every array kept an array.
    param([object[]] $Value)

    return (ConvertTo-Json -InputObject $Value -Depth 32 -Compress)
}

function Initialize-PresentationWork {
    param([object[]] $Sections, [object[]] $Scenes)

    [string] $build = Join-Path $script:Work 'build'
    [string] $hosts = Join-Path $script:Work 'output/brand-presenters'
    New-Item -ItemType Directory -Force -Path $build, $hosts | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $build 'story.json'),
        (ConvertTo-PresentationJson -Value $Sections), $script:Utf8)

    [string] $assets = Join-Path $script:Material 'assets'

    foreach ($image in Get-ChildItem -LiteralPath $assets -Filter *.png) {
        Copy-Item -LiteralPath $image.FullName -Destination (Join-Path $hosts $image.Name) -Force
    }

    for ([int] $index = 0; $index -lt $Sections.Count; $index++) {
        [string] $prefix = Join-Path $build "overview-narration-$index"
        [object[]] $caption = @($Scenes[$index]['caption'])

        if (-not (Test-PresentationNarration -Section $Sections[$index] -Caption $caption)) {
            [string[]] $stale = "$prefix.wav", "$prefix.json"
            Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue
            "Regenerate narration for section $($index + 1)."
            continue
        }

        [string] $track = Join-Path $script:Material "audio/$($Scenes[$index]['file'])"
        Copy-Item -LiteralPath $track -Destination "$prefix.wav" -Force
        [System.IO.File]::WriteAllText("$prefix.json",
            (ConvertTo-PresentationJson -Value $caption), $script:Utf8)
    }

    "Prepared $($Sections.Count) sections in $script:Work."
}

function Get-PresentationCaptionLine {
    # One [[scene.caption]] table as the generated JSON wrote it: each value's
    # own JSON token, which is a TOML value as it stands.
    param([System.Text.Json.JsonElement] $Caption)

    '[[scene.caption]]'

    foreach ($property in $Caption.EnumerateObject()) {
        "$($property.Name) = $($property.Value.GetRawText())"
    }

    ''
}

function Save-PresentationNarration {
    param([object[]] $Sections)

    [System.Collections.Generic.List[string]] $lines = @(
        '# Generated sentence timing for the checked-in narration.', '')
    [System.Collections.Generic.List[object]] $pending = @()

    for ([int] $index = 0; $index -lt $Sections.Count; $index++) {
        [string] $prefix = Join-Path $script:Work "build/overview-narration-$index"
        [string] $text = [System.IO.File]::ReadAllText("$prefix.json", $script:Utf8)
        [object[]] $caption = @($text | ConvertFrom-Json -AsHashtable)

        if (-not (Test-PresentationNarration -Section $Sections[$index] -Caption $caption)) {
            throw "REFUSED. Regenerated narration differs from section $($index + 1)."
        }

        if (-not (Test-Path -LiteralPath "$prefix.wav" -PathType Leaf)) {
            throw "REFUSED. Missing audio: $prefix.wav"
        }

        [string] $name = 'scene-{0:00}.wav' -f ($index + 1)
        $pending.Add([pscustomobject]@{ From = "$prefix.wav"; To = "audio/$name" })
        $lines.AddRange([string[]] @('[[scene]]', "file = `"$name`"", ''))
        $document = [System.Text.Json.JsonDocument]::Parse($text)

        foreach ($element in $document.RootElement.EnumerateArray()) {
            $lines.AddRange([string[]] @(Get-PresentationCaptionLine -Caption $element))
        }
    }

    foreach ($track in $pending) {
        [string] $into = Join-Path $script:Material $track.To
        Copy-Item -LiteralPath $track.From -Destination $into -Force
    }

    [System.IO.File]::WriteAllText((Join-Path $script:Material 'audio/timing.toml'),
        ($lines -join "`n"), $script:Utf8)
    'Collected matching narration and timing into the repository.'
}

function Test-PresentationTrack {
    param([object[]] $Sections, [object[]] $Scenes)

    for ([int] $index = 0; $index -lt $Sections.Count; $index++) {
        [object[]] $caption = @($Scenes[$index]['caption'])

        if (-not (Test-PresentationNarration -Section $Sections[$index] -Caption $caption)) {
            throw "REFUSED. Audio text differs from section $($index + 1)."
        }

        [string] $track = Join-Path $script:Material "audio/$($Scenes[$index]['file'])"

        if (-not (Test-Path -LiteralPath $track -PathType Leaf)) {
            throw "REFUSED. Missing voice track for section $($index + 1)."
        }
    }

    "OK: $($Sections.Count) sections, source references and narration records."
}

$story = Get-PresentationStory

if ($Validate) {
    Test-PresentationTrack -Sections $story.Sections -Scenes $story.Scenes
}
elseif ($CollectNarration) {
    Save-PresentationNarration -Sections $story.Sections
}
else {
    Initialize-PresentationWork -Sections $story.Sections -Scenes $story.Scenes
}
