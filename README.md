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
| `tools/graybox`, `tools/mapkit`, `tools/map` | `ServerStorage.DevTools` (dev tools, never run in a game) |

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

The graybox (the Core, three wings and Insertion; 14 cameras, 8 shell docks, 11 lockable doors, 3 terminals, 5 charging stations, 10 Overload traps, and since milestone 3 the Core platform, its floodlights and emergency lights in every wing room), merc movement, the Chimera's facility mode, shells on a server-authoritative controller, and perception-gated replication. The full map (see "The full map: Axiom Tower, Level 61") has since replaced the graybox in the place.

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
- **Terminals.** Hold E to reboot: 40 s (Technician 28 s), and progress stays when you let go. One operator at a time; the operator can't shoot or use gear, and any damage interrupts. The Chimera gets an alert naming the terminal and room when a reboot starts. Corrupt takes 20% off, locks the terminal for 10 s and adds 3% upload. A rebooted terminal lights its wing's amber emergency lamps and shuts that wing's docks for the rest of the match. Any three of the full map's five terminals trigger Lockdown (on the slice's graybox it was two of three; `Config.Terminals.ForLockdown`).
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

### The shell body

A shell's body (`src/shared/ShellRig.luau`) is built from six body modules, one per R6 block: the head, the torso, two arms and two legs. Each module is a dark inner frame wrapped in hinged armour panels (41 panels in all). The three-segment tail rounds it out.

- **In its dock** a dormant shell stands unformed: its panels hang open, its head is bowed and its arms sag off the shoulders.
- **Booting** (the Chimera holding E on the dock): the frame glows red, the eyes light and the panels twitch part-way shut. If the take is cancelled, they fall open again.
- **Taken**: the modules lock into place in turn: legs, torso, arms, then head. Each flashes red along its seams as it locks. The visor slams shut last, the eyes ignite and the module parts slide out, 1.25 s in all. Then the body fades into its look over 0.35 s.
- **Formed**: the seams glow dull red on a Revealed body and on the Chimera's own view. Cloaked and Exposed bodies draw only the six R6 blocks and the tail in Phase Weave's shimmer, exactly as before, so the panels never make a cloaked shell easier to see.
- **Collapse**: when the Chimera leaves or runs dry, the cloak drops and the bare panels fall apart. A destroyed shell still bursts apart.

The server stamps each shell with the time it was taken (`bornAt`), and clients time the lock-in from it. A merc who first sees a shell mid-take sees the rest of it; a shell that's already up shows formed. The panels, their hinges and the timeline are tables at the top of ShellRig.

Calls made where the request left it open, all easy to change in ShellRig:
- The lock-in doesn't slow the Chimera: it can move as soon as it takes the shell (the legs lock first).
- A merc who perceives a fresh shell sees the bare body form for 1.25 s before the cloak engages. The dormant shell stood in plain view a moment before, so this gives away little.
- A shell that collapses because the Chimera left drops its cloak, so mercs who perceive it see bare panels fall (before, the shimmer fell).

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

`tools/map/BuildMap.luau` builds the current map (see below). `tools/graybox/BuildGraybox.luau` still builds the old three-wing graybox for reference; both replace `Workspace.Map` and `Workspace.Facility` (BuildMap also `Workspace.City` and `Workspace.Weather`), so hand edits are lost.

### The full map: Axiom Tower, Level 61

Axiom Data Vault is the 61st floor of a corporate skyscraper at night. The squad rides the service lift up and steps out into the elevator lobby; ahead is the Reception (the Core), a two-storey atrium round the reception desk, with a wall of glass on its far side looking out over the city. The wings wrap round it. The plan is `tools/map/plan.png` (north, where the glass faces downtown, is up; the Observation Deck is the outlined upper level over the lobby).

| Area | Rooms (the room the game sees, with its camera) |
| --- | --- |
| The Reception (the Core) | Reception: the round reception desk on a stone dais (the finale platform) about the Uplink, a black glass monolith to the ceiling; the Purge console beside the desk; speed gates in from the lobby; lounges, columns with uplights, the Axiom name on the walls, the city through the glass, the four floodlights on the columns. 2 cameras (CORE_NE, the Chimera's start camera, and CORE_SW), 2 docks |
| The lift lobby (Insertion) | Elevator Lobby: the lift bank (one car stuck ajar on a dark shaft); the squad spawns inside the service car |
| Observation Deck (upper level) | Observation Deck: a lounge behind glass over the atrium, with the terminal and both of the wing's docks; the West and East Stairwells (fire stairs, the way down chained off) climb to it from the service corridors |
| Office Wing (west) | Open Office (cubicles along the windows, the corridor behind, a dock), Executive Office (terminal; the corner office), Conference Room (dock), Break Room (kitchen, vending machines, restrooms), Records Room (shelving) |
| Server Farms (east) | Data Hall (contained rack aisles, a dock), Network Operations (terminal; glass onto the Data Hall), UPS Room, Rack Hall (dock) |
| Cooling Plant (south-east) | Pump Room (louvres to the storm, a dock), Chiller Hall (chillers, tanks, mist; a dock), Plant Control (terminal) |
| Maintenance (back of house) | West and East Service Corridors (the east one has a dock), Freight Hall (the freight lift, pallets; a dock), Boiler Room (terminal) |
| Fabrication Bays (behind the lifts) | Assembly Bay, Print Floor (shells half-printed on gantries); one dock each, online until Lockdown |

In all: 23 rooms, 24 cameras, 14 shell docks, 5 terminals, 23 lockable doors, 5 charging stations and 15 Overload traps, about 29,000 parts and 2,600 more in the city. The wings join each other (the Break Room's service door and the Records Room lead to the back of house; the Rack Hall leads to the Cooling Plant; the service corridors join the Reception, the stairs, the Freight Hall, the Fabrication Bays and the Chiller Hall), so every wing can be reached without crossing the Reception.

The doc's layout rules, as built:
- Every terminal room has two exits, and a dock in it or next door.
- No two terminals are within 20 s' walk: the closest pair (Network Operations and Plant Control) is 287 studs apart, the farthest 611. From the lift, the terminals are 224 to 428 studs away. `python tools/map/design_map.py --walk` measures them round the props.
- Every room has a camera, camera links follow the doorways both ways, and every dock is in a camera's view: the server's startup map check reports no problems.
- Every room has lights the Chimera can kill and a light panel by a door.
- Sightlines are broken up by columns, cubicles, racks, plant and clutter; the Reception and the long aisles still have a few lines longer than 60 studs.

How it looks real:
- Rooms are clear rectangles carved out of a solid block, with 2-thick walls finished like a real building: painted plaster with rubber bases in the offices, wood panelling in the executive suite and the deck, stone and wood in the lobby, two-tone painted block in the stairs and back of house, tile in the restrooms. Floors follow the room (carpet tile, terrazzo, vinyl, raised floor, epoxy, bare concrete); offices have drop ceilings with a few tiles missing (wires hang out, the tile lies below), plant rooms an exposed slab with ducts, pipes and trays.
- The textures are PS1-style pixel art like the kit's, drawn by `tools/map/textures/make_map_textures.py` (MaterialVariants AxiomPlaster, AxiomCarpet, AxiomCeiling, AxiomTerrazzo, AxiomWood, AxiomBlock, AxiomTile, AxiomConcrete, AxiomVinyl, AxiomFabric; the ids are in `MATERIALS` in `design_map.py`), plus four night facades for the city and rain on glass.
- The props are the map's own prefabs (`tools/map/mapgen/props.py`: about 135 of them, from troffers and sofas to vending machines, toilets and claw gashes), with the kit's gameplay pieces, screens and server gear. Desks are left as people left them: screens on, chairs pushed back or knocked over, mugs, papers, bags, a kid's drawing. Notes and posters tell the story ("DON'T TRUST THE CAMERAS", "they printed another one last night").
- Doors are sliding pocket doors that look the part (walnut office doors, steel security doors, the glass office entrance), each with a badge reader whose light shows the door's state, and exit signs over the main doorways.
- Outside, `Workspace.City` holds the city 900 studs down (blocks of lit towers, sodium-lit streets), and `Workspace.Weather` the rain past the windows and the cool city glow that falls in through them.

Light, and the mood:
- Dark: a low ambient, and most light comes from what's in the room (desk lamps left on, screens, vending machines, the reception desk's strip) and the city through the windows. A share of every room's fixtures are dead, and some flicker or sputter. Fixtures still follow the contract (Blackout, gunfire, the Upload finale).
- `src/client/Ambience.luau` runs the mood on every client: failing lights stutter while their room has power, lightning flashes over the city every minute or so (it lights the rooms through the glass), rain runs down the windows, the masts' beacons blink. It's decoration and touches nothing the server owns.
- Emergency lamps are amber, as the doc has them (red is the Chimera's alone): twin-head packs on the walls of every wing room.

Calls made where the doc or the request left it open, all easy to change in `tools/map/design_map.py` and `tools/map/mapgen/`:
- The Core is the Reception: its finale platform is the dais round the reception desk (36 x 34), the Uplink is the monolith inside the desk, and the Purge console stands beside it.
- The Observation Deck's glass blocks movement, shots and sight like a wall, as before; its two docks are on the deck itself (the stairwells have cameras but no docks).
- The stairs carry mercs and shells on an invisible ramp under each flight (a shell steps up 1.1 at most).
- Breachable walls, crawlspaces, data ports and the Volatile Asset spots still aren't placed: nothing in the code uses them.
- BuildMap sets the place's lighting (night, a low ambient, haze over the city, bloom and a desaturated grade). It also tries `Lighting.Technology = Future`, which some script contexts can't set: if the lights look flat, set it in the Properties window.

To change the map, edit the layout in `tools/map/design_map.py` or the dressing in `tools/map/mapgen/` (`core.py` the shell and finishes, `props.py` the prefabs, `dress.py` the rooms, `city.py` the city), then:
1. `python tools/map/design_map.py` checks it (overlaps, doorways, wall clearances, footprints) and writes `tools/map/MapLayout.luau` (the placements and prefabs, as JSON) and `tools/map/plan.png`. Add `--check` to only check, `--walk` for the walking distances.
2. Let Rojo sync it, then in Edit mode: `require(game.ServerStorage.DevTools.BuildMap:Clone()).build()` (or `.run()` to build in the background). It needs the kit in `ServerStorage.MapKit` for the gameplay pieces, screens and racks. A build takes about 3 s.
3. Save the place.

### The map kit

`ServerStorage.MapKit` holds 89 dark-metal pieces for dressing the facility, built by `tools/mapkit/BuildMapKit.luau` (it syncs to `ServerStorage.DevTools.BuildMapKit`). The kit itself places nothing in the world; the full map uses its gameplay pieces, screens, racks and industrial props alongside the map's own prefabs.

| Folder | Pieces |
| --- | --- |
| Walls | 8x16 and 8x12 wall panels (plate, ribbed, vent, pipes, live screen, hazard, access hatch), 4-wide fillers, upper panels to stack for taller rooms (8x8, 4x8) and over doors (8x4, 4x4), light upper panels for walls 24+ studs up (`_Lite`: the same face without chamfers or bolts), a floor-to-ceiling window (`WallGlass_8x16`, with the pane) and the glazed band for the far side of the wall (`WallWindow_8x8`), a cap, 16 and 12 pillars |
| Floors | diamond plate and grate tiles (8x8), a hazard strip (8x1), a floor hatch (4x4) |
| Ceilings | ceiling panel (8x8), I-beam, duct, cable tray, hanging pipes |
| Doorways | frames for the graybox openings: 8x10, 12x10, 24x12, 24x14 |
| Lights | ceiling strip, caged wall lamp, pendant, a room's light panel (the Blackout target; its `Panel` part goes straight into the room's Lights folder) |
| Office | desk, a dressed workstation, monitors (one per feed), keyboard, mouse, laptop, mug, paper tray, PC tower, chair, control console, wall monitors (map, camera, status), filing cabinet, locker, storage shelf |
| ServerRoom | two server racks, a cooling unit, a cable bundle under a floor protector |
| Industrial | pipe runs (horizontal with a valve and gauge, and vertical), junction box, crate, crate stack, barrel, railing |
| Signs | sector (names its room), direction, warning, restricted, and a Lockdown sign that lights up |
| Gameplay | contract-ready Mainframe Terminal, security camera, sliding door (for `DoorFrame_8x10`), emergency beacon, shell dock (a printing cradle, open behind the shell so the Chimera's camera isn't blocked), charging station and floodlight |

How the pieces fit:
- Everything sits on a 4-stud grid and most pieces are 8 wide, matching the graybox walls and openings.
- A piece's pivot is where it mounts and its front faces -Z (the `Mount` attribute): wall pieces pivot at the bottom of their back on the wall's face, floor pieces at the bottom centre, desk pieces on a desk top (desks are 2.8 high), ceiling pieces at the top centre, and doorway frames at the bottom of the opening on the wall's centre line. On a wall lined with panels, mount props on the panel sheets, 0.52 in front of the wall's face.
- The `PlaceIn` attribute says which folder of the map contract a piece goes in. Lights go in `Facility/Lights/<RoomId>`; their glowing part is named `Fixture`, so Blackout turns them off and mercs can shoot them out.
- The Gameplay pieces carry the contract's attributes with placeholder ids (`TERM_NEW`, `CAM_NEW`, `D_NEW`): set them when you place one. The door is placed closed in the doorway and slides its `Slide` attribute's studs along its X to open; `FacilityMap` works out its open and closed positions. The beacon's red `Lamp` lights when the wing's terminal is rebooted.
- Only the big parts collide, so nothing snags a merc or a shell sliding along a wall. Everything still blocks sight and shots.
- Signs, screen headings and the whole HUD share two fonts from `src/shared/Fonts.luau`: Zekton for headings, labels, buttons and big numbers, and Roboto Mono for data and running text.
- `Model:ScaleTo` resizes a piece cleanly.

Live pieces. `src/client/FacilityScreens.luau` drives them on every client from facts the client already has (the match state, terminal, camera and door attributes, which lights are on, merc vitals), so they send nothing and show nothing a player couldn't already see. The pieces are found by CollectionService tag, wherever they're placed:
- Screens (`KitScreen`) each show one feed from `src/shared/ScreenFeeds.luau`, set by the screen's `Feed` attribute: Status, Upload, Terminals, Camera (set `CameraId`, or leave it empty for the room's own camera), Room, Squad, Log, Map (drawn from the real room layout, with a you-are-here dot), Graph, Alert, Terminal or Off. Change `Feed` on a placed screen to change what it shows. The Log feed lists facility events as they happen (doors sealed, power failures, terminal faults and reboots, cameras shot out, downs). Screens in a blacked-out room dim, and the Upload finale makes them glitch.
- Rack LEDs and console buttons (`KitLeds`) blink faster as the upload climbs and turn amber in Lockdown and magenta in the Upload finale. Status lights (`KitStatus`) go amber in a dark room, green in a secured wing and red in Lockdown or a finale. Door lights (`KitDoorLight`) on doorframes show the nearest door: green open, amber sealed, white welded. Sector signs show their room, doorframe headers show the room through the door, and the Lockdown sign lights up for Lockdown and the finales.
- Screens animate within 60 studs of the camera and refresh slowly out to 160; LEDs animate within 70.

Textures. The kit wears PS1-style pixel-art textures drawn by `tools/mapkit/textures/make_textures.py`: painted steel, diamond tread, rusted metal, rubber, cardboard, leather and hazard stripes. Each is drawn as 256x256 pixel art with ordered dithering and a few tones, then scaled up 4x with hard edges to 1024x1024 so the pixels stay crisp; steel shows about 26 pixels per stud. Each tiles seamlessly, and to keep repeats from showing, a tile covers 4 to 10 studs, detail is spread evenly at small scales with no single large feature, and the textures with no direction (steel, rust, rubber, leather) use Roblox's Organic tiling, which shuffles tiles so they don't line up. They're uploaded as image assets, and the kit build turns them into MaterialVariants in MaterialService (`AxiomSteel`, `AxiomTread`, `AxiomWorn`, `AxiomRubber`, `AxiomCardboard`, `AxiomLeather`, `AxiomHazard`), which kit parts use by material. The textures are grey, so part colours still set each part's tone, and a part falls back to its plain colour if its texture can't load. To change one, edit the script, run `python tools/mapkit/textures/make_textures.py` (add a file path to also get a preview sheet), upload the new PNG, put its asset id in the `TEXTURES` table at the top of `BuildMapKit.luau`, and rebuild the kit.

Running `require(game.ServerStorage.DevTools.BuildMapKit:Clone())()` rebuilds the kit and replaces `ServerStorage.MapKit`. `require(game.ServerStorage.DevTools.BuildMapKit:Clone()).gallery()` lays every piece out in `Workspace.MapKitGallery`, far from the map (around z 490 to 700), one row per folder with a nameplate under each piece; delete it before saving the place. `require(game.ServerStorage.DevTools.BuildMapKit:Clone()).audit()` checks every piece, and a sample hallway built from them, for Z-fighting: faces that point the same way, lie in the same plane and overlap. It reports the ones you could see and counts the ones buried inside other parts. If a gallery shot from the MCP looks unlit, move the Studio camera there first and wait a few seconds for the lighting to catch up.
