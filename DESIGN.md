# Design

The console is an **Operate** surface: someone is here to read a balance, mint a
key, or change a price, usually late, usually in a hurry. Brand lives in the
details, not in decoration.

## The world

A ledger. Warm black paper, one accent of bamboo green, hairlines instead of
cards, numbers that line up. Nothing floats, nothing glows, nothing is glass.

## Tokens

| Token | Value | Use |
|---|---|---|
| `--ground` | `#0b0d0a` | page |
| `--panel` | `#111411` | inset blocks, code |
| `--raised` | `#171b16` | inputs |
| `--rule` | `rgba(232,240,226,.10)` | hairlines |
| `--ink` | `#eef2e9` | primary text |
| `--ink-soft` | `#b9c2b2` | secondary text |
| `--ink-faint` | `#7f8a78` | labels, meta |
| `--bamboo` | `#8fd694` | accent, primary action |
| `--bamboo-deep` | `#4f8f5a` | borders on accent |
| `--clay` | `#e0a86b` | warning |
| `--danger` | `#e2836f` | destructive |

Type: **Newsreader** for display (roman, never italic — the italic serif hero is
the tell this project refuses), **IBM Plex Sans** for body, **IBM Plex Mono** for
money, ids, and code. Scale steps 12.5 / 15 / 18 / 24 / 36 / 52 px.

## Rules

1. **Hairlines, not cards.** A section is a heading over a rule and a table.
   Cards appear only where a thing is genuinely separate (a notice, a secret).
2. **Money is monospace and right-aligned.** Tabular figures everywhere a column
   of numbers can appear.
3. **One accent.** Green marks the primary action and the current nav item. It
   never fills a surface larger than a button.
4. **No italic display type.** Emphasis comes from weight, size, and the accent
   colour.
5. **Labels are small caps, body is never below 12.5px.**
6. **One motion.** The main column settles 6px upward once, 260ms, staggered by
   40ms per block; disabled under `prefers-reduced-motion`.
7. **Browser surfaces are designed.** Selection colour, focus ring, scrollbar,
   caret, and the underline offset are all set from the palette.

## Verification

```bash
npx impeccable detect assets/app.css src/ui/
npx impeccable detect http://localhost:8787/docs
npx impeccable detect http://localhost:8787/login
```

Both pass with no findings. The detector is also the reason the display face is
Newsreader rather than Instrument Serif, and the reason the hero is roman.
