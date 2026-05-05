import Foundation
import AppKit

enum BitmapGenerator {
    static func makeGraphicsPNG(
        width: Int,
        height: Int,
        pixels: [ProgressPixel],
        scale: Int = 1
    ) throws -> Data {
        guard pixels.count == width * height else {
            throw AppError.message("Pixel buffer size mismatch")
        }
        let safeScale = max(1, scale)
        let exportWidth = width * safeScale
        let exportHeight = height * safeScale

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: exportWidth,
            pixelsHigh: exportHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: exportWidth * 4,
            bitsPerPixel: 32
        ), let bitmap = rep.bitmapData else {
            throw AppError.message("Could not allocate bitmap")
        }

        for y in 0..<height {
            for x in 0..<width {
                let source = pixels[y * width + x]
                let rgba = source.rgba
                let yBase = (height - 1 - y) * safeScale
                for dy in 0..<safeScale {
                    for dx in 0..<safeScale {
                        let px = x * safeScale + dx
                        let py = yBase + dy
                        let dst = (py * exportWidth + px) * 4
                        bitmap[dst + 0] = rgba.r
                        bitmap[dst + 1] = rgba.g
                        bitmap[dst + 2] = rgba.b
                        bitmap[dst + 3] = rgba.a
                    }
                }
            }
        }

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw AppError.message("Could not encode PNG")
        }
        return data
    }

    static func loadGraphicsPixels(from url: URL, width: Int, height: Int) throws -> [ProgressPixel] {
        guard let image = NSImage(contentsOf: url) else {
            throw AppError.message("Could not read PNG image")
        }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else {
            throw AppError.message("Could not allocate bitmap for import")
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw AppError.message("Could not create graphics context")
        }
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(NSColor.black.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        context.flushGraphics()

        var output = Array(repeating: ProgressPixel.off, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sampleY = (height - 1) - y
                guard let color = rep.colorAt(x: x, y: sampleY)?.usingColorSpace(.deviceRGB) else {
                    output[y * width + x] = .off
                    continue
                }
                output[y * width + x] = pixelFromImportedColor(color)
            }
        }
        return output
    }

    static func pixelFromImportedColor(_ color: NSColor) -> ProgressPixel {
        if color.alphaComponent < 0.05 {
            return .off
        }
        let r = color.redComponent
        let g = color.greenComponent
        let b = color.blueComponent
        let samples: [(ProgressPixel, Double, Double, Double)] = [
            (.off, 0.0, 0.0, 0.0),
            (.red, 1.0, 0.0, 0.0),
            (.green, 0.0, 1.0, 0.0),
            (.orange, 1.0, 0.647, 0.0)
        ]
        var best = ProgressPixel.off
        var bestDistance = Double.greatestFiniteMagnitude
        for (pixel, pr, pg, pb) in samples {
            let dr = Double(r) - pr
            let dg = Double(g) - pg
            let db = Double(b) - pb
            let d = dr * dr + dg * dg + db * db
            if d < bestDistance {
                bestDistance = d
                best = pixel
            }
        }
        return best
    }

    static func makeRGB565BMP(width: Int, height: Int, pixels: [ProgressPixel]) -> Data {
        let bytesPerPixel = 2
        let rowBytes = width * bytesPerPixel
        let rowStride = ((rowBytes + 3) / 4) * 4
        let imageSize = rowStride * height
        let pixelOffset = 14 + 40 + 12
        let fileSize = pixelOffset + imageSize

        var data = Data()
        data.append(contentsOf: [0x42, 0x4d])
        data.appendLE32(UInt32(fileSize))
        data.appendLE16(0)
        data.appendLE16(0)
        data.appendLE32(UInt32(pixelOffset))
        data.appendLE32(40)
        data.appendLE32(UInt32(width))
        data.appendLE32(UInt32(height))
        data.appendLE16(1)
        data.appendLE16(16)
        data.appendLE32(3)
        data.appendLE32(UInt32(imageSize))
        data.appendLE32(0)
        data.appendLE32(0)
        data.appendLE32(0)
        data.appendLE32(0)
        data.appendLE32(0x0000f800)
        data.appendLE32(0x000007e0)
        data.appendLE32(0x0000001f)

        let padding = rowStride - rowBytes
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width {
                data.appendLE16(pixels[y * width + x].rgb565)
            }
            if padding > 0 {
                data.append(contentsOf: repeatElement(UInt8(0), count: padding))
            }
        }
        return data
    }
}
