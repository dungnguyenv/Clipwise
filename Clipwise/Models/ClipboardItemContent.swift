import Foundation
import SwiftData

@Model
final class ClipboardItemContent {
    var type: String  // UTType identifier, e.g. "public.utf8-plain-text"
    var value: Data?

    var item: ClipboardItem?

    init(type: String, value: Data?) {
        self.type = type
        self.value = value
    }

    var contentType: ContentType? {
        ContentType.classify(
            .init(type) ?? .data
        )
    }
}
