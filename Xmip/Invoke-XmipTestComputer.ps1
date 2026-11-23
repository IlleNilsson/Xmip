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

    Over ssh a shell runs $script:XmipTestComputerShell: it receives a send
    into the mirror, or makes the copy, <folder>/xmip, the mirror as sent
    with what runs left in it kept, gives a run the environment it builds in
    and one of the computer's build slots, and starts pwsh in the copy. The
    slot is a lock on ~/slot<n>.lock, which every builder there takes, held
    by the run's own processes until the last of them ends. Where every slot
    is taken the start waits, as every builder there waits, saying once a
    minute who holds them; a wait whose console has gone ends at that line,
    since it cannot be written, so nothing starts later on its own (the
    owner, 2026-09-12: nothing starts itself). What the computer says is
    shown here as it says it, prefixed with its name.

    Style: doc/governance/powershell-style.md
#>


# What the computer's shell runs: $1 the folder under the account's home,
# $2 what is asked, $3 how many build slots, $4 the working area's name
# (Get-XmipEstateLayout), $5 what is given: for receive, whole or
# difference; for start and observe, the pwsh command, encoded.
[string] $script:XmipTestComputerShell = @'
set -eu
folder=$HOME/$1; asked=$2; slots=$3; work=$4; given=${5:-}
mirror=$folder/mirror; tree=$folder/xmip
case $asked in
probe)
  mkdir -p "$folder"
  if [ -d "$mirror" ]; then echo held; else echo none; fi
  exit 0 ;;
receive)
  if [ "$given" = whole ]; then rm -rf "$mirror"; fi
  mkdir -p "$mirror"
  if [ -s "$folder/send.tar" ]; then tar -xf "$folder/send.tar" -C "$mirror"; fi
  if [ -s "$folder/gone.txt" ]; then
    (cd "$mirror" && xargs -d '\n' rm -f -- < "$folder/gone.txt")
  fi
  rm -f "$folder/send.tar" "$folder/gone.txt"
  exit 0 ;;
esac
if [ "$asked" = observe ] && [ ! -d "$tree" ]; then
  echo "REFUSED. Nothing was ever started here: $tree is not there." >&2
  exit 7
fi
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export PATH="$HOME/.local/bin:$PATH"
export CARGO_TARGET_DIR="$folder/target"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Local endpoints in the folder, never under /run/user/<uid>, which the
# system removes when the account's last session ends, a detached run's ssh
# among them.
export XMIP_RUNTIME_DIRECTORY="$folder/run"
mkdir -p -m 700 "$XMIP_RUNTIME_DIRECTORY"
# No .NET build server outlives its build, holding the slot (2026-11-20).
export MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_USE_MSBUILD_SERVER=0 UseSharedCompilation=false
# -Command, never -EncodedCommand: pwsh given an encoded command also writes
# what it shows to stderr as CLIXML, which PowerShell at the other end shows again.
run="& ([scriptblock]::Create([Text.Encoding]::UTF8.GetString("
run="$run[Convert]::FromBase64String('$given'))))"
if [ "$asked" = observe ]; then
  cd "$tree"
  exec pwsh -NoProfile -NonInteractive -Command "$run" < /dev/null
