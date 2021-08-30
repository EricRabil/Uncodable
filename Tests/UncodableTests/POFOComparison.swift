////  File.swift
//  
//
//  Created by Eric Rabil on 8/29/21.
//  
//

import Foundation
import XCTest

func CompareJSON(_ json1: Data, _ json2: Data) throws {
    let pofo1 = try JSONSerialization.jsonObject(with: json1, options: []) as! NSObject
    let pofo2 = try JSONSerialization.jsonObject(with: json2, options: []) as! NSObject
    
    XCTAssertEqual(pofo1, pofo2)
}

func CompareJSON(_ json: Data, serializingOther value: Any) throws {
    try CompareJSON(json, try JSONSerialization.data(withJSONObject: value, options: []))
}

