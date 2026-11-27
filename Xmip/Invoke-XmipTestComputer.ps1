#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Running one of the test cmdlets on a test computer, in the copy of the
    estate sent there, and bringing back what it answered.

.DESCRIPTION
    The computer runs the estate's own cmdlets: Start-XmipTest starts a suite
    there as it starts one here, detached, and Get-XmipTestStatus,
    Stop-XmipTest and Get-XmipTestResult read and stop it as they do here.
    Nothing of a suite is written twice: this side sends the estate
    (Send-XmipTestComputerEstate), asks over ssh and reads the answer. What a
    cmdlet answers crosses as PowerShell's own serialization, the form its
    remoting crosses computers in, and its words are shown as it says them.

    Over ssh the account's own shell, bash or zsh, starts pwsh, and pwsh runs
    the computer's side (Invoke-XmipTestComputerRemote), so the computer is
    Linux or macOS with pwsh, rsync, tar and git, which its first probe asks
    for, refusing a computer that lacks one by name. It receives a send into
    the mirror, or makes the copy, <folder>/xmip, the mirror as sent with
    what runs left in it kept, gives a run the environment it builds in and
    one of the computer's build slots, and starts pwsh in the copy. One run
    works in a copy at a time: the folder's lock, <folder>/tree.lock,
    refuses a second start and a send while a run holds it. The slot is a
    lock on ~/slot<n>.lock, which every builder there takes; a holder holds
    both until the run's last process ends (Lock-XmipTestComputerRun).
    Where every slot is taken the start waits, as every builder there
    waits, saying once a minute who holds them; a wait whose console has
    gone ends at that line, since it cannot be written, so nothing starts
    later on its own (the owner, 2026-09-12: nothing starts itself). What
    the computer says is shown here as it says it, prefixed with its name,
    every control character taken out.

    Style: doc/governance/powershell-style.md
#>


# What starts the line carrying a cmdlet's answer, among the lines it said.
[string] $script:XmipTestComputerAnswer = 'xmip-answer '

# What is taken out of every line the computer writes before it is kept or
# shown: the control characters, C0, delete and C1, but the tab.
[string] $script:XmipTestComputerUnprintable = '[\p{Cc}-[\t]]'


function Invoke-XmipTestComputer {
    <#
        .SYNOPSIS
            Runs -Command with -Parameter in the copy of the estate on the
            computer and returns what it answered; what it said is shown as
            it says it, prefixed with the computer's name, and its refusal
            is this command's error.

        .PARAMETER Computer
            The computer, from Read-XmipTestComputer.

        .PARAMETER Command
            The estate's cmdlet to run there.

        .PARAMETER Parameter
            Its parameters, by name; a switch as $true or $false.

        .PARAMETER Start
            Makes the copy from the mirror and takes a build slot first, for
            a start; otherwise the copy is read as it is.

        .PARAMETER AllowAbsent
            Answers nothing, rather than refusing, where nothing was ever
            started there.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [ValidateSet('Start-XmipTest', 'Get-XmipTestStatus', 'Stop-XmipTest',
            'Get-XmipTestResult')]
        [string] $Command,

        [Parameter(Mandatory)]
        [hashtable] $Parameter,

        [Parameter()]
        [switch] $Start,

        [Parameter()]
        [switch] $AllowAbsent
    )

    [hashtable] $made = @{ Command = $Command; Parameter = $Parameter; Prepare = [bool] $Start }
    [string] $script = New-XmipTestComputerCommand @made
    [string] $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    [string] $asked = if ($Start) { 'start' } else { 'observe' }
    $answer = Invoke-XmipTestComputerShell -Computer $Computer -Asked $asked -Given $encoded

    if ($AllowAbsent -and $answer.Code -eq $script:XmipTestComputerAbsent) {
        return
    }

    return Read-XmipTestComputerAnswer -Computer $Computer -Answer $answer -Doing $Command
}


