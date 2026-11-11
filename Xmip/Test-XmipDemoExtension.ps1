#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The demo readiness check's extension part: the VS Code extension's VSIX
    and its language server, xmip-lsp, built, and the server answering an
    initialize request over stdio.

.DESCRIPTION
    The VSIX is Build-XmipService -Extension VsCode's. The server is built as
    the getting-started guide builds it, cargo in the extension's own crate,
    by the one patched build a roll's binaries are built by
    (Invoke-XmipPatchedBuild: every estate crate patched to its working tree,
    a shared build directory's unhashed libraries cleared first), and found
    where cargo says it wrote it, so CARGO_TARGET_DIR moves it and nothing
    here guesses. Then the server is started as the extension starts it
    (Start-XmipLanguageServer, audited) and asked what the Language Server
    Protocol asks first; it answers with its capabilities, and is shut down
    and told to exit as an editor does (ADR-0028, amendment 2026-11-10).

    Style: doc/governance/powershell-style.md
#>


# How long the language server is given to answer before the check says it
# did not. An answer is milliseconds; how long it took is said either way.
[timespan] $script:XmipDemoServerWait = [timespan]::FromSeconds(10)


function Test-XmipDemoExtension {
    <#
        .SYNOPSIS
            Builds the VS Code extension and its language server and asks the
            server to initialize; returns what it found in words, or throws
            why not.

        .PARAMETER Run
            The run, from New-XmipDemoState. Nothing of this part outlives
            it, so nothing is launched into it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run
    )

    $built = Build-XmipService -Extension VsCode -ErrorAction Stop | Select-Object -Last 1

    if ($null -eq $built -or -not (Test-Path -LiteralPath $built.Path -PathType Leaf)) {
        throw 'Build-XmipService -Extension VsCode wrote no VSIX.'
    }

    [string] $server = Build-XmipDemoServer
    [string] $answered = Test-XmipLanguageServer -Path $server

    return "the VSIX is $($built.Path); xmip-lsp, $server, $answered"
}


function Build-XmipDemoServer {
    <#
        .SYNOPSIS
            Builds xmip-lsp and returns the executable cargo wrote; throws
            with cargo's first error.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [hashtable] $building = @{
        Directory = (Get-XmipEssentialsLayout).Extension
        Argument  = @('--bin', 'xmip-lsp', '--message-format=json-render-diagnostics')
    }
    [pscustomobject] $built = Invoke-XmipPatchedBuild @building

    if (-not $built.Passed) {
        [string] $first = @($built.Said | Where-Object { $_ -match '^error' }) +
            @($built.Said) | Select-Object -First 1

        throw "xmip-lsp did not build: $first"
    }

    [string] $server = Get-XmipCargoExecutable -Said $built.Said -Name 'xmip-lsp'

    if ($server -eq '' -or -not (Test-Path -LiteralPath $server -PathType Leaf)) {
        throw "xmip-lsp built, and cargo names no executable of it that is there ('$server')."
    }

    return $server
}


function Get-XmipCargoExecutable {
    <#
        .SYNOPSIS
            The executable cargo says it wrote for a binary target, from what
            cargo --message-format=json said; empty where it said none. Pure.

        .PARAMETER Said
            cargo's lines.

        .PARAMETER Name
            The binary target's name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Said,

        [Parameter(Mandatory)]
        [string] $Name
    )

    [string] $found = ''

    foreach ($line in @($Said | Where-Object { $_ -match '^\{"reason":"compiler-artifact"' })) {
        [hashtable] $artifact = $line | ConvertFrom-Json -AsHashtable

        if ($artifact['target']['name'] -eq $Name -and $artifact['executable']) {
            $found = [string] $artifact['executable']
        }
    }

    return $found
}


function Test-XmipLanguageServer {
    <#
        .SYNOPSIS
            Starts a language server over stdio, asks it to initialize, and
            shuts it down; returns "answered initialize in <ms> ms", or
            throws what it answered instead, or that it did not.

        .PARAMETER Path
            The server's executable.

        .PARAMETER Wait
            How long it is given to answer each request.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [timespan] $Wait = $script:XmipDemoServerWait
    )

    $server = Start-XmipLanguageServer -Path $Path

    try {
        [System.IO.Stream] $told = $server.StandardInput.BaseStream
        [System.IO.Stream] $heard = $server.StandardOutput.BaseStream
        [hashtable] $asked = @{
            jsonrpc = '2.0'; id = 1; method = 'initialize'
            params  = @{ processId = $PID; rootUri = $null; capabilities = @{} }
        }
        [System.Diagnostics.Stopwatch] $clock = [System.Diagnostics.Stopwatch]::StartNew()
        Write-XmipLspFrame -Stream $told -Message $asked
        [hashtable] $answer = Read-XmipLspAnswer -Stream $heard -Id 1 -Wait $Wait
        [int] $took = [int] $clock.Elapsed.TotalMilliseconds

        if ($null -eq $answer['result'] -or $null -eq $answer['result']['capabilities']) {
            [string] $said = ConvertTo-Json -InputObject $answer -Depth 8 -Compress
            throw "it answered initialize without its capabilities: $said"
        }

        [hashtable] $shutdown = @{ jsonrpc = '2.0'; id = 2; method = 'shutdown' }
        Write-XmipLspFrame -Stream $told -Message $shutdown
        $null = Read-XmipLspAnswer -Stream $heard -Id 2 -Wait $Wait
        Write-XmipLspFrame -Stream $told -Message @{ jsonrpc = '2.0'; method = 'exit' }
        [bool] $ended = $server.WaitForExit([int] $Wait.TotalMilliseconds)
        [string] $exit = if ($ended) {
            "exited $($server.ExitCode) when told to exit"
        }
        else {
            'did not exit when told to'
        }

        return "answered initialize in $took ms and $exit"
    }
    finally {
        if (-not $server.HasExited) {
            $server.Kill($true)
        }

        $server.Dispose()
    }
}


