import UniformTypeIdentifiers

extension UTType {
    static let srtSubtitle = UTType(filenameExtension: "srt") ?? .plainText
    static let matroskaVideo = UTType(filenameExtension: "mkv") ?? .data
}
