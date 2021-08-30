import XCTest
import Foundation
@testable import Uncodable
import Runtime

extension Uncodable {
    var data: Data {
        try! JSONEncoder().encode(self)
    }
    
    var json: String {
        String(decoding: data, as: UTF8.self)
    }
    
    @discardableResult
    func compare(_ dict: [String: AnyHashable]) throws -> Self.Type {
        let json1 = try JSONSerialization.jsonObject(with: data, options: []) as! AnyHashable
        
        XCTAssertEqual(json1, dict)
        
        return Self.self
    }
    
    @discardableResult
    func compare(_ value: Self) throws -> Self.Type {
        let deserialized = try JSONDecoder().decode(Self.self, from: data)
        
        XCTAssertEqual(deserialized.data, value.data)
        
        return Self.self
    }
}

final class EnumTests: XCTestCase {
    class NestedCodable: Codable, Hashable {
        static func == (lhs: EnumTests.NestedCodable, rhs: EnumTests.NestedCodable) -> Bool {
            lhs.value == rhs.value
        }
        
        var value = 5
        
        init(value: Int) {
            self.value = value
        }
        
        init() {}
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(value)
        }
    }
    
    enum InlinableEnumeration: Uncodable, CustomizedUncodable {
        case inliningOne(namedValue: Bool, otherNamedValue: Bool)
        case mixedContent(namedValue: Bool, Bool)
        case otherMixedContent(namedValue: Bool, Bool)
        case otherMixedContent1(namedValue: Bool, Bool)
        case otherMixedContent2(namedValue: Bool, Bool)
        case noContent
        
        static let configuration: UncodableCustomizationDefinition = .customized(
            .enumCustomizations([
                .caseNameKey("type"),
                .mixedPayloadResolutionStrategy(.unnamedToRemainder(key: "remainder")),
                .inliningPayload
            ])
        )
    }
    
    enum NestedCodableTests: Uncodable {
        case nested(NestedCodable)
    }
    
    func testInlinedEncoding() throws {
        try InlinableEnumeration
            .inliningOne(namedValue: true, otherNamedValue: false).compare([
                "type": "inliningOne",
                "namedValue": true,
                "otherNamedValue": false
            ])
            .mixedContent(namedValue: false, true).compare([
                "type": "mixedContent",
                "namedValue": false,
                "remainder": [true]
            ])
            .noContent.compare([
                "type": "noContent"
            ])
    }
    
    func testInlinedDecoding() throws {
        try InlinableEnumeration
            .inliningOne(namedValue: true, otherNamedValue: false)
            .compare(.inliningOne(namedValue: true, otherNamedValue: false))
            .mixedContent(namedValue: true, false)
            .compare(.mixedContent(namedValue: true, false))
            .noContent
            .compare(.noContent)
    }
    
    func testHeapEncoding() throws {
        try NestedCodableTests
            .nested(NestedCodable()).compare([
                "type": "nested",
                "payload": [
                    "value": 5
                ]
            ])
    }
    
    func testHeapDecoding() throws {
        try NestedCodableTests
            .nested(NestedCodable(value: 10)).compare(.nested(NestedCodable(value: 10)))
    }
}
