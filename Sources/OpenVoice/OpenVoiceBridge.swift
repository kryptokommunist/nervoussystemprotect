import Foundation
import AVFoundation
import Darwin

/// High-performance Swift bridge to the OpenVoice V2 Tone Color Converter engine.
/// Supports both file-based conversion and low-latency chunk streaming via Unix domain socket daemon.
public final class OpenVoiceBridge: @unchecked Sendable {
    public static let shared = OpenVoiceBridge()

    public let modelsDirectory: URL
    public let pythonExecutable: URL
    public let runnerScript: URL
    public let daemonScript: URL
    public let socketPath: String = "/tmp/openvoice.sock"
    public let modelSampleRate: Double = 22050.0

    private var daemonProcess: Process?
    private let daemonLock = NSLock()
    private let socketQueue = DispatchQueue(label: "com.openvoice.socket.queue", qos: .userInteractive)
    private var cachedSocketFD: Int32 = -1

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("OpenVoiceModels")
        self.pythonExecutable = URL(fileURLWithPath: "/opt/homebrew/bin/python3.11")

        let resourceDir = Bundle.main.resourceURL
        let inBundleRunner = resourceDir?.appendingPathComponent("scripts/run_openvoice.py")
        let inBundleDaemon = resourceDir?.appendingPathComponent("scripts/openvoice_daemon.py")

        let projectRoot = URL(fileURLWithPath: "/Users/I771869/Documents/Code/meetingagency")
        let scriptCandidate = projectRoot.appendingPathComponent("scripts/run_openvoice.py")
        let daemonCandidate = projectRoot.appendingPathComponent("scripts/openvoice_daemon.py")

        if let inBundle = inBundleRunner, FileManager.default.fileExists(atPath: inBundle.path) {
            self.runnerScript = inBundle
        } else if FileManager.default.fileExists(atPath: scriptCandidate.path) {
            self.runnerScript = scriptCandidate
        } else {
            self.runnerScript = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("scripts/run_openvoice.py")
        }

