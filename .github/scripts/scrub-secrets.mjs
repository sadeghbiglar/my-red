#!/usr/bin/env node
// Redact token-shaped strings from the state backups BEFORE they are committed.
//
// Why this exists: my-red is public and GitHub Push Protection is on. The backup
// step copies hermes/state.db, whose `messages` table holds verbatim tool output —
// including a GitHub PAT that once printed in a terminal. Push protection then
// rejects the whole push (GH013), so NOTHING in that sync lands: no hermes state,
// no 9router db, no reserve db. That is how the reserve bookings were lost.
//
// Byte-safe on purpose: files are rewritten through latin1, so sqlite/other binary
// files keep every byte outside the matched spans, and each match is replaced by the
// SAME number of bytes so file offsets (and therefore sqlite pages) do not move.
//
// Usage: node scrub-secrets.mjs <dir> [<dir> ...]

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// The lookbehind keeps `sk-` from eating ordinary words like `task-<hash>`.
const SOURCES = [
  'gh[pousr]_[A-Za-z0-9]{16,}',
  'github_pat_[A-Za-z0-9_]{16,}',
  '(?<![A-Za-z0-9])sk-[A-Za-z0-9]{20,}',
  'AKIA[0-9A-Z]{16}',
  'xox[baprs]-[A-Za-z0-9-]{10,}',
  'AIza[0-9A-Za-z_-]{30,}',
];

const MATCHER = new RegExp(SOURCES.join('|'), 'g');
const PREFILTER = new RegExp(SOURCES.map((s) => s.replace(/^\(\?<[^\>]*\)/, '')).join('|'));

const MAX_BYTES = 64 * 1024 * 1024;

function walk(dir, out = []) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) walk(path, out);
    else if (entry.isFile()) out.push(path);
  }
  return out;
}

let filesScanned = 0;
let filesChanged = 0;
let spansRedacted = 0;

for (const root of process.argv.slice(2)) {
  for (const file of walk(root)) {
    let buf;
    try {
      buf = readFileSync(file);
    } catch {
      continue;
    }
    if (buf.length === 0 || buf.length > MAX_BYTES) continue;
    filesScanned += 1;

    // latin1 round-trip is byte-exact: one char per byte, no utf8 mangling.
    const before = buf.toString('latin1');
    if (!PREFILTER.test(before)) continue;

    let spans = 0;
    const after = before.replace(MATCHER, (match) => {
      spans += 1;
      return 'x'.repeat(match.length);
    });
    if (spans === 0 || after === before) continue;

    if (after.length !== before.length) {
      // A length change would shift bytes; refuse rather than corrupt a db.
      console.error(`refusing to write ${file}: replacement changed length`);
      process.exitCode = 1;
      continue;
    }
    writeFileSync(file, Buffer.from(after, 'latin1'));
    filesChanged += 1;
    spansRedacted += spans;
    console.log(`redacted ${spans} span(s) in ${file}`);
  }
}

console.log(
  `scrub-secrets: ${filesScanned} files scanned, ${filesChanged} rewritten, ${spansRedacted} span(s) redacted`,
);
