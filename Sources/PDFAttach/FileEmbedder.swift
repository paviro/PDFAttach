import Foundation

final class FileEmbedder {
    let fileData: Data
    let fileName: String
    let options: EmbeddedFileOptions

    // PDF Name escaping: encode delimiter, whitespace, '#' and non-ASCII bytes as #xx
    private func encodeAsPDFName(_ value: String) -> String {
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

    init(fileData: Data, fileName: String, options: EmbeddedFileOptions = EmbeddedFileOptions()) {
        self.fileData = fileData
        self.fileName = fileName
        self.options = options
    }

    func embed(into context: PDFContext, ref: PDFRef) throws -> PDFRef {
        let hexString = fileData.map { String(format: "%02X", $0) }.joined()
        let asciiHex = hexString + ">"
        guard let streamData = asciiHex.data(using: .ascii) else {
            throw NSError(domain: "FileEmbedder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode hex stream"])
        }
        let normalizedMime = (options.mimeType?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        ) ?? "application/octet-stream"
        let subtypeName = encodeAsPDFName(normalizedMime)
        var streamDict: [String: PDFObject] = [
            "Type": .name("EmbeddedFile"),
            "Subtype": .name(subtypeName),
            "Filter": .name("ASCIIHexDecode"),
            "Length": .int(streamData.count)
        ]
        var params: [String: PDFObject] = ["Size": .int(fileData.count)]
        if let cd = options.creationDate {
            params["CreationDate"] = .string(cd.description)
        }
        if let md = options.modificationDate {
            params["ModDate"] = .string(md.description)
        }
        streamDict["Params"] = .dictionary(params)
        let streamObj = PDFObject.stream(dict: streamDict, data: streamData)
        let streamRef = context.registerObject(streamObj)
        var fsDict: [String: PDFObject] = [
            "Type": .name("Filespec"),
            "F": .string(fileName),
            "UF": .hexString(Data(fileName.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] })),
            "EF": .dictionary(["F": .reference(number: streamRef.number, generation: streamRef.generation)])
        ]
        if let desc = options.description {
            fsDict["Desc"] = .string(desc)
        }
        if let af = options.afRelationship {
            fsDict["AFRelationship"] = .name(af)
        }
        let fsObj = PDFObject.dictionary(fsDict)
        context.assignObject(ref, object: fsObj)
        return ref
    }
}


