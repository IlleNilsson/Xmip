import fs from "node:fs/promises";
import path from "node:path";
import { root, task, external } from "./environment.mjs";
const { Presentation, PresentationFile } = await external("@oai/artifact-tool");
const data = JSON.parse(await fs.readFile(task + "/build/story.json", "utf8"));
const p = Presentation.create({ slideSize: { width: 1280, height: 720 } });
p.theme.defaultFont = "Arial";
const actors = {};
for (const g of ["male", "female", "male-power", "female-power"]) {
  const b = await fs.readFile(task + "/output/brand-presenters/xmip-" + g + "-host.png");
  actors[g] = b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
}
function text(s, value, x, y, w, h, size, color, bold = false) {
  const q = s.shapes.add({
    geometry: "textbox",
    position: { left: x, top: y, width: w, height: h },
    fill: "none",
    line: { fill: "none", width: 0 },
  });
  q.text = value;
  q.text.style = { typeface: "Arial", fontSize: size, color, bold };
  return q;
}
function host(s, g, x, y, w) {
  s.images.add({
    blob: actors[g],
    contentType: "image/png",
    position: { left: x, top: y, width: w, height: w * 1.5 },
    fit: "contain",
    alt: "Fictional illustrated " + g + " Xmip presenter",
  });
}

const layouts = data.map((d) => d.layout);
const chapter = (i) =>
  i < 4
    ? "PURPOSE"
    : i < 8
      ? "MESSAGE FLOW"
      : i < 14
        ? "DESIGN AND EXTENSION"
        : i < 19
          ? "DEPLOYMENT"
          : i < 24
            ? "OPERATIONS"
            : "THE PROJECT";
