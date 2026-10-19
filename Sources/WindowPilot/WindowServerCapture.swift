import CoreGraphics
import Darwin

/// Captures a window's last rendered backing store through the window server.
///
/// ScreenCaptureKit fails with `SCStreamError -3811` for windows that are not on the current Space.
/// The window server still keeps the contents of windows on other desktops, and
/// `CGSHWCaptureWindowList` (the call Mission Control-style switchers use) can read it. It is a
/// private SkyLight symbol, so it is resolved at runtime and every failure simply returns `nil`.
/// It is subject to the same Screen Recording permission, and the window server still withholds
/// windows whose owner disabled sharing (e.g. password managers). Minimized windows have no
/// retained contents and return `nil`.
enum WindowServerCapture {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CaptureWindowList = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?

    private static let ignoreGlobalClipShape: UInt32 = 1 << 11
    private static let nominalResolution: UInt32 = 1 << 9

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let mainConnectionID: MainConnectionID? = symbol("CGSMainConnectionID")
    private static let captureWindowList: CaptureWindowList? = symbol("CGSHWCaptureWindowList")

    private static func symbol<T>(_ name: String) -> T? {
        guard let skyLight, let pointer = dlsym(skyLight, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static func image(of windowID: CGWindowID) -> CGImage? {
        guard let mainConnectionID, let captureWindowList else { return nil }
        var id = windowID
        guard let array = captureWindowList(mainConnectionID(), &id, 1, ignoreGlobalClipShape | nominalResolution)?.takeRetainedValue(),
              let image = (array as? [CGImage])?.first,
              image.width > 1, image.height > 1, !isBlank(image) else { return nil }
        return image
    }

    /// Windows that were never drawn come back as a single flat color; an app icon is more useful.
    private static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        for channel in 0..<4 {
            var low = UInt8.max, high = UInt8.min
            for pixel in stride(from: channel, to: pixels.count, by: 4) {
                low = min(low, pixels[pixel]); high = max(high, pixels[pixel])
            }
            if high - low > 6 { return false }
        }
        return true
    }
}
