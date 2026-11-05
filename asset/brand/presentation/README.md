# Xmip presentation material

The English, self-guided Xmip overview for CEOs, CIOs, developers and operators.
This directory is the working home for both formats. Revise them together.

## View

- [PowerPoint: 28 slides](Xmip-overview.pptx)
- [Animated video: about 11 minutes 26 seconds](Xmip-overview.mp4)
- [Video captions](Xmip-overview.srt)

The media uses Git LFS. After cloning, run `git lfs pull` to obtain the actual
files. The current exports were reviewed on 2026-11-05. Project source references
record the documentation used, rather than a promise of release readiness.

## Edit

`story.xmip` is the shared editorial source, in TOML. Each section contains
slide layout text, concise video text, narration, host selection and project
source references. The PowerPoint is editable; carry textual corrections back
into the story so the video does not drift from it.

`assets/` holds four approved transparent character images: female and male
hosts, each welcoming and flexing. `audio/` holds their current voice tracks
and generated sentence timing. These PNGs and WAVs are generated assets.
The logo stays in [the brand directory](../README.md).

## Presentation conventions

- Explain Xmip through its own purpose and strengths. Do not name competitors,
  shame other products or users, or imply superiority through belittling comparisons.
- Use English. Pronounce Xmip as **Smip**, one syllable.
- Keep the female voice as the reference for a warm, conversational pairing.
  The male voice should be light and friendly, with comparable pace and loudness.
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

The Python preparation helper requires Python 3.11+ with tomllib. From the root:

```text
python asset/brand/presentation/tools/prepare.py --validate
python asset/brand/presentation/tools/prepare.py
```

Preparation checks project source references and writes temporary JSON transfer
data plus copies of matching voice tracks and host images into the working area.
JSON here is an interchange format; the tracked editorial source is TOML.
It does not reuse a voice track when its transcript differs from the story.

For replacement narration, retain the approved pronunciation and voice character.
The current tracks use Kokoro-82M-v1.0-ONNX, fp32, af_heart (female) and
am_puck (male), generated at speed 1. The male sentences are tempo-matched to
the checked-in caption durations, preserving pitch. Both voices use two-pass
loudness normalization targeting -18 LUFS, a -2 dBTP ceiling and an 11 LU
loudness range. Preserve sentence timing when replacing audio in the existing
video; otherwise regenerate its captions and scene timing together.
Model weights and voice tooling stay outside Git.
Place regenerated overview-narration-N.wav and overview-narration-N.json files
in the working area's build/ directory, with N starting at zero. Timing JSON
is an array of sentence objects containing text, start and duration in seconds.
Run prepare.py --collect-narration to validate and collect matching audio and
timing, then run preparation again before rendering.

Inspect slides and validate the PowerPoint package before replacing the tracked
deck. Review video playback, scene boundaries and captions before replacing the
MP4 and SRT. The current video was compressed after rendering; a new render need
not be byte-identical. Keep the short tracked filenames above.

Commit the story, changed media and both final formats together. Follow
[CONTRIBUTING.md](../../../CONTRIBUTING.md) for the repository workflow.
