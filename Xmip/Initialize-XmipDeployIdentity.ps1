#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Initialize-XmipDeployIdentity {
    <#
        .SYNOPSIS
            Each certificate an environment's machines are given, issued in
            its private state from the cluster's authority where none is:
            each node's and each far end's, node.pem, node.key and
            anchors.pem in identity/<name>; and the operator's, operator.pem,
            operator.key and anchors.pem in operator, for this account's
            person, whom every node lists among its operators, and whom
            Start-XmipTest -VirtualMachine asks each node with. Nobody issues
            one by hand (ADR-0015, amendment 2026-11-25).

        .DESCRIPTION
            The authority is the environment's, kept in the private state's
            authority folder, made there where none is: the folder the trust
            reads beside a slice, so the operator's request is signed by the
            slice of the node the cluster file declares [provision.operator]
            for, signed by it (Write-XmipOperatorSlice), as the System Tests'
            tester's is. Each is the operator module's own: New-XmipCertificate
            -Node and -Operator, and -Request with -Configuration.

        .PARAMETER Read
            The environment, as Get-XmipDeployEnvironment read it.

        .PARAMETER Facts
            What the host gives, Get-XmipDeployHost's: Authority, Identity,
            Operator and Operators.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $Facts
    )

    Import-XmipOperatorModule
    [string[]] $named = @(@($Read.Nodes | ForEach-Object { $_.node }) +
        @($Read.FarEnds | ForEach-Object { $_.name }))
    foreach ($name in $named) {
        [string] $folder = Join-Path $Facts.Identity $name
        if (Test-Path -LiteralPath (Join-Path $folder 'node.pem') -PathType Leaf) {
            continue
        }
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        [hashtable] $issued = @{ Node = $name; Cluster = $Read.Cluster
            Authority = $Facts.Authority; Path = $folder }
        New-XmipCertificate @issued -Confirm:$false | Out-Null
    }
    [string] $operator = $Facts.Operator
    if (Test-Path -LiteralPath (Join-Path $operator 'operator.pem') -PathType Leaf) {
        return
    }
    New-Item -Path $operator -ItemType Directory -Force | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $operator 'operator.key') -PathType Leaf)) {
        [string] $person = ([string] $Facts.Operators[0]) -replace '^CN=', ''
        New-XmipCertificate -Operator $person -Path $operator -Confirm:$false | Out-Null
    }
    [hashtable] $slicing = @{ File = $Read.File; Cluster = $Read.Cluster
        Authority = $Facts.Authority }
    [string] $configuration = Write-XmipOperatorSlice @slicing
    [hashtable] $signed = @{ Request = Join-Path $operator 'operator.csr'
        Configuration = $configuration; Path = Join-Path $operator 'operator.pem' }
    New-XmipCertificate @signed -Confirm:$false | Out-Null
    Copy-Item -LiteralPath (Join-Path $Facts.Authority 'authority.pem') -Destination (
        Join-Path $operator 'anchors.pem') -Force
}
