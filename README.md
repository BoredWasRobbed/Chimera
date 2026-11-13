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

Rojo can miss a file change made while a playtest is running. If a change doesn't show up after you stop the playtest, save the file again with a real edit.

`rojo build -o Chimera.rbxlx` builds a place with just the code, which is handy for a quick check. Git ignores place files.

## Playing the vertical slice

The first player in a server is the Chimera and everyone else is a merc. Mercs get the first slice class with room under its cap: Assault (2), Technician (2), Medic (1), Scout (1). Starting values for every number are in `src/shared/Config.luau`.

| Role | Controls |
| --- | --- |
| Merc | WASD move, Shift sprint (20 studs/s for 5 s), mouse aim (hold Left Alt for a cursor). LMB fire, R reload, G class gear, F flashlight, V Flash, H Stim, T hold or holster the motion tracker. E on prompts: revive a downed teammate, force a locked door, weld a door (Technician) |
| Chimera, at a camera | Click a camera marker or press 1-9 to hop (0.5 s); right-drag or A/D/W/S to look; scroll to zoom. E on a light, door or terminal for Interface, or on a steam valve or power conduit to arm it with Overload; hold E on a stocked dock to take its shell. F casts Static Decoy where you point |
| Chimera, in a shell | WASD move, Space jump, mouse look. LMB Energy Claws, E Interface (hold E on a downed merc to Assimilate), R System Leap to the camera or terminal under the crosshair, F Static Decoy, hold Q for 1 s to leave |

### Milestone 1: movement and replication

The graybox (the Core, three wings and Insertion; 14 cameras, 8 shell docks, 11 lockable doors, 3 placeholder terminals, 5 charging stations, 10 Overload traps), merc movement, the Chimera's facility mode, shells on a server-authoritative controller, and perception-gated replication.

### Milestone 2: combat, visibility, downs and assimilation

- **Visibility.** A shell is Cloaked (a shimmer that grows with speed), Exposed in a flashlight beam within 15 studs, or Revealed with a red outline: for 1 s after each hit or swipe, 2 s after a Flash, 3 s from a sensor dart, and while assimilating. Module parts show on a Revealed shell. Perception gating follows these states.
- **Detection.** The server computes the motion tracker (a moving shell within 40 studs; four strengths, eight directions) and the heartbeat (an occupied shell within 10 studs, Scout 15). Clients never get a position from either.
- **Light.** 200 s of battery; Flash costs 20% and has a 20 s cooldown; charging stations refill 25% a second. The Chimera sees beams through walls within 40 studs of its viewpoint.
- **Mercs.** The four slice classes with their weapons, gear and passives. The server owns every hit (lag-compensated against the shell's recent positions), all damage and every cooldown. Mercs can shoot out lights and cameras (the Chimera is thrown off a shot-out camera with 2 s of static) and smash dormant shells (300 HP; the Chimera gets an alert).
- **The Chimera.** Phase Weave (1,000 HP), Energy Claws, System Leap, Static Decoy and Overload. Claws break a weld in 4 s of attacks. A destroyed shell sends the Chimera back to the cameras and blocks taking another for 20 s. Shells no longer walk through mercs.
- **Health.** 100 HP, no regen, one Stim. Downed mercs crawl at 30% and bleed out after 45, then 30, then 15 s. Revive takes 5 s (Medic 2.5 s) and leaves 30 HP. Assimilate takes 3 s, Revealed and rooted, and breaks on a stagger or on losing 25% of the shell's HP. Eliminated mercs watch through the cameras (basic Overwatch; the full version is milestone 3).
- **Upload hooks.** `src/server/MatchEvents.luau` fires MercDowned, MercAssimilated, MercBledOut, ShellDestroyed and TerminalCorrupted for the upload meter in milestone 3.

Calls made where the design doc gives no number or rule, all easy to change in `Config.luau`:
- Grenades don't hurt mercs, so there's no friendly fire.
- Trip mines and sensor darts are single-use.
- Welds hold until the Chimera claws through them.
- The leap channel roots the shell.
- Steam clouds last 4 s.
- A conduit slows a merc to 60% for 2 s.
- Medic's Stim is the same +40; their extra healing is the Nano-Regen station.

### Testing in Studio

- To see both sides at once, use the Test tab: Clients and Servers, 2 players, Start. Player1 is the Chimera.
- Alone, use the DEV panel (Studio only; the DEV button, top right):
  - Switch role.
  - Turn the test shell on or off, and switch it between patrolling the Core and hunting mercs (it claws and assimilates).
  - Cycle its visibility state.
  - Perception overlay: why the server does or doesn't send you the shell.
  - Spawn a dummy merc to down, assimilate or revive.
  - Cycle class, Down me, and Respawn me (also brings an eliminated merc back).
- Cue sounds are placeholders: in Studio a yellow label shows where each tell played and who heard it.
- `ServerScriptService.ChimeraTestHook` and the client's `ReplicatedStorage.ChimeraClientHook` (both Studio only) return JSON state and run scripted checks; see `src/server/Debug.luau`.

### The map contract

The map is built in Studio, and the code finds everything by folder and attribute: see the header of `src/shared/FacilityMap.luau`. The server checks the layout rules at startup and warns in the Output about one-way camera links, rooms without a camera and docks no camera can see.

`tools/graybox/BuildGraybox.luau` generated the current graybox. Running it again replaces `Workspace.Map` and `Workspace.Facility`, so hand edits are lost: `require(game.ServerStorage.DevTools.BuildGraybox:Clone())()` from the command bar in Edit mode (the clone skips the module cache).
