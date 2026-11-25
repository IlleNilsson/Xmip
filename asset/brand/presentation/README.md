# Xmip presentation material

The English, self-guided Xmip overview for CEOs, CIOs, developers and operators,
and the environment deck beside it. This directory is the working home for the
overview's both formats. Revise them together.

## View

- [PowerPoint: 16 slides](Xmip-overview_en-US.pptx)
- [Animated video: about 10 minutes](Xmip-overview_en-US.mp4)
- [Video captions](Xmip-overview_en-US.srt)
- [The environment, PowerPoint: 4 slides](Xmip-environment.pptx): the nodes
  Xmip's tests and demos run, the functions beside the message path, the
  machines and four ways to run one plan. Every node in it is optional; Xmip
  runs on one node with all roles. Its shapes and tables are editable.

The media uses Git LFS. After cloning, run `git lfs pull` to obtain the actual
files. Narration, flex poses and accessibility notes were updated on 2026-11-07.
On 2026-11-22 the node roles, the parts around the nodes and the five ways to
run one plan were added, and the integration path replaced the Application
section in both formats. On 2026-11-23 the story, the deck, the video and its
captions took the System Tests and the Systems Tests, and containers as the
sixth way to run the plan. On 2026-11-24 the overview was rebuilt as one
design in both formats: sixteen scenes, each with one message in large type
and a figure or a screenshot, current content, recorded figures, and the
video rendered from the deck's own slides; both decks count four ways to run
the plan, local processes, containers, virtual machines and physical
machines, the hypervisors being the virtual machines' (ADR-0015, amendment
2026-11-24). On 2026-11-25 *One order through Xmip* became one order followed
to completion, an example flow like one Xmip's own tests run and longer than
the System Tests': a Work Process Instance per order counting, in values of
its own, the lines ordered, delivered and accepted, every party's message
brought to it by a Correlation on the order number, goods shipped in parts, a
deadline of thirty days, and the operator's Instances view (ADR-0066,
amendment 2026-11-25; the owner, 2026-11-25: "In the presentation and video,
the work steps are too simplistic" and "Better scenario, a completion. Goods
can be shipped in parts"); and *Measured* counts 70 of the 88 transports
(ADR-0015, amendment 2026-11-25). The two scenes were voiced again, the other
fourteen tracks kept as they were, and the deck, the video and its captions
built again. The order example now also shows payment or an accepted promise
to pay, followed by factory production or fulfillment from warehouse stock.
Its title, diagram and narration explicitly identify an illustrative business
flow; its business steps and thirty-day deadline are choices for this example.
Slide 3, its voice track, accessibility notes and the video captions agree.
Project source references record
the documentation used, rather than a promise of release readiness.

## Outreach

The approved material was introduced to 34 public organizational contacts on
2026-11-05: national routes across 27 EU countries, two European Commission
teams and five companies. This was an initial batch, not exhaustive coverage.
The [outreach record](outreach/2026-11-05.xmip) preserves the recipients, official
contact sources, exact message wording and immutable links to the shared files.
All 34 send requests succeeded; recipient delivery and responses are not confirmed.

Private Outlook identifiers, mailbox links and raw tool responses remain in the
local working area. Review drafts remain in Outlook and must not be resent.

## Edit

