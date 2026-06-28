import Foundation

struct MarkedTextState {
    private(set) var string = ""

    var isActive: Bool {
        !string.isEmpty
    }

    var utf16Count: Int {
        string.utf16.count
    }

    mutating func replace(with string: String) {
        self.string = string
    }

    mutating func clear() {
        string = ""
    }
}
