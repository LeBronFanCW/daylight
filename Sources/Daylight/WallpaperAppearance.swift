import AppKit
import Foundation

struct WallpaperPresentation: Equatable {
    let appearance: DaylightAppearance
    let washOpacity: Double

    static func analyzing(luminances: [Double]) -> WallpaperPresentation? {
        guard !luminances.isEmpty else { return nil }

        let clamped = luminances.map { min(max($0, 0), 1) }
        let average = clamped.reduce(0, +) / Double(clamped.count)
        let variance = clamped.reduce(0) { result, luminance in
            result + pow(luminance - average, 2)
        } / Double(clamped.count)
        let deviation = sqrt(variance)

        // Mid-tone and visually busy images need a little more separation. Bright
        // or dark, quiet images can remain almost untouched.
        let midtoneAmount = 1 - min(abs(average - 0.5) * 2, 1)
        let detailAmount = min(deviation / 0.30, 1)
        let opacity = min(max(0.18 + (0.10 * midtoneAmount) + (0.08 * detailAmount), 0.18), 0.36)

        return WallpaperPresentation(
            appearance: average >= 0.52 ? .light : .dark,
            washOpacity: opacity
        )
    }
}

enum WallpaperAppearanceAnalyzer {
    static func analyze(url: URL) -> WallpaperPresentation? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return analyze(image: image)
    }

    static func analyze(image: NSImage) -> WallpaperPresentation? {
        let sampleSize = 24
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: sampleSize,
            pixelsHigh: sampleSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(
            in: NSRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var luminances: [Double] = []
        luminances.reserveCapacity(sampleSize * sampleSize)
        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = (0.2126 * color.redComponent)
                    + (0.7152 * color.greenComponent)
                    + (0.0722 * color.blueComponent)
                // Treat transparent pixels as neutral so they cannot force an
                // unexpectedly dark palette.
                luminances.append((luminance * color.alphaComponent) + (0.5 * (1 - color.alphaComponent)))
            }
        }

        return WallpaperPresentation.analyzing(luminances: luminances)
    }
}