        if let inBundle = inBundleDaemon, FileManager.default.fileExists(atPath: inBundle.path) {
            self.daemonScript = inBundle
        } else if FileManager.default.fileExists(atPath: daemonCandidate.path) {
            self.daemonScript = daemonCandidate
        } else {
            self.daemonScript = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("scripts/openvoice_daemon.py")
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

    // MARK: - Daemon Lifecycle & Socket Connection

    public func startDaemonIfNeeded() {
        daemonLock.lock()
        defer { daemonLock.unlock() }

        if isSocketResponsive() { return }

        // If daemon process is already running, wait up to 15s for it to become responsive
        if let proc = daemonProcess, proc.isRunning {
            let deadline = Date().addingTimeInterval(15.0)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
                if isSocketResponsive() { return }
            }
        }

        // Clean up stale socket file if any
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        let proc = Process()
        proc.executableURL = pythonExecutable
        proc.arguments = [daemonScript.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            self.daemonProcess = proc

            // Wait up to 15 seconds for daemon to load weights, pre-warm MPS shaders, and listen on socket
            let deadline = Date().addingTimeInterval(15.0)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
                if isSocketResponsive() { break }
            }
        } catch {
            print("❌ Failed to spawn OpenVoice daemon: \(error)")
        }
    }

    private func isSocketResponsive() -> Bool {
        if cachedSocketFD >= 0 {
            var error: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(cachedSocketFD, SOL_SOCKET, SO_ERROR, &error, &len) == 0 && error == 0 {
                return true
            }
        }
        guard let fd = connectSocket(retries: 1) else { return false }
        defer { close(fd) }

        let msg = "PING\n"
        _ = msg.withCString { send(fd, $0, msg.utf8.count, 0) }

        var buffer = [CChar](repeating: 0, count: 64)
        let bytesRead = recv(fd, &buffer, 63, 0)
        guard bytesRead > 0 else { return false }
        let resp = String(cString: buffer)
        return resp.hasPrefix("PONG")
    }

    private func connectSocket(retries: Int = 3) -> Int32? {
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }

        for attempt in 0...retries {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                if attempt < retries { Thread.sleep(forTimeInterval: 0.01); continue }
                return nil
            }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let charPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                _ = socketPath.withCString { strncpy(charPtr, $0, 100) }
            }

            let res = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            if res == 0 {
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                return fd
            } else {
                close(fd)
                if attempt < retries {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
        }
        return nil
    }

    /// Retrieve or create a persistent socket file descriptor (called on socketQueue)
    private func getPersistentSocket() -> Int32? {
        if cachedSocketFD >= 0 {
            var error: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(cachedSocketFD, SOL_SOCKET, SO_ERROR, &error, &len) == 0 && error == 0 {
                return cachedSocketFD
            }
            close(cachedSocketFD)
            cachedSocketFD = -1
        }
        if let fd = connectSocket() {
            cachedSocketFD = fd
            return fd
        }
        return nil
    }

    private func invalidateCachedSocket() {
        if cachedSocketFD >= 0 {
            close(cachedSocketFD)
            cachedSocketFD = -1
        }
    }

    private func readLine(from fd: Int32) -> String {
        var line = ""
        var charBuf: UInt8 = 0
        while true {
            let n = recv(fd, &charBuf, 1, 0)
            if n <= 0 { break }
            if charBuf == UInt8(ascii: "\n") { break }
            line.append(Character(UnicodeScalar(charBuf)))
        }
        return line
    }

    // MARK: - Target Speaker & Settings

    public func setTargetVoice(path: String) async {
        startDaemonIfNeeded()
        await withCheckedContinuation { continuation in
            socketQueue.async {
                guard let fd = self.getPersistentSocket() else {
                    continuation.resume()
                    return
                }

                let cmd = "SET_TARGET \(path)\n"
                let sent = cmd.withCString { send(fd, $0, cmd.utf8.count, 0) }
                if sent <= 0 {
                    self.invalidateCachedSocket()
                    continuation.resume()
                    return
                }
                _ = self.readLine(from: fd)
                continuation.resume()
            }
        }
    }

    public func setTau(tau: Float) async {
        startDaemonIfNeeded()
        await withCheckedContinuation { continuation in
            socketQueue.async {
                guard let fd = self.getPersistentSocket() else {
                    continuation.resume()
                    return
                }

                let cmd = "SET_TAU \(String(format: "%.3f", tau))\n"
                let sent = cmd.withCString { send(fd, $0, cmd.utf8.count, 0) }
                if sent <= 0 {
                    self.invalidateCachedSocket()
                    continuation.resume()
                    return
                }
                _ = self.readLine(from: fd)
                continuation.resume()
            }
        }
    }

    public func resetContext() async {
        await withCheckedContinuation { continuation in
            socketQueue.async {
                if let fd = self.getPersistentSocket() {
                    let cmd = "RESET_CONTEXT\n"
                    _ = cmd.withCString { send(fd, $0, cmd.utf8.count, 0) }
                    _ = self.readLine(from: fd)
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Low-Latency Real-Time Streaming Conversion

    public func convertChunk(samples: [Float], tau: Float = 0.3) async throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        startDaemonIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            socketQueue.async {
                guard let fd = self.getPersistentSocket() else {
                    continuation.resume(returning: samples)
                    return
                }

                let byteCount = samples.count * MemoryLayout<Float>.size
                let cmd = "CONVERT_CHUNK \(byteCount) \(String(format: "%.3f", tau))\n"

                // 1. Send command
                let sent = cmd.withCString { send(fd, $0, cmd.utf8.count, 0) }
                if sent <= 0 {
                    self.invalidateCachedSocket()
                    continuation.resume(returning: samples)
                    return
                }

                // 2. Send raw float bytes
                var sendErr = false
                samples.withUnsafeBytes { rawPtr in
                    guard let base = rawPtr.baseAddress else { return }
                    if send(fd, base, byteCount, 0) <= 0 {
                        sendErr = true
                    }
                }
                if sendErr {
                    self.invalidateCachedSocket()
                    continuation.resume(returning: samples)
                    return
                }

                // 3. Read response header "CHUNK <num_bytes>\n"
                var headerStr = ""
                var charBuf: UInt8 = 0
                while true {
                    let n = recv(fd, &charBuf, 1, 0)
                    if n <= 0 { break }
                    if charBuf == UInt8(ascii: "\n") { break }
                    headerStr.append(Character(UnicodeScalar(charBuf)))
                }

                guard headerStr.hasPrefix("CHUNK "),
                      let outBytesCount = Int(headerStr.replacingOccurrences(of: "CHUNK ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)),
                      outBytesCount > 0 else {
                    self.invalidateCachedSocket()
                    continuation.resume(returning: samples)
                    return
                }

                // 4. Read raw converted audio bytes
                var resultData = Data(count: outBytesCount)
                var totalReceived = 0
                var readErr = false
                resultData.withUnsafeMutableBytes { (bufPtr: UnsafeMutableRawBufferPointer) in
                    guard let basePtr = bufPtr.baseAddress else { return }
                    while totalReceived < outBytesCount {
                        let chunk = recv(fd, basePtr.advanced(by: totalReceived), outBytesCount - totalReceived, 0)
                        if chunk <= 0 {
                            readErr = true
                            break
                        }
                        totalReceived += chunk
                    }
                }

                if readErr || totalReceived < outBytesCount {
                    self.invalidateCachedSocket()
                    continuation.resume(returning: samples)
                    return
                }

                let outFloatCount = outBytesCount / MemoryLayout<Float>.size
                let res = resultData.withUnsafeBytes { rawPtr in
                    let floatPtr = rawPtr.bindMemory(to: Float.self)
                    return Array(floatPtr.prefix(outFloatCount))
                }
                continuation.resume(returning: res)
            }
        }
    }

    // MARK: - File-Based Conversion

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

        startDaemonIfNeeded()

        let daemonConverted: Bool = await withCheckedContinuation { continuation in
            socketQueue.async {
                if let fd = self.connectSocket() {
                    defer { close(fd) }

                    // Set temperature tau
                    let tauCmd = "SET_TAU \(String(format: "%.3f", tau))\n"
                    _ = tauCmd.withCString { send(fd, $0, tauCmd.utf8.count, 0) }
                    var tauBuf = [CChar](repeating: 0, count: 32)
                    _ = recv(fd, &tauBuf, 31, 0)

                    let refPath = referenceURL?.path ?? ""
                    let cmd = "CONVERT_FILE \(inputURL.path) \(outputURL.path)\(refPath.isEmpty ? "" : " " + refPath)\n"
                    _ = cmd.withCString { send(fd, $0, cmd.utf8.count, 0) }

                    var buffer = [CChar](repeating: 0, count: 128)
                    let bytesRead = recv(fd, &buffer, 127, 0)
                    if bytesRead > 0 {
                        let resp = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                        if resp.hasPrefix("OK") {
                            continuation.resume(returning: true)
                            return
                        }
                    }
                }
                continuation.resume(returning: false)
            }
        }

        if daemonConverted {
            return
        }

        // Fallback to direct process run
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

    public func stopDaemon() {
        daemonLock.lock()
        defer { daemonLock.unlock() }

        socketQueue.sync {
            self.invalidateCachedSocket()
        }

        if let fd = connectSocket() {
            let msg = "QUIT\n"
            _ = msg.withCString { send(fd, $0, msg.utf8.count, 0) }
            close(fd)
        }

        daemonProcess?.terminate()
        daemonProcess = nil
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    deinit {
        stopDaemon()
    }
}
