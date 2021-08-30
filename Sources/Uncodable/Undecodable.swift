//
//  File.swift
//  
//
//  Created by Eric Rabil on 8/25/21.
//

import Foundation

public protocol Undecodable: Decodable {
}

public extension Undecodable {
    init(from decoder: Decoder) throws {
        self = try RuntimeDecode(Self.self, from: decoder)
    }
}
