#requires -Version 7.6.5

Set-StrictMode -Version Latest

# A process name is the image file's name, and a running process cannot be
# renamed. So a name that says which cluster and which node — the owner,
# 2026-09-20: Cluster, Node and test suite shall be incorporated in the process
# name — is a file per instance. The files are hard links where the file system
# makes them, which costs a directory entry rather than twenty-one megabytes a
# node, and copies where it will not. They live under .local-work, device-local
# and never in the repository (CONTRIBUTING.md), and go when the roll does.
#
# ADR-0053, amendment 2026-09-20.

function Get-XmipPlaygroundImageArea {
    <#
        .SYNOPSIS
            Where one cluster's images live: a directory of its own under the
            Playground's image area, so two clusters never share a file.

        .PARAMETER Cluster
            The cluster the images are for.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    return Join-Path -Path (Get-XmipPlaygroundLayout).Image -ChildPath $Cluster
}

function Get-XmipPlaygroundImageName {
    <#
        .SYNOPSIS
            What one instance of the Playground is called:
            xmip-playground-<cluster>-<what>, where what is roll, cluster or
            node-<name>. Pure.

        .PARAMETER Cluster
            The cluster it belongs to.

        .PARAMETER What
            roll, cluster, or node- and the node's name. The node marker is
            what makes the kind a shape rather than a word a node may not be
            called. The owner, 2026-09-20: a node is a node and can have one
            or more roles, roll is something different. So
            xmip-playground-U1-node-roll is the node called roll, and
            xmip-playground-U1-roll is still the roll; nothing collides and no
            name is refused (ADR-0053, amendment 2026-09-20).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [string] $What
    )

    return "xmip-playground-$Cluster-$What"
}

function New-XmipPlaygroundImage {
    <#
        .SYNOPSIS
            Links the binaries a roll's tree runs into the cluster's own image
            area and answers the roll's image, the one the operator will see as
            xmip-playground-<cluster>-roll.

        .DESCRIPTION
            Three files are laid down here. The roll's carries the cluster's
            name, because Start-XmipTest starts it. The cluster and node
            binaries are laid down under their own names beside it, because the
            roll looks for its cluster beside its own image and the cluster
            looks for its node the same way (`src/cluster/binary.rs`); each then
            makes its own per-instance image beside them, which is why nothing
            here needs to know the nodes.

            A hard link is tried first and a copy is the fallback: a link on the
            same volume costs a directory entry, and the node binary is
            twenty-one megabytes, which a brutal level's forty nodes would turn
            into eight hundred.

            The area is cleared first, so a roll never runs an image linked to
            a binary two builds ago.

        .PARAMETER Cluster
            The cluster the roll rolls as.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    $layout = Get-XmipPlaygroundLayout
    [string] $area = Get-XmipPlaygroundImageArea -Cluster $Cluster

    if (-not $PSCmdlet.ShouldProcess($area, 'Link the Playground images')) {
        return ''
    }

    Remove-XmipPlaygroundImage -Cluster $Cluster -Confirm:$false
    New-Item -ItemType Directory -Path $area -Force | Out-Null

    [string] $name = Get-XmipPlaygroundImageName -Cluster $Cluster -What 'roll'
    [string] $roll = Join-Path -Path $area -ChildPath "$name$($layout.Suffix)"

    Copy-XmipPlaygroundImage -Source $layout.Roll -Image $roll
    Copy-XmipPlaygroundImage -Source $layout.Cluster -Image (
        Join-Path -Path $area -ChildPath (Split-Path -Leaf $layout.Cluster))
    Copy-XmipPlaygroundImage -Source $layout.Node -Image (
        Join-Path -Path $area -ChildPath (Split-Path -Leaf $layout.Node))

    return $roll
}

function Copy-XmipPlaygroundImage {
    <#
        .SYNOPSIS
            One image: a hard link to the built binary, or a copy of it where a
            link cannot be made — another volume, or a file system without them.
            Says in words which it was, on the Verbose stream.

        .PARAMETER Source
            The built binary.

        .PARAMETER Image
            Where the image goes.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Image
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "REFUSED: $Source is not built; there is nothing to link an image to."
    }

    try {
        New-Item -ItemType HardLink -Path $Image -Target $Source -ErrorAction Stop | Out-Null
        Write-Verbose "linked $Image to $Source"
    }
    catch {
        Copy-Item -LiteralPath $Source -Destination $Image -Force
        Write-Verbose "copied $Source to ${Image}: $($_.Exception.Message)"
    }
}

function Remove-XmipPlaygroundImage {
    <#
        .SYNOPSIS
            Takes a cluster's images away. A process holds its own image open,
            so this is called once a roll's tree has stopped, and again before
            the next roll on the same cluster starts.

        .PARAMETER Cluster
            The cluster whose images to remove.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    [string] $area = Get-XmipPlaygroundImageArea -Cluster $Cluster

    if (-not (Test-Path -LiteralPath $area)) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess($area, 'Remove the Playground images')) {
        return
    }

    # Removed one by one, so an image still held open leaves the rest gone
    # rather than stopping the sweep at the first file that will not go.
    foreach ($file in @(Get-ChildItem -LiteralPath $area -File -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    }

    # Recurse, so a folder with anything left in it is removed rather than
    # asked about: the question failed a non-interactive session outright
    # (2026-09-25). A file still held open stays, and so does its folder.
    Remove-Item -LiteralPath $area -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

function Test-XmipPlaygroundOwnImage {
    <#
        .SYNOPSIS
            Whether a path is one of the Playground's own per-instance images.
            Nothing but New-XmipPlaygroundImage and the roll's tree write that
            directory, so a process running out of it is the Playground's,
            whatever the binary beside the repository is called now.

        .PARAMETER Path
            The image path to judge; empty is not one.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    [string] $area = (Get-XmipPlaygroundLayout).Image

    try {
        [string] $full = [System.IO.Path]::GetFullPath($Path)
        [string] $root = [System.IO.Path]::GetFullPath($area).TrimEnd('\', '/')
    }
    catch {
        return $false
    }

    return $full.StartsWith("$root$([System.IO.Path]::DirectorySeparatorChar)",
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-XmipPlaygroundImageKind {
    <#
        .SYNOPSIS
            Which of the Playground's three a process name is: Roll, Cluster,
            Node, or the empty string for a name that is none of them. Pure.

        .DESCRIPTION
            The name is xmip-playground-<cluster>-<what> since 2026-09-20, and
            xmip-playground-<what> where no cluster named it — a roll started by
            hand, or this crate's own tests. What is roll, cluster, or
            node-<name>, and the node marker is read first: it is what lets a
            node be called roll without being one (the owner, 2026-09-20). A
            name carrying no marker and ending in neither word is a node too,
            which is what the bare xmip-playground-node is.

        .PARAMETER Name
            The process name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    [string] $prefix = 'xmip-playground-'

    if ($Name -notlike "$prefix*" -or $Name.Length -le $prefix.Length) {
        return ''
    }

    [string] $rest = $Name.Substring($prefix.Length).ToLowerInvariant()

    # The marker before the endings: xmip-playground-orders-node-roll is the
    # node called roll, never the orders cluster's roll, and that is the whole
    # point of the marker.
    if ($rest.Contains('-node-')) {
        return 'Node'
    }

    foreach ($kind in 'roll', 'cluster') {
        if ($rest -eq $kind -or $rest.EndsWith("-$kind")) {
            return (Get-Culture).TextInfo.ToTitleCase($kind)
        }
    }

    return 'Node'
}
