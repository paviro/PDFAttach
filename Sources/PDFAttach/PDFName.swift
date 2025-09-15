import Foundation

enum PDFName {
    static func encode(_ value: String) -> String {
        var result = ""
        for byte in value.utf8 {
            let isDelimiter = byte == 0x28 /* ( */ || byte == 0x29 /* ) */ || byte == 0x3C /* < */ || byte == 0x3E /* > */ || byte == 0x5B /* [ */ || byte == 0x5D /* ] */ || byte == 0x7B /* { */ || byte == 0x7D /* } */ || byte == 0x2F /* / */ || byte == 0x25 /* % */
            let isWhitespace = byte <= 0x20
            let isHash = byte == 0x23 /* # */
            let isAsciiPrintable = byte >= 0x21 && byte <= 0x7E
            if isAsciiPrintable && !isDelimiter && !isWhitespace && !isHash {
                let scalar = UnicodeScalar(byte)
                result.append(Character(scalar))
            } else {
                result.append(String(format: "#%02X", byte))
            }
        }
        return result
    }

    static func decode(_ name: String) -> String {
        var result = ""
        var i = name.startIndex
        while i < name.endIndex {
            if name[i] == "#", name.index(i, offsetBy: 2, limitedBy: name.endIndex) != nil {
                let h1Index = name.index(after: i)
                let h2Index = name.index(i, offsetBy: 2)
                if h2Index < name.endIndex {
                    let hexStr = String(name[h1Index...h2Index])
                    if let byte = UInt8(hexStr, radix: 16) {
                        result.append(Character(UnicodeScalar(byte)))
                        i = name.index(i, offsetBy: 3)
                        continue
                    }
                }
            }
            result.append(name[i])
            i = name.index(after: i)
        }
        return result
    }
}
