import fs from "node:fs/promises";
import { task, external } from "./environment.mjs";
const { KokoroTTS } = await external("kokoro-js");
const { env, RawAudio, StyleTextToSpeech2Model, AutoTokenizer } = await external(
  "@huggingface/transformers",
);
env.cacheDir = process.env.PRESENTATION_MODEL_CACHE || task + "/model-cache";
env.allowRemoteModels = false;
console.log("Loading neural voices");
const modelId = "onnx-community/Kokoro-82M-v1.0-ONNX";
const model = await StyleTextToSpeech2Model.from_pretrained(modelId, {
  dtype: "fp32",
  device: "cpu",
  session_options: { intraOpNumThreads: 4, interOpNumThreads: 1 },
});
const tts = new KokoroTTS(model, await AutoTokenizer.from_pretrained(modelId));
const scenes = JSON.parse(await fs.readFile(task + "/build/story.json", "utf8"));
for (let i = 0; i < scenes.length; i++) {
  const out = task + "/build/overview-narration-" + i;
  try {
    await fs.access(out + ".wav");
    await fs.access(out + ".json");
    console.log("Retained", i + 1);
    continue;
  } catch {}
  const { voice, narration } = scenes[i];
  const sentences = narration.match(/[^.!?]+[.!?]+|[^.!?]+$/g);
  const samples = [];
  const timings = [];
  let count = 0;
  for (const sentence of sentences) {
    const spoken = sentence
      .replace(/Xmip/gi, "Smip")
      .replace(/TOML/g, "Tom ul")
      .replace(/C ABI/g, "C A B I")
      .replace(/MCP/g, "M C P")
      .replace(/TLS/g, "T L S")
      .replace(/BPMN/g, "B P M N")
      .replace(/VS Code/g, "Visual Studio Code")
      .replace(/macOS/g, "Mac O S");
    const a = await tts.generate(spoken, {
      voice: voice === "female" ? "af_heart" : "am_michael",
      speed: 1,
    });
    timings.push({
      text: sentence.trim(),
      start: count / 24000,
      duration: a.audio.length / 24000,
    });
    samples.push(a.audio, new Float32Array(4320));
    count += a.audio.length + 4320;
  }
  const merged = new Float32Array(count);
  let offset = 0;
  for (const a of samples) {
    merged.set(a, offset);
    offset += a.length;
  }
  let peak = 0;
  for (const v of merged) peak = Math.max(peak, Math.abs(v));
  if (peak > 0) for (let j = 0; j < merged.length; j++) merged[j] *= 0.9 / peak;
  await fs.writeFile(out + ".json", JSON.stringify(timings));
  await new RawAudio(merged, 24000).save(out + ".wav");
  console.log("Scene", i + 1, voice, (count / 24000).toFixed(2));
}
console.log("Complete");
process.exit(0);
