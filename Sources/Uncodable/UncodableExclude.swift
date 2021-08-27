//
//  File.swift
//  
//
//  Created by Eric Rabil on 8/25/21.
//

import Foundation

@propertyWrapper
struct Excluded<T> {
    var wrappedValue: T
    
    init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}
