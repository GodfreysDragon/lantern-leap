# Levels

Each level is a plain-text file: `key: value` header lines, a `---` separator,
then an ASCII map where one character is one 16×16 tile. Rows may be ragged;
the loader pads them with empty space.

| Char | Tile | Notes |
|------|------|-------|
| `#` | Solid rock | Merged into large collision rectangles at load time |
| `-` | One-way platform | Jump up through it, land on top |
| `^` | Spikes | Auto-orient away from the adjacent solid tile |
| `x` | Crumbling block | Breaks 0.45s after being touched, reforms after 2.2s |
| `S` | Spring | Launches ~7.5 tiles high and refills the dash |
| `*` | Dash crystal | Refills the dash mid-air, regrows after 2.5s |
| `o` | Gem | Optional collectible |
| `C` | Checkpoint | Lamp post; becomes the respawn point |
| `E` | Exit | Needs one free tile above it for the door |
| `P` | Player start | Exactly one per level |

Header keys: `name` (shown in the HUD) and `hint` (tutorial line shown on
entry). Repeat `hint` for several lines; they are shown one after another.

## Movement budget (for designing jumps)

With the default tuning in `scripts/player/player.gd`:

- **Jump**: ~3 tiles up (2 is comfortable), ~5 tiles across on flat ground.
- **Jump + dash**: ~7 tiles up with good timing (5 is comfortable), ~9 across.
- **Wall jump**: ~2.5 tiles of height per kick, pushing out half a tile. A
  single wall climbs at about 10 tiles a second.
- **Wall touch**: touching a wall in the air refills the dash. Keep any wall the
  player shouldn't use for this out of reach (a one-way `-` ledge has no sides).
- **Spring**: ~7.5 tiles up.
- **Ledge extensions**: walking off the edge of a `#` or `-` platform, the
  player keeps their footing for one more tile. The level adds them wherever
  the drop is at least 2 tiles, there's room to stand and no spike in reach,
  and the gap is at least 3 tiles wide (narrower gaps would be bridged).
- **Coyote time**: a jump still fires up to 0.1 s after leaving the ground or
  the end of a ledge extension.

## Design rules

- **Size challenges without the ledge extensions.** They, coyote time
  and jump buffering are there to forgive the player, not to make a jump
  possible.
- **Put optional gems where a natural move collects them**, e.g. at the top of
  a full jump. Don't make the player perform a move the level hasn't taught.
- **Warm up before every main challenge.** Show it first in a low-stakes form,
  as Crumbling Way does.
- **Make one-way sections obviously one-way.** Use a drop taller than the
  player can climb back, past a wall they can't cling to, such as the
  spike-lined drop in Glass Air.

`tests/run_tests.gd` validates every level file (one start, one exit, known
characters, door headroom, nothing spawning inside rock).

Adding a level: drop a new file here and append its path to `LEVELS` in
`scripts/main.gd`.
