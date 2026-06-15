# display/

Scripts und Findings rund um Notch, Menüleiste und Display-Verhalten auf macOS.

---

## hide-notch — Schwarzer Balken über den Notch

### Was es tut

`notch-black.swift` zeichnet einen schwarzen Balken über den Notch-Bereich des
Wallpapers. Das Original-Wallpaper wird nie verändert – der Balken wird in eine
temporäre PNG-Kopie gezeichnet und als Wallpaper gesetzt.

`setup-hide-notch.sh` installiert das Script als LaunchAgent (startet automatisch
beim Login) und verwaltet Backups.

### Erkenntnisse (hardgefunden)

#### 1. HEIC Wallpapers sind quadratisch

Sonoma.heic ist **6016×6016px** – macOS croppt es via Aspect-Fill von der Mitte
auf die Display-Auflösung (3024×1964px physisch). Der Balken muss deshalb im
Bildkoordinatensystem berechnet werden, nicht in Screen-Koordinaten.

Formel:
```
fillScale = max(screenW / imgW, screenH / imgH)
offsetY    = (imgH * fillScale - screenH) / 2 / fillScale
visibleTop = imgH - offsetY          // oberster sichtbarer Pixel (CG: Y=0 unten)
barHeight  = notchHeight / fillScale // Balkenhöhe im Bildkoordinatensystem
```

#### 2. menuBarHeight ≠ Notch-Höhe

`NSScreen.visibleFrame` liefert die Höhe der gesamten Menüleiste (inkl. Padding),
nicht die tatsächliche Notch-Höhe. Auf MBP 14" M-Series:
- `visibleFrame`-basierte Menüleistenhöhe: **65px** physisch
- Tatsächliche Notch-Höhe via `safeAreaInsets.top`: **~37pt = 74px @2x**

**Lösung:** `screen.safeAreaInsets.top * backingScaleFactor` – gibt den exakten
Notch-Wert zurück, funktioniert auf allen Displays (gibt 0 zurück auf Displays
ohne Notch → kein Balken gezeichnet).

#### 3. Script liest eigenes Temp-PNG als Wallpaper

Wenn der LaunchAgent neu startet, ist das aktive Wallpaper bereits das
modifizierte Temp-PNG. `workspace.desktopImageURL(for: screen)` liefert dann
das Temp-PNG statt des Originals → Endlosschleife mit degradiertem Bild.

**Lösung:** Original-Pfad wird persistent gespeichert:
```
~/Library/Application Support/hide-notch/original-wallpaper.txt
```
Beim Start: gespeicherter Pfad hat Priorität. Nur beim allerersten Start
(kein State-File, kein Temp-PNG aktiv) wird der aktuelle Pfad als Original
gespeichert.

Wallpaper wechseln:
```zsh
rm ~/Library/Application\ Support/hide-notch/original-wallpaper.txt
pkill -f notch-black.swift
```
Beim nächsten Start nimmt das Script das neue Wallpaper.

#### 4. `defaults read com.apple.desktop Background` ist leer

Auf diesem System gibt es keinen Dynamic Desktop – der Key existiert nicht.
`NSWorkspace.desktopImageURL` ist der richtige Weg.

---

### Backups

Jedes `setup-hide-notch.sh`-Install sichert das aktuelle Wallpaper:
```
~/Library/Application Support/hide-notch/backups/
  wallpaper_YYYY-MM-DD_HH-MM-SS_<name>.backup       ← Bildkopie
  wallpaper_YYYY-MM-DD_HH-MM-SS_<name>.backup.path  ← Original-Pfad
```
Max. 10 Backups werden behalten. Nie automatisch gelöscht außer >10 Stück.

---

### Usage

```zsh
# Installieren + LaunchAgent einrichten
cd ~/git/dotfiles-macos && ./display/setup-hide-notch.sh

# Manuell testen (Ctrl+C stellt Original wieder her)
swift display/notch-black.swift

# Wallpaper wechseln
rm ~/Library/Application\ Support/hide-notch/original-wallpaper.txt
pkill -f notch-black.swift

# Alles entfernen
./display/setup-hide-notch.sh --uninstall

# Logs
tail -f /tmp/hide-notch.log
```

---

### Was wir ausprobiert und verworfen haben

| Ansatz | Problem |
|---|---|
| `defaults read com.apple.desktop Background` | Key existiert nicht auf diesem System |
| `visibleFrame`-basierte Balkenhöhe mit Faktor | Faktor musste manuell erraten werden (0.72 → 0.95 → 1.05 → ...) |
| `NSImage(contentsOf:)` direkt für HEIC | Lädt erstes Frame, nicht das angezeigte |
| Balken in Screen-Koordinaten | Falsch – HEIC wird aspect-fill gecroppt, Balken landet in der Bildmitte |
