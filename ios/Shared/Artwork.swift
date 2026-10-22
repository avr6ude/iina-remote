import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI

/// The current video frame, which stands in for cover art.
struct Artwork {
    let image: UIImage
    let tint: Tint

    static func load(from url: URL) async -> Artwork? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1280,
              ] as CFDictionary)
        else { return nil }
        return Artwork(image: UIImage(cgImage: image), tint: Tint(averageOf: image))
    }
}

/// A deep color taken from the artwork, dark enough for white text, like the backgrounds in Music.
struct Tint: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    init(averageOf image: CGImage) {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        var pixel = [UInt8](repeating: 0, count: 4)
        if let output = filter.outputImage {
            CIContext().render(output, toBitmap: &pixel, rowBytes: 4, bounds: output.extent, format: .RGBA8,
                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        UIColor(hue: hue, saturation: min(1, saturation * 1.3 + 0.1), brightness: 0.3, alpha: 1)
            .getRed(&red, green: &green, blue: &blue, alpha: nil)
        (self.red, self.green, self.blue) = (red, green, blue)
    }
}
