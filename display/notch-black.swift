#!/usr/bin/env swift
import Cocoa
import CoreGraphics

guard let screen = NSScreen.main else { exit(1) }
let workspace = NSWorkspace.shared

// Original-Wallpaper-Pfad persistent speichern, damit das Script
// beim Neustart nicht sein eigenes Temp-PNG als Quelle liest.
let stateFile = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Application Support/hide-notch/original-wallpaper.txt")

func loadOriginalURL() -> URL? {
    guard let saved = try? String(contentsOf: stateFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
          !saved.isEmpty else { return nil }
    let url = URL(fileURLWithPath: saved)
    // Nur verwenden wenn es NICHT unser eigenes Temp-PNG ist
    guard !saved.contains("notch-wallpaper") else { return nil }
    return url
}

func saveOriginalURL(_ url: URL) {
    try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? url.path.write(to: stateFile, atomically: true, encoding: .utf8)
}

var originalWallpaperURL: URL = URL(fileURLWithPath: "/")

func restoreWallpaper() {
    guard let s = NSScreen.main else { return }
    try? NSWorkspace.shared.setDesktopImageURL(originalWallpaperURL, for: s, options: [:])
    print("Original wiederhergestellt: \(originalWallpaperURL.path)")
}

// Original ermitteln: gespeicherter Wert hat Priorität vor aktuellem Wert
// (verhindert dass wir unser eigenes Temp-PNG als Original merken)
let currentURL = workspace.desktopImageURL(for: screen)
let isTempPNG = currentURL?.path.contains("notch-wallpaper") ?? false

if let saved = loadOriginalURL() {
    // Gespeicherter Original-Pfad vorhanden → verwenden
    originalWallpaperURL = saved
    print("Original-Wallpaper aus State-File: \(saved.path)")
} else if let current = currentURL, !isTempPNG {
    // Erster Start: aktuelles Wallpaper ist noch das echte Original
    originalWallpaperURL = current
    saveOriginalURL(current)
    print("Original-Wallpaper gespeichert: \(current.path)")
} else {
    print("Kein Original-Wallpaper gefunden"); exit(1)
}

let screenFrame = screen.frame
let scaleFactor = screen.backingScaleFactor
let screenW = screenFrame.width * scaleFactor   // physische Pixel
let screenH = screenFrame.height * scaleFactor

// Notch-Höhe direkt von macOS: safeAreaInsets.top gibt den exakten Notch-Wert
// in Points zurück – unabhängig von Auflösung und Display-Modell.
// Multipliziert mit backingScaleFactor = physische Pixel.
let notchPt = screen.safeAreaInsets.top          // z.B. 37pt auf MBP 14"
let menuBarHeight = ceil(notchPt * scaleFactor)  // physische Pixel, aufgerundet

print("Screen (physisch): \(screenW) x \(screenH)")
print("safeAreaInsets.top: \(notchPt)pt → \(menuBarHeight)px physisch")

guard let originalImage = NSImage(contentsOf: originalWallpaperURL),
      let cgOriginal = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { print("Bild laden fehlgeschlagen"); exit(1) }

let imgW = CGFloat(cgOriginal.width)
let imgH = CGFloat(cgOriginal.height)
print("Bild: \(imgW) x \(imgH)")

// macOS Wallpaper Scaling: "Fill Screen" = aspect-fill von der Mitte
// Skalierungsfaktor damit Bild den Screen ausfüllt
let scaleX = screenW / imgW
let scaleY = screenH / imgH
let fillScale = max(scaleX, scaleY)  // aspect-fill

let scaledW = imgW * fillScale
let scaledH = imgH * fillScale

// Offset (wie viel vom Bild wird abgeschnitten)
let offsetX = (scaledW - screenW) / 2 / fillScale
let offsetY = (scaledH - screenH) / 2 / fillScale

print("fillScale: \(fillScale), offsetX: \(offsetX), offsetY: \(offsetY)")

// Schwarzer Balken: oben im Bild = offsetY + (imgH - offsetY*2 - screenH/fillScale ... )
// Einfacher: direkt im skalierten Koordinatensystem rechnen
// Der obere Rand des sichtbaren Bereichs im Bild:
let visibleTopInImg = imgH - offsetY  // Y von oben im Bild (CG: Y=0 unten)
let barHeightInImg = menuBarHeight / fillScale

print("Balken in Bild-Koordinaten: y=\(visibleTopInImg - barHeightInImg), h=\(barHeightInImg)")

let colorSpace = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil,
    width: Int(imgW),
    height: Int(imgH),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

ctx.draw(cgOriginal, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: visibleTopInImg - barHeightInImg, width: Double(imgW), height: Double(barHeightInImg)))

guard let modifiedCG = ctx.makeImage() else { print("Bild rendern fehlgeschlagen"); exit(1) }

let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notch-wallpaper.png")
let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, modifiedCG, nil)
CGImageDestinationFinalize(dest)

do {
    try workspace.setDesktopImageURL(tempURL, for: screen, options: [:])
    print("Wallpaper gesetzt: \(tempURL.path)")
} catch {
    print("Fehler: \(error)"); exit(1)
}

signal(SIGTERM) { _ in restoreWallpaper(); exit(0) }
signal(SIGINT)  { _ in restoreWallpaper(); exit(0) }

RunLoop.main.run()
