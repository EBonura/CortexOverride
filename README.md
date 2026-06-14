# Cortex Override

In a world where sentient machines govern our digital existence, a virus-like AI called Barracuda has infected the grid, birthing grotesque cybernetic monstrosities. You are the last uncorrupted nano-drone, a digital spark in a sea of static.

A fast-paced, top-down shooter built as a single cartridge for [PICO-8](https://www.lexaloffle.com/pico-8.php).

### Controls
- Arrow keys (⬆️⬇️⬅️➡️): Move and navigate menus
- ❎ (X or V): Fire selected weapon / confirm / buy
- 🅾️ (Z or C): Back / cancel
- Hold 🅾️: Open the weapon wheel
- P or Enter: Pause menu

### Main objectives
- Hack all terminals to execute the system purge
- Reach the extraction point

### Optional objectives
- Collect all data shards
- Eliminate all enemy units

Features
- Fast-paced, top-down combat
- Four weapons: Rifle Burst, Machine Gun, Missiles, Plasma Cannon
- Roguelike elements: Upgrade your loadout between missions
- Four distinct missions with unique challenges
- Dynamic enemy AI with different behaviors
- Interactive environment: Exploding barrels, laser doors, terminals
- Mini-game for hacking terminals
- Pixel art graphics with dynamic lighting and shadow effects

### Terminals and Laser Doors:
Terminals are scattered throughout the game, with many linked to color-coded laser doors. Unlock terminals via a hacking mini-game to deactivate linked doors and access new areas. Some terminals aren't connected to doors but are still vital for the system purge. Hacking all terminals is crucial to complete the main objective.

### Data Shards:
Data shards are vital collectibles scattered throughout each level. Each shard restores 25 health points and awards 50 credits when collected. Gathering all data shards in a level is an optional objective.

## Entities
In Cortex Override, you'll encounter various entities, each with their own abilities and characteristics. Eliminating all entities in a level is an optional objective.

### Corrupted Bots
1. **Dervish**
   - Ability: Machine Gun
   - Health: 50
   - Attack Range: 60
   - Kill Value: 100 credits

2. **Vanguard**
   - Ability: Rifle Burst
   - Health: 70
   - Attack Range: 50
   - Kill Value: 120 credits

3. **Warden**
   - Ability: Missiles
   - Health: 100
   - Attack Range: 70
   - Kill Value: 200 credits

### Cybernetic Monstrosities
1. **Cyberseer**
   - Abilities: Rifle Burst, Missiles
   - Health: 160
   - Attack Range: 80
   - Kill Value: 300 credits

2. **Quantum Cleric**
   - Abilities: Machine Gun, Plasma Cannon
   - Health: 170
   - Attack Range: 70
   - Kill Value: 320 credits

## Development
The game is a single PICO-8 cartridge, `v0.3.p8`. The four missions are 72×72 maps stored in PICO-8's extended memory, so they live as compressed blobs inside the cart rather than the standard map region.

Common tasks (via `make`):

| Command | What it does |
| --- | --- |
| `make run` | Launch the cart |
| `make count` | Token budget check (shrinko8 rules) |
| `make editor` | Serve the standalone 72×72 map editor; Export saves straight back to the cart |
| `make export` | Build the HTML5 export into `export/` |
| `make deploy` | Export, commit, and push (GitHub Actions then pushes `export/` to itch.io via butler) |

Set a non-standard PICO-8 path in a gitignored `local.mk` (`PICO8 = /path/to/pico8`).

### Repository layout
- `v0.3.p8` — the game (active development)
- `maptool/` — standalone map editor (`editor.html`) and the LZ map pipeline (`lz3.py`, `gen72.py`, `swap72.py`, `verify72.py`, `serve.py`)
- `versions/` — earlier builds, kept as the project's lineage
- `tests/` — lighting and shadow experiment carts
- `export/` — prebuilt HTML5 build pushed to itch.io
- `.github/workflows/deploy.yml` — itch.io deploy workflow

Title font: [Vermin Vibes 1989](https://www.dafont.com/vermin-vibes-1989.font?text=cortex+override). Minified with [shrinko8](https://thisismypassport.github.io/shrinko8/).


## Author

Cortex Override is a passion project by Emanuele Bonura.

- Itch.io: [https://izzy88izzy.itch.io/](https://izzy88izzy.itch.io/)
- GitHub: [https://github.com/EBonura/CortexOverride](https://github.com/EBonura/CortexOverride)
- Instagram: [https://www.instagram.com/izzy88izzy/](https://www.instagram.com/izzy88izzy/)