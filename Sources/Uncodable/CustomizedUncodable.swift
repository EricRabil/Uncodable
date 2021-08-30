////  File.swift
//  
//
//  Created by Eric Rabil on 8/30/21.
//  
//

import Foundation
import Runtime

public enum MixedTupleResolutionStrategy {
    // store unnamed entries to an array at the given nested key
    case unnamedToRemainder(key: String) // default
    case useIndicesAsNames
    case custom(encoder: (_ entries: Mirror.Children, _ tupleEncoder: Encoder) throws -> (), decoder: (_ entries: [PropertyInfo], _ decoder: Decoder) throws -> Any)
}

public enum UncodableEnumCustomization {
    // keypath for the enum case name
    case caseNameKey(String) // default: type
    // encode the payload to a nested keypath
    case payloadKey(String) // default: payload
    
    // allows you to encode the payload on the same level as the case name key
    // attempting to inline a case with multiple payloads will result in a mixed-tuple resolution
    case inliningPayload
    // allows you to determine how to handle the encoding of unnamed entries in a mixed-content scenario
    // same as tuple configuration since payloads are stored as tuples
    case mixedPayloadResolutionStrategy(MixedTupleResolutionStrategy) // default: .unnamedToRemainder(remainder)
}

public enum UncodableStrategyCustomization {
    case mixedTupleResolutionStrategy(MixedTupleResolutionStrategy) // default: .unnamedToRemainder(remainder)
    case enumCustomizations([UncodableEnumCustomization])
}

public final class UncodableCustomizationDefinition {
    public typealias EnumCustomizationDefinition = (
        caseNameKey: String,
        payloadKey: String,
        inliningPayload: Bool,
        mixedPayloadResolutionStrategy: MixedTupleResolutionStrategy?
    )
    
    public static let defaultEnumCustomizations: EnumCustomizationDefinition = (
        caseNameKey: "type",
        payloadKey: "payload",
        inliningPayload: false,
        mixedPayloadResolutionStrategy: .unnamedToRemainder(key: "remainder")
    )
    
    public static let defaultMixedTupleResolutionStrategy: MixedTupleResolutionStrategy = .unnamedToRemainder(key: "remainder")
    
    public static func customized(_ customizations: UncodableStrategyCustomization...) -> UncodableCustomizationDefinition {
        UncodableCustomizationDefinition(customizations)
    }
    
    public static let `default` = UncodableCustomizationDefinition([])
        
    public var enumCustomizations: EnumCustomizationDefinition
    public var mixedTupleResolutionStrategy: MixedTupleResolutionStrategy
    
    public init(_ customizations: [UncodableStrategyCustomization]) {
        enumCustomizations = Self.defaultEnumCustomizations
        mixedTupleResolutionStrategy = Self.defaultMixedTupleResolutionStrategy
        
        for customization in customizations {
            switch customization {
            case .enumCustomizations(let customizations):
                for customization in customizations {
                    switch customization {
                    case .caseNameKey(let caseNameKey):
                        enumCustomizations.caseNameKey = caseNameKey
                    case .payloadKey(let payloadKey):
                        enumCustomizations.payloadKey = payloadKey
                    case .inliningPayload:
                        enumCustomizations.inliningPayload = true
                    case .mixedPayloadResolutionStrategy(let strategy):
                        enumCustomizations.mixedPayloadResolutionStrategy = strategy
                    }
                }
            case .mixedTupleResolutionStrategy(let strategy):
                self.mixedTupleResolutionStrategy = strategy
            }
        }
    }
}

public protocol CustomizedUncodable {
    static var configuration: UncodableCustomizationDefinition { get }
}

func ExtrapolateConfiguration(_ type: Any.Type) -> UncodableCustomizationDefinition {
    if let customizable = type as? CustomizedUncodable.Type {
        return customizable.configuration
    }
    
    return .default
}
