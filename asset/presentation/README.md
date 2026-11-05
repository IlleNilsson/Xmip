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
hosts, each welcoming and flexing. `audio/` holds their approved voice tracks
and generated sentence timing. These PNGs and WAVs are generated assets.
The logo stays in [the brand directory](../brand/README.md).

## Presentation conventions

- Explain Xmip through its own purpose and strengths. Do not name competitors,
  shame other products or users, or imply superiority through belittling comparisons.
- Use English. Pronounce Xmip as **Smip**, one syllable.
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

## Authoring tools

The tools in `tools/` preserve the authoring workflow. They are publishing
helpers, not Xmip runtime code or estate dependencies. They use external media
libraries because Xmip does not supply slide, voice or video authoring tools.
Temporary transfer data, renders and caches stay in `.ai-interaction/presentation/`.

Requirements: Python 3.11+ with tomllib, Node.js, the Codex presentation runtime's
@oai/artifact-tool, Playwright with Chromium, and, only when voices change,
kokoro-js with @huggingface/transformers and a local
onnx-community/Kokoro-82M-v1.0-ONNX fp32 model cache.

Set PRESENTATION_NODE_MODULES to the external node_modules directory for the tool
being run. Set PRESENTATION_BROWSER to a Chromium executable, or install
Playwright's default Chromium. Set PRESENTATION_MODEL_CACHE for voice generation.
The authoring tools use no machine-specific paths; model weights stay local.
Voices are af_heart
(female) and am_michael (male), at speed 1.

From the repository root:

```text
python asset/presentation/tools/prepare.py --validate
python asset/presentation/tools/prepare.py
node asset/presentation/tools/render-slides.mjs
node asset/presentation/tools/render-video.mjs --check-only
```

Preparation does not reuse narration whose transcript differs from the story.
After editing narration, run tools/narrate.mjs with its dependencies and model
cache configured, then prepare.py --collect-narration to collect matching WAVs
and timing into this directory. Prepare again before rendering. Unchanged
approved tracks are reused.

The slide renderer writes build/draft-overview.pptx beneath the working area.
Use the presentation skill's finalization checks and inspect rendered slides
before replacing the tracked PowerPoint. Run the video renderer without
--check-only for the full animation and SRT; recording runs in real time.
Outputs are beneath the working area's output/ directory. Review playback,
scene boundaries and captions before replacing the tracked files. Keep the short
tracked filenames above. The current video was compressed after rendering;
a fresh render need not be byte-identical.

Commit the story, changed media and both final formats together. Follow
[CONTRIBUTING.md](../../CONTRIBUTING.md) for the repository workflow.
