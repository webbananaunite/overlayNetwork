//
//  OverlayNetworkBinaryAddress.swift
//  blocks
//
//  Created by よういち on 2023/12/14.
//  Copyright © 2023 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

public protocol OverlayNetworkBinaryAddress {
    static var binaryAddressBits: Int {
        get
    }
    static var binaryAddressBytes: Int {
        get
    }
    func hexAsData() -> String
    static var OverlayNetworkBinaryAddressNull: OverlayNetworkBinaryAddress {
        get
    }
    func moduloAsData(exponentOf2: UInt) -> OverlayNetworkBinaryAddress
    static var ByteBits: UInt {
        get
    }
    func bitShiftRightAsData(_ bits: UInt) -> (OverlayNetworkBinaryAddress, OverlayNetworkBinaryAddress)
    func subtractAsData(exponent: UInt) -> OverlayNetworkBinaryAddress
    static var ModuloAsExponentOf2: UInt {
        get
    }
    static var Radix: UInt {
        get
    }
    static var LSBIndex: UInt {
        get
    }
    static var Modulo: Data {
        get
    }
    var countAsData: Int {
        get
    }
    var toData: Data {
        get
    }
    func decrementAsData(index: UInt, decrementValue: UInt8, turnaround: Bool?, savedIndex: UInt?, savedDecrementValue: UInt8?, carryDown: Bool) -> (OverlayNetworkBinaryAddress, String)
    static var byteBits: Int {
        get
    }
    func addAsData(exponent: UInt) -> OverlayNetworkBinaryAddress
    func greaterThan(_ rhs: OverlayNetworkBinaryAddress) -> Bool
    func greaterEqual(_ rhs: OverlayNetworkBinaryAddress) -> Bool
    func lessThan(_ rhs: OverlayNetworkBinaryAddress) -> Bool
    func lessEqual(_ rhs: OverlayNetworkBinaryAddress) -> Bool
    func inRangeAsData(intervalType: Interval, to upperAddress: OverlayNetworkBinaryAddress, about targetNode: OverlayNetworkBinaryAddress) -> Bool
    func inRangeAsData(intervalType: Interval, to upperAddress: Node?, about targetNode: Node?) -> Bool
}

/*
 Dataが()開区間の範囲に含まれるか
     開区間
     (self, address): self < x < upperAddress
     
     ex.
     (30013, 30051)
 
 parenthesis (): Exclude
 square bracket []: Include
 */
public enum Interval: String {
    case include = "[]"         //closed interval
    case exclude = "()"         //open interval
    case includeExclude = "[)"  //half-open interval
    case excludeInclude = "(]"  //half-open interval
    
