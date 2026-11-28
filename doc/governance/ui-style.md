# Xmip UI style

The rules every Xmip surface with a user interface follows: the VS Code
extension, the Operation Desktop and Mobile (one .NET MAUI app, its Android
build the phone app), and the web, the Operations Web and the Blazor
components it shares with the Desktop. Where a rule has a meaning for a text
surface, the command line and the PowerShell module follow it too, and the
rule says how. It is the companion to `rust-style.md` and
`powershell-style.md`, and the one home of these rules: a surface's README
says how it meets them, never the rules again.

What a surface says is the runtime's: its words, sentences and orders are
`operate::surface`'s, asked Rust to Rust or through the C ABI (ADR-0052,
amendment 2026-11-18), so a rule below about what is said is met once, in
the runtime, for every surface.

## 1. Tooltips explain and carry what lies beneath

The owner, 2026-11-28: *Also all UI need to use tooltips for explanation and
underlying information.*

Every control, figure, abbreviation, state and name a surface shows carries
a tooltip: what it is, what acting on it does, and the information beneath
it that the surface shows only in short. A tooltip adds; it is never the
only place something is said, since a keyboard or touch user and a screen
reader may not reach it (section 2), and it is the accessible description
of what it is on.

A name shown short carries its long form. A cluster is shown by the short
name its file declares, `[service] short_name`, and its tooltip carries the
file's name, the short name where it differs from the cluster's name, the
cluster's name its file declares and the file (ADR-0028, amendment
2026-11-28). Both are the runtime's rule,
`operate::surface::cluster_named`, asked through `xmip_cluster_said_v1`.

A text surface has no tooltip, and says beside the short form what a
tooltip would carry: `xmip health` writes the cluster's short name and, in
parentheses, the rest; `Get-XmipHealth` gives each row a `Cluster` and a
`ClusterTitle`.

## 2. The standard features

The owner approved these as estate rules on 2026-11-28: *Do it*.

1. **WCAG 2.2 AA.** Every control is reachable by the keyboard alone, with a
   focus that is visible on every theme; every item has an accessible name
   that says what it is and what it acts on, never the verb alone; text has
   a contrast of at least 4.5:1 against what it stands on, and a focus
   outline or a control's edge at least 3:1; and nothing is said by color
   alone: a state is said in words or a shape as well. CONTRIBUTING's *Say
   outcomes in words — OK, FAILED, REFUSED — never color alone* is this
   rule for the text surfaces.
2. **The theme follows the operating system**: light, dark and high
   contrast, the person's own choice kept where they make one. Brand green
   (`xmip.css`'s brand tokens) is an accent only, never a mood or a state:
   a mood has its own color and its own word.
3. **Usable at 200 % zoom and on a high DPI screen**: the layout reflows
   rather than scrolling sideways, a wide table scrolls inside its own box,
   and pinch zoom is never blocked. **Reduced motion is honored**: what
   moves stands still where the system asks for less motion.
4. **Every view has an empty, a loading and an error state**, each saying
   why and what to do next. A view is never blank, and a view that has not
   been answered yet says so rather than saying that nothing is there.
5. **Long work shows its progress with its ETA**: what it is doing, how far
   it has come and when it will be done, by what the same work took the
   last time where nothing better is known.
6. **A destructive act confirms first**, naming what goes, and offers undo
   where the act allows it. Remove, Dismiss, Revoke, Replay, Discard and a
   replacing Set are destructive acts.
7. **Lists and tables sort, filter and search**, and a value in them can be
   copied: an id, a scope, a fingerprint, a name.
8. **Help in place**: F1, or a link to the view's documentation, from every
   view.
9. **Keyboard shortcuts** for the acts a person repeats, said in the
   control's tooltip and accessible name, and **a command palette on the
   Desktop**.
10. **Layout and the last view are remembered**: the arrangement, the theme
    and the view a person was on come back as they left them, by the
    surface's own preference store, never by guessing.
11. **Text is kept in resources**, never as literals in markup, and **dates
    and numbers are said by one rule**, the runtime's, in US English for
    now: one time zone and one form for a moment, one grouping for a
    figure.

## 3. Where the surfaces stand

The audit of 2026-11-28 held each surface against these rules and recorded
every gap as an open problem with its size, in
`doc/planning/open-problems.md`, one per surface: 241 the VS Code
extension, 242 the Operation Desktop's own pages, 243 the web and the views
it shares with the Desktop and the phone, and 244 the phone app. Each cites
this document's section 1 and the items of its section 2 by number. A rule a test can hold gets the test as its problem
is built, as the rest of the estate's style is held by `test/*.Test.ps1`.
