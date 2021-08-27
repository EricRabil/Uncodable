//
//  File.swift
//  
//
//  Created by Eric Rabil on 8/25/21.
//

import Foundation

private func isExcluded(_ value: Any?) -> Bool {
    guard let value = value else {
        return false
    }
    
    return String(describing: Mirror(reflecting: value).subjectType).starts(with: "Excluded<")
}

internal struct _DictionaryCodingKey: CodingKey {
  internal let stringValue: String
  internal let intValue: Int?

  internal init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = Int(stringValue)
  }

  internal init?(intValue: Int) {
    self.stringValue = "\(intValue)"
    self.intValue = intValue
  }
}

private func encodeDictionary(_ dictionary: [String: Any], encoder: Encoder) throws {
    var container = encoder.container(keyedBy: _DictionaryCodingKey.self)
    
    for (key, value) in dictionary {
        try encodeArbitrary(value, to: container.superEncoder(forKey: _DictionaryCodingKey(stringValue: key)!))
    }
}

private func encodeArray(_ array: [Any], to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    
    for value in array {
        try encodeArbitrary(value, to: container.superEncoder())
    }
}

private func encodeArbitrary(_ value: Any, to encoder: Encoder) throws {
    switch value {
    case let encodable as Encodable:
        try encodable.encode(to: encoder)
    case let dictionary as [String: Any]:
        try encodeDictionary(dictionary, encoder: encoder)
    case let array as [Any]:
        try encodeArray(array, to: encoder)
    default:
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

public struct MirroredValue: Encodable {
    public let mirror: Mirror
    public let reflectedValue: Any
    
    public init(_ value: Any) {
        mirror = Mirror(reflecting: value)
        reflectedValue = value
    }
    
    public func encode(to encoder: Encoder) throws {
        guard let pureValue = pureValue else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }
        
        try encodeArbitrary(pureValue, to: encoder)
    }
    
    public var pureValue: Any? {
        if reflectedValue is Encodable, !(reflectedValue is Unencodable) {
            return reflectedValue
        }
        
        guard let displayStyle = mirror.displayStyle else {
            return reflectedValue
        }
        
        switch displayStyle {
        case .enum:
            guard let (label, value) = mirror.children.first else {
                return nil
            }
            
            return [
                "type": label,
                "value": MirroredValue(value).pureValue
            ]
        case .tuple:
            return mirror.children.map { label, value -> Any in
                guard let label = label, !label.starts(with: ".") else {
                    return value
                }
                
                return [
                    label: MirroredValue(value).pureValue
                ]
            }
        case .optional:
            guard let value = mirror.children.first?.value else {
                return nil
            }
            
            return MirroredValue(value).pureValue
        case .set:
            fallthrough
        case .collection:
            return mirror.children
                .map(\.value)
                .map(MirroredValue.init)
                .map(\.pureValue)
        case .struct:
            fallthrough
        case .class:
            fallthrough
        case .dictionary:
            return mirror.children
                .compactMap { label, value -> (String, Any?)? in
                    let (key, value) = value as! (key: String, value: Any)
                    
                    guard !isExcluded(value) else {
                        return nil
                    }
                    
                    return (key, MirroredValue(value).pureValue)
                }
                .reduce(into: [String: Any?]()) { dict, element in
                    dict[element.0] = element.1
                }
        @unknown default:
            return nil
        }
    }
}
