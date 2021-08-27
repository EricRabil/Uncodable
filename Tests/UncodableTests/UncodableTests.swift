import XCTest
import Foundation
@testable import Uncodable

private extension Dictionary where Key: Hashable, Value == Any {
    var hashable: [Key: AnyHashable] {
        compactMapValues {
            $0 as? AnyHashable
        }
    }
}

private func cast(_ value: Any) -> AnyHashable? {
    switch value {
    case let hashable as AnyHashable:
        return hashable
    case let dict as [String: Any]:
        return dict.hashable
    default:
        return nil
    }
}

internal func __XCTAssertEqual(_ a: Any, _ b: Any, _ message: String? = nil) {
    let match: () -> Bool = {
        guard let a = a as? AnyHashable, let b = b as? AnyHashable else {
            return false
        }
        
        return a == b
    }
    
    if let message = message {
        XCTAssert(match(), message)
    } else {
        XCTAssert(match())
    }
}

internal func _XCTAssertEqual(_ a: [Any], _ b: [Any], _ message: String? = nil) {
    let match: () -> [Bool] = {
        a.enumerated().map { index, a in
            guard let a1 = cast(a), b.indices.contains(index), let b1 = cast(b[index]) else {
                return false
            }
            
            return a1 == b1
        }
    }
    
    if let message = message {
        XCTAssert(!match().contains(false), message)
    } else {
        XCTAssert(!match().contains(false))
    }
}

private extension MirroredValue {
    var tupleValue: [Any] {
        pureValue as! [Any]
    }
}

final class TupleTests: XCTestCase {
    func testNamedTuples() {
        let tupleValue = MirroredValue((a: 0, b: 1, c: 2)).tupleValue
        
        XCTAssert(tupleValue is [[String: Int]], "tupleValue of named pairs should result in an array of dictionaries")
        
        XCTAssertEqual(tupleValue as! [[String: Int]], [
            ["a": 0],
            ["b": 1],
            ["c": 2]
        ])
    }
    
    func testUnnamedTuples() {
        let tupleValue = MirroredValue((1,2,3)).tupleValue
        
        XCTAssert(tupleValue is [Int], "tupleValue of an integer tuple should be an integer array")
        
        XCTAssertEqual(tupleValue as! [Int], [1,2,3], "(1,2,3) should translate to [1,2,3]")
    }
    
    func testMixedTuples() {
        let tupleValue = MirroredValue((0, b: 1, 2)).tupleValue
        
        _XCTAssertEqual(tupleValue, [
            0,
            ["b": 1],
            2
        ])
    }
}

final class EnumTests: XCTestCase {
    enum TestEnum: Unencodable {
        case bitch(Int)
    }
    
    func testBasicEnum() throws {
        let encoded = String(decoding: try JSONEncoder().encode(TestEnum.bitch(5)), as: UTF8.self)
        let reference = String(decoding: try JSONSerialization.data(withJSONObject: ["type": "bitch", "value": 5], options: []), as: UTF8.self)
        
        XCTAssert(encoded == reference)
    }
}
