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

A server plays round after round. In the lobby, Chimera Chance picks the Chimera and everyone else plays a merc (up to five). Mercs pick a slice class within its cap during the loadout: Assault (2), Technician (2), Medic (1), Scout (1). Starting values for every number are in `src/shared/Config.luau`.

| Role | Controls |
| --- | --- |
| Lobby and loadout | Click Merc only to never be picked as the Chimera. Click a class card to pick it |
| Merc | WASD move, Shift sprint (20 studs/s for 5 s), mouse aim (hold Left Alt for a cursor). LMB fire, R reload, G class gear, F flashlight, V Flash, H Stim, T hold or holster the motion tracker. E on prompts: revive a downed teammate, force a locked door, weld a door (Technician). Hold E at a terminal to reboot it. Z or middle mouse: tap to ping where you aim, hold for the ping wheel |
| Merc on Overwatch (eliminated) | Click a camera in the list or press A/D to switch; right-drag to look. Click the view to ping that spot for the living mercs; F tags the Chimera if it's Exposed or Revealed on your camera |
| Chimera, at a camera | Click a camera marker or press 1-9 to hop (0.5 s); right-drag or A/D/W/S to look; scroll to zoom. E on a light, door or terminal for Interface, or on a steam valve or power conduit to arm it with Overload; hold E on a stocked dock to take its shell. F casts Static Decoy where you point |
| Chimera, in a shell | WASD move, Space jump, mouse look. LMB Energy Claws, E Interface (hold E on a downed merc to Assimilate), R System Leap to the camera or terminal under the crosshair, F Static Decoy, hold Q for 1 s to leave |

### Milestone 1: movement and replication

The graybox (the Core, three wings and Insertion; 14 cameras, 8 shell docks, 11 lockable doors, 3 terminals, 5 charging stations, 10 Overload traps, and since milestone 3 the Core platform, its floodlights and emergency lights in every wing room), merc movement, the Chimera's facility mode, shells on a server-authoritative controller, and perception-gated replication.

### Milestone 2: combat, visibility, downs and assimilation

