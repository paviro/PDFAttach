import Testing
import Foundation
import CoreGraphics
@testable import PDFAttach

@Test func attachAndExtractJson_roundTrip() throws {
    // 1) Create a minimal, valid single-page PDF in-memory using CoreGraphics
    let pdfData = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
        #expect(Bool(false), "Failed to create CGDataConsumer")
        return
    }
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        #expect(Bool(false), "Failed to create CGContext for PDF")
        return
    }
    ctx.beginPDFPage(nil)
    ctx.setFillColor(CGColor(gray: 0.95, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    ctx.endPDFPage()
    ctx.closePDF()

    let originalPDF = pdfData as Data

    // 2) Attach JSON data to the PDF using the library
    let fileName = "data.json"
    let jsonObject: [String: Any] = [
        "name": "Alice",
        "age": 30,
        "isMember": true,
        "tags": ["swift", "pdf", "test"],
        "meta": ["created": "2024-01-01", "score": 9.5]
    ]
    let json = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])

    let attachedPDF = try PDFAttach.addAttachment(
        to: originalPDF,
        fileName: fileName,
        fileData: json,
        mimeType: "application/json"
    )

    // 3) Extract the attachment by name and compare content
    let extractedPairs = try PDFAttach.extractAttachments(from: attachedPDF, named: fileName)
    #expect(extractedPairs.count == 1)

    guard let (extractedName, extractedData) = extractedPairs.first else {
        #expect(Bool(false), "Attachment not found after embedding")
        return
    }
    #expect(extractedName == fileName)
    #expect(extractedData == json)

    // 4) Verify the resulting PDF is still openable by CoreGraphics
    guard let provider = CGDataProvider(data: attachedPDF as CFData) else {
        #expect(Bool(false), "CGDataProvider failed for attached PDF")
        return
    }
    let parsed = CGPDFDocument(provider)
    #expect(parsed != nil)
    #expect(parsed?.numberOfPages ?? 0 >= 1)
}
