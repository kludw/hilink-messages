import Foundation

/// Reads and writes the stick's XML with the Codable types generated from `openapi.yaml`.
///
/// The stick's documents are simple: an element is either text or a set of child elements,
/// and a repeated child is an array. Element names are matched without regard to case,
/// because the firmware is not consistent about it.
enum XMLCoding {
    static func decode<T: Decodable>(_ type: T.Type, from root: XMLNode) throws -> T {
        try T(from: ElementDecoder(elements: [root], codingPath: []))
    }

    /// Encodes `value` as a document with the given root element, e.g. `request`.
    static func encode<T: Encodable>(_ value: T, root: String) throws -> String {
        let holder = XMLNode(name: "")
        try value.encode(to: ElementEncoder(parent: holder, name: root, codingPath: []))
        guard let element = holder.children.first else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Nothing was encoded."))
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + serialize(element)
    }

    private static func serialize(_ node: XMLNode) -> String {
        let body = node.children.isEmpty ? escape(node.text) : node.children.map(serialize).joined()
        return "<\(node.name)>\(body)</\(node.name)>"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Decoding

private func scalar<T: LosslessStringConvertible>(_ node: XMLNode, _ key: (any CodingKey)? = nil) throws -> T {
    if T.self == Bool.self {
        return (["1", "true", "yes"].contains(node.text.lowercased())) as! T
    }
    guard let value = T(node.text) else {
        throw DecodingError.dataCorrupted(.init(codingPath: key.map { [$0] } ?? [],
                                                debugDescription: "<\(node.name)> is not a \(T.self): \"\(node.text)\""))
    }
    return value
}

/// Decodes from the elements that share one name under a parent: the first for a single value,
/// all of them for an array.
private struct ElementDecoder: Decoder {
    let elements: [XMLNode]
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard let element = elements.first else {
            throw DecodingError.valueNotFound(XMLNode.self, .init(codingPath: codingPath, debugDescription: "Element missing."))
        }
        return KeyedDecodingContainer(Keyed<Key>(element: element, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        Unkeyed(elements: elements, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        Single(elements: elements, codingPath: codingPath)
    }

    private struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let element: XMLNode
        let codingPath: [any CodingKey]

        var allKeys: [Key] { element.children.compactMap { Key(stringValue: $0.name) } }

        private func children(_ key: Key) -> [XMLNode] {
            element.children.filter { $0.name.caseInsensitiveCompare(key.stringValue) == .orderedSame }
        }

        private func child(_ key: Key) throws -> XMLNode {
            guard let node = children(key).first else {
                throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No <\(key.stringValue)> element."))
            }
            return node
        }

        func contains(_ key: Key) -> Bool { !children(key).isEmpty }

        /// An absent element, or an empty one, is "no value": the stick sends `<Msisdn></Msisdn>`.
        func decodeNil(forKey key: Key) throws -> Bool {
            guard let node = children(key).first else { return true }
            return node.text.isEmpty && node.children.isEmpty
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try scalar(child(key), key) }
        func decode(_ type: String.Type, forKey key: Key) throws -> String { try scalar(child(key), key) }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try scalar(child(key), key) }
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try scalar(child(key), key) }
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try scalar(child(key), key) }
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try scalar(child(key), key) }
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try scalar(child(key), key) }
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try scalar(child(key), key) }
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try scalar(child(key), key) }
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try scalar(child(key), key) }
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try scalar(child(key), key) }
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try scalar(child(key), key) }
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try scalar(child(key), key) }
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try scalar(child(key), key) }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            try T(from: ElementDecoder(elements: children(key), codingPath: codingPath + [key]))
        }

        func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
            try ElementDecoder(elements: children(key), codingPath: codingPath + [key]).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            Unkeyed(elements: children(key), codingPath: codingPath + [key])
        }

        func superDecoder() throws -> any Decoder { ElementDecoder(elements: [element], codingPath: codingPath) }
        func superDecoder(forKey key: Key) throws -> any Decoder {
            ElementDecoder(elements: children(key), codingPath: codingPath + [key])
        }
    }

    private struct Unkeyed: UnkeyedDecodingContainer {
        let elements: [XMLNode]
        let codingPath: [any CodingKey]
        var currentIndex = 0

        var count: Int? { elements.count }
        var isAtEnd: Bool { currentIndex >= elements.count }

        private mutating func next() throws -> XMLNode {
            guard !isAtEnd else {
                throw DecodingError.valueNotFound(XMLNode.self, .init(codingPath: codingPath, debugDescription: "No more elements."))
            }
            defer { currentIndex += 1 }
            return elements[currentIndex]
        }

        mutating func decodeNil() throws -> Bool { false }

        mutating func decode(_ type: Bool.Type) throws -> Bool { try scalar(next()) }
        mutating func decode(_ type: String.Type) throws -> String { try scalar(next()) }
        mutating func decode(_ type: Double.Type) throws -> Double { try scalar(next()) }
        mutating func decode(_ type: Float.Type) throws -> Float { try scalar(next()) }
        mutating func decode(_ type: Int.Type) throws -> Int { try scalar(next()) }
        mutating func decode(_ type: Int8.Type) throws -> Int8 { try scalar(next()) }
        mutating func decode(_ type: Int16.Type) throws -> Int16 { try scalar(next()) }
        mutating func decode(_ type: Int32.Type) throws -> Int32 { try scalar(next()) }
        mutating func decode(_ type: Int64.Type) throws -> Int64 { try scalar(next()) }
        mutating func decode(_ type: UInt.Type) throws -> UInt { try scalar(next()) }
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try scalar(next()) }
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try scalar(next()) }
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try scalar(next()) }
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try scalar(next()) }

        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try T(from: ElementDecoder(elements: [next()], codingPath: codingPath))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
            try ElementDecoder(elements: [next()], codingPath: codingPath).container(keyedBy: type)
        }

        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
            Unkeyed(elements: try next().children, codingPath: codingPath)
        }

        mutating func superDecoder() throws -> any Decoder {
            ElementDecoder(elements: [try next()], codingPath: codingPath)
        }
    }

    private struct Single: SingleValueDecodingContainer {
        let elements: [XMLNode]
        let codingPath: [any CodingKey]

        private func element() throws -> XMLNode {
            guard let node = elements.first else {
                throw DecodingError.valueNotFound(XMLNode.self, .init(codingPath: codingPath, debugDescription: "Element missing."))
            }
            return node
        }

        func decodeNil() -> Bool {
            guard let node = elements.first else { return true }
            return node.text.isEmpty && node.children.isEmpty
        }

        func decode(_ type: Bool.Type) throws -> Bool { try scalar(element()) }
        func decode(_ type: String.Type) throws -> String { try scalar(element()) }
        func decode(_ type: Double.Type) throws -> Double { try scalar(element()) }
        func decode(_ type: Float.Type) throws -> Float { try scalar(element()) }
        func decode(_ type: Int.Type) throws -> Int { try scalar(element()) }
        func decode(_ type: Int8.Type) throws -> Int8 { try scalar(element()) }
        func decode(_ type: Int16.Type) throws -> Int16 { try scalar(element()) }
        func decode(_ type: Int32.Type) throws -> Int32 { try scalar(element()) }
        func decode(_ type: Int64.Type) throws -> Int64 { try scalar(element()) }
        func decode(_ type: UInt.Type) throws -> UInt { try scalar(element()) }
        func decode(_ type: UInt8.Type) throws -> UInt8 { try scalar(element()) }
        func decode(_ type: UInt16.Type) throws -> UInt16 { try scalar(element()) }
        func decode(_ type: UInt32.Type) throws -> UInt32 { try scalar(element()) }
        func decode(_ type: UInt64.Type) throws -> UInt64 { try scalar(element()) }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try T(from: ElementDecoder(elements: elements, codingPath: codingPath))
        }
    }
}