fi
mkdir -p "$tree"
# One run in a copy at a time: a start never rewrites a tree a run works in.
for p in /proc/[0-9]*; do
  case "$(readlink "$p/cwd" 2>/dev/null)" in "$tree"|"$tree"/*)
    echo "REFUSED. A run is going on in $tree, pid ${p#/proc/}: stop it, or name" \
      "another computer file with a folder of its own." >&2
    exit 5 ;;
  esac
done
rsync -a --delete --filter="P /$work/" --filter='P /.git/' --filter='P obj/' \
  --filter='P bin/Debug/' --filter='P bin/Release/' --filter='P node_modules/' \
  "$mirror/" "$tree/" > "$folder/rsync.log"
cd "$tree"
# Tests read git ls-files: the copy is one repository of what the estate
# holds, its .gitignore files deciding, as they do at home.
[ -d .git ] || git init -q
git add -A
# A build slot, as every builder here takes one, waited for while every slot
# is taken, who holds them said once a minute. A wait whose console has gone
# ends at its next line, which cannot be written, and starts nothing.
holders() {
  for n in $(seq 1 "$slots"); do
    for p in /proc/[0-9]*; do
      if ls -l "$p/fd" 2>/dev/null | grep -q "/slot$n.lock"; then
        printf ' slot%s, %s;' "$n" "$(ps -o pid=,etime=,args= -p "${p#/proc/}" | cut -c1-80)"
        break
      fi
    done
  done
}
taken=; waited=0
while :; do
  for n in $(seq 1 "$slots"); do
    exec 9>"$HOME/slot$n.lock"
    if flock -n 9; then taken=$n; break 2; fi
    exec 9>&-
  done
  if [ $((waited % 60)) -eq 0 ]; then echo "Waiting for a build slot:$(holders)"; fi
  sleep 5; waited=$((waited + 5))
done
echo "Build slot $taken of $slots taken."
exec setsid --wait pwsh -NoProfile -NonInteractive -Command "$run" < /dev/null
'@

# What starts the line carrying a cmdlet's answer, among the lines it said.
[string] $script:XmipTestComputerAnswer = 'xmip-answer '


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

    if ($AllowAbsent -and $answer.Code -eq 7) {
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
            Runs $script:XmipTestComputerShell on the computer over ssh and
            returns Code, its exit code; Out, what it wrote; and Err, what it
            wrote as errors. The one place the module calls ssh.

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

    # The script travels encoded, so no shell reads it but the one that runs
    # it, with line feeds alone whatever this file was checked out with.
    [string] $shell = $script:XmipTestComputerShell.Replace("`r`n", "`n")
    [string] $packed = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($shell))
    [string] $work = Split-Path -Leaf -Path (Get-XmipEstateLayout).Work
    [string] $remote = ("bash -c ""`$(echo $packed | base64 -d)"" xmip " +
        "$($Computer.Folder) $Asked $($Computer.Slots) $work $Given").TrimEnd()
    [string[]] $argument = @(Get-XmipTestComputerOption -Computer $Computer) +
        "$($Computer.User)@$($Computer.Host)" + $remote

    [System.Collections.Generic.List[string]] $out = @()
    [System.Collections.Generic.List[string]] $err = @()
    [bool] $show = $Asked -in 'start', 'observe'

    # What a cmdlet says there is shown as it says it, all but its answer.
    & ssh @argument 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $err.Add("$_")
            return
        }

        [string] $line = "$_"
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


function Assert-XmipTestComputerAnswer {
    <#
        .SYNOPSIS
            Refuses, in the computer's own words, an answer whose exit code
            is not zero.

        .PARAMETER Doing
            What was asked, for the words.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [pscustomobject] $Answer,

        [Parameter(Mandatory)]
        [string] $Doing
    )

    if ($Answer.Code -eq 0) {
        return
    }

    [string] $said = (@($Answer.Err) + @($Answer.Out | Select-Object -Last 3)) -join ' '

    if ($said -match '^\s*REFUSED') {
        throw $said.Trim()
    }

    throw "FAILED. $($Computer.Name) could not $Doing (exit $($Answer.Code)): $said"
}


function Read-XmipTestComputerAnswer {
    <#
        .SYNOPSIS
            What a cmdlet answered on the computer, as objects, from the one
            line among what it wrote that carries its answer; a failure
            refused in the computer's words.

        .PARAMETER Doing
            The cmdlet, for the words of a failure.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [pscustomobject] $Answer,

        [Parameter(Mandatory)]
        [string] $Doing
    )

    [string] $sent = ''

    foreach ($line in @($Answer.Out)) {
        if ($line.StartsWith($script:XmipTestComputerAnswer, [StringComparison]::Ordinal)) {
            $sent = $line.Substring($script:XmipTestComputerAnswer.Length)
        }
    }

    Assert-XmipTestComputerAnswer -Computer $Computer -Answer $Answer -Doing "run $Doing"

    if ($sent -eq '') {
        return
    }

    [string] $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($sent))

    return [System.Management.Automation.PSSerializer]::Deserialize($text)
}
