import Foundation

final class PDFContext {
    let data: Data
    private(set) var objects: [PDFRef: PDFObject] = [:]
    private var trailer: [String: PDFObject] = [:]
    var pagesReference: PDFRef? {
        if let obj = trailer["Pages"], case let .reference(num, gen) = obj {
            return PDFRef(number: num, generation: gen)
        }
        return nil
    }
    private var nextObjectNumber: Int = 0
    private var originalStartXref: Int = 0

    init(data: Data) throws {
        self.data = data
        try parseTrailerAndXRef()
        if let sizeObj = trailer["Size"], case let .int(size) = sizeObj {
            nextObjectNumber = size
        }
    }

    private func parseTrailerAndXRef() throws {
        guard let str = String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "PDFContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode PDF data as ISO Latin1"])
        }
        let nsStr = str as NSString
        let regexStart = try NSRegularExpression(pattern: "startxref[\\s\\r\\n]*(\\d+)", options: [])
        let matches = regexStart.matches(in: str, options: [], range: NSRange(location: 0, length: nsStr.length))
        guard let match = matches.last, match.numberOfRanges >= 2 else {
            throw NSError(domain: "PDFContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "startxref not found"])
        }
        let offsetRange = match.range(at: 1)
        guard let offset = Int(nsStr.substring(with: offsetRange)) else {
            throw NSError(domain: "PDFContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid startxref offset"])
        }
        originalStartXref = offset

        let regexSize = try NSRegularExpression(pattern: "/Size[\\s\\r\\n]*(\\d+)", options: [])
        guard let sizeMatch = regexSize.firstMatch(in: str, options: [], range: NSRange(location: 0, length: nsStr.length)),
              sizeMatch.numberOfRanges >= 2,
              let size = Int(nsStr.substring(with: sizeMatch.range(at: 1))) else {
            throw NSError(domain: "PDFContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "Size entry not found"])
        }
        trailer["Size"] = .int(size)

        let regexRoot = try NSRegularExpression(pattern: "/Root[\\s\\r\\n]*(\\d+)[\\s\\r\\n]*(\\d+)[\\s\\r\\n]*R", options: [])
        if let rootMatch = regexRoot.firstMatch(in: str, options: [], range: NSRange(location: 0, length: nsStr.length)),
           rootMatch.numberOfRanges >= 3,
           let num = Int(nsStr.substring(with: rootMatch.range(at: 1))),
           let gen = Int(nsStr.substring(with: rootMatch.range(at: 2))) {
            trailer["Root"] = .reference(number: num, generation: gen)
        }
        let regexPages = try NSRegularExpression(pattern: "/Pages[\\s\\r\\n]*(\\d+)[\\s\\r\\n]*(\\d+)[\\s\\r\\n]*R", options: [])
        if let pagesMatch = regexPages.firstMatch(in: str, options: [], range: NSRange(location: 0, length: nsStr.length)),
           pagesMatch.numberOfRanges >= 3,
           let pagesNum = Int(nsStr.substring(with: pagesMatch.range(at: 1))),
           let pagesGen = Int(nsStr.substring(with: pagesMatch.range(at: 2))) {
            trailer["Pages"] = .reference(number: pagesNum, generation: pagesGen)
        }
    }

    private func serializeString(_ obj: PDFObject) -> String {
        switch obj {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return "\(i)"
        case .real(let r): return "\(r)"
        case .name(let n): return "/\(n)"
        case .string(let str):
            let esc = str.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
            return "(\(esc))"
        case .hexString(let data):
            let hex = data.map { String(format: "%02X", $0) }.joined()
            return "<\(hex)>"
        case .array(let arr):
            let items = arr.map { serializeString($0) }.joined(separator: " ")
            return "[\(items)]"
        case .reference(let num, let gen):
            return "\(num) \(gen) R"
        default:
            return ""
        }
    }

    private func serialize(_ obj: PDFObject) -> Data {
        switch obj {
        case .dictionary(let dict):
            var data = Data("<<".utf8)
            for (k, v) in dict {
                data.append(" /\(k) ".data(using: .ascii)!)
                switch v {
                case .dictionary(_), .stream(_, _):
                    data.append(serialize(v))
                default:
                    let text = serializeString(v)
                    data.append(text.data(using: .ascii)!)
                }
            }
            data.append(" >>\n".data(using: .ascii)!)
            return data
        case .stream(let dict, let d):
            var header = Data("<<".utf8)
            for (k, v) in dict {
                header.append(" /\(k) ".data(using: .ascii)!)
                switch v {
                case .dictionary(_), .stream(_, _):
                    header.append(serialize(v))
                default:
                    let text = serializeString(v)
                    header.append(text.data(using: .ascii)!)
                }
            }
            header.append(" >>\nstream\n".data(using: .ascii)!)
            var block = Data()
            block.append(header)
            block.append(d)
            block.append("\nendstream\n".data(using: .ascii)!)
            return block
        default:
            let s = serializeString(obj) + "\n"
            return s.data(using: .ascii)!
        }
    }

    func nextRef() -> PDFRef {
        nextObjectNumber += 1
        return PDFRef(number: nextObjectNumber, generation: 0)
    }

    @discardableResult
    func registerObject(_ object: PDFObject) -> PDFRef {
        let ref = nextRef()
        objects[ref] = object
        return ref
    }

    func assignObject(_ ref: PDFRef, object: PDFObject) {
        objects[ref] = object
    }

    func save() throws -> Data {
        let originalSize: Int
        if case let .int(size) = trailer["Size"] {
            originalSize = size
        } else {
            throw NSError(domain: "PDFContext", code: 3, userInfo: [NSLocalizedDescriptionKey: "Original Size not available"])
        }
        let newRefs = objects.keys.filter { $0.number > originalSize }.sorted { $0.number < $1.number }
        var output = data
        if let last = output.last, last != 0x0A {
            output.append(0x0A)
        }
        var offsets: [Int: Int] = [:]
        for ref in newRefs {
            offsets[ref.number] = output.count
            let header = "\(ref.number) \(ref.generation) obj\n"
            output.append(header.data(using: .ascii)!)

            if let obj = objects[ref] {
                output.append(serialize(obj))
            }
            output.append("endobj\n".data(using: .ascii)!)
        }
        let xrefOffset = output.count
        var xref = "xref\n\(newRefs.first?.number ?? 0) \(newRefs.count)\n"
        for ref in newRefs {
            let off = offsets[ref.number] ?? 0
            xref += String(format: "%010d %05d n\n", off, ref.generation)
        }
        output.append(xref.data(using: .ascii)!)
        let newSize = originalSize + newRefs.count
        var trailerStr = "trailer\n<< /Size \(newSize) /Prev \(originalStartXref)\n"
        if let root = trailer["Root"] {
            trailerStr += "/Root " + serializeString(root) + "\n"
        }
        trailerStr += ">>\nstartxref\n\(xrefOffset)\n%%EOF"
        output.append(trailerStr.data(using: .ascii)!)
        return output
    }

    func setRootReference(_ ref: PDFRef) {
        trailer["Root"] = .reference(number: ref.number, generation: ref.generation)
    }
}


