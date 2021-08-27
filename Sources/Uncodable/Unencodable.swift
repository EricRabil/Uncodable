public protocol Unencodable: Encodable {
}

extension Unencodable {
    func encode(to encoder: Encoder) throws {
        try MirroredValue(self).encode(to: encoder)
    }
}