`story.toml` is the shared editorial source, in TOML. Each section is one
scene: its one message (`headline`, the slide's title), its body (`screen`),
its figure (`layout`, `["scene", "<figure>"]`) and the figure's alt text
(`alt`), its narration, its host selection and its project source references.
The PowerPoint is editable; carry textual corrections back into the story so
the video does not drift from it.

`assets/` holds four approved transparent character images: female and male
hosts, each welcoming and flexing. `audio/` holds their current voice tracks
and generated sentence timing. These PNGs and WAVs are generated assets.
The logo stays in [the brand directory](../README.md).

## Presentation conventions

- Explain Xmip through its own purpose and strengths. Do not name competitors,
  shame other products or users, or imply superiority through belittling comparisons.
- Xmip stands for **Cross OS Messaging & Integration Platform**. Declare the full
  name in both openings, including video narration and captions.
- Use English. Pronounce Xmip as **Smip**, one syllable.
- Keep the female voice as the reference for a warm, conversational pairing.
  The male voice should sound natural, clear and assured, with comparable loudness.
  Avoid exaggerated character acting and slowed or stretched speech.
- The female host speaks first and stands to the left of the male. A solo female
  host also stands on the left.
- Keep the hosts fictional, ageless, modest and plainly drawn. Avoid realism,
  glamour and sexualization. Pointed ears are not required.
- Keep belts in Xmip brand lime, `#75c93b`. Use warm white and charcoal for
  large areas, with restrained green accents.
- Use flex poses for open source, TOML, VS Code configuration, phone operations
  and cross-operating-system working. Do not turn these into exclusivity claims.
- Keep architecture, working capabilities and validation milestones accurate,
  while concentrating on what Xmip offers its audience.
- Keep flex poses modest, with visible rounded biceps and restrained shoulders.
- Keep flex poses visual. Do not announce a "flex moment" in narration.
  Describe the poses in each affected slide's notes for accessibility; keep
  these descriptions in the story's `accessibility_notes` field.
- Review changed sections in both formats, including narration and captions.
  Keep slides understandable without a presenter.

## Authoring workflow

The editable PowerPoint and shared TOML story are the authoring masters.
Use the story's layout, screen text, narration and source references when
revising either format. The PNG artwork and WAV tracks can also be used in a
video editor. Retain the format, hosts and visual conventions above.

The repository does not track JavaScript or TypeScript publishing recipes.
A media-authoring session may generate temporary recipes in
`.ai-interaction/presentation/`, using the presentation skill or a media editor.
The project sources and approved media in this directory remain the durable inputs.
The environment deck is drawn the same way, through PowerPoint's COM
automation from PowerShell 7; the deck itself is its master.

Since 2026-11-24 each scene is drawn once, for both formats. The deck is built
from the story through PowerPoint's COM automation: the title and body are
PowerPoint text, the figure is drawn as SVG and placed as a PNG, and the
speaking host stands beside it. Each slide is then exported without its hosts,
and the video draws its animated hosts, captions and progress over that
export, so the two formats cannot drift apart. A title is at least 36 pt, body
text at least 20 pt, and no text in a figure under 16 pt on the slide. The
bottom band of every slide is where the video's captions run.

The media of 2026-11-22 were made this way. The deck was edited in PowerPoint
through its COM automation from PowerShell 7. The narration was generated with
kokoro-js on Node.js from the local model weights. The scenes were drawn on a
canvas and encoded in headless Microsoft Edge through Playwright. Loudness,
muxing and compression were done by ffmpeg called from PowerShell: H.264 High
at CRF 30, with AAC at 128 kb/s, 48 kHz stereo. A figure is placed as a PNG
drawn from its SVG by headless Edge, since an SVG inserted through automation
carries no fallback for viewers without SVG support. On 2026-11-23 the same
recipes ran on VS Code's own Node.js (`ELECTRON_RUN_AS_NODE`), with
playwright-core installed into the working area driving the installed
Microsoft Edge, never a downloaded browser.

The preparation helper is PowerShell 7, reading the TOML through the estate
module's one reader. From the root:

```powershell
./asset/brand/presentation/tools/prepare.ps1 -Validate
./asset/brand/presentation/tools/prepare.ps1
```

Preparation checks project source references and writes temporary JSON transfer
data plus copies of matching voice tracks and host images into the working area.
JSON here is an interchange format; the tracked editorial source is TOML.
It does not reuse a voice track when its transcript differs from the story.

For replacement narration, retain the approved pronunciation and voice character.
How the voice says a written term is `pronunciation.toml`, beside the story:
each acronym or technical term the narration uses, its spoken form as
practitioners say it aloud, a project's own stated pronunciation first and
cited, the common convention otherwise and marked so. It is applied to the
narration before synthesis only, the longest term first and only as a whole
word; the slides and the captions keep the written form. A narration that uses
a term the lexicon lacks gets the term added before it is narrated.
The current tracks use Kokoro-82M-v1.0-ONNX, fp32, af_heart (female) and
am_fenrir (male), generated at speed 1. Keep the natural generated cadence;
regenerate caption and scene timing to follow the speech instead of stretching
the recordings to old timings. Both voices use two-pass
loudness normalization targeting -18 LUFS, a -2 dBTP ceiling and an 11 LU
loudness range. Keep the female recordings unchanged when revising only the male
voice. Rebuild the video and captions whenever narration timing changes.
Model weights and voice tooling stay outside Git.
Place regenerated overview-narration-N.wav and overview-narration-N.json files
in the working area's build/ directory, with N starting at zero. Timing JSON
is an array of sentence objects containing text, start and duration in seconds.
Run `prepare.ps1 -CollectNarration` to validate and collect matching audio and
timing, then run preparation again before rendering.

Preparation refuses a story and `audio/timing.toml` with different numbers of
sections. When sections are added or removed, first re-index the voice tracks
and timing to the new order, giving a new section a placeholder caption that
preparation then asks to regenerate. To keep this directory untouched while
authoring, run an unchanged copy of it from `.ai-interaction/presentation/material/`;
the copy resolves the same repository root and working area.

Inspect slides and validate the PowerPoint package before replacing the tracked
deck. Review video playback, scene boundaries and captions before replacing the
MP4 and SRT. The current video was compressed after rendering; a new render need
not be byte-identical. Keep the short tracked filenames above.

Commit the story, changed media and both final formats together. Follow
[CONTRIBUTING.md](../../../CONTRIBUTING.md) for the repository workflow.
