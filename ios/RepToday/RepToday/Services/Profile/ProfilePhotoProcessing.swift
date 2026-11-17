import CoreGraphics
import UIKit

/// Turns a photo from the camera, the library or the account into the profile photo the app stores: a
/// square crop, downscaled and compressed. Pure image work with no I/O.
enum ProfilePhotoProcessing {
    /// The stored photo's side in pixels: sharp at the Profile header's size on a 3x screen, small
    /// enough to store and upload in a moment.
    static let outputPixelSide: CGFloat = 512
    /// JPEG quality of the stored photo.
    static let jpegQuality: CGFloat = 0.82
    /// The longest side, in pixels, a photo is reduced to before cropping, so a full-resolution camera
    /// photo never sits in memory at full size while the user adjusts the crop.
    static let croppingPixelSide: CGFloat = 2048

    /// The image drawn upright (its EXIF orientation applied) at a scale of 1, its longest side no more
    /// than `maxPixelSide`. Pixel coordinates then match what the crop screen shows.
    static func upright(_ image: UIImage, maxPixelSide: CGFloat = croppingPixelSide) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        let factor = longest > maxPixelSide ? maxPixelSide / longest : 1
        let target = CGSize(width: (pixelSize.width * factor).rounded(), height: (pixelSize.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// The stored photo: the part of `image` inside `normalizedCrop` (a unit-square rectangle over the
    /// upright image, from `ProfilePhotoCropGeometry`), made square, `outputPixelSide` wide and
    /// JPEG-compressed. `nil` when the image cannot be read.
    static func croppedPhoto(from image: UIImage, normalizedCrop: CGRect) -> Data? {
        let upright = image.imageOrientation == .up && image.scale == 1 ? image : upright(image)
        guard let cgImage = upright.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let unit = normalizedCrop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !unit.isNull, unit.width > 0, unit.height > 0 else { return nil }
        // A square in pixels, whatever floating-point error the normalized rectangle carried.
        let side = min(min(unit.width * width, unit.height * height).rounded(), width, height)
        guard side >= 1 else { return nil }
        let pixelRect = CGRect(
            x: min(max(0, (unit.midX * width - side / 2).rounded()), width - side),
            y: min(max(0, (unit.midY * height - side / 2).rounded()), height - side),
            width: side,
            height: side
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return encoded(UIImage(cgImage: cropped))
    }

    /// The account's image made into a stored photo: decoded, centered square crop, downscaled and
    /// compressed the same way. `nil` when the data is not an image.
    static func storedPhoto(fromAccountImage data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return croppedPhoto(from: image, normalizedCrop: ProfilePhotoCropGeometry.centeredSquare(for: uprightPixelSize(of: image)))
    }

    /// The image's pixel size once drawn upright.
    static func uprightPixelSize(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// `image` (already square) drawn at `outputPixelSide`, never upscaled, as JPEG.
    private static func encoded(_ image: UIImage) -> Data? {
        let side = min(outputPixelSide, image.size.width * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let target = CGSize(width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: jpegQuality)
    }
}

/// The crop screen's geometry: a square crop frame of side `frameSide` points over an image of
/// `imageSize` pixels, which the user zooms (`zoom`, from 1 - the image just filling the frame - to
/// `maxZoom`) and drags (`offset`, the image center's distance from the frame center, in points).
/// Pure, so the mapping from what the user sees to the pixels kept is tested without a screen.
struct ProfilePhotoCropGeometry: Equatable {
    static let maxZoom: CGFloat = 4

    let imageSize: CGSize
    let frameSide: CGFloat

    /// Points per pixel at zoom 1: the image's shorter side exactly spans the frame.
    var fillScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return frameSide / min(imageSize.width, imageSize.height)
    }

    /// The image's on-screen size at `zoom`.
    func displayedSize(zoom: CGFloat) -> CGSize {
        let scale = fillScale * clampedZoom(zoom)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, 1), Self.maxZoom)
    }

    /// `offset` limited so the image always covers the whole frame.
    func clampedOffset(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let displayed = displayedSize(zoom: zoom)
        let maxX = max(0, (displayed.width - frameSide) / 2)
        let maxY = max(0, (displayed.height - frameSide) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    /// The frame's square over the image, as a unit-square rectangle (0...1 on each axis).
    func normalizedCrop(zoom: CGFloat, offset: CGSize) -> CGRect {
        let zoom = clampedZoom(zoom)
        let offset = clampedOffset(offset, zoom: zoom)
        let displayed = displayedSize(zoom: zoom)
        guard displayed.width > 0, displayed.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        // The frame's top-left corner in the displayed image's coordinates.
        let originX = displayed.width / 2 - offset.width - frameSide / 2
        let originY = displayed.height / 2 - offset.height - frameSide / 2
        return CGRect(
            x: originX / displayed.width,
            y: originY / displayed.height,
            width: frameSide / displayed.width,
            height: frameSide / displayed.height
        )
    }

    /// The centered square of an image of `size` pixels, as a unit-square rectangle.
    static func centeredSquare(for size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let side = min(size.width, size.height)
        let width = side / size.width
        let height = side / size.height
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
}
