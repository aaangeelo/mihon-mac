import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = directory.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.55, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.9, height: p * 0.9), xRadius: p * 0.2, yRadius: p * 0.2).fill()
        let book = NSBezierPath()
        book.move(to: NSPoint(x: p * 0.5, y: p * 0.25))
        book.line(to: NSPoint(x: p * 0.23, y: p * 0.34))
        book.line(to: NSPoint(x: p * 0.23, y: p * 0.71))
        book.line(to: NSPoint(x: p * 0.5, y: p * 0.63))
        book.line(to: NSPoint(x: p * 0.77, y: p * 0.71))
        book.line(to: NSPoint(x: p * 0.77, y: p * 0.34))
        book.close()
        NSColor.white.setFill(); book.fill()
        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: p * 0.5, y: p * 0.25)); seam.line(to: NSPoint(x: p * 0.5, y: p * 0.63))
        seam.lineWidth = max(1, p * 0.012)
        NSColor(calibratedRed: 0.65, green: 0.67, blue: 0.87, alpha: 1).setStroke(); seam.stroke()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = rep.representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", directory.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at: iconset)
