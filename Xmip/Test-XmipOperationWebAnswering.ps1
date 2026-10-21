#requires -Version 7.6.7

Set-StrictMode -Version Latest

function Test-XmipOperationWebAnswering {
    <#
        .SYNOPSIS
            Whether something already listens where a web host would.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Url
    )

    [uri] $address = $Url
    [string] $reach = $address.Host

    if ($reach -in '0.0.0.0', '+', '*') {
        $reach = '127.0.0.1'
    }

    $client = [System.Net.Sockets.TcpClient]::new()

    try {
        $client.Connect($reach, $address.Port)
        return $true
    }
    catch [System.Net.Sockets.SocketException] {
        return $false
    }
    finally {
        $client.Dispose()
    }
}
