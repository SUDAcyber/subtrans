import Foundation
import CoreFoundation

public enum TextFileDecoderError: Error, LocalizedError {
    case unsupportedEncoding

    public var errorDescription: String? {
        "无法识别字幕文件编码，请转换为 UTF-8 后重试"
    }
}

public enum TextFileDecoder {
    public static func decode(_ data: Data) throws -> String {
        for encoding in candidateEncodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw TextFileDecoderError.unsupportedEncoding
    }

    private static var candidateEncodings: [String.Encoding] {
        [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            gb18030,
            .isoLatin1,
            .windowsCP1252
        ]
    }

    private static var gb18030: String.Encoding {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
