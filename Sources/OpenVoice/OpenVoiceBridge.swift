import Foundation
import AVFoundation

/// Swift bridge to the OpenVoice V2 Tone Color Converter engine.
public final class OpenVoiceBridge: @unchecked Sendable {
    public static let shared = OpenVoiceBridge()

    public let modelsDirectory: URL
    public let pythonExecutable: URL
    public let runnerScript: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("OpenVoiceModels")
        self.pythonExecutable = URL(fileURLWithPath: "/opt/homebrew/bin/python3.11")
        
        let bundlePath = Bundle.main.bundleURL
        let scriptCandidate = bundlePath.deletingLastPathComponent().appendingPathComponent("scripts/run_openvoice.py")
        if FileManager.default.fileExists(atPath: scriptCandidate.path) {
            self.runnerScript = scriptCandidate
        } else {
            self.runnerScript = URL(fileURLWithPath: "/Users/I771869/Documents/Code/meetingagency/scripts/run_openvoice.py")
        }
    }

    /// Check if OpenVoice models and python environment are ready
    public var isAvailable: Bool {
        let configPath = modelsDirectory.appendingPathComponent("config.json").path
        let ckptPath = modelsDirectory.appendingPathComponent("checkpoint.pth").path
        return FileManager.default.fileExists(atPath: pythonExecutable.path) &&
               FileManager.default.fileExists(atPath: configPath) &&
               FileManager.default.fileExists(atPath: ckptPath) &&
               FileManager.default.fileExists(atPath: runnerScript.path)
    }

    /// Perform full audio file conversion using OpenVoice V2
    public func convert(
        inputURL: URL,
        outputURL: URL,
        referenceURL: URL? = nil,
        tau: Float = 0.3
    ) async throws {
        guard isAvailable else {
            throw NSError(domain: "OpenVoiceBridge", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "OpenVoice models or Python 3.11 environment not available"
            ])
        }

        let refPath = referenceURL?.path ?? ""
        var arguments = [runnerScript.path, "--input", inputURL.path, "--output", outputURL.path, "--tau", String(format: "%.2f", tau)]
        if !refPath.isEmpty {
            arguments += ["--reference", refPath]
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = self.pythonExecutable
                proc.arguments = arguments
                
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe

                do {
                    try proc.run()
                    proc.waitUntilExit()

                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: NSError(domain: "OpenVoiceBridge", code: Int(proc.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: "OpenVoice conversion failed: \(errMsg)"
                        ]))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
