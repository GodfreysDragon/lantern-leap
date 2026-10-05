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

Header keys: `name` (shown in the HUD) and `hint` (tutorial line shown on entry).

## Movement budget (for designing jumps)

With the default tuning in `scripts/player/player.gd`:

- **Jump**: ~3 tiles up (2 is comfortable), ~5 tiles across on flat ground.
- **Jump + dash**: ~7 tiles up with good timing (5 is comfortable), ~9 across.
- **Wall jump**: ~2.5 tiles of height per kick; shafts 4 tiles wide feel best.
- **Spring**: ~7.5 tiles up.

`tests/run_tests.gd` validates every level file (one start, one exit, known
characters, door headroom, nothing spawning inside rock).

Adding a level: drop a new file here and append its path to `LEVELS` in
`scripts/main.gd`.
