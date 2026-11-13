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

`rojo build -o Chimera.rbxlx` builds a place with just the code, which is handy for a quick check. Git ignores place files.