// MARK: - Encoding

/// Encodes one value as the element (or, for an array, the repeated elements) called `name` under `parent`.
private struct ElementEncoder: Encoder {
    let parent: XMLNode
    let name: String
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let element = XMLNode(name: name)
        parent.children.append(element)
        return KeyedEncodingContainer(Keyed<Key>(element: element, codingPath: codingPath))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        Repeated(parent: parent, name: name, codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        Repeated(parent: parent, name: name, codingPath: codingPath)
    }

    private struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let element: XMLNode
        let codingPath: [any CodingKey]

        private func add(_ name: String, _ text: String) {
            let child = XMLNode(name: name)
            child.text = text
            element.children.append(child)
        }

        mutating func encodeNil(forKey key: Key) throws { add(key.stringValue, "") }

        mutating func encode(_ value: Bool, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: String, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: Double, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: Float, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: Int, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { add(key.stringValue, String(value)) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { add(key.stringValue, String(value)) }

        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            try value.encode(to: ElementEncoder(parent: element, name: key.stringValue, codingPath: codingPath + [key]))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
            ElementEncoder(parent: element, name: key.stringValue, codingPath: codingPath + [key]).container(keyedBy: keyType)
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            ElementEncoder(parent: element, name: key.stringValue, codingPath: codingPath + [key]).unkeyedContainer()
        }

        mutating func superEncoder() -> any Encoder { ElementEncoder(parent: element, name: "super", codingPath: codingPath) }
        mutating func superEncoder(forKey key: Key) -> any Encoder {
            ElementEncoder(parent: element, name: key.stringValue, codingPath: codingPath + [key])
        }
    }

    /// Writes each value as another `<name>` element under the parent: one for a single value, several for an array.
    private struct Repeated: UnkeyedEncodingContainer, SingleValueEncodingContainer {
        let parent: XMLNode
        let name: String
        let codingPath: [any CodingKey]
        var count = 0

        private mutating func add(_ text: String) {
            let child = XMLNode(name: name)
            child.text = text
            parent.children.append(child)
            count += 1
        }

        mutating func encodeNil() throws { add("") }

        mutating func encode(_ value: Bool) throws { add(String(value)) }
        mutating func encode(_ value: String) throws { add(String(value)) }
        mutating func encode(_ value: Double) throws { add(String(value)) }
        mutating func encode(_ value: Float) throws { add(String(value)) }
        mutating func encode(_ value: Int) throws { add(String(value)) }
        mutating func encode(_ value: Int8) throws { add(String(value)) }
        mutating func encode(_ value: Int16) throws { add(String(value)) }
        mutating func encode(_ value: Int32) throws { add(String(value)) }
        mutating func encode(_ value: Int64) throws { add(String(value)) }
        mutating func encode(_ value: UInt) throws { add(String(value)) }
        mutating func encode(_ value: UInt8) throws { add(String(value)) }
        mutating func encode(_ value: UInt16) throws { add(String(value)) }
        mutating func encode(_ value: UInt32) throws { add(String(value)) }
        mutating func encode(_ value: UInt64) throws { add(String(value)) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            try value.encode(to: ElementEncoder(parent: parent, name: name, codingPath: codingPath))
            count += 1
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
            count += 1
            return ElementEncoder(parent: parent, name: name, codingPath: codingPath).container(keyedBy: keyType)
        }

        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            count += 1
            let element = XMLNode(name: name)
            parent.children.append(element)
            return Repeated(parent: element, name: "item", codingPath: codingPath)
        }

        mutating func superEncoder() -> any Encoder { ElementEncoder(parent: parent, name: name, codingPath: codingPath) }
    }
}