    /*
     Comparing UInt8 Each Other.
     */
    func contain(target: UInt8, start: UInt8, end: UInt8) -> Bool {
        switch self {
        case .exclude:
            if target > start && target < end {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .include:
            if target >= start && target <= end {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .includeExclude:
            if target >= start && target < end {
                Log(true)
                return true
            } else {
                Log(false)
                return false
            }
        case .excludeInclude:
            if target > start && target <= end {
                Log()
                return true
            } else {
                Log()
                return false
            }
        }
    }
    
    func containLowerSide(target: UInt8, start: UInt8) -> Bool {
        switch self {
        case .exclude:
            if target > start {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .include:
            if target >= start {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .includeExclude:
            if target >= start {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .excludeInclude:
            if target > start {
                Log()
                return true
            } else {
                Log()
                return false
            }
        }
    }
    
    func containUpperSide(target: UInt8, end: UInt8) -> Bool {
        switch self {
        case .exclude:
            if target < end {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .include:
            if target <= end {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .includeExclude:
            if target < end {
                Log()
                return true
            } else {
                Log()
                return false
            }
        case .excludeInclude:
            if target <= end {
                Log()
                return true
            } else {
                Log()
                return false
            }
        }
    }

}

extension Data: OverlayNetworkBinaryAddress {
    public static var binaryAddressBits: Int = 512
    public static var binaryAddressBytes: Int = 64

    public var isValid: Bool {
        get {
            self.count == Data.binaryAddressBytes
        }
    }
    
    public func hexAsData() -> String {
        self.hex()
    }

    public static var OverlayNetworkBinaryAddressNull: OverlayNetworkBinaryAddress = Data([UInt8.zero]) as OverlayNetworkBinaryAddress
    /*
     -Abstract
     Make Modulo Arithmetic by 2^{exponentOf2}.

     Data is Positive Value(+: MSB != 0x00):
        Make the Data Shift Right by Exponent Power of 2.
     
     Data is Negative Value(-: MSB == 0x00):
        Make Subtract Modulo from the Data.

     -Restrict:
        {exponentOf2} is multiple of 8.
     */
    public func moduloAsData(exponentOf2: UInt) -> OverlayNetworkBinaryAddress {
        Log()
        return self.modulo(exponentOf2: exponentOf2) as OverlayNetworkBinaryAddress
    }

    /*
     Dividing Arithmetic by Make self Shift Right {bits} bit.
     
     Data UInt8 Array is did Arithmetic As Little Endian.
        ex. Data[UInt8](64)
            Data[0] : Least significant digit
            Data[63]: Most significant digit
     
     Restricted Condition:
        {bits} is multiple of 8.
     */
    public static var ByteBits: UInt = UInt(UInt8.bitWidth)
    public func bitShiftRightAsData(_ bits: UInt) -> (OverlayNetworkBinaryAddress, OverlayNetworkBinaryAddress) {
        return self.bitShiftRight(bits)
    }

    /*
     -Abstract
     Make Subtracting 2^exponent into Data[UInt8]
     
     Take Data index and subtracting value into Data[UInt8]
     with Detecting UnderFlow processes.
     
     -Arguments
     exponent:
        Exponent Power of 2
     
     -Return
        if MostSignificantByte is UInt8(00), Indicate Negative Value.
     */
    public func subtractAsData(exponent: UInt) -> OverlayNetworkBinaryAddress {
        return self.subtract(exponent: exponent) as OverlayNetworkBinaryAddress
    }
    
    /*
     -Abstract
     Only Decrementation for One Digit Recursively, Applying Digit Carry Down.
     Radix: 256
     
     -Restruct
     self:
        MSB must Positive Value (as MSB value must Except 0x00).
     
     -Arguments
     index:
        Data[]'s subscript
     decrementValue:
        Power of 2 value within  UInt8
     turnaround:
        Operation Direction
        初回呼び出された時に内部で設定する
     
        true: decrementValue*2^index > abs(self)
            decrementValue*2^index contained 0...self
            Subtract decrementValue - self[index]
        false: decrementValue*2^index <= abs(self)
            decrementValue*2^index uncontained 0...self
            Subtract self[index] - decrementValue

     -Return
        if MostSignificantByte is UInt8(00), Indicate Negative Value.
     */
    public static var ModuloAsExponentOf2: UInt = 512
    public static var Radix: UInt = 256
    public static var LSBIndex: UInt = 0
    public static var Modulo: Data = Data(repeating: 0, count: Int(ModuloAsExponentOf2 / 8)) + Data(repeating: 1, count: 1)
    public var countAsData: Int {
        self.count
    }
    //New Type Rewrite function
    public func decrementAsData(index: UInt, decrementValue: UInt8, turnaround: Bool? = nil, savedIndex: UInt? = nil, savedDecrementValue: UInt8? = nil, carryDown: Bool = false) -> (OverlayNetworkBinaryAddress, String) {
        return self.decrement(index: index, decrementValue: decrementValue, turnaround: turnaround, savedIndex: savedIndex, savedDecrementValue: savedDecrementValue, carryDown: carryDown)
    }
    
    /*
     -Abstract
     Radix: 256 (0b100000000)   0x10
     
     Make adding 2^{exponent} into Data[UInt8] as Radix 256 digits with Little Endian.

     -Example
     2^1
     remainder
     0b10   0x02
     0b01 << (1-index*8)

     index
     0
     
     Data[index] += remainder

     ---
     2^3
     remainder
     0b1000   0x08
     0b01 << (3-index*8)
     
     index
     0
     
     Data[index] += remainder

     ---
     2^16
     remainder
     0b0   0x00
     0b01 << (16-index*8)

     index
     2

     Data[index] += remainder

     ---
     2^512
     remainder
     0b10{512}
     0b01 >> (512-index*8)

     index
     64
     Add New Byte into [UInt8](64)

     Data[index] += remainder
     */
    public static var byteBits: Int = UInt8.bitWidth    //8
    public func addAsData(exponent: UInt) -> OverlayNetworkBinaryAddress {
        return self.add(exponent: exponent)
    }

    /*
     true:
       rhs
     [0 --- self)
     =
     rhs < self
     =
     self > rhs
     
     false:
     self <= rhs
     */
    public func greaterThan(_ rhs: OverlayNetworkBinaryAddress) -> Bool {
        Log()
        return Data.DataNull.inRange(intervalType: .includeExclude, to: self, about: rhs.toData)
    }

    /*
     true:
       rhs
     [0 --- self]
     =
     rhs <= self
     =
     self >= rhs
     
     false:
     self < rhs
     */
    public func greaterEqual(_ rhs: OverlayNetworkBinaryAddress) -> Bool {
        Log()
        return Data.DataNull.inRange(intervalType: .include, to: self, about: rhs.toData)
    }

    /*
     true:
     self < rhs

     false:
       rhs
     [0 --- self]
     =
     rhs <= self
     =
     self >= rhs
     */
    public func lessThan(_ rhs: OverlayNetworkBinaryAddress) -> Bool {
        Log()
        return !Data.DataNull.inRange(intervalType: .include, to: self, about: rhs.toData)
    }

    /*
     true:
     self <= rhs

     false:
       rhs
     [0 --- self)
     =
     rhs < self
     =
     self > rhs
     */
    public func lessEqual(_ rhs: OverlayNetworkBinaryAddress) -> Bool {
        Log()
        return !Data.DataNull.inRange(intervalType: .includeExclude, to: self, about: rhs.toData)
    }

    /*
     Make Check {about} is between {self} and {to} based on {IntervalType}.
     
     Regardless Negative, Positive.
     */
    public var toData: Data {
        self
    }
    public func inRangeAsData(intervalType: Interval, to upperAddress: OverlayNetworkBinaryAddress, about targetNode: OverlayNetworkBinaryAddress) -> Bool {
        return self.inRange(intervalType: intervalType, to: upperAddress.toData, about: targetNode.toData)
    }

    public func inRangeAsData(intervalType: Interval, to upperAddress: Node?, about targetNode: Node?) -> Bool {
        return self.inRange(intervalType: intervalType, to: upperAddress, about: targetNode)
    }
}
