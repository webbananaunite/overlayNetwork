//
//  UnsafeMutableRawBufferPointer+.swift
//  blocks
//
//  Created by よういち on 2023/11/10.
//  Copyright © 2023 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

/*
 ex.
 UnsafeMutableRawBufferPointer.allocate(byteCount: Stream.MTU, alignment: MemoryLayout<CChar>.alignment)
 */
public extension UnsafeMutableRawBufferPointer {
    /*
     Transform UnsafeMutableRawBufferPointer to String
     */
    func toString(byteLength: Int) -> String {
        //UnsafeMutableRawBufferPointer → UnsafeMutablePointer<Int8>
        let int8Pointer = self.bindMemory(to: Int8.self)
        //UnsafeMutablePointer → UnsafeMutableBufferPointer
        let int8Buffer: UnsafeMutableBufferPointer<Int8> = UnsafeMutableBufferPointer(start: int8Pointer.baseAddress, count: byteLength)
        //UnsafeMutableBufferPointer<Int8> → [CChar]
        let cchars: [CChar] = Array(int8Buffer)
        //[CChar] → String
        let transformedString: String = cchars.withUnsafeBufferPointer { ccharbuffer in
            String(cString: ccharbuffer.baseAddress!)
        }
        return transformedString
    }
    func toString(byteRange: Range<Int>) -> String {
        //UnsafeMutableRawBufferPointer → UnsafeMutablePointer<Int8>
        let int8Pointer = self.bindMemory(to: Int8.self)
        //UnsafeMutablePointer → UnsafeMutableBufferPointer
//        let int8Buffer: UnsafeMutableBufferPointer<Int8> = UnsafeMutableBufferPointer(start: int8Pointer.baseAddress, count: byteLength)
        guard let baseAddress = int8Pointer.baseAddress else {
            return ""
        }
        let int8Buffer: UnsafeMutableBufferPointer<Int8> = UnsafeMutableBufferPointer(start: baseAddress + byteRange.lowerBound, count: byteRange.count)
        //UnsafeMutableBufferPointer<Int8> → [CChar]
        let cchars: [CChar] = Array(int8Buffer)
        //[CChar] → String
        let transformedString: String = cchars.withUnsafeBufferPointer { ccharbuffer in
            String(cString: ccharbuffer.baseAddress!)
        }
        return transformedString
    }
    func toByte(byteLength: Int) -> [CChar] {
        //UnsafeMutableRawBufferPointer → UnsafeMutablePointer<Int8>
        let int8Pointer = self.bindMemory(to: Int8.self)
        //UnsafeMutablePointer → UnsafeMutableBufferPointer
        let int8Buffer: UnsafeMutableBufferPointer<Int8> = UnsafeMutableBufferPointer(start: int8Pointer.baseAddress, count: byteLength)
        //UnsafeMutableBufferPointer<Int8> → [CChar]
        let cchars: [CChar] = Array(int8Buffer)
//        //[CChar] → String
//        let transformedString: String = cchars.withUnsafeBufferPointer { ccharbuffer in
//            String(cString: ccharbuffer.baseAddress!)
//        }
//        return transformedString
        return cchars
    }

}