- **Visibility.** A shell is Cloaked (a shimmer that grows with speed), Exposed in a flashlight beam within 15 studs, or Revealed with a red outline: for 1 s after each hit or swipe, 2 s after a Flash, 3 s from a sensor dart, and while assimilating. Module parts show on a Revealed shell. Perception gating follows these states.
- **Detection.** The server computes the motion tracker (a moving shell within 40 studs; four strengths, eight directions) and the heartbeat (an occupied shell within 10 studs, Scout 15). Clients never get a position from either.
- **Light.** 200 s of battery; Flash costs 20% and has a 20 s cooldown; charging stations refill 25% a second. The Chimera sees beams through walls within 40 studs of its viewpoint.
- **Mercs.** The four slice classes with their weapons, gear and passives. The server owns every hit (lag-compensated against the shell's recent positions), all damage and every cooldown. Mercs can shoot out lights and cameras (the Chimera is thrown off a shot-out camera with 2 s of static) and smash dormant shells (300 HP; the Chimera gets an alert).
- **The Chimera.** Phase Weave (1,000 HP), Energy Claws, System Leap, Static Decoy and Overload. Claws break a weld in 4 s of attacks. A destroyed shell sends the Chimera back to the cameras and blocks taking another for 20 s. Shells no longer walk through mercs.
- **Health.** 100 HP, no regen, one Stim. Downed mercs crawl at 30% and bleed out after 45, then 30, then 15 s. Revive takes 5 s (Medic 2.5 s) and leaves 30 HP. Assimilate takes 3 s, Revealed and rooted, and breaks on a stagger or on losing 25% of the shell's HP. Eliminated mercs play Overwatch (milestone 3).
- **Upload hooks.** `src/server/MatchEvents.luau` fires MercDowned, MercAssimilated, MercBledOut, ShellDestroyed and TerminalCorrupted; the upload meter listens.

Calls made where the design doc gives no number or rule, all easy to change in `Config.luau`:
- Grenades don't hurt mercs, so there's no friendly fire.
- Trip mines and sensor darts are single-use.
- Welds hold until the Chimera claws through them.
- The leap channel roots the shell.
- Steam clouds last 4 s.
- A conduit slows a merc to 60% for 2 s.
- Medic's Stim is the same +40; their extra healing is the Nano-Regen station.

### Milestone 3: terminals, the upload meter and both finales

- **Rounds.** Lobby (20 s) → Loadout (25 s) → Deployment (15 s) → the race (up to 8:00) → a finale (2:00, never past 10:00 from the start of the race) → Results (10 s) → back to the lobby. A round needs 4 players. Chimera Chance: a weight that starts at 1, gains 1 for each round played as a merc and resets when picked; the lobby shows everyone's chance. During Deployment mercs enter at the Insertion lift and the Chimera can hop cameras but can't use Interface, modules or shells.
- **Terminals.** Hold E to reboot: 40 s (Technician 28 s), and progress stays when you let go. One operator at a time; the operator can't shoot or use gear, and any damage interrupts. The Chimera gets an alert naming the terminal and room when a reboot starts. Corrupt takes 20% off, locks the terminal for 10 s and adds 3% upload. A rebooted terminal lights its wing's red emergency lamps and shuts that wing's docks for the rest of the match. Two of the slice's three terminals trigger Lockdown.
- **The upload meter and Threat Level.** The meter fills over 8:00 and moves with the match events: down +10%, assimilation +15%, bleed-out +5%, corrupted terminal +3%, shell destroyed with the Chimera inside −10%. Threat rises at 2:00, 4:00 and 6:00 and is 4 in either finale. Both teams see the meter, every terminal's progress and Threat on the top bar.
- **Lockdown and the Purge finale.** Every dock shuts down and the Chimera is locked into one body: the shell it's in, or a last one booted at a Core dock 5 s later. Mercs standing on the Core platform hold it; the Chimera's body anywhere in the Core stalls them. The Core is floodlit (no Blackout there) and a scan pulse Reveals the Chimera every 15 s. Destroying the body or 45 s held wins it for the mercs; time running out wins it for the Chimera.
- **The Upload finale.** The Chimera's body on the platform holds; any standing merc in the Core stalls it. Every Core light dies, and every 15 s a network scan outlines the mercs in the Core for the Chimera. A lost body costs 5 s of held time and a new one boots at a Core dock 10 s later. 45 s held wins it for the Chimera; time running out wins it for the mercs.
- **Win and leave rules.** Eliminating every merc wins for the Chimera at any point. If the Chimera leaves (or idles 45 s), the mercs win. A merc who leaves is removed and gives no upload. 45 s idle in a match moves a player to spectating until the next round; a Chimera idle since the lobby is re-picked at deployment. Players who join mid-match spectate. Each merc short of five at deployment makes reboots 10% faster and shells 10% weaker.
- **Pings and Overwatch.** The ping wheel (Chimera here, Going here, Terminal, Need revive, Low battery, Watch this door) and tap pings show the sender's name and a 📻 voice-line mark; a fake ping (Corrupt Data, a later module: `Pings.fake`) has no 📻. Overwatch can watch any camera, ping (3 charges, one back every 20 s) and Tag an Exposed or Revealed shell on its camera, outlining it in orange for the living mercs for 3 s (30 s cooldown). The camera the Chimera is in shows static on Overwatch.

Calls made where the design doc gives no number or rule, all in `Config.luau` or easy to change:
- Threat starts at 1; each level above 1 gives +15% energy regen and −10% on System Leap and Static Decoy cooldowns (Threat 4: +45%, −30%).
- If neither side has triggered a finale by 8:00, the Upload finale starts (the meter is built to fill by then; destroyed shells can hold it back).
- A bodiless Chimera at the start of either finale boots a shell at a Core dock after 5 s, and it can't leave its body in either finale. The boot picks the Core dock farthest from the mercs.
- Held time is a total, counts only standing mercs, and doesn't go faster with more holders.
- A scan pulse Reveals the Chimera for 2 s; a network scan outlines the mercs for 2 s.
- Emergency lamps stay on until the next round and Blackout doesn't affect them.
- Results show for 10 s. Pings last 8 s, and a merc can send 4 every 3 s.
- If everyone picks Merc only, someone is picked anyway. Players beyond six watch the round.
- A Chimera who leaves during Loadout is replaced from the mercs; from Deployment on, leaving is a merc win.

### Testing in Studio

- To see both sides at once, use the Test tab: Clients and Servers, 2 players, Start. Chimera Chance picks the Chimera; click Merc only on one client in the lobby to decide who it is.
- Studio rules: a round starts with 1 player and idle players aren't sent to the lobby (an untouched test client would be). The DEV panel's Min players and Idle kicks buttons switch to the real rules.
- Alone, use the DEV panel (Studio only; the DEV button, top right):
  - Combat: switch role; turn the test shell on or off, and switch it between patrolling the Core and hunting mercs (it claws and assimilates); cycle its visibility state; the perception overlay; spawn a dummy merc; cycle class; Down me; Respawn me.
  - Match: skip the phase (in the race it starts the Upload finale; in a finale it runs the clock out), +60 s on the clock, +10% upload, force either finale, +10 s held.
  - With Merc only on and nobody else in the server, the round has no Chimera player: the test shell plays the Chimera (spawn it before forcing the Purge finale, since Lockdown shuts every dock).
- Cue sounds are placeholders: in Studio a yellow label shows where each tell played and who heard it.
- `ServerScriptService.ChimeraTestHook` and the client's `ReplicatedStorage.ChimeraClientHook` (both Studio only) return JSON state and run scripted checks; see `src/server/Debug.luau`. The hook's `studio keepGoing` option stops "every merc eliminated" from ending a solo test, for trying Overwatch.

### The map contract

The map is built in Studio, and the code finds everything by folder and attribute: see the header of `src/shared/FacilityMap.luau`. The server checks the layout rules at startup and warns in the Output about one-way camera links, rooms without a camera and docks no camera can see.

`tools/graybox/BuildGraybox.luau` generated the current graybox. Running it again replaces `Workspace.Map` and `Workspace.Facility`, so hand edits are lost: `require(game.ServerStorage.DevTools.BuildGraybox:Clone())()` from the command bar in Edit mode (the clone skips the module cache).
