import AppKit
import Foundation

let destination = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("No drawing context")
}

let outer = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(red: 0.06, green: 0.12, blue: 0.13, alpha: 1),
    NSColor(red: 0.02, green: 0.05, blue: 0.07, alpha: 1)
])!
gradient.draw(in: outer, angle: -45)

context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: NSColor.black.withAlphaComponent(0.30).cgColor)
let sheet = NSBezierPath(roundedRect: NSRect(x: 208, y: 174, width: 608, height: 676), xRadius: 92, yRadius: 92)
NSColor(red: 0.94, green: 0.92, blue: 0.84, alpha: 1).setFill()
sheet.fill()
context.setShadow(offset: .zero, blur: 0, color: nil)

let header = NSBezierPath(roundedRect: NSRect(x: 208, y: 690, width: 608, height: 160), xRadius: 92, yRadius: 92)
NSColor(red: 0.96, green: 0.70, blue: 0.24, alpha: 1).setFill()
header.fill()
NSColor(red: 0.96, green: 0.70, blue: 0.24, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 208, y: 690, width: 608, height: 80)).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let number = String(Calendar.current.component(.day, from: Date())) as NSString
number.draw(
    in: NSRect(x: 208, y: 276, width: 608, height: 340),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 280, weight: .semibold),
        .foregroundColor: NSColor(red: 0.06, green: 0.11, blue: 0.12, alpha: 1),
        .paragraphStyle: paragraph
    ]
)

for x in [330.0, 694.0] {
    let ring = NSBezierPath(roundedRect: NSRect(x: x - 24, y: 792, width: 48, height: 116), xRadius: 24, yRadius: 24)
    NSColor(red: 0.48, green: 0.82, blue: 0.73, alpha: 1).setFill()
    ring.fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
try png.write(to: URL(fileURLWithPath: destination))
