# Chimera

A 1v5 asymmetric horror game for Roblox. Code is synced into Roblox Studio with [Rojo](https://rojo.space). The map, lighting and other world content live in the Roblox place itself, so this repo tracks code only.

## Setup (once per computer)

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder. It installs the Rojo version pinned in `rokit.toml`.
2. Install the Rojo plugin in Studio, either from the Creator Store or with `rojo plugin install`. Use one or the other, not both.

## Working

1. Open the Chimera place in Roblox Studio.
2. Run `rojo serve` in this folder.
3. In Studio, open the Rojo plugin and click Connect.

Edit code in `src/`, never in Studio: Rojo overwrites synced scripts whenever their files change.

| Folder | Syncs to |
| --- | --- |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared` | `ReplicatedStorage.Shared` |
| `tools/graybox` | `ServerStorage.DevTools` (dev tools, never run in a game) |

`default.project.json` also sets the place settings the code relies on: no auto-spawned characters (the Chimera has no body), merc walk speed 14, no shift-lock (Shift is sprint) and streaming off (the Chimera watches distant rooms through cameras). If you add a new service to the project file, disconnect and reconnect the Rojo plugin: live sync doesn't pick up new services.

`rojo build -o Chimera.rbxlx` builds a place with just the code, which is handy for a quick check. Git ignores place files.

## Milestone 1: movement and replication

What's in: the graybox (the Core, three wings and Insertion; 14 cameras, 8 shell docks, 11 lockable doors, 3 placeholder terminals), merc movement, the Chimera's facility mode, shells on a server-authoritative controller, and perception-gated replication. Combat, terminals and finales are milestones 2 and 3. Starting values for every number are in `src/shared/Config.luau`.

The first player in a server is the Chimera and everyone else is a merc.

| Role | Controls |
| --- | --- |
| Merc | WASD move, hold Shift to sprint (20 studs/s for 5 s) |
| Chimera, at a camera | Click a camera marker or press 1-9 to hop (0.5 s); right-drag or A/D/W/S to look; scroll to zoom; E on a light, door or terminal for Interface; hold E on a stocked dock to take its shell |
| Chimera, in a shell | WASD move, Space jump, mouse look, E for Interface, hold Q for 1 s to leave |

### Testing in Studio

- To see both sides at once, use the Test tab: Clients and Servers, 2 players, Start. Player1 is the Chimera.
- Alone, use the DEV panel (Studio only, top right): Switch role, Test shell on/off (a server-driven shell patrolling the Core), Cycle visibility (Cloaked, Exposed, Revealed) and Perception overlay (why the server does or doesn't send you the shell).
- Cue sounds are placeholders: in Studio a yellow label shows where each tell played and who heard it.
- `ServerScriptService.ChimeraTestHook` and the client's `ReplicatedStorage.ChimeraClientHook` (both Studio only) return JSON state for scripted checks.

### The map contract

The map is built in Studio, and the code finds everything by folder and attribute: see the header of `src/shared/FacilityMap.luau`. The server checks the layout rules at startup and warns in the Output about one-way camera links, rooms without a camera and docks no camera can see.

`tools/graybox/BuildGraybox.luau` generated the current graybox. Running it again replaces `Workspace.Map` and `Workspace.Facility`, so hand edits are lost: `require(game.ServerStorage.DevTools.BuildGraybox)()` from the command bar in Edit mode.
