# ADR-0055: Bad input is refused at the door

- Status: Accepted
- Date: 2026-09-19
- Related: ADR-0014 (the operator surfaces), ADR-0011 (names), ADR-0052
  (the operator surfaces share one model), ADR-0028 (the Playground),
  ADR-0053 (every System Process says whose it is)

## In brief

- Theme: Operating Xmip
- Subject: When an operator surface checks what it was given, and what it
  says when the answer is no
- Name: Bad input is refused at the door
- Order: 14
- Concepts: refusal at the door; offered choice; late failure

**Every operator surface — the PowerShell module, the CLI and the web GUI
— checks what it was given at the earliest point it can, and refuses in
words that name what was wrong and what would be right. Better than
refusing is not letting it be said: where the set of right answers is
known, the surface offers that set and takes nothing else.**

## Context

The owner, 2026-09-19, after an afternoon of surfaces that took a wrong
thing quietly and failed somewhere else: *if the PowerShell cmdlets or CLI
and GUI get invalid input it shall be validated as soon as possible and
reported back to the user. Even better the user shall not be able to do
faulty parameters or selections.*

That afternoon produced the evidence.

- `Start-XmipOperationWeb` with no `-Snapshot` started a host that read
  its own document and showed an empty page. Nothing was wrong enough to
  report, and nothing was right. The owner asked three times why he saw
  nothing.
- A second host on an address the first still held died on the taken port
  and printed nothing at all. The owner was reading a host from an hour
  before and could not have known.
- `Get-XmipTestStatus | Start-XmipOperationWeb` with nothing rolling
  named no run, and started a host over no surface.
- The Playground's roll met a scenario name it did not know, wrote one
  line to standard error and rolled on without it. A typo cost a whole
  run.

None of these was a crash. Each was a surface that took what it was given,
did something defensible with it, and left the operator to work out from
an empty page what it had decided.

## Decision

1. **The door is the parameter, not the body.** Where the right answers
   are a fixed set, a range or a pattern, the surface declares it where
   the caller is bound: `ValidateSet`, `ValidateRange`, `ValidatePattern`,
   a parameter set, a typed enum. A check in the body of a function runs
   after the caller has already been accepted, and a check in the body is
   the last resort, not the first.

2. **What cannot be declared is checked first.** A file that must exist,
   an address that must be free, a roster that must hold a role: these
   cannot be a `ValidateSet`, so they are the first thing the body does,
   before anything is started, written or spawned. Nothing is half done
   before the refusal.

3. **A refusal says three things**: that it refused, what was wrong, and
   what would be right. It begins with the word REFUSED. It names the
   value it got and the values it would take. The estate says its
   outcomes in words (CLAUDE.md), and a refusal is an outcome.

4. **Better than refusing is offering.** Where the set is known, the
   surface offers it: tab completion on a PowerShell parameter, the
   commands and options in the CLI's usage, a list or a disabled control
   in the web GUI. A wrong value the operator cannot type is a refusal
   that never has to be written.

5. **Silence is not an answer.** A surface that cannot do what it was
   asked never carries on with something else instead. It refuses, or —
   where carrying on is right but is not what the operator probably meant
   — it says so with a warning that names the better command.

6. **Every refusal is tested.** A refusal is a behavior of the surface,
   so it has a test beside the others, asserting the words and that
   nothing was started.

## Consequences

- Built the same day, from the evidence above:
  - `Start-XmipOperationWeb` refuses an address that already answers and
    names the pid holding it; refuses an empty pipeline, which means
    nothing is rolling; and warns, when a roll is running and no
    `-Snapshot` was given, that this host will not show it and how to
    follow it.
  - The Playground's roll refuses an unknown scenario name and lists the
    names there are, instead of printing and rolling on.
  - `Start-XmipTest` refuses a RoundTrip over role nodes whose roster has
    no R, no P or no S, before anything is spawned.
  - Each has a test asserting the refusal and that nothing started.
- `Start-XmipTest` already declares most of its shape at the door:
  `-Suite` and `-Stress` are sets, `-Rounds` and `-TimeFactor` are
  ranges, `-Cluster` and `-LoadBytes` are patterns, `-Test` offers its
  names through an argument completer, and node names are asserted before
  a process is spawned.
- **Still open.** `-Test` is offered but not bound to its set, because
  the set differs by suite; a wrong test name is caught in the body.
  `Start-XmipOperationWeb -Snapshot` takes a path that does not exist and
  `-Url` takes text that is not an address. The web GUI has not been
  audited against clause 4. These are named here so the gap is on the
  record rather than in someone's memory.

## Alternatives considered

**Validate at the point of use.** It is where the knowledge is, and it is
what produced every failure in the Context: by then a process is started,
a file is written, and the operator is reading an empty page instead of a
sentence.

**Throw and let the message carry it.** A stack trace names the line that
threw, not the value the operator typed or the value they should have
typed. The estate already rules that outcomes are said in words.

**Make everything mandatory.** It would refuse the empty case and it
would also refuse the ordinary one: `Start-XmipTest -Suite Estate` needs
no cluster, and a mandatory parameter prompts, which is a question asked
of a script that cannot answer.

## Provenance

The requirement is the owner's, 2026-09-19, quoted in the Context. The six
clauses, the evidence and what was built are the assistant's drafting of
it, for the owner to confirm or strike.