for (let i = 0; i < data.length; i++) {
  const d = data[i],
    l = layouts[i],
    kind = l[0],
    s = p.slides.add();
  const feature = kind.startsWith("feature");
  const dark = [0, 4, 8, 12, 15, 18, 22, 27].includes(i),
    ink = dark ? "#FAF9F6" : "#242A30",
    muted = dark ? "#D0D4D8" : "#596168",
    accent = dark ? "#B3C6A7" : "#526D46";
  s.background.fill = dark ? "#242A30" : "#FAF9F6";
  const tx = (value, x, y, w, h, size = 26, color = ink, bold = false) =>
    text(s, value, x, y, w, h, size, color, bold);
  if (kind === "cover") {
    const b = await fs.readFile(path.join(root, "asset/brand/xmip-logo.png"));
    s.images.add({
      blob: b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength),
      contentType: "image/png",
      position: { left: 64, top: 55, width: 280, height: 127 },
      fit: "contain",
    });
    tx(l[1], 555, 160, 655, 255, 58, ink, true);
    tx("A self-guided introduction to Xmip", 560, 460, 620, 65, 26, muted);
    tx("CEO, CIO, Developer and Operator", 560, 548, 620, 60, 23, muted);
    host(s, "female", 64, 305, 210);
    host(s, "male", 270, 305, 210);
  } else if (kind === "feature") {
    const female = d.voice === "female",
      x = female ? 465 : 64,
      w = female ? 740 : 785;
    tx("XMIP STRENGTH", 64, 42, 800, 36, 22, "#596168", true);
    tx(l[1], x, 112, w, 160, 58, "#242A30", true);
    l[2].forEach((r, j) => {
      tx(r[0], x, 310 + j * 94, w, 32, 24, "#242A30", true);
      tx(r[1], x, 344 + j * 94, w, 63, 24, "#596168");
    });
    host(s, d.voice + "-power", female ? 64 : 920, 205, female ? 325 : 295);
    const small =
      i === 20
        ? "Mobile design; device validation remains ahead"
        : i === 24
          ? "AGPL-3.0-or-later"
          : "";
    if (small) tx(small, x, 635, w, 40, 18, "#596168");
  } else if (kind === "feature-pair") {
    tx("XMIP STRENGTH", 64, 42, 800, 36, 22, "#596168", true);
    tx(l[1], 64, 105, 1150, 165, 58, "#242A30", true);
    tx(l[2], 64, 290, 1120, 60, 34, "#242A30", true);
    host(s, "female-power", 64, 380, 200);
    host(s, "male-power", 260, 380, 200);
    tx(l[3], 555, 390, 650, 240, 30, "#596168");
  } else if (kind === "closing") {
    tx("XMIP IN ONE VIEW", 64, 38, 1100, 36, 22, accent, true);
    tx(l[1], 64, 100, 1130, 175, 60, ink, true);
    tx(l[2], 560, 305, 650, 105, 32, accent, true);
    host(s, "female", 64, 385, 180);
    host(s, "male", 245, 385, 180);
    l[3].forEach((r, j) => {
      const x = 560 + (j % 2) * 330,
        y = 465 + Math.floor(j / 2) * 95;
      tx(r[0], x, y, 300, 34, 23, accent, true);
      tx(r[1], x, y + 35, 305, 55, 23, muted);
    });
  } else {
    tx(chapter(i), 64, 30, 1120, 34, 18, accent, true);
    tx(l[1], 64, 92, 1148, 110, 44, ink, true);
    if (kind === "split")
      l[2].forEach((r, j) => {
        const x = 64 + j * 600;
        tx(r[0], x, 230, 548, 40, 23, accent, true);
        tx(r[1], x, 290, 548, 100, 38, ink, true);
        tx(r[2], x, 415, 548, 130, 27, muted);
      });
    if (kind === "three")
      l[2].forEach((r, j) => {
        const x = 64 + j * 400;
        tx(r[0], x, 230, 350, 40, 23, accent, true);
        tx(r[1], x, 292, 350, 105, 34, ink, true);
        tx(r[2], x, 420, 350, 145, 25, muted);
      });
    if (kind === "journey")
      l[2].forEach((r, j) => {
        const x = 64 + j * 400;
        tx(r[0], x, 210, 350, 100, 76, accent, true);
        tx(r[1], x, 330, 350, 85, 32, ink, true);
        tx(r[2], x, 430, 350, 120, 25, muted);
      });
    if (kind === "rows")
      l[2].forEach((r, j) => {
        tx(r[0], 64, 224 + j * 110, 280, 75, 30, accent, true);
        tx(r[1], 375, 224 + j * 110, 830, 100, 27, ink);
      });
    if (kind === "catalog")
      l[2].forEach((r, j) => {
        const x = 64 + (j % 2) * 600,
          y = 225 + Math.floor(j / 2) * 105;
        tx(r[0], x, y, 548, 35, 22, accent, true);
        tx(r[1], x, y + 38, 548, 60, 31, ink, true);
      });
    if (l[3]) tx(l[3], 64, 580, 1125, 80, 20, muted);
  }
  const footInk = feature ? "#596168" : muted;
  tx(
    "XMIP   /   " + chapter(i),
    kind === "cover" || kind === "closing" ? 560 : 64,
    682,
    kind === "cover" || kind === "closing" ? 500 : 860,
    25,
    13,
    footInk,
  );
  tx(
    String(i + 1).padStart(2, "0") + " / " + data.length,
    1090,
    682,
    100,
    25,
    13,
    footInk,
  );
  s.speakerNotes.text =
    d.narration +
    "\n\n" +
    d.note +
    "\n\nSources, read 2026-11-05:\n" +
    d.sources.map((f) => f).join("\n") +
    "\nPronunciation: Smip. Female presenter first and to the left.";
  await fs.writeFile(
    task + "/build/overview-slide-" + (i + 1) + ".png",
    new Uint8Array(
      await (await p.export({ slide: s, format: "png", scale: 1 })).arrayBuffer(),
    ),
  );
  console.log("Rendered", i + 1);
}
await (await PresentationFile.exportPptx(p)).save(task + "/build/draft-overview.pptx");
