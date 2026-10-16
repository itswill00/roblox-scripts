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

## Greedy Growers (`greedy-growers/`)

`greedy-growers.lua` — v0.1.0, game Knit (Services.<Svc>.RF/.RE):

- Auto Buy Seed (ID di CONFIG), Auto Plant (tipe + modifier di CONFIG).
- Auto Harvest via prompt fallback (remote khusus belum ke-map).
- Auto Dead Tree, Auto Sell + SELL NOW, Auto Quest (default off).
- UI v2 + grab-anywhere drag + UNLOAD.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/itswill00/roblox-scripts/main/greedy-growers/greedy-growers.lua"))()
```
