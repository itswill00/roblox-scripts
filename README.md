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
