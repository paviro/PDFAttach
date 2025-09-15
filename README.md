# PDFAttach

Ultra-minimal helpers to embed and extract file attachments in existing PDFs from Swift.

> Heads up: this code is highly hacky and bare-bones, coded with heavy LLM usage, and based on Hopding's [pdf-lib](https://github.com/Hopding/pdf-lib). Use at your own risk.

## What it does

- Adds a file as an EmbeddedFile to an existing PDF
- Extracts embedded files from a PDF (optionally by name)


## Usage

### Add an attachment to a PDF

```swift
import Foundation
import PDFAttach

let pdfURL = URL(fileURLWithPath: "/path/to/input.pdf")
let attachmentURL = URL(fileURLWithPath: "/path/to/metadata.json")

let pdfData = try Data(contentsOf: pdfURL)
let fileData = try Data(contentsOf: attachmentURL)

let updatedData = try PDFAttach.addAttachment(
    to: pdfData,
    fileName: attachmentURL.lastPathComponent,
    fileData: fileData,
    mimeType: "application/json"
)

let outURL = URL(fileURLWithPath: "/path/to/output.pdf")
try updatedData.write(to: outURL)
```

### Extract attachments from a PDF

```swift
import Foundation
import PDFAttach

let pdfURL = URL(fileURLWithPath: "/path/to/document.pdf")
let pdfData = try Data(contentsOf: pdfURL)

// Get all attachments (empty array if none)
let attachments: [(String, Data, String?)] = try PDFAttach.extractAttachments(from: pdfData)
for (name, data, mime) in attachments {
    print("Found attachment: \(name) (\(data.count) bytes), mime=\(mime ?? "unknown")")
}

// Or, get a specific file by name
let invoice = try PDFAttach.extractAttachments(from: pdfData, named: "invoice.json").first
if let (name, data, mime) = invoice {
    print("Got \(name) with mime=\(mime ?? "unknown") and \(data.count) bytes")
}
```

## Public API

- `PDFAttach.addAttachment(to:fileName:fileData:mimeType) throws -> Data`
  - Returns a new PDF `Data` with the file embedded.
- `PDFAttach.extractAttachments(from:named:) throws -> [(String, Data, String?)]`
  - Returns a list of `(fileName, data, mimeType)` tuples (empty if none). Pass `named:` to filter.

Notes:
- MIME type is stored in the embedded file stream's `Subtype` as a PDF Name. Characters such as `/` are hex-escaped in PDF Names, so the value is decoded back into a conventional MIME string (e.g. `application/json`).

## How adding the attachment works (brief)

- Parses minimal trailer entries from the original PDF (`/Size`, `/Root`, `/Pages`) via regex.
- Appends new objects using incremental update semantics: new xref section and trailer with `/Prev` pointing to the original `startxref`.
- Writes the embedded file stream using `ASCIIHexDecode` and a simple Filespec.
- Writes a minimal Catalog with `Names.EmbeddedFiles` and `AF` pointing to the new file spec.

## Limitations and caveats

This is not a full PDF writer and takes many shortcuts:

- Assumes well-formed, non-encrypted PDFs; encrypted or highly optimized PDFs will likely fail.
- Minimal parsing — only looks for `/Size`, `/Root`, and `/Pages`; complex/edge cases are not supported.
- Replaces the Catalog reference with a freshly written, minimal Catalog; existing `Names` or `AF` entries are not merged.
- Streams are encoded as ASCII Hex; no compression is applied.
- No validation/repair of existing cross-reference tables.
- Lightly tested against a small set of PDFs only.

If you need robust PDF manipulation don't use this!
