import Foundation

enum TyphoonInstallerError: LocalizedError {
    case missingInstaller
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingInstaller:
            return "应用包中缺少 Typhoon 安装脚本"
        case let .failed(message):
            return "Typhoon 安装失败：\(message)"
        }
    }
}

enum TyphoonInstaller {
    static func install(onStatus: @escaping @Sendable (String) -> Void) async throws {
        guard let scriptURL = Bundle.module.url(
            forResource: "install_typhoon",
            withExtension: "sh",
            subdirectory: "Resources"
        ) else {
            throw TyphoonInstallerError.missingInstaller
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collector = OutputCollector(onStatus: onStatus)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            collector.consume(handle.availableData)
        }

        try process.run()
        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            }
        } onCancel: {
            process.terminate()
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        collector.consume(pipe.fileHandleForReading.readDataToEndOfFile())
        try Task.checkCancellation()
        guard status == 0, TyphoonTranscriber.isInstalled else {
            throw TyphoonInstallerError.failed(collector.tail)
        }
    }

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var recentLines: [String] = []
        private let onStatus: @Sendable (String) -> Void

        init(onStatus: @escaping @Sendable (String) -> Void) {
            self.onStatus = onStatus
        }

        var tail: String {
            lock.withLock { recentLines.suffix(8).joined(separator: "\n") }
        }

        func consume(_ data: Data) {
            guard !data.isEmpty else { return }
            let statuses: [String] = lock.withLock {
                buffer.append(data)
                var found: [String] = []
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    guard let line = String(data: lineData, encoding: .utf8) else { continue }
                    recentLines.append(line)
                    if recentLines.count > 30 { recentLines.removeFirst(recentLines.count - 30) }
                    if line.hasPrefix("STATUS ") { found.append(String(line.dropFirst(7))) }
                }
                return found
            }
            statuses.forEach(onStatus)
        }
    }
}
