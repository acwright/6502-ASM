#!/usr/bin/env node
//
//  make-gallery.mjs — generate Gallery.inc, the eight banked pictures
//
//  Each picture is a 256 x 192 one-bit image, cut into 8 x 8 cells, with the
//  cells deduplicated into a Graphics I pattern table. What comes out is the
//  2,848 bytes the VDP wants, laid out identically in every bank:
//
//      $C000  2,048  pattern table   256 patterns of 8 rows
//      $C800     32  color table     one fg/bg byte per group of 8 patterns
//      $C820    768  name table      32 x 24 cells, each naming a pattern
//      $CB20         (unused)
//
//  Identical layout in every bank is the point. ShowPicture in BankedDemo.asm
//  reads one set of addresses and works on whichever bank is selected, which
//  is what "the bank is just memory once you have selected it" means in
//  practice.
//
//      node tools/make-gallery.mjs            write Gallery.inc
//      node tools/make-gallery.mjs --check    fail if Gallery.inc is stale
//
//  Graphics I gives a picture 256 patterns for 768 cells, so a picture has to
//  repeat itself — these are geometric on purpose, not because the generator
//  gave up. A picture that does come out with more than 256 distinct cells
//  keeps its 256 commonest and maps the rest to the nearest one it kept; the
//  summary line says how many that was, and a number much above zero means the
//  picture wants redesigning rather than the generator fixing.
//

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const OUT = join(dirname(dirname(fileURLToPath(import.meta.url))), "Gallery.inc");

const W = 256, H = 192;
const COLS = 32, ROWS = 24;
const MAX_PATTERNS = 256;

// A small deterministic PRNG, so the committed Gallery.inc is reproducible on
// any machine and `--check` means something.
function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5;  s >>>= 0;
    return s / 4294967296;
  };
}

// --- The eight pictures -----------------------------------------------------
//
// ink and paper are TMS9918A palette indices: 1 black, 2 medium green, 3 light
// green, 4 dark blue, 5 light blue, 6 dark red, 7 cyan, 8 medium red, 9 light
// red, 10 dark yellow, 11 light yellow, 12 dark green, 13 magenta, 14 gray,
// 15 white. The color table holds ink << 4 | paper.

