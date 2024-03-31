//
//  [CChar]+.swift
//
//
//  Created by よういち on 2024/03/06.
//

import Foundation

public extension [CChar] {
    var toString: String {
        self.withUnsafeBufferPointer { ccharPointer in
            String(cString: ccharPointer.baseAddress!)
        }
    }
}
