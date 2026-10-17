# NullShight Roblox scripts

Luau murni, executor-agnostic (Delta / Fluxus / Wave mobile). Tiap game satu
folder: skrip + catatan mapping versi game.

## Slice A Dummy! (`slice-a-dummy/`)

`slice-a-dummy.lua` — v0.1.0, jalan apa adanya:

- Anti-AFK, FPS boost opsional, notifikasi status.
- Auto-swing 3 lapis: RemoteEvent kalau `CONFIG.SwingRemote` diisi, fallback
  aktivasi tool, fallback klik ClickDetector dummy.

### Mapping remote (sekali per update game)

1. Buka game + executor, jalanin Dex / SimpleSpy.
2. Ayun sekali manual, catat RemoteEvent/RemoteFunction yang fire
   (nama + path dari ReplicatedStorage, misal `Events.SwingEvent`).
3. Tulis ke `CONFIG.SwingRemote` / `RebirthRemote` / `EggRemote` di skrip.
4. Paste skrip ke executor, run. Kalau remote berubah pas update game,
   ulangi langkah 2–3 — cuma 3 baris itu yang rawan jebol.

Kirim hasil mapping (nama remote) ke saya kalau mau saya yang finalize.

## Cara pakai (loadstring, tanpa copy-paste)

Di Delta cukup run satu baris ini — tiap update skrip tinggal run ulang:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/slice-a-dummy/slice-a-dummy.lua"))()
```

## Mine A Mountain (`mine-a-mountain/`)

`mine-a-mountain.lua` — v0.1.0:

- Auto-mine crystal/boulder terdekat (`DigRequest` + fallback ayun tool).
- Auto-collect (prompt + hold-complete), auto-sell berkala + tombol SELL NOW.
- Ore ESP (nama + value, cap 40 biar enteng), anti-AFK, FPS boost opsional.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/mine-a-mountain/mine-a-mountain.lua"))()
```

Remote teramati dari skrip publik — kalau game update dan ada yang mati,
mapping ulang via SimpleSpy, yang diganti cuma CONFIG.

`slice.lua` — v0.4.0, cache-proof mirror (same content). "NS Console" UI:
left icon rail, dense hairline rows, signature accent per game, breathing
emblem, live hit readout, grab-anywhere drag, generation guard.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/slice-a-dummy/slice.lua"))()
```

## Greedy Growers (`greedy-growers/`)

`greedy-growers.lua` — v0.1.0, game Knit (Services.<Svc>.RF/.RE):

- Auto Buy Seed (ID di CONFIG), Auto Plant (tipe + modifier di CONFIG).
- Auto Harvest via prompt fallback (remote khusus belum ke-map).
- Auto Dead Tree, Auto Sell + SELL NOW, Auto Quest (default off).
- UI v2 + grab-anywhere drag + UNLOAD.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/greedy-growers/gg.lua"))()
```

## NetLens RemoteSpy (`remote-spy/`)

`remote-spy.lua` — v1.2.5, full English, landscape single page:

- Merges duplicate calls (xN), tap row to copy paste-ready snippet,
  per-row blacklist, pause/clear/copy-all, merge + args-only toggles.
- Capped buffer, truncated previews, discreet GUI names.
- Verifies itself at startup: fires a canary RemoteEvent and reports
  `LIVE <mode>` or `DEAD` instead of always claiming "armed".

### v1.2.5 — hook install fix (v1.2.4 was dead on mobile executors)

v1.2.4 used `hookfunction`'s return value both as the "did it install?" flag
and as the original to call through. Several mobile executors return nothing
on success, so the hook went live with a `nil` passthrough: every
`:FireServer()`/`:InvokeServer()` in the game threw `attempt to call a nil
value` and zero rows were ever logged, while the status line still read
"armed". The same trap in the `__namecall` fallbacks broke every `:Method()`
call in the client, not just remotes.

- Originals are captured **before** hooking; `hookfunction`'s return value is
  never read.
- Probe instances are never destroyed — some executors return per-instance
  bound closures, and `Destroy` silently unhooks the game.
- `getnamecallmethod` is no longer a fatal gate; falls back to `debug.info`
  then to RemoteClass classification instead of logging nothing.
- The `hookmetamethod` path refuses to install when it has no safe passthrough.
- `unload()` restores against the current slot occupant (v1.2.4 hooked a
  destroyed probe instance) and clears state.
- Arguments carry an explicit count end to end, so `InvokeServer(x, nil, nil)`
  is no longer truncated to one argument on replay.

If the verdict reads `DEAD`, the executor's `hookfunction` is genuinely stubbed
and no script-side change can make remote logging work there. The diagnostic
now says so instead of leaving an empty panel.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/remote-spy/remote-spy.lua"))()
```

## Build the Pyramid (`build-a-pyramid/`)

`build-a-pyramid.lua` — v0.1.0, Knit game (Services.<Svc>.RF):

- Auto Pickup (`BlockService.RF.Pickup` + quarry region), PICKUP x5 button.
- Auto Deliver (`PyramidService.RF.Place` + prompt fallback).
- Train Speed/Strength toggles (honest: warn until remotes mapped).
- Landscape tabs + grab-anywhere + UNLOAD, all English.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/build-a-pyramid/build-a-pyramid.lua"))()
```

## Sword Loot Monarch (`sword-loot-monarch/`)

`sword-loot-monarch.lua` — v0.1.0, full English:

- Auto Click (`Remotes.MainEvent` + click args), CLICK x50 burst.
- FARM tab ready: Train / Stage / Rebirth / Collect (honest: warn until mapped).
- Landscape tabs + grab-anywhere + UNLOAD.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/sword-loot-monarch/sword-loot-monarch.lua"))()
```

## Clicker Tap (`clicker-simulator/`)

`clicker-simulator.lua` — v0.1.0, full English. Remote-free auto clicker:
synthetic screen taps via VirtualInputManager (works with unnamed remotes).

- Auto Tap (configurable point), Turbo toggle, TAP x50 burst.
- REMOTE tab ready for when the real remote gets mapped.
- Landscape tabs + grab-anywhere + UNLOAD.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/clicker-simulator/clicker-simulator.lua"))()
```
