import Foundation
import SubtitleForgeCore

enum TyphoonTranscriberError: LocalizedError {
    case notInstalled
    case conversionFailed(String)
    case bridgeFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Typhoon ASR 尚未安装 请先在终端运行应用目录下的 install_typhoon.sh 或联系开发者"
        case let .conversionFailed(reason):
            return "音频转换失败：\(reason)"
        case let .bridgeFailed(reason):
            return "Typhoon 识别失败：\(reason)"
        case .emptyResult:
            return "Typhoon 没有识别到任何语音"
        }
    }
}

/// Thai-specialized transcription via SCB10X Typhoon ASR (FastConformer-Transducer),
/// running in a local Python venv as a subprocess. The bridge script does energy-VAD
/// chunking so subtitle timestamps are real speech boundaries — the pip package's own
/// `with_timestamps` only fabricates evenly-spaced word times.
struct TyphoonTranscriber: SubtitleTranscriber {
    static var venvPython: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SUDA字幕翻译助手/typhoon/venv/bin/python3")
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
    }

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> [TranscribedSegment] {
        guard Self.isInstalled else { throw TyphoonTranscriberError.notInstalled }

        onProgress(.preparingModel)

        // Typhoon's Python stack reads WAV reliably; convert via the system's afconvert.
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typhoon-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        try await Self.convertToWav16k(input: audioURL, output: wavURL)
        try Task.checkCancellation()

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typhoon-bridge-\(UUID().uuidString).py")
        try Self.bridgeScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let output = try await Self.runBridge(
            python: Self.venvPython,
            script: scriptURL,
            audio: wavURL,
            onProgress: onProgress
        )

        struct BridgeResult: Decodable {
            struct Segment: Decodable {
                let start: Double
                let end: Double
                let text: String
            }

            let segments: [Segment]
        }

        guard let jsonLine = output
            .components(separatedBy: .newlines)
            .last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }),
            let result = try? JSONDecoder().decode(BridgeResult.self, from: Data(jsonLine.utf8))
        else {
            throw TyphoonTranscriberError.bridgeFailed(String(output.suffix(300)))
        }
        guard !result.segments.isEmpty else { throw TyphoonTranscriberError.emptyResult }

        return result.segments.map {
            TranscribedSegment(start: $0.start, end: $0.end, text: $0.text)
        }
    }

    private static func convertToWav16k(input: URL, output: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", input.path, output.path]
        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TyphoonTranscriberError.conversionFailed(String(message.suffix(200)))
        }
    }

    private static func runBridge(
        python: URL,
        script: URL,
        audio: URL,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> String {
        let process = Process()
        process.executableURL = python
        process.arguments = [script.path, audio.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PYTHONUNBUFFERED": "1", "TOKENIZERS_PARALLELISM": "false"]
        ) { _, new in new }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Drain stdout continuously: reading only after termination deadlocks once
        // the JSON exceeds the ~64KB pipe buffer (long episodes easily do).
        let stdoutCollector = DataCollector()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutCollector.append(data)
            }
        }

        // Stream stderr for PROGRESS lines, buffering partial lines across reads.
        let stderrLines = LineBuffer()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for line in stderrLines.consumeLines(appending: data) {
                if line.hasPrefix("PROGRESS "), let fraction = Double(line.dropFirst(9)) {
                    onProgress(.transcribing(fraction: min(0.999, fraction)))
                }
            }
        }

        try process.run()

        let status: Int32 = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { proc in
                    continuation.resume(returning: proc.terminationStatus)
                }
            }
        } onCancel: {
            process.terminate()
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        stdoutCollector.append(outPipe.fileHandleForReading.readDataToEndOfFile())
        let output = String(data: stdoutCollector.snapshot(), encoding: .utf8) ?? ""

        try Task.checkCancellation()
        guard status == 0 else {
            throw TyphoonTranscriberError.bridgeFailed(String(output.suffix(300)))
        }
        return output
    }

    /// Thread-safe byte accumulator for pipe readability handlers.
    private final class DataCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    /// Accumulates pipe chunks and yields only complete lines, holding partial
    /// tail bytes (including split UTF-8 sequences) until the next read.
    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func consumeLines(appending chunk: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(chunk)
            var lines: [String] = []
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                if let line = String(data: lineData, encoding: .utf8) {
                    lines.append(line)
                }
            }
            return lines
        }
    }

    /// Python bridge: energy-VAD chunking + batched NeMo transcription → JSON segments.
    static let bridgeScript = #"""
    import json, os, sys, tempfile, warnings, logging

    warnings.filterwarnings("ignore")
    logging.disable(logging.WARNING)
    os.environ.setdefault("NEMO_LOGGING_LEVEL", "ERROR")

    import numpy as np
    import librosa
    import soundfile as sf
    import nemo.collections.asr as nemo_asr

    SR = 16000
    MAX_LEN = 6.0      # seconds per subtitle cue cap
    SPLIT_GAP = 0.45   # any silence longer than this starts a new cue
    MIN_LEN = 0.25     # drop blips shorter than this
    PAD = 0.12         # context padding around each chunk

    def hyp_text(h):
        return h.text if hasattr(h, "text") else str(h)

    def main():
        audio_path = sys.argv[1]
        model_name = sys.argv[2] if len(sys.argv) > 2 else "scb10x/typhoon-asr-realtime"

        print("PHASE loading", file=sys.stderr, flush=True)
        model = nemo_asr.models.ASRModel.from_pretrained(model_name=model_name, map_location="cpu")

        y, _ = librosa.load(audio_path, sr=SR, mono=True)
        duration = len(y) / SR

        intervals = librosa.effects.split(y, top_db=35, frame_length=2048, hop_length=512)

        # Prefer breaking cues at real silences: only bridge tiny gaps, and never
        # let a cue grow past MAX_LEN even mid-speech (hard split as last resort).
        chunks = []
        for s_i, e_i in intervals:
            s, e = s_i / SR, e_i / SR
            if chunks and s - chunks[-1][1] < SPLIT_GAP and e - chunks[-1][0] <= MAX_LEN:
                chunks[-1][1] = e
            else:
                chunks.append([s, e])

        final = []
        for s, e in chunks:
            while e - s > MAX_LEN:
                final.append([s, s + MAX_LEN])
                s += MAX_LEN
            if e - s >= MIN_LEN:
                final.append([s, e])

        if not final:
            print(json.dumps({"segments": []}, ensure_ascii=False))
            return

        tmpdir = tempfile.mkdtemp()
        paths = []
        for i, (s, e) in enumerate(final):
            s2, e2 = max(0, s - PAD), min(duration, e + PAD)
            seg = y[int(s2 * SR):int(e2 * SR)]
            peak = float(np.max(np.abs(seg))) + 1e-8
            path = os.path.join(tmpdir, f"c{i}.wav")
            sf.write(path, seg / peak, SR)
            paths.append(path)

        print(f"PHASE transcribing {len(paths)}", file=sys.stderr, flush=True)
        texts = [""] * len(paths)
        BATCH = 8
        for i in range(0, len(paths), BATCH):
            batch = paths[i:i + BATCH]
            out = model.transcribe(audio=batch, batch_size=len(batch), verbose=False)
            for j, hyp in enumerate(out):
                texts[i + j] = (hyp_text(hyp) or "").strip()
            print(f"PROGRESS {min(1.0, (i + len(batch)) / len(paths)):.3f}", file=sys.stderr, flush=True)

        segments = [
            {"start": round(s, 3), "end": round(e, 3), "text": t}
            for (s, e), t in zip(final, texts) if t
        ]
        print(json.dumps({"segments": segments}, ensure_ascii=False))

    if __name__ == "__main__":
        main()
    """#
}
