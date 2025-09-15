import Foundation

struct EmbeddedFileOptions {
    var mimeType: String?
    var description: String?
    var creationDate: Date?
    var modificationDate: Date?
    var afRelationship: String?
    init(mimeType: String? = nil, description: String? = nil, creationDate: Date? = nil, modificationDate: Date? = nil, afRelationship: String? = nil) {
        self.mimeType = mimeType
        self.description = description
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.afRelationship = afRelationship
    }
}


