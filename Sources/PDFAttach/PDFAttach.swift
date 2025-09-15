import Foundation
import CoreGraphics

public enum PDFAttachError: Error {
    case generic(String)
    case invalidPDF
    case missingPagesReference
    case missingCatalog
}

public final class PDFAttach {
    public static func addAttachment(
        to pdfData: Data,
        fileName: String,
        fileData: Data,
        mimeType: String
    ) throws -> Data {
        let context = try PDFContext(data: pdfData)
        guard let pagesRef = context.pagesReference else {
            throw PDFAttachError.missingPagesReference
        }

        let options = EmbeddedFileOptions(mimeType: mimeType, description: nil, creationDate: nil, modificationDate: nil, afRelationship: nil)
        let embedder = FileEmbedder(fileData: fileData, fileName: fileName, options: options)

        let fileSpecRef = context.nextRef()
        _ = try embedder.embed(into: context, ref: fileSpecRef)

        let nameArray = PDFObject.array([.string(fileName), .reference(number: fileSpecRef.number, generation: fileSpecRef.generation)])
        let embeddedFilesTree = PDFObject.dictionary(["Names": nameArray])
        let namesTree = PDFObject.dictionary(["EmbeddedFiles": embeddedFilesTree])
        let afArray = PDFObject.array([.reference(number: fileSpecRef.number, generation: fileSpecRef.generation)])

        let catalogDict: [String: PDFObject] = [
            "Type": .name("Catalog"),
            "Pages": .reference(number: pagesRef.number, generation: pagesRef.generation),
            "Names": namesTree,
            "AF": afArray
        ]
        let newCatalogRef = context.registerObject(.dictionary(catalogDict))
        context.setRootReference(newCatalogRef)

        return try context.save()
    }

    public static func extractAttachments(from pdfData: Data, named fileName: String? = nil) throws -> [(String, Data)] {
        guard let provider = CGDataProvider(data: pdfData as CFData) else { throw PDFAttachError.invalidPDF }
        guard let pdf = CGPDFDocument(provider) else { throw PDFAttachError.invalidPDF }
        guard let catalog = pdf.catalog else { throw PDFAttachError.missingCatalog }
        var namesDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &namesDict), let namesDict = namesDict else { return [] }
        var efDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(namesDict, "EmbeddedFiles", &efDict), let efDict = efDict else { return [] }
        var namesArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(efDict, "Names", &namesArray), let namesArray = namesArray else { return [] }
        let count = CGPDFArrayGetCount(namesArray)
        var results: [(String, Data)] = []
        var i = 0
        while i + 1 < count {
            var nameObj: CGPDFObjectRef?
            var fileSpecObj: CGPDFObjectRef?
            guard CGPDFArrayGetObject(namesArray, i, &nameObj),
                  CGPDFArrayGetObject(namesArray, i+1, &fileSpecObj),
                  let nameObj = nameObj,
                  let fileSpecObj = fileSpecObj else { i += 2; continue }
            var cfName: CGPDFStringRef?
            if CGPDFObjectGetValue(nameObj, .string, &cfName), let cfName = cfName,
               let embeddedFileName = CGPDFStringCopyTextString(cfName) as String? {
                var fileSpecDict: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(fileSpecObj, .dictionary, &fileSpecDict), let fileSpecDict = fileSpecDict {
                    var efSub: CGPDFDictionaryRef?
                    if CGPDFDictionaryGetDictionary(fileSpecDict, "EF", &efSub), let efSub = efSub {
                        var stream: CGPDFStreamRef?
                        if CGPDFDictionaryGetStream(efSub, "F", &stream), let stream = stream {
                            var format = CGPDFDataFormat.raw
                            if let cfData = CGPDFStreamCopyData(stream, &format) {
                                let data = cfData as Data
                                if let fileName = fileName {
                                    if embeddedFileName == fileName {
                                        return [(embeddedFileName, data)]
                                    }
                                } else {
                                    results.append((embeddedFileName, data))
                                }
                            }
                        }
                    }
                }
            }
            i += 2
        }
        return results
    }
}


