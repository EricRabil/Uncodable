////  File.swift
//  
//
//  Created by Eric Rabil on 8/30/21.
//  
//

import Foundation
import Runtime

public struct TupleUncodingContext {
    var tupleResolutionOverride: MixedTupleResolutionStrategy? = nil
    var inlined: Bool = false
}

extension TypeInfo {
    typealias SeparatedProperties = (namedProperties: [PropertyInfo], unnamedProperties: [Int: String])
    
    @_optimize(speed)
    func separatedProperties() -> SeparatedProperties {
        var namedProperties: [PropertyInfo] = [], unnamedProperties: [Int: String] = [:]
        
        for (index, property) in properties.enumerated() {
            if property.name.count == 0 {
                unnamedProperties[property.offset] = index.description
            } else {
                namedProperties.append(property)
            }
        }
        
        return (namedProperties, unnamedProperties)
    }
}

@_optimize(speed)
@_transparent
func decodeProperty(_ info: PropertyInfo, from decoder: Decoder) throws -> Any {
    switch info.type {
    case let type as Decodable.Type:
        return try type.init(from: decoder)
    default:
        return try RuntimeDecode(info.type.self, from: decoder)
    }
}

/**
 Tuples have three states:
 - All keyed
 - All unkeyed
 - Mixed content
 
 The first two are easy, dictionary or array and back again.
 The third is confusing, because no such type truly exists. The solution are two reconciliation strategies, and a bail-out where the user can add their own implementation.
 
 Strategy 1: Just use the indices as names on the same level as the dictionary. This is a bit ugly, but it works if you just need to serialize and deserialize.
 Strategy 2: Unnamed-to-remainder. All unkeyed values are stored in an array under the key of your choice.
 Strategy 3 (Bailout): An arbitrary function is invoked with the entries and en/decoder.
 */

@_optimize(speed)
func DecodeTuple<P>(type: Any.Type, decoder: Decoder, context: TupleUncodingContext = TupleUncodingContext()) throws -> P {
    let info = try typeInfo(of: type)
    
    let (namedProperties, unnamedProperties) = info.separatedProperties()
    
    @_optimize(speed)
    func decodeDictionary(container: KeyedDecodingContainer<StringLiteralCodingKey>, _ unnamedCallout: ((PropertyInfo) throws -> Any)? = nil) throws -> Any {
        try buildStruct(type: type) { info in
            if info.name.count == 0, let unnamedCallout = unnamedCallout {
                return try unnamedCallout(info)
            }
            
            return try decodeProperty(info, from: container.superDecoder(forKey: StringLiteralCodingKey(unnamedProperties[info.offset] ?? info.name)))
        }
    }
    
    @_optimize(speed)
    func runMixedResolution(container: KeyedDecodingContainer<StringLiteralCodingKey>? = nil) throws -> Any {
        let container = try container ?? decoder.container(keyedBy: StringLiteralCodingKey.self)
        
        let mixedStrategy = context.tupleResolutionOverride ?? ExtrapolateConfiguration(type).mixedTupleResolutionStrategy
        
        switch mixedStrategy {
        case .unnamedToRemainder(key: let remainderKey):
            // all unkeyed values will go into an array under the remainderKey
            var remainderContainer = try container.nestedUnkeyedContainer(forKey: StringLiteralCodingKey(remainderKey))
            
            return try decodeDictionary(container: container) { unkeyedProperty in
                try decodeProperty(unkeyedProperty, from: remainderContainer.superDecoder())
            }
        case .useIndicesAsNames:
            // all unkeyed values will be keyed by their order of occurrance
            return try decodeDictionary(container: container)
        case .custom(_, let customDecoder):
            // hand off to a custom decoder
            return *(try customDecoder(info.properties, decoder))
        }
    }
    
    if namedProperties.count > 0 && unnamedProperties.count > 0 {
        // mixed content
        return try *runMixedResolution()
    } else if namedProperties.count > 0 && unnamedProperties.count == 0 {
        // dictionary style
        return try *decodeDictionary(container: decoder.container(keyedBy: StringLiteralCodingKey.self))
    } else if namedProperties.count == 0 && unnamedProperties.count > 0 {
        // array style
        guard !context.inlined else {
            // you cannot inline an array (that doesnt make sense) so defer to mixed resolution
            return try *runMixedResolution()
        }
        
        var container = try decoder.unkeyedContainer()
        
        return try *buildStruct(type: type) { info in
            return try decodeProperty(info, from: container.superDecoder())
        }
    } else {
        // degenerate type
        return UnsafeMutableRawBufferPointer.allocate(byteCount: info.size, alignment: info.alignment)
                .baseAddress!.assumingMemoryBound(to: P.self).pointee
    }
}

@_optimize(speed)
func EncodeTuple<P>(value: P, encoder: Encoder, context: TupleUncodingContext = TupleUncodingContext()) throws {
    let mirror = Mirror(reflecting: value)
    let children = mirror.children
    let runtimeType = mirror.subjectType
    
    var namedChildren: [Mirror.Child] = [], unnamedChildren: [Mirror.Child] = []
    
    for child in children {
        if child.label!.starts(with: ".") {
            unnamedChildren.append(child)
        } else {
            namedChildren.append(child)
        }
    }
    
    @discardableResult
    @_optimize(speed)
    func encodeDictionary(_ values: [Mirror.Child]) throws -> KeyedEncodingContainer<StringLiteralCodingKey> {
        var container = encoder.container(keyedBy: StringLiteralCodingKey.self)
        
        try values.forEach { child in
            try RuntimeEncode(child.value, encoder: container.superEncoder(forKey: .init(child.label!)))
        }
        
        return container
    }
    
    @_optimize(speed)
    func encodeArray(_ values: [Mirror.Child], _ container: @autoclosure () -> UnkeyedEncodingContainer) throws {
        var container = container()
        
        try values.forEach { child in
            try RuntimeEncode(child.value, encoder: container.superEncoder())
        }
    }
    
    @_optimize(speed)
    func runMixedResolution() throws {
        // mixed content
        let mixedStrategy = context.tupleResolutionOverride ?? ExtrapolateConfiguration(runtimeType).mixedTupleResolutionStrategy
        
        switch mixedStrategy {
        case .unnamedToRemainder(key: let remainderKey):
            // dictionary style
            var container = try encodeDictionary(namedChildren)
            
            try encodeArray(unnamedChildren, container.nestedUnkeyedContainer(forKey: .init(remainderKey)))
        case .useIndicesAsNames:
            // inline unnamed using their indices
            try encodeDictionary(namedChildren + unnamedChildren)
        case .custom(let customEncoder, _):
            // hand off unnamed to encoder after named are encoded
            try customEncoder(children, encoder)
        }
    }
    
    if namedChildren.count > 0 && unnamedChildren.count > 0 {
        // mixed content
        try runMixedResolution()
    } else if namedChildren.count > 0 && unnamedChildren.count == 0 {
        // dictionary style
        try encodeDictionary(namedChildren)
    } else if namedChildren.count == 0 && unnamedChildren.count > 0 {
        // array style
        guard !context.inlined else {
            // you cannot inline an array (that doesnt make sense) so defer to mixed resolution
            return try runMixedResolution()
        }
        
        try encodeArray(unnamedChildren, encoder.unkeyedContainer())
    } else {
        // nil?
        
    }
}
