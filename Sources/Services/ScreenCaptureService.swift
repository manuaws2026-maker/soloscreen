import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

/// Captures screenshots using ScreenCaptureKit, excluding the app's own window.
///
/// Requires macOS 14+ for `SCScreenshotManager`. All operations are actor-isolated
/// for thread safety.
actor ScreenCaptureService {

    // MARK: - Errors

    enum CaptureError: LocalizedError {
        case noDisplaysFound
        case screenCaptureNotAvailable
        case captureReturnedNoImage
        case tooManyDisplays
        case permissionDenied
        case unknown(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noDisplaysFound:
                return "No displays found for screen capture."
            case .screenCaptureNotAvailable:
                return "Screen capture is not available on this system."
            case .captureReturnedNoImage:
                return "Screen capture completed but returned no image data."
            case .tooManyDisplays:
                return "Too many displays detected. Maximum supported is 5."
            case .permissionDenied:
                return "Screen recording permission has not been granted. Please enable it in System Settings > Privacy & Security > Screen Recording."
            case .unknown(let err):
                return "Screen capture failed: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Singleton

    static let shared = ScreenCaptureService()

    // MARK: - Constants

    private static let maxDisplayCount = 5

    // MARK: - Window Exclusion

    /// The window ID of SubtleAI's own overlay, so it can be excluded from captures.
    /// Set this from the main actor after the stealth window is created.
    private var excludedWindowIDs: Set<UInt32> = []

    /// Register a window to be excluded from all future captures.
    func excludeWindow(id: UInt32) {
        excludedWindowIDs.insert(id)
    }

    /// Remove a window from the exclusion set.
    func removeWindowExclusion(id: UInt32) {
        excludedWindowIDs.remove(id)
    }

    // MARK: - Single Display Capture

    /// Capture the main display as PNG data at 2x (Retina) resolution.
    ///
    /// The app's own stealth overlay is excluded from the capture.
    /// - Returns: PNG-encoded image data of the main display.
    func captureScreen() async throws -> Data {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw mapPermissionError(error)
        }

        guard let mainDisplay = content.displays.first else {
            throw CaptureError.noDisplaysFound
        }

        // Build a filter that excludes SubtleAI's own windows.
        let excludedWindows = content.windows.filter { window in
            excludedWindowIDs.contains(UInt32(window.windowID))
        }

        let filter = SCContentFilter(display: mainDisplay, excludingWindows: excludedWindows)

        return try await captureWithFilter(filter, display: mainDisplay)
    }

    // MARK: - All Displays Capture

    /// Capture all connected displays as PNG data at 2x (Retina) resolution.
    ///
    /// - Returns: An array of PNG-encoded image data, one per display (up to 5).
    func captureAllScreens() async throws -> [Data] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw mapPermissionError(error)
        }

        let displays = content.displays
        guard !displays.isEmpty else {
            throw CaptureError.noDisplaysFound
        }
        guard displays.count <= Self.maxDisplayCount else {
            throw CaptureError.tooManyDisplays
        }

        let excludedWindows = content.windows.filter { window in
            excludedWindowIDs.contains(UInt32(window.windowID))
        }

        var results: [Data] = []
        results.reserveCapacity(displays.count)

        for display in displays {
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let imageData = try await captureWithFilter(filter, display: display)
            results.append(imageData)
        }

        return results
    }

    // MARK: - Internal Capture Logic

    /// Perform the actual capture using a content filter and return PNG data.
    private func captureWithFilter(_ filter: SCContentFilter, display: SCDisplay) async throws -> Data {
        let config = SCStreamConfiguration()

        // 2x resolution for Retina sharpness.
        config.width = Int(display.width) * 2
        config.height = Int(display.height) * 2
        config.scalesToFit = false
        config.showsCursor = false

        // Use pixel format compatible with PNG encoding.
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let cgImage: CGImage
        do {
            if #available(macOS 14.0, *) {
                cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
            } else {
                throw CaptureError.screenCaptureNotAvailable
            }
        } catch let error as CaptureError {
            throw error
        } catch {
            throw mapPermissionError(error)
        }

        return try encodePNG(cgImage)
    }

    /// Encode a CGImage as PNG data.
    private func encodePNG(_ cgImage: CGImage) throws -> Data {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw CaptureError.captureReturnedNoImage
        }
        return pngData
    }

    /// Map ScreenCaptureKit errors to user-friendly CaptureError cases.
    private func mapPermissionError(_ error: Error) -> CaptureError {
        let nsError = error as NSError
        // SCStreamError code 1 is typically a permission denial.
        if nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == 1 {
            return .permissionDenied
        }
        return .unknown(underlying: error)
    }
}
