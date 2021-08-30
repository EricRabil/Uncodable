////  File.swift
//  
//
//  Created by Eric Rabil on 8/29/21.
//  
//

import Foundation
import Runtime
import Echo

private extension PropertyInfo {
    func peek(_ object: Any, _ parentInfo: TypeInfo) throws -> Any {
        switch parentInfo.kind {
        case .tuple:
            var value = object
            
            return withUnsafeBytes(of: &value) { buffer in
                buffer.baseAddress!
                    .advanced(by: self.offset)
                    .assumingMemoryBound(to: *self.type)
                    .pointee
            }
        default:
            return try self.get(from: object)
        }
    }
}

@_optimize(speed)
func RuntimeEncode<P>(_ value: P, encoder: Encoder, tupleContext: @autoclosure () -> TupleUncodingContext = TupleUncodingContext()) throws {
    if let encodable = value as? Encodable, !(value is Unencodable) {
        // re-enter normal codable system
        return try encodable.encode(to: encoder)
    }
    
    let info = try typeInfo(of: Mirror(reflecting: value).subjectType)
    
    switch info.kind {
    case .optional:
        var container = encoder.singleValueContainer()
        
        let value = value as Optional<Any>
        
        switch value {
        case .none:
            try container.encodeNil()
        case .some(let value):
            try RuntimeEncode(value, encoder: encoder)
        }
    case .tuple:
        try EncodeTuple(value: value, encoder: encoder, context: tupleContext())
    case .struct:
        fallthrough
    case .class:
        var container = encoder.container(keyedBy: StringLiteralCodingKey.self)
        
        try info.properties.forEach { property in
            try RuntimeEncode(property.get(from: value), encoder: container.superEncoder(forKey: .init(property.name)))
        }
    case .enum:
        try EncodeEnum(value: value, encoder: encoder)
    case .opaque:
        fatalError("Cannot decode an opaque type at this time")
    case .function:
        fatalError("Cannot decode a function at this time")
    case .existential:
        fatalError("Cannot decode an existential at this time")
    case .metatype:
        fatalError("Cannot decode a metatype at this time")
    case .objCClassWrapper:
        fatalError("Cannot decode an obj-c class wrapper at this time")
    case .existentialMetatype:
        fatalError("Cannot decode an existential metatype at this time")
    case .foreignClass:
        fatalError("Cannot decode a foreign class at this time")
    case .heapLocalVariable:
        fatalError("Cannot decode a heap-local variable at this time")
    case .heapGenericLocalVariable:
        fatalError("Cannot decode a heap-generic variable at this time")
    case .errorObject:
        fatalError("Cannot decode an error object at this time")
    }
}
