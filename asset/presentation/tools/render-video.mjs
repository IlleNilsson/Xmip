import fs from "node:fs/promises";
import path from "node:path";
import { root, task, external } from "./environment.mjs";
const { chromium } = await external("playwright");
const data = JSON.parse(await fs.readFile(task + "/build/story.json", "utf8"));
const browser = await chromium.launch({
  executablePath: process.env.PRESENTATION_BROWSER,
  headless: true,
  args: ["--autoplay-policy=no-user-gesture-required"],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const assets = {};
for (const g of ["male", "female", "male-power", "female-power"])
  assets[g] =
    "data:image/png;base64," +
    (
      await fs.readFile(task + "/output/brand-presenters/xmip-" + g + "-host.png")
    ).toString("base64");
assets.logo =
  "data:image/png;base64," +
  (await fs.readFile(path.join(root, "asset/brand/xmip-logo.png"))).toString("base64");
const audio = [],
  captions = [];
for (let i = 0; i < data.length; i++) {
  audio.push(
    (await fs.readFile(task + "/build/overview-narration-" + i + ".wav")).toString(
      "base64",
    ),
  );
  captions.push(
    JSON.parse(
      await fs.readFile(task + "/build/overview-narration-" + i + ".json", "utf8"),
    ),
  );
}
await page.setContent(
  '<body style="margin:0"><canvas width="1280" height="720"></canvas></body>',
);
const timing = await page.evaluate(
  async ({ data, assets, audio, captions }) => {
    const ctx = document.querySelector("canvas").getContext("2d"),
      c = ctx.canvas,
      pics = {};
    for (const [k, src] of Object.entries(assets)) {
      pics[k] = new Image();
      pics[k].src = src;
      await pics[k].decode();
    }
    const ac = new AudioContext(),
      buffers = [];
    for (const b64 of audio)
      buffers.push(
        await ac.decodeAudioData(
          Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)).buffer,
        ),
      );
    const starts = [];
    let total = 0;
    for (const b of buffers) {
      starts.push(total);
      total += Math.max(12, b.duration + 2);
    }
    function text(str, x, y, w, size, color, bold = false) {
      ctx.font = (bold ? "bold " : "") + size + "px Arial";
      ctx.fillStyle = color;
      let yy = y;
      for (const row of str.split("\n")) {
        let line = "";
        for (const word of row.split(" ")) {
          const test = line ? line + " " + word : word;
          if (ctx.measureText(test).width > w) {
            ctx.fillText(line, x, yy);
            yy += size * 1.25;
            line = word;
          } else line = test;
        }
        ctx.fillText(line, x, yy);
        yy += size * 1.25;
      }
      return yy;
    }
    window.draw = (t) => {
      const k = Math.max(
          0,
          starts.findLastIndex((s) => s <= t),
        ),
        local = t - starts[k],
        length = (starts[k + 1] ?? total) - starts[k],
        d = data[k],
        pair = String(d.power).startsWith("both"),
        femaleSolo = d.voice === "female" && !pair;
      ctx.fillStyle = "#242a30";
      ctx.fillRect(0, 0, 1280, 720);
      ctx.globalAlpha = Math.min(1, local * 2, Math.max(0, (length - local) * 2));
      text("XMIP", 64, 54, 700, 23, "#b3c6a7", true);
      if (k === 0) {
        ctx.drawImage(pics.logo, 64, 88, 300, 136);
        text(d.headline, 64, 300, 750, 45, "#fff", true);
        text(
          "Open-source Rust platform · On premises first",
          64,
          460,
          760,
          27,
          "#d0d4d8",
        );
        text("CEO, CIO, Developer and Operator", 64, 510, 760, 25, "#d0d4d8");
      } else {
        const x = femaleSolo ? 390 : 64,
          w = femaleSolo ? 820 : 780;
        text(d.title, 64, 130, 1140, 42, "#fff", true);
        text(d.headline, x, 235, w, 36, "#b3c6a7", true);
        text(d.screen, x, 352, w, 28, "#d0d4d8");
        if (d.note && k !== 27) text(d.note, x, 542, w, 16, "#d0d4d8");
      }
      const sway = Math.sin(local * 1.5) * 2;
      function actor(g, x, y, w) {
        ctx.save();
        ctx.translate(x + w / 2, y + w * 1.5);
        ctx.rotate(Math.sin(local * 1.4) * 0.004);
        ctx.drawImage(pics[g], -w / 2, -w * 1.5 + sway, w, w * 1.5);
        ctx.restore();
      }
      if (pair) {
        const suffix = d.power === "both-power" && local >= 2 ? "-power" : "";
        actor("female" + suffix, 860, 225, 180);
        actor("male" + suffix, 1030, 225, 180);
      } else
        actor(
          d.voice + (d.power && local >= 2 ? "-power" : ""),
          femaleSolo ? 64 : 915,
          165,
          280,
        );
      ctx.globalAlpha = 1;
      ctx.fillStyle = "#1b2025";
      ctx.fillRect(0, 590, 1280, 130);
      const vtime = Math.max(0, local - 0.5),
        sentences = captions[k];
      const sentence =
        sentences[
          Math.max(
            0,
            sentences.findLastIndex((s) => s.start <= vtime),
          )
        ];
      const words = sentence.text.split(" "),
        chunks = [],
        chunkSize = Math.ceil(words.length / Math.ceil(words.length / 14));
      for (let j = 0; j < words.length; j += chunkSize)
        chunks.push(words.slice(j, j + chunkSize).join(" "));
      const ci = Math.min(
        chunks.length - 1,
        Math.floor(
          (Math.max(0, vtime - sentence.start) / sentence.duration) * chunks.length,
        ),
      );
      text(chunks[ci], 64, 627, 1152, 25, "#fff");
      ctx.fillStyle = "#596168";
      ctx.fillRect(64, 693, 1152, 3);
      ctx.fillStyle = "#b3c6a7";
      ctx.fillRect(64, 693, (1152 * t) / total, 3);
    };
    window.record = async () => {
      await ac.resume();
      const dest = ac.createMediaStreamDestination(),
        stream = new MediaStream([
          ...c.captureStream(24).getVideoTracks(),
          ...dest.stream.getAudioTracks(),
        ]);
      const mime = "video/mp4;codecs=avc1.42001E,mp4a.40.2";
      const rec = new MediaRecorder(stream, {
          mimeType: mime,
          videoBitsPerSecond: 4500000,
        }),
        chunks = [];
      rec.ondataavailable = (e) => {
        if (e.data.size) chunks.push(e.data);
      };
      const stopped = new Promise((r) => (rec.onstop = r));
      rec.start(1000);
      const start = ac.currentTime;
      buffers.forEach((b, i) => {
        const s = ac.createBufferSource();
        s.buffer = b;
        s.connect(dest);
        s.start(start + starts[i] + 0.5);
      });
      await new Promise((resolve) => {
        function frame() {
          const t = ac.currentTime - start;
          window.draw(Math.min(t, total - 0.05));
          if (t < total) requestAnimationFrame(frame);
          else resolve();
        }
        requestAnimationFrame(frame);
      });
      rec.stop();
      await stopped;
      const bytes = new Uint8Array(await new Blob(chunks, { type: mime }).arrayBuffer());
      let binary = "";
      for (let i = 0; i < bytes.length; i += 32768)
        binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
      return btoa(binary);
    };
    return { starts, durations: buffers.map((b) => b.duration), total };
  },
  { data, assets, audio, captions },
);
function stamp(s) {
  const ms = Math.round(s * 1000);
  return (
    String(Math.floor(ms / 3600000)).padStart(2, "0") +
    ":" +
    String(Math.floor(ms / 60000) % 60).padStart(2, "0") +
    ":" +
    String(Math.floor(ms / 1000) % 60).padStart(2, "0") +
    "," +
    String(ms % 1000).padStart(3, "0")
  );
}
let lines = [],
  n = 0;
for (let i = 0; i < data.length; i++)
  for (const sentence of captions[i]) {
    lines.push(
      String(++n),
      stamp(timing.starts[i] + 0.5 + sentence.start) +
        " --> " +
        stamp(timing.starts[i] + 0.5 + sentence.start + sentence.duration),
      sentence.text,
      "",
    );
  }
await fs.writeFile(task + "/output/Xmip-overview-presentation.srt", lines.join("\n"));
console.log(JSON.stringify(timing));
await fs.writeFile(task + "/build/overview-timing.json", JSON.stringify(timing));
for (let i = 0; i < data.length; i++) {
  await page.evaluate((t) => window.draw(t), timing.starts[i] + 5);
  await page.screenshot({ path: task + "/build/overview-scene-" + (i + 1) + ".png" });
}
if (!process.argv.includes("--check-only")) {
  console.log("Recording");
  const r = await page.evaluate(() => window.record());
  await fs.writeFile(
    task + "/output/Xmip-overview-presentation.mp4",
    Buffer.from(r, "base64"),
  );
  console.log("Saved mp4");
}
await Promise.race([browser.close(), new Promise((r) => setTimeout(r, 2000))]);
process.exit(0);
