////  File.swift
//  
//
//  Created by Eric Rabil on 8/30/21.
//  
//

import Foundation
import Echo

public enum EnumMagicError: Error {
    case invalidCaseName
    case reflectionFailure
}

@_optimize(speed)
public func InitializeEnum<P>(_ enumType: Any.Type, caseName: String, payload: UnsafeMutableRawPointer? = nil) throws -> P {
    guard let info = reflectEnum(enumType) else {
        throw EnumMagicError.reflectionFailure
    }
    
    let payload = payload ?? UnsafeMutableRawPointer.allocate(byteCount: info.vwt.size, alignment: info.vwt.flags.alignment)
    
    let cases = info.contextDescriptor.fields.records.map(\.name)
    
    let tag = cases.firstIndex(of: caseName)
    
    guard let tag = tag else {
        throw EnumMagicError.invalidCaseName
    }
    
    info.enumVwt.destructiveInjectEnumTag(for: payload, tag: UInt32(tag))
    
    return payload.assumingMemoryBound(to: P.self).pointee
}
