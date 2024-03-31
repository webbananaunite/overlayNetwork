//
//  ContiguousArray<CChar>+.swift
//
//
//  Created by よういち on 2024/03/06.
//

import Foundation

public extension ContiguousArray<CChar> {
    var toString: String {
        return self.withUnsafeBufferPointer {
            String(cString: $0.baseAddress!)
        }
    }
}
