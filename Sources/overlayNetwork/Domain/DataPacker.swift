//
//  DataPacker.swift
//  blocks
//
//  Created by よういち on 2024/03/04.
//
//  Not In Use.

import Foundation

/*
 Thank:
 https://stackoverflow.com/a/24147252
 */
struct MyMessage {
    var version : UInt16
    var length : UInt32
    var reserved : UInt16
    var data : [UInt8]
}

/*
 Big Endien
 */
extension Int {     // as 32 bit platform
    func loByte() -> UInt8 { return UInt8(self & 0xFF) }
    func hiByte() -> UInt8 { return UInt8((self >> 8) & 0xFF) }
    func loWord() -> Int16 { return Int16(self & 0xFFFF) }
    func hiWord() -> Int16 { return Int16((self >> 16) & 0xFFFF) }
}

extension UInt {    //  as 32 bit platform
    func loByte() -> UInt8 { return UInt8(self & 0xFF) }
    func hiByte() -> UInt8 { return UInt8((self >> 8) & 0xFF) }
    func loWord() -> UInt16 { return UInt16(self & 0xFFFF) }
    func hiWord() -> UInt16 { return UInt16((self >> 16) & 0xFFFF) }
}

extension Int16 {
    func loByte() -> UInt8 { return UInt8(self & 0xFF) }
    func hiByte() -> UInt8 { return UInt8((self >> 8) & 0xFF) }
}

extension UInt16 {
    func loByte() -> UInt8 { return UInt8(self & 0xFF) }
    func hiByte() -> UInt8 { return UInt8((self >> 8) & 0xFF) }
}

class DataPacker {
//    class func pack(format: String, values: AnyObject...) -> String? {
    class func pack(format: String, values: Any...) -> String? {
        var bytes = [UInt8]()
        var index = 0
        for char in format {
            let value : Any = values[index]
            index += 1
            switch(char) {
            case "h":   //2 Byte = short int signed
                if let intValue = value as? Int16 {
                    bytes.append(intValue.loByte())
                    bytes.append(intValue.hiByte())
                }
            case "H":   //2 Byte = short int unsigned
                if let uintValue = value as? UInt16 {
                    bytes.append(uintValue.loByte())
                    bytes.append(uintValue.hiByte())
                }
            case "i":   //4 Byte = long int signed as 32 bit platform
                if let intValue = value as? Int {
                    bytes.append(intValue.loWord().loByte())
                    bytes.append(intValue.loWord().hiByte())
                    bytes.append(intValue.hiWord().loByte())
                    bytes.append(intValue.hiWord().hiByte())
                }
            case "I":   //4 Byte = long int unsigned as 32 bit platform
                if let uintValue = value as? UInt {
                    bytes.append(uintValue.loWord().loByte())
                    bytes.append(uintValue.loWord().hiByte())
                    bytes.append(uintValue.hiWord().loByte())
                    bytes.append(uintValue.hiWord().hiByte())
                }
            default:
                Log("Unrecognized character: \(char)")
            }
        }
//        return String.stringWithBytes(bytes, length: bytes.count, encoding: NSASCIIStringEncoding)
        return String(bytes: bytes, encoding: .ascii)
    }
}

func test() {
    let packedString = DataPacker.pack(format: "HHI", values: 0x100, 0x0, 512)
    print(packedString ?? "nil")
}
