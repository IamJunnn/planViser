import Foundation
import ScreenCaptureKit
import AppKit

final class ScreenCaptureService {
    static let shared = ScreenCaptureService()
    private init() {}

    /// Triggers the system permission prompt by requesting shareable content.
    func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    /// Captures the main display as JPEG data at reduced quality/scale.
    func captureScreen() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5])
        else {
            throw CaptureError.conversionFailed
        }

        return jpegData
    }

    enum CaptureError: Error, LocalizedError {
        case noDisplay
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found for capture"
            case .conversionFailed: return "Failed to convert screenshot to JPEG"
            }
        }
    }
}
