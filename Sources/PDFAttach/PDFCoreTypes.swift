import Foundation

enum PDFObject {
    case null
    case bool(Bool)
    case int(Int)
    case real(Double)
    case name(String)
    case string(String)
    case hexString(Data)
    case array([PDFObject])
    case dictionary([String: PDFObject])
    case stream(dict: [String: PDFObject], data: Data)
    case reference(number: Int, generation: Int)
}

struct PDFRef: Hashable {
    let number: Int
    let generation: Int
    init(number: Int, generation: Int) {
        self.number = number
        self.generation = generation
    }
}


