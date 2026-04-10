import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine

/// Manages microphone recording and system audio capture for transcription.
///
/// Two independent modes:
/// - **Mic recording**: Uses `AVAudioEngine` to capture the default input device.
///   Returns raw audio data (16 kHz mono PCM) when stopped.
/// - **System audio capture**: Uses ScreenCaptureKit's `SCStream` to capture
///   system-wide audio output. Delivers audio buffers via a callback for real-time
///   streaming to a transcription service.
@MainActor
final class AudioService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isRecordingMic: Bool = false
    @Published private(set) var isCapturingSystemAudio: Bool = false
    @Published private(set) var micAudioLevel: Float = 0.0

    // MARK: - Mic Recording State

    private var audioEngine: AVAudioEngine?
    private var micBuffer: Data = Data()
    private let targetSampleRate: Double = 16_000
    private let targetChannelCount: AVAudioChannelCount = 1

    // MARK: - System Audio Capture State

    private var systemStream: SCStream?
    private var systemStreamOutput: SystemAudioStreamOutput?
    private var audioBufferCallback: ((Data) -> Void)?

    // MARK: - Errors

    enum AudioError: LocalizedError {
        case micNotAvailable
        case engineStartFailed(underlying: Error)
        case noInputNode
        case noAudioDataRecorded
        case systemAudioNotAvailable
        case conversionFailed
        case alreadyRecording
        case notRecording

        var errorDescription: String? {
            switch self {
            case .micNotAvailable:
                return "No microphone input is available."
            case .engineStartFailed(let err):
                return "Failed to start audio engine: \(err.localizedDescription)"
            case .noInputNode:
                return "No audio input node available on this device."
            case .noAudioDataRecorded:
                return "No audio data was recorded."
            case .systemAudioNotAvailable:
                return "System audio capture is not available."
            case .conversionFailed:
                return "Failed to convert audio to the required format."
            case .alreadyRecording:
                return "A recording session is already in progress."
            case .notRecording:
                return "No recording session is active."
            }
        }
    }

    // MARK: - Mic Recording

    /// Start recording from the default microphone.
    ///
    /// Audio is captured at 16 kHz mono PCM, suitable for transcription APIs.
    /// Call `stopMicRecording()` to retrieve the recorded data.
    func startMicRecording() throws {
        guard !isRecordingMic else { throw AudioError.alreadyRecording }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Verify that an input device is available.
        guard inputNode.inputFormat(forBus: 0).sampleRate > 0 else {
            throw AudioError.micNotAvailable
        }

        micBuffer = Data()

        // Target format: 16 kHz, mono, 16-bit signed integer PCM.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: true
        ) else {
            throw AudioError.conversionFailed
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // If the hardware format differs from our target, we need a converter.
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != targetChannelCount {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Compute audio level for the UI meter.
            let level = Self.computeAudioLevel(buffer: buffer)
            Task { @MainActor in
                self.micAudioLevel = level
            }

            // Convert to target format if needed, then append raw bytes.
            let pcmData: Data
            if let converter {
                pcmData = Self.convertBuffer(buffer, using: converter, targetFormat: targetFormat)
            } else {
                pcmData = Self.extractPCMData(from: buffer)
            }

            Task { @MainActor in
                self.micBuffer.append(pcmData)
            }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioError.engineStartFailed(underlying: error)
        }

        self.audioEngine = engine
        isRecordingMic = true
    }

    /// Stop the current mic recording and return the captured audio data.
    ///
    /// - Returns: Raw 16 kHz mono 16-bit PCM audio data.
    func stopMicRecording() throws -> Data {
        guard isRecordingMic, let engine = audioEngine else {
            throw AudioError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.audioEngine = nil
        isRecordingMic = false
        micAudioLevel = 0.0

        let data = micBuffer
        micBuffer = Data()

        guard !data.isEmpty else {
            throw AudioError.noAudioDataRecorded
        }

        return data
    }

    // MARK: - System Audio Capture

    /// Start capturing system-wide audio output.
    ///
    /// Uses ScreenCaptureKit to capture all system audio. Each audio buffer
    /// is delivered to the `onAudioBuffer` closure as 16 kHz mono PCM data,
    /// suitable for streaming to a transcription service.
    ///
    /// - Parameter onAudioBuffer: Closure called on each audio buffer delivery.
    func startSystemAudioCapture(onAudioBuffer: @escaping (Data) -> Void) async throws {
        guard !isCapturingSystemAudio else { throw AudioError.alreadyRecording }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw AudioError.systemAudioNotAvailable
        }

        guard let display = content.displays.first else {
            throw AudioError.systemAudioNotAvailable
        }

        // Create an audio-only stream configuration.
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = Int(targetChannelCount)

        // We only want audio — minimize video overhead.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 FPS minimum

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = SystemAudioStreamOutput(onAudioBuffer: onAudioBuffer)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        do {
            try await stream.startCapture()
        } catch {
            throw AudioError.systemAudioNotAvailable
        }

        self.systemStream = stream
        self.systemStreamOutput = output
        self.audioBufferCallback = onAudioBuffer
        isCapturingSystemAudio = true
    }

    /// Stop the current system audio capture session.
    func stopSystemAudioCapture() async {
        guard isCapturingSystemAudio, let stream = systemStream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            #if DEBUG
            print("[AudioService] Error stopping system audio capture: \(error.localizedDescription)")
            #endif
        }

        systemStream = nil
        systemStreamOutput = nil
        audioBufferCallback = nil
        isCapturingSystemAudio = false
    }

    // MARK: - Audio Level Computation

    /// Compute a normalized 0..1 audio level from a PCM buffer.
    private static func computeAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return 0.0 }

        var sum: Float = 0.0
        for frame in 0..<frameLength {
            let sample = channelData[0][frame]
            sum += sample * sample
        }

        let rms = sqrtf(sum / Float(frameLength))

        // Convert to a 0..1 range using a simple dB mapping.
        // RMS of 0.0 -> 0.0, RMS of ~0.5 -> ~1.0
        let level = min(1.0, max(0.0, rms * 2.0))
        return level
    }

    // MARK: - PCM Conversion Helpers

    /// Convert an audio buffer to the target format using an AVAudioConverter.
    private static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> Data {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return Data()
        }

        var inputConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error else {
            return Data()
        }

        return extractPCMData(from: outputBuffer)
    }

    /// Extract raw PCM bytes from a PCM buffer.
    private static func extractPCMData(from buffer: AVAudioPCMBuffer) -> Data {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return Data() }

        if let int16Data = buffer.int16ChannelData {
            let byteCount = frameLength * MemoryLayout<Int16>.size
            return Data(bytes: int16Data[0], count: byteCount)
        }

        if let floatData = buffer.floatChannelData {
            // Convert float samples to Int16.
            var result = Data(count: frameLength * MemoryLayout<Int16>.size)
            result.withUnsafeMutableBytes { rawBuffer in
                guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<frameLength {
                    let sample = max(-1.0, min(1.0, floatData[0][i]))
                    int16Ptr[i] = Int16(sample * Float(Int16.max))
                }
            }
            return result
        }

        return Data()
    }
}

// MARK: - SCStream Audio Output Handler

/// Receives audio sample buffers from ScreenCaptureKit's system audio stream
/// and forwards the raw PCM data to a callback.
private final class SystemAudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {

    private let onAudioBuffer: (Data) -> Void

    init(onAudioBuffer: @escaping (Data) -> Void) {
        self.onAudioBuffer = onAudioBuffer
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Extract audio data from the CMSampleBuffer.
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr)
        }

        onAudioBuffer(data)
    }
}