const PICTURES = [
  {
    name: "Checkers",
    ink: 15, paper: 4,
    pixel(x, y) {
      const bx = x >> 5, by = y >> 5;             // 32-pixel squares
      const on = (bx + by) & 1;
      const ix = x & 31, iy = y & 31;
      const inset = ix >= 8 && ix < 24 && iy >= 8 && iy < 24;
      return on ? (inset ? 0 : 1) : (inset ? 1 : 0);
    },
  },
  {
    name: "Rings",
    ink: 3, paper: 1,
    // Drawn on a 2-pixel grid. At one-pixel resolution a circle crosses 487 of
    // the 768 cells differently and the pattern table cannot hold them; at two
    // the count is 146 and the curve still reads as a curve.
    pixel(x, y) {
      const dx = (x & ~1) - 128, dy = ((y & ~1) - 96) * 1.33;  // circular, not elliptical
      const r = Math.sqrt(dx * dx + dy * dy);
      return (Math.floor(r / 12) & 1) ^ 1;
    },
  },
  {
    name: "Stripes",
    ink: 7, paper: 4,
    pixel(x, y) {
      const d = x + y * 2;
      const period = 48;
      const p = d % period;
      return p < 8 || (p >= 20 && p < 24) ? 1 : 0;
    },
  },
  {
    name: "Starfield",
    ink: 11, paper: 6,
    pixel: (() => {
      // Stars are placed per cell, so the number of distinct cells stays small:
      // one blank cell plus one cell per star shape actually used.
      const grid = new Uint8Array(COLS * ROWS);
      const r = rng(0xACE6502);
      for (let i = 0; i < grid.length; i++) {
        const v = r();
        grid[i] = v < 0.06 ? 3 : v < 0.14 ? 2 : v < 0.30 ? 1 : 0;
      }
      const SHAPES = [
        null,
        [[4, 3]],                                           // a speck
        [[3, 3], [4, 3], [3, 4], [4, 4]],                   // a dot
        [[3, 1], [3, 2], [1, 3], [2, 3], [3, 3], [4, 3],
         [5, 3], [3, 4], [3, 5]],                           // a twinkle
      ];
      return (x, y) => {
        const shape = SHAPES[grid[(y >> 3) * COLS + (x >> 3)]];
        if (!shape) return 0;
        const px = x & 7, py = y & 7;
        return shape.some(([sx, sy]) => sx === px && sy === py) ? 1 : 0;
      };
    })(),
  },
  {
    name: "Maze",
    ink: 5, paper: 12,
    pixel: (() => {
      // The Commodore one-liner: every cell is a "/" or a "\\", chosen at
      // random, and the diagonals join up into a maze. Two distinct cells for
      // the whole screen, which is a fair demonstration of what the name table
      // does on its own.
      const r = rng(0x5A5A1234);
      const lean = new Uint8Array(COLS * ROWS);
      for (let i = 0; i < lean.length; i++) lean[i] = r() < 0.5 ? 1 : 0;
      return (x, y) => {
        const px = x & 7, py = y & 7;
        const rise = lean[(y >> 3) * COLS + (x >> 3)] ? 7 - py : py;
        return Math.abs(px - rise) <= 1 ? 1 : 0;
      };
    })(),
  },
  {
    name: "Waves",
    ink: 13, paper: 1,
    pixel(x, y) {
      for (let n = 0; n < 6; n++) {
        const base = 14 + n * 30;
        const amp = 8 + n * 2;
        const wave = base + Math.round(Math.sin((x / 256) * Math.PI * 2 * (n + 1)) * amp);
        if (y >= wave && y < wave + 4) return 1;
      }
      return 0;
    },
  },
  {
    name: "Spiral",
    ink: 15, paper: 13,
    // On a 2-pixel grid, for the reason Rings gives.
    pixel(x, y) {
      const dx = (x & ~1) - 128, dy = ((y & ~1) - 96) * 1.33;
      const r = Math.sqrt(dx * dx + dy * dy);
      const a = Math.atan2(dy, dx);
      const t = (r / 10) - (a / (Math.PI * 2)) * 2;
      return (Math.floor(t) & 1) ? 1 : 0;
    },
  },
  {
    name: "Lattice",
    ink: 9, paper: 10,
    pixel(x, y) {
      const u = (x + y) % 32, v = (x - y + 512) % 32;
      const on = (u < 3) || (v < 3);
      const dot = ((x % 32) - 16) ** 2 + ((y % 32) - 16) ** 2 < 16;
      return on || dot ? 1 : 0;
    },
  },
];

// --- Rendering --------------------------------------------------------------

function render(picture) {
  // Every cell as 8 bytes, msb = leftmost pixel.
  const cells = [];
  for (let cy = 0; cy < ROWS; cy++) {
    for (let cx = 0; cx < COLS; cx++) {
      const rows = new Uint8Array(8);
      for (let ry = 0; ry < 8; ry++) {
        let bits = 0;
        for (let rx = 0; rx < 8; rx++) {
          if (picture.pixel(cx * 8 + rx, cy * 8 + ry)) bits |= 0x80 >> rx;
        }
        rows[ry] = bits;
      }
      cells.push(rows);
    }
  }

  // Deduplicate, counting how often each distinct cell is used.
  const index = new Map();
  const order = [];
  const counts = [];
  const cellPattern = cells.map((rows) => {
    const key = Array.from(rows).join(",");
    let id = index.get(key);
    if (id === undefined) {
      id = order.length;
      index.set(key, id);
      order.push(rows);
      counts.push(0);
    }
    counts[id]++;
    return id;
  });

  // Over budget: keep the commonest 256 and fold the rest into the nearest
  // kept pattern by Hamming distance.
  let remap = null;
  let keptPatterns = null;
  let folded = 0;
  if (order.length > MAX_PATTERNS) {
    const ranked = counts.map((c, i) => [c, i]).sort((a, b) => b[0] - a[0]);
    const kept = ranked.slice(0, MAX_PATTERNS).map(([, i]) => i);
    keptPatterns = new Map(kept.map((id, slot) => [id, slot]));
    remap = new Array(order.length);
    for (let id = 0; id < order.length; id++) {
      if (keptPatterns.has(id)) { remap[id] = keptPatterns.get(id); continue; }
      let best = 0, bestDistance = Infinity;
      for (const [other, slot] of keptPatterns) {
        let d = 0;
        for (let r = 0; r < 8; r++) d += popcount(order[id][r] ^ order[other][r]);
        if (d < bestDistance) { bestDistance = d; best = slot; }
      }
      remap[id] = best;
      folded += counts[id];
    }
  }

  // Only a KEPT pattern writes its own bytes; a folded one just points at the
  // neighbour that survived. Writing the folded bytes too would overwrite the
  // very pattern it was folded into.
  const patterns = new Uint8Array(MAX_PATTERNS * 8);
  if (remap) {
    for (const [id, slot] of keptPatterns) patterns.set(order[id], slot * 8);
  } else {
    order.forEach((rows, i) => patterns.set(rows, i * 8));
  }

  const names = Uint8Array.from(cellPattern.map((id) => (remap ? remap[id] : id)));
  const colors = new Uint8Array(32).fill((picture.ink << 4) | picture.paper);

  return { patterns, colors, names, distinct: order.length, folded };
}

