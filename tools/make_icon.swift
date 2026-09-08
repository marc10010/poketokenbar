#!/usr/bin/env swift
// Genera assets/AppIcon.icns. Dibuja una barra de HP pixelada sobre fondo
// oscuro: es de lo que va la app y no usa nada con dueño (los sprites de
// Pokémon no se distribuyen, se bajan de PokeAPI en tiempo de ejecución).
//
//   swift tools/make_icon.swift && ./scripts/bundle.sh

import AppKit

let side = 1024
let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
    let context = NSGraphicsContext.current!.cgContext

    // Fondo: degradado azul noche con esquinas redondeadas al estilo macOS.
    let corner = rect.width * 0.22
    let background = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    background.addClip()
    NSGradient(
        starting: NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.24, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.11, alpha: 1)
    )?.draw(in: rect, angle: -90)

    // Rejilla tenue: guiño al pixel art sin dibujar nada de nadie.
    NSColor.white.withAlphaComponent(0.04).setStroke()
    let step = rect.width / 16
    let grid = NSBezierPath()
    grid.lineWidth = 2
    for index in 1..<16 {
        let offset = step * CGFloat(index)
        grid.move(to: NSPoint(x: offset, y: 0))
        grid.line(to: NSPoint(x: offset, y: rect.height))
        grid.move(to: NSPoint(x: 0, y: offset))
        grid.line(to: NSPoint(x: rect.width, y: offset))
    }
    grid.stroke()

    // Barra de HP: cinco bloques, de verde a rojo, el último vacío.
    let blocks = 5
    let filled = 4
    let barWidth = rect.width * 0.66
    let barHeight = rect.height * 0.2
    let gap = barWidth * 0.035
    let blockWidth = (barWidth - gap * CGFloat(blocks - 1)) / CGFloat(blocks)
    let originX = (rect.width - barWidth) / 2
    let originY = (rect.height - barHeight) / 2 - rect.height * 0.03

    let palette = [
        NSColor(calibratedRed: 0.32, green: 0.82, blue: 0.40, alpha: 1),
        NSColor(calibratedRed: 0.52, green: 0.85, blue: 0.35, alpha: 1),
        NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.28, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.25, alpha: 1),
        NSColor.white.withAlphaComponent(0.12),
    ]

    for index in 0..<blocks {
        let blockRect = NSRect(
            x: originX + (blockWidth + gap) * CGFloat(index),
            y: originY,
            width: blockWidth,
            height: barHeight
        )
        let path = NSBezierPath(roundedRect: blockRect, xRadius: blockWidth * 0.16, yRadius: blockWidth * 0.16)
        (index < filled ? palette[index] : palette[blocks - 1]).setFill()
        path.fill()
    }

    // "1 token = 1 HP" reducido a su mínimo legible a 16 px: un punto y la barra.
    let dotSide = rect.width * 0.11
    let dot = NSBezierPath(ovalIn: NSRect(
        x: (rect.width - dotSide) / 2,
        y: originY + barHeight + rect.height * 0.09,
        width: dotSide,
        height: dotSide
    ))
    NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.35, alpha: 1).setFill()
    dot.fill()

    _ = context
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("no se pudo renderizar el icono\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: "assets/icon-1024.png")
try png.write(to: output)
print("escrito \(output.path)")
