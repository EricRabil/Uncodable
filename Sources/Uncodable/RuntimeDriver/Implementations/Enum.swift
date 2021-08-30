////  File.swift
//  
//
//  Created by Eric Rabil on 8/30/21.
//  
//

import Foundation
import Echo
import Runtime

public enum UncodingError: Error {
    case reflectionFailure(value: Any, codingPath: [CodingKey])
    case invalidCase(String)
}

extension EnumMetadata {
    typealias CaseInformation = (name: String, noPayload: Bool)
    
    func caseInformation(for tag: Int) -> CaseInformation {
        let record = contextDescriptor.fields.records[tag]
        
        return (record.name, tag >= descriptor.numPayloadCases)
    }
    
    func caseInformation(for value: UnsafeRawPointer) -> CaseInformation {
        caseInformation(for: Int(enumVwt.getEnumTag(for: value)))
    }
    
    func caseInformation(for name: String) throws -> CaseInformation {
        guard let tag = contextDescriptor.fields.records.firstIndex(where: { $0.name == name }) else {
            throw UncodingError.invalidCase(name)
        }
        
        return caseInformation(for: Int(tag))
    }
}

@_optimize(speed)
func EncodeEnum(value: Any, encoder: Encoder) throws {
    guard let reflection = reflectEnum(value) else {
        throw UncodingError.reflectionFailure(value: value, codingPath: encoder.codingPath)
    }
    
    let runtimeType = reflection.type
    let (caseNameKey, payloadKey, inliningPayload, mixedPayloadResolutionStrategy) = ExtrapolateConfiguration(runtimeType).enumCustomizations
    var container = encoder.container(keyedBy: StringLiteralCodingKey.self)
    
    var value = value
    let (name, noPayload) = reflection.caseInformation(for: &value)
    
    if noPayload {
        return try container.encode(name, forKey: .init(caseNameKey))
    }
    
    let mirror = Mirror(reflecting: value)
    
    guard let (_, value) = mirror.children.first else {
        preconditionFailure()
    }
    
    try container.encode(name, forKey: .init(caseNameKey))
    
    var payloadContainer: Encoder
    
    if inliningPayload {
        payloadContainer = encoder
    } else {
        payloadContainer = container.superEncoder(forKey: .init(payloadKey))
    }
    
    try RuntimeEncode(value, encoder: payloadContainer, tupleContext: TupleUncodingContext(tupleResolutionOverride: mixedPayloadResolutionStrategy, inlined: inliningPayload))
}

@_optimize(speed)
func DecodeEnum<P>(type: Any.Type, decoder: Decoder) throws -> P {
    guard let reflection = reflectEnum(type) else {
        throw UncodingError.reflectionFailure(value: type, codingPath: decoder.codingPath)
    }
    
    let container = try decoder.container(keyedBy: StringLiteralCodingKey.self)
    let (caseNameKey, payloadKey, inliningPayload, mixedPayloadResolutionStrategy) = ExtrapolateConfiguration(type).enumCustomizations
    
    let caseName = try container.decode(String.self, forKey: .init(caseNameKey))
    
    let (_, noPayload) = try reflection.caseInformation(for: caseName)
    
    if noPayload {
        return try InitializeEnum(type, caseName: caseName)
    }
    
    guard let caseInfo = try typeInfo(of: type).cases.first(where: { $0.name == caseName }) else {
        throw UncodingError.reflectionFailure(value: type, codingPath: decoder.codingPath)
    }
    
    var payloadContainer: Decoder
    
    if inliningPayload {
        payloadContainer = decoder
    } else {
        payloadContainer = try container.superDecoder(forKey: .init(payloadKey))
    }
    
    var payload: Any = try RuntimeDecode(caseInfo.payloadType!, from: payloadContainer, tupleContext: TupleUncodingContext(tupleResolutionOverride: mixedPayloadResolutionStrategy, inlined: inliningPayload))
    
    return try InitializeEnum(type, caseName: caseName, payload: &payload)
}