function popcount(n) {
  let c = 0;
  while (n) { c += n & 1; n >>= 1; }
  return c;
}

// --- Emitting ---------------------------------------------------------------

function bytes(data, indent = "  ") {
  const lines = [];
  for (let i = 0; i < data.length; i += 16) {
    const row = Array.from(data.slice(i, i + 16), (b) => "$" + b.toString(16).toUpperCase().padStart(2, "0"));
    lines.push(indent + ".byte " + row.join(","));
  }
  return lines.join("\n");
}

function emit() {
  const parts = [];
  const summary = [];
  parts.push(`; =============================================================================
;   Gallery.inc — eight pictures, one per bank
; =============================================================================
;   GENERATED by tools/make-gallery.mjs. Do not edit; \`make gallery\` rewrites
;   it and \`make check-gallery\` fails on a stale copy.
;
;   Every bank has the same layout, which is what lets one ShowPicture read
;   any of them:
;
;     $C000  PIC_PATTERNS  2,048   256 patterns of 8 rows, msb leftmost
;     $C800  PIC_COLORS       32   ink << 4 | paper, one per 8 patterns
;     $C820  PIC_NAMES       768   32 x 24 cells, each naming a pattern
;
;   2,848 bytes of an 8,192-byte bank. The rest is $FF, and that is fine: a
;   bank is 8 KB whether you fill it or not. Eight of these is 22,784 bytes,
;   which is 6,406 more than the 16,378 a fixed cartridge has — which is the
;   whole reason this demo is banked.
; =============================================================================
`);

  PICTURES.forEach((picture, n) => {
    const r = render(picture);
    summary.push(
      `  bank $0${n}  ${picture.name.padEnd(10)} ${String(r.distinct).padStart(3)} distinct cells` +
      (r.folded ? `, ${r.folded} folded into a neighbour` : "")
    );
    const bank = "BANK0" + n;
    parts.push(`
; --- ${picture.name} — bank $0${n} ---------------------------------------------------

.segment "${bank}"

Pic${n}:
  ; pattern table
${bytes(r.patterns)}
  .assert * - Pic${n} = $0800, lderror, "${bank}: pattern table is not 2048 bytes"
  ; color table
${bytes(r.colors)}
  .assert * - Pic${n} = $0820, lderror, "${bank}: color table is not 32 bytes"
  ; name table
${bytes(r.names)}
  .assert * - Pic${n} = $0B20, lderror, "${bank}: name table is not 768 bytes"
`);
  });

  const text = parts.join("");
  return { text, summary };
}

const { text, summary } = emit();
const check = process.argv.includes("--check");

if (check) {
  let current = null;
  try { current = readFileSync(OUT, "utf8"); } catch { /* missing */ }
  if (current !== text) {
    console.error("Gallery.inc is stale — run `make gallery`");
    process.exit(1);
  }
  console.log("Gallery.inc is current");
} else {
  writeFileSync(OUT, text);
  console.log("Gallery.inc: " + PICTURES.length + " pictures");
}
console.log(summary.join("\n"));