function Write-XmipLspFrame {
    <#
        .SYNOPSIS
            Writes one Language Server Protocol message: Content-Length, the
            blank line, and the JSON-RPC body in UTF-8.

        .PARAMETER Stream
            Where it is written: a server's standard input.

        .PARAMETER Message
            The JSON-RPC message.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream] $Stream,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Message
    )

    [byte[]] $body = [System.Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $Message -Depth 8 -Compress))
    [byte[]] $head = [System.Text.Encoding]::ASCII.GetBytes(
        "Content-Length: $($body.Length)`r`n`r`n")

    $Stream.Write($head, 0, $head.Length)
    $Stream.Write($body, 0, $body.Length)
    $Stream.Flush()
}


function Read-XmipLspFrame {
    <#
        .SYNOPSIS
            Reads one Language Server Protocol message and returns its body;
            throws where none is framed, the stream ends, or -Wait passes.

        .PARAMETER Stream
            Where it is read: a server's standard output.

        .PARAMETER Wait
            How long the whole message may take.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream] $Stream,

        [Parameter(Mandatory)]
        [timespan] $Wait
    )

    [System.Diagnostics.Stopwatch] $clock = [System.Diagnostics.Stopwatch]::StartNew()
    [System.IO.MemoryStream] $header = [System.IO.MemoryStream]::new()
    [byte[]] $byte = [byte[]]::new(1)
    [string] $ended = "`r`n`r`n"

    while (-not [System.Text.Encoding]::ASCII.GetString($header.ToArray()).EndsWith($ended)) {
        Read-XmipStreamFully -Stream $Stream -Buffer $byte -Clock $clock -Wait $Wait
        $header.WriteByte($byte[0])
    }

    [string] $said = [System.Text.Encoding]::ASCII.GetString($header.ToArray())

    if ($said -notmatch '(?im)^Content-Length:\s*(\d+)\s*$') {
        throw "it framed no Content-Length: $said"
    }

    [byte[]] $body = [byte[]]::new([int] $Matches[1])
    Read-XmipStreamFully -Stream $Stream -Buffer $body -Clock $clock -Wait $Wait

    return [System.Text.Encoding]::UTF8.GetString($body)
}


function Read-XmipLspAnswer {
    <#
        .SYNOPSIS
            Reads messages until the answer to one request, and returns it as
            a hashtable; what a server may send before it — a log message, a
            request of its own — is passed over. Throws where -Wait passes.

        .PARAMETER Stream
            Where it is read: a server's standard output.

        .PARAMETER Id
            The request's id.

        .PARAMETER Wait
            How long the answer may take, whatever comes before it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream] $Stream,

        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [timespan] $Wait
    )

    [System.Diagnostics.Stopwatch] $clock = [System.Diagnostics.Stopwatch]::StartNew()

    while ($true) {
        [timespan] $left = $Wait - $clock.Elapsed

        if ($left -le [timespan]::Zero) {
            throw "it did not answer within $Wait."
        }

        [hashtable] $said = Read-XmipLspFrame -Stream $Stream -Wait $left |
            ConvertFrom-Json -AsHashtable
        [bool] $answers = $said.ContainsKey('id') -and $said['id'] -eq $Id

        # A request of the server's own carries an id and a method; an answer
        # carries no method.
        if ($answers -and -not $said.ContainsKey('method')) {
            return $said
        }
    }
}


function Read-XmipStreamFully {
    <#
        .SYNOPSIS
            Fills a buffer from a stream; throws where the stream ends first
            or the wait, measured on -Clock, passes.

        .PARAMETER Stream
            The stream.

        .PARAMETER Buffer
            What is filled, whole.

        .PARAMETER Clock
            Running since the wait began.

        .PARAMETER Wait
            How long the wait may take in all.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream] $Stream,

        [Parameter(Mandatory)]
        [byte[]] $Buffer,

        [Parameter(Mandatory)]
        [System.Diagnostics.Stopwatch] $Clock,

        [Parameter(Mandatory)]
        [timespan] $Wait
    )

    [int] $filled = 0

    while ($filled -lt $Buffer.Length) {
        [int] $left = [int] ($Wait - $Clock.Elapsed).TotalMilliseconds
        $reading = $Stream.ReadAsync($Buffer, $filled, $Buffer.Length - $filled)

        if ($left -le 0 -or -not $reading.Wait($left)) {
            throw "it did not answer within $Wait."
        }

        if ($reading.Result -eq 0) {
            throw 'it closed its output before it answered.'
        }

        $filled += $reading.Result
    }
}