function New-XmipTestComputerCommand {
    <#
        .SYNOPSIS
            The pwsh script that runs -Command in the copy: the estate's
            module imported from it, the parameters deserialized, and the
            answer written as one line after $script:XmipTestComputerAnswer.

        .PARAMETER Prepare
            Makes the copy ready to build first, for a start
            (Install-XmipTestComputerLibrary).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Command,

        [Parameter(Mandatory)]
        [hashtable] $Parameter,

        [Parameter()]
        [switch] $Prepare
    )

    [string] $given = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
            [System.Management.Automation.PSSerializer]::Serialize($Parameter)))
    [string] $marker = ConvertTo-XmipLiteral -Text $script:XmipTestComputerAnswer
    [string] $ready = if ($Prepare) {
        '    & (Get-Module -Name Xmip) { Install-XmipTestComputerLibrary -Confirm:$false }'
    }

    return @(
        '$ErrorActionPreference = ''Stop'''
        '$ProgressPreference = ''SilentlyContinue'''
        '$PSStyle.OutputRendering = ''PlainText'''
        'try {'
        '    Import-Module -Name ./Xmip/Xmip.psd1 3>$null'
        '    $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('
        "        '$given'))"
        '    $given = [System.Management.Automation.PSSerializer]::Deserialize($text)'
        $ready
        "    `$said = @(& '$Command' @given)"
        '    $sent = [System.Management.Automation.PSSerializer]::Serialize($said, 4)'
        "    $marker + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$sent))"
        '}'
        'catch {'
        '    [Console]::Error.WriteLine($_.Exception.Message)'
        '    exit 1'
        '}'
    ) -join "`n"
}


function Invoke-XmipTestComputerShell {
    <#
        .SYNOPSIS
            Runs the computer's side (Invoke-XmipTestComputerRemote) there
            over ssh and returns Code, its exit code; Out, what it wrote; and
            Err, what it wrote as errors. The one place the module calls ssh.

        .PARAMETER Asked
            probe, receive, start or observe.

        .PARAMETER Given
            For receive, whole or difference; for start and observe, the pwsh
            command, encoded.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [ValidateSet('probe', 'receive', 'start', 'observe')]
        [string] $Asked,

        [Parameter()]
        [string] $Given = ''
    )

    [hashtable] $asking = @{
        Asked = $Asked; Folder = $Computer.Folder; Slots = $Computer.Slots; Given = $Given
        Work  = Split-Path -Leaf -Path (Get-XmipEstateLayout).Work
    }
    [hashtable] $made = @{ Script = Get-XmipTestComputerRemoteScript; Asked = $asking }
    [string] $command = New-XmipTestComputerRemoteCommand @made
    # The account's own shell, bash or zsh, runs no more than this: cargo's
    # and the account's own programs on the path, and pwsh, named where it is
    # not there, given what it runs between single quotes, never read by a
    # shell, and nothing to read.
    [string] $lacking = $script:XmipTestComputerLack -f '$(uname -s)', 'pwsh'
    [string] $remote = ('[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"; ' +
        'export PATH="$HOME/.local/bin:$PATH"; command -v pwsh > /dev/null 2>&1 || ' +
        "{ echo ""$lacking"" >&2; exit $script:XmipTestComputerLacking; }; " +
        "exec pwsh -NoProfile -NonInteractive -Command '$command' < /dev/null")
    # No option after `--`, whatever the account or the host begins with.
    [string[]] $argument = @(Get-XmipTestComputerOption -Computer $Computer) + '--' +
        "$($Computer.User)@$($Computer.Host)" + $remote

    [System.Collections.Generic.List[string]] $out = @()
    [System.Collections.Generic.List[string]] $err = @()
    [bool] $show = $Asked -in 'start', 'observe'

    # What a cmdlet says there is shown as it says it, all but its answer and
    # any control character, which this console would obey: a title, a link,
    # a write to the clipboard.
    & ssh @argument 2>&1 | ForEach-Object {
        [string] $line = "$_" -replace $script:XmipTestComputerUnprintable, ''

        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $err.Add($line)
            return
        }

        $out.Add($line)

        if ($show -and -not $line.StartsWith($script:XmipTestComputerAnswer, 'Ordinal')) {
            Write-Host "$($Computer.Name)| $line"
        }
    }

    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out.ToArray(); Err = $err.ToArray() }
}


function Get-XmipTestComputerOption {
    <#
        .SYNOPSIS
            What ssh and scp are given for the computer: its key, no prompt,
            and ten seconds to connect. The host's key is checked against
            this account's known hosts, as every ssh checks it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer
    )

    return @('-i', $Computer.Key, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')
}
