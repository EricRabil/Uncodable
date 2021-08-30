////  File.swift
//  
//
//  Created by Eric Rabil on 8/29/21.
//  
//

import Foundation
import Runtime

struct StringLiteralCodingKey: CodingKey, ExpressibleByStringLiteral {
    var stringValue: String
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init(stringLiteral: String) {
        self.stringValue = stringLiteral
    }
    
    init(_ stringValue: String) {
        self.stringValue = stringValue
    }
    
    var intValue: Int?
    
    init?(intValue: Int) {
        fatalError("what the fuck are you doing")
    }
}

func setProperties(typeInfo: TypeInfo,
                   pointer: UnsafeMutableRawPointer,
                   constructor: ((PropertyInfo) throws -> Any)? = nil) throws {
    for property in typeInfo.properties {
        let value = try constructor.map { (resolver) -> Any in
            return try resolver(property)
        } ?? defaultValue(of: property.type)
        
        let valuePointer = pointer.advanced(by: property.offset)
        let sets = setters(type: property.type)
        sets.set(value: value, pointer: valuePointer, initialize: true)
    }
}

func defaultValue(of type: Any.Type) throws -> Any {
    
    if let constructable = type as? DefaultConstructor.Type {
        return constructable.init()
    } else if let isOptional = type as? ExpressibleByNilLiteral.Type {
        return isOptional.init(nilLiteral: ())
    }
    
    return try createInstance(of: type)
}

func buildStruct(type: Any.Type, constructor: ((PropertyInfo) throws -> Any)? = nil) throws -> Any {
    let info = try typeInfo(of: type)
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: info.size, alignment: info.alignment)
    defer { pointer.deallocate() }
    try setProperties(typeInfo: info, pointer: pointer, constructor: constructor)
    return getters(type: type).get(from: pointer)
}

protocol Getters {}
extension Getters {
    static func get(from pointer: UnsafeRawPointer) -> Any {
        return pointer.assumingMemoryBound(to: Self.self).pointee
    }
}

struct ProtocolTypeContainer {
    let type: Any.Type
    let witnessTable: Int
}

func getters(type: Any.Type) -> Getters.Type {
    let container = ProtocolTypeContainer(type: type, witnessTable: 0)
    return unsafeBitCast(container, to: Getters.Type.self)
}

protocol Setters {}
extension Setters {
    static func set(value: Any, pointer: UnsafeMutableRawPointer, initialize: Bool = false) {
        if let value = value as? Self {
            let boundPointer = pointer.assumingMemoryBound(to: self);
            if initialize {
                boundPointer.initialize(to: value)
            } else {
                boundPointer.pointee = value
            }
        }
    }
}

func setters(type: Any.Type) -> Setters.Type {
    let container = ProtocolTypeContainer(type: type, witnessTable: 0)
    return unsafeBitCast(container, to: Setters.Type.self)
}

prefix operator *
@_transparent
@_optimize(speed)
prefix func * <P>(_ value: Any) -> P {
    if value is AnyClass.Type || value is AnyClass {
        return unsafeBitCast(value, to: P.self)
    } else {
        return withUnsafePointer(to: value) {
            UnsafeRawPointer(OpaquePointer($0)).assumingMemoryBound(to: P.self).pointee
        }
    }
}

@_optimize(speed)
func RuntimeDecode<P>(_ type: Any.Type, from decoder: Decoder, tupleContext: @autoclosure () -> TupleUncodingContext = TupleUncodingContext()) throws -> P {
    if let decodable = type as? Decodable.Type, !(type is Undecodable.Type) {
        return try *decodable.init(from: decoder)
    }
    
    let info = try! typeInfo(of: type)
    
    switch info.kind {
    case .optional:
        // MARK: - this is probably wrong
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            return *(Optional<P>.none as Any)
        } else {
            return try RuntimeDecode(info.genericTypes.first!, from: decoder)
        }
    case .struct:
        fallthrough
    case .class:
        let container = try decoder.container(keyedBy: StringLiteralCodingKey.self)
        
        return try *createInstance(of: type) { info -> Any in
            try RuntimeDecode(info.type, from: container.superDecoder(forKey: .init(info.name)))
        }
    case .tuple:
        return try DecodeTuple(type: type, decoder: decoder, context: tupleContext())
    case .enum:
        return try DecodeEnum(type: type, decoder: decoder)
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
