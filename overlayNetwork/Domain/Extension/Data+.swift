/*
 レイヤー: Domain/Extension
 責任: ハッシュ生成
 */
//
//  Data+.swift
//  EnglishApp
//
import Foundation
import CryptoKit

public extension Data {
    /*
     utf8String:
        Can NOT Signature Data to String.
        Should Use Data#base64EncodedString()
     */
    var utf8String: String? {
        String(data: self, encoding: .utf8)
    }
    var base64String: String {
        self.base64EncodedString()
    }
    var string: String? {
        self.base64String
    }
}

public extension Data {
    var hash: Data {
        Data(SHA512.hash(data: self))
    }

    /*
     Generics Type You Want
     */
    func toInteger<TypeWant>() -> TypeWant {
        self.withUnsafeBytes {
            $0.load(as: TypeWant.self)
        }
    }
    func hashAsInteger<TypeWant>() -> TypeWant {
        Data(SHA512.hash(data: self)).toInteger()
    }

    /*
     SHA512のハッシュを生成しBase64文字列で返す
        ascii 86文字(6bit == ASCII１文字)
     */
    func hashAsBase64() -> String {
        let sha512digest = SHA512.hash(data: self)
        Log(sha512digest)
        return Data(sha512digest).base64String
    }
    /*
     SHA512のハッシュを生成しHex文字列で返す
        ascii 128文字(4bit == Hex１文字)
     */
    func hashAsHex() -> (String, Data) {
        let sha512digest = SHA512.hash(data: self)
        Log(sha512digest)
        Dump(Data(sha512digest))
        return (sha512digest.compactMap {
            String(format: "%02x", $0)
        }.joined(), Data(sha512digest))
    }

    func hex() -> String {
        return self.compactMap {
            String(format: "%02x", $0)
        }.joined()
    }
}

//Thank: https://stackoverflow.com/a/40687742
public extension Data {
    func append(to fileURL: URL, truncate: Bool = false) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            if truncate {
                try fileHandle.truncate(atOffset: 0)
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

public extension Data {
    static let DataNull = Data([UInt8.zero])
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
    func modulo(exponentOf2: UInt) -> Data {
        LogEssential()
        precondition(exponentOf2 % Data.ByteBits == 0, "exponentOf2 must multiple of 8.")
        /*
         if Data[UInt8] is Negative Value (if MSB is 00), Do Other Way.
         */
        var (quotient, remainder) = (Data.DataNull, Data.DataNull)
        if self != Data.DataNull && self[self.count - 1] == 0x00 {
            //self == 負数のとき
            Log("Data is Negative.")
            /*
             self is did arithmetic as Negative Value.
             答がマイナスなら、finger tableに沿って、Moduloから減算して値を求めるrecursivelyに。

             x プラス(MSB != 0x00)になるまでModuloから減算する
             Modulo > Data になるまで減算(Data - Modulo)する

             Ex.)
             Modulo 8の時
                1 - 3
                =-2
                =Modulo(8) - 2
                =6

             Modulo 8の時
                1 - 8
                =-7
                =8-7
                =1

             Modulo 8の時
                1-10
                =-9
                =8-9
                =-1
                =8-1
                =7　プラスになるまでModuloから減算する
             */
            /*
             2^512 - self
             ==
             -(self - 2^512)

             ,so
             Modulo > Data になるまで減算(Data - Modulo)する
             */
            Dump(self)
            remainder = self
            let index = UInt(Int(exponentOf2) / Data.byteBits)
            let data = UInt8(0b01 << (exponentOf2 - index*8))
            Log(index)
            Log(data)
            Dump(remainder)
            Log("<")
            Dump(Data(repeating: 0, count: Int(index)) + Data(repeating: data, count: 1))
            while (remainder.greaterThan(Data(repeating: 0, count: Int(index)) + Data(repeating: data, count: 1))) {
                /*
                 Remainder less than or equal 2^{exponentOf2}.
                 */
                remainder = remainder.subtract(exponent: exponentOf2)
                quotient = quotient.add(exponent: 0)
                Dump(remainder)
                Log("<")
                Dump(Data(repeating: 0, count: Int(index)) + Data(repeating: data, count: 1))
            }
            Log("Made Modulo.")
            Log("quotient, remainder")
            Dump(quotient)
            Dump(remainder)
        } else {
            Log("Data is Positive.")
            (quotient, remainder) = self.bitShiftRight(exponentOf2)
            Log("Made Modulo.")
            Log("quotient, remainder")
            Dump(quotient)
            Dump(remainder)
        }
        return remainder
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
    func bitShiftRight(_ bits: UInt) -> (Data, Data) {
        Log()
        precondition(bits % Data.ByteBits == 0, "Bit must multiple of 8.")

        Log(Data.ByteBits)
        Log(self.count)
        Log("\(bits) < \(UInt(self.count) * Data.ByteBits)")
        var quotient = self
        var remainder = Data.DataNull
        guard bits % Data.ByteBits == 0 && bits < (UInt(self.count) * Data.ByteBits) else {
            Log()
            return (remainder, quotient)
        }

        /*
         Right shift by Byte(8 bit)
         */
        let shiftBytes: UInt = bits / Data.ByteBits
        let dividendBytes: UInt = UInt(self.count)
        Log(shiftBytes)
        Log(dividendBytes)
        if shiftBytes > 0 {
            Log()
            Log("self: \(shiftBytes)...\(dividendBytes - 1)")
            Log("self: ...\(shiftBytes - 1)")
            quotient = self[shiftBytes...(dividendBytes - 1)]
            remainder = self[...(shiftBytes - 1)]
        }
        return (quotient, remainder)
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
    func subtract(exponent: UInt) -> Data {
        LogEssential()
        Dump(self)
        var newSelf = self
        LogEssential(exponent)
        let index = UInt(Int(exponent) / Data.byteBits)
        let remainder = UInt8(0b01 << (exponent - index*8))
        Log(index)
        Log(remainder)
        var sign: String
        (newSelf, sign) = newSelf.decrement(index: index, decrementValue: remainder)
        Dump(newSelf)
        return newSelf
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
    //New Type Rewrite function
    func decrement(index: UInt, decrementValue: UInt8, turnaround: Bool? = nil, savedIndex: UInt? = nil, savedDecrementValue: UInt8? = nil, carryDown: Bool = false) -> (Data, String) {Log("---")
        LogEssential(index)
        Log(savedIndex)
        Dump(self)
        Log(decrementValue)
        Log(turnaround ?? "nil")
        var newTurnaround: Bool
        var newSelf = self
        var sign: String
        if let turnaround = turnaround {
            Log()
            newTurnaround = turnaround
        } else {
            Log()
            /*
             if decrementValue*2^index == 0...abs(self)
                as decrementValue*2^index <= abs(self)
                turnaround = false
                self - decrementValue

             ,otherwise
                turnaround = true
                decrementValue - self
             */
            Dump(Data.DataNull)
            Dump(self)
            Dump(Data(repeating: 0, count: Int(index)) + Data(repeating: decrementValue, count: 1))
            newTurnaround = !Data.DataNull.inRange(intervalType: .include, to: self, about: Data(repeating: 0, count: Int(index)) + Data(repeating: decrementValue, count: 1))
            Log(newTurnaround)
            if newTurnaround {
                let newIndex = Data.LSBIndex
                (newSelf, sign) = newSelf.decrement(index: newIndex, decrementValue: newIndex == index ? decrementValue : 0, turnaround: newTurnaround, savedIndex: index, savedDecrementValue: decrementValue)
                Log()
                return (newSelf, sign)
            }
        }
        Log(newTurnaround)
        if Int(index) > (newSelf.count - 1) {
            Log()
            newSelf += (0..<(Int(index) - (newSelf.count - 1))).map {_ in Data.DataNull}.joined()
        }
        Dump(newSelf)

        /*
         Data[index] - val = ans
         if ans == Positive
            Data[index] = ans
         else
            //１の位から減算しなおす
            //再帰手続きする
            decrement2(0, 256+Data[index])
         29382
        -30000
        ------
         00618

         29382
        -30001
        ------
         00619

         29382
        -2999(10)

         20382
        - 1000
        ------

         0x 92894379...
       - 0x  3000000...   //Only 2^n
       ----------------


         */
        var lhs, rhs: UInt8
        if newTurnaround {
            Log("T decrementValue - self[index]")
            lhs = decrementValue
            rhs = newSelf[Int(index)]
            sign = "-"
        } else {
            Log("self[index] - decrementValue")
            lhs = newSelf[Int(index)]
            rhs = decrementValue
            sign = "+"
        }
        Log("(\(index)) \(lhs) - \(rhs) turnaround:\(newTurnaround) carryDown:\(carryDown) savedIndex:\(savedIndex)")
        let decrementedByte: Int = Int(lhs) - Int(rhs)

        Log(decrementedByte)
        Log(carryDown)
        if ((newTurnaround && index == savedIndex) || (!newTurnaround && !carryDown && decrementedByte >= 0) || (carryDown && decrementedByte > 0)) {
            Log("Positive result OR index == savedIndex")
            /*
             Positive Result
             */
            if carryDown {
                newSelf[Int(index)] = UInt8(decrementedByte - 1)
            } else {
                newSelf[Int(index)] = UInt8(decrementedByte)
            }
        } else {
            Log("Negative result OR CarryDown(decremented <= 0)")
            /*
             Negative Result

             Subtract Sequentialy from LSB.
             */
            Log()
            let carryDownValue: UInt = index == Data.LSBIndex ? Data.Radix : Data.Radix - 1
            Log(carryDownValue)
            if newTurnaround {
                Log("T \(carryDownValue) + \(UInt(decrementValue)) - \(UInt(newSelf[Int(index)]))")
                newSelf[Int(index)] = UInt8(carryDownValue + UInt(decrementValue) - UInt(newSelf[Int(index)]))
            } else {
                Log("\(carryDownValue) + \(UInt(newSelf[Int(index)])) - \(UInt(decrementValue))")
                newSelf[Int(index)] = UInt8(carryDownValue + UInt(newSelf[Int(index)]) - UInt(decrementValue))
            }
            var nowDecrementValue: UInt8
            if let value = savedDecrementValue {
                Log()
                nowDecrementValue = value - 1
            } else {
                Log()
                nowDecrementValue = 0
            }
            Log(index)
            Log(savedIndex)
            Log(nowDecrementValue)
            Log(savedDecrementValue)
            (newSelf, sign) = newSelf.decrement(index: UInt(index + 1), decrementValue: index + 1 == savedIndex ? nowDecrementValue : 0, turnaround: newTurnaround, savedIndex: savedIndex, savedDecrementValue: savedDecrementValue, carryDown: (turnaround == nil || turnaround == false) ? true : false)
        }
        return (newSelf, sign)
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
    func add(exponent: UInt) -> Data {
        var newSelf = self
        /*
         selfが負数(MSB == 0x00)の場合に対応する
             self(負数 MSB: 0x00) + 2^512

           - 0x092894379...
           + 0x100000000...   //Only 2^n
           ----------------
             ↓
            MostSignificantBit Digit Carry Down
           - 0x 92894379...
           + 0x fffffff(16)...
           ----------------

         2^512 - self
         =
         -(self - 2^512)

         8 - 1
         =7
         -(1 - 8)
         =7


         1-10
         =-9
         =8-9
         =-1
         =8-1
         =7　プラスになるまでModuloから減算する　←符号はないので、判断をどうするか？

         1-10
         =-9
         =-(9-8)
         =-1
         =-(1-8)
         =7　プラス(MSB != 0x00)になるまでModuloから減算する
         */
        let index = Int(exponent / UInt(Data.byteBits))
        let remainder = UInt8(0b01 << (exponent - UInt(index*8)))
        newSelf = newSelf.increment(index: index, incrementValue: remainder)
        return newSelf
    }

    /*
     Radix: 256 (0b100000000)   0x10

     Make Adding {incrementValue} into Data[UInt8]({index}) as Radix 256 digits as Little Endian with Detecting Overflow Recursively.
     */
    func increment(index: Int, incrementValue: UInt8) -> Data {
        var newSelf = self
        if (index - (newSelf.count - 1)) > 0 {
            newSelf += (0..<(index - (newSelf.count - 1))).map {_ in Data.DataNull}.joined()
        }
        let incrementedByte:UInt = UInt(newSelf[index]) + UInt(incrementValue)
        newSelf[index] = UInt8(incrementedByte & 0b11111111)
        if incrementedByte & 0b11111111_00000000 != 0 {
            /*
             Detected Overflow, Do Carry Up Digit
             */
            if index + 1 <= newSelf.count - 1 {
                let incrementValue = UInt8((incrementedByte >> 8) & 0b11111111)
                newSelf = newSelf.increment(index: index + 1, incrementValue: incrementValue)
            } else {
                newSelf = newSelf + Data([UInt8((incrementedByte >> 8) & 0b11111111)])
            }
        }
        return newSelf
    }

    /*
     Notice:
     The Function Result is Boolean.

     Return:
     true: lhs & rhs != 0
     false: lhs & rhs == 0

     Data[UInt8] As Little Endian.
     */
    @inlinable
    static func &(lhs: Data, rhs: Data) -> Bool {
        Log()
        Log("&(lhs:rhs:)->Bool")
        Dump(lhs)
        Dump(rhs)
        var index = -1
        let and = lhs.reduce(false) { //index: 0..<lhs.count
            index += 1
            print("index:\(index) lhs: \(lhs[index]) rhs: \(rhs[index])")
            if (rhs.count - 1) < index {
                return $0 || false
            } else {
                return $0 || ($1 & rhs[index] != 0)
            }
        }
        return and
    }
}

public extension Data {
    /*
     Make Check {about} is between {self} and {to} based on {IntervalType}.

     Regardless Negative, Positive.
     */
    func inRange(intervalType: Interval, to upperAddress: Data, about targetNode: Data) -> Bool {
        LogEssential(intervalType)
        LogEssential("lower:")
        LogEssential(self.hex())
        LogEssential("upper:")
        LogEssential(upperAddress.hex())
        LogEssential("about:")
        LogEssential(targetNode.hex())
        if self == Data.DataNull {
            Log()
        } else {
            Log()
            if upperAddress.greaterThan(self) {
                Log()
            } else {
                Log("Value is UpSide Down.")
                Log("OutRange.")
                return false
            }
        }
        Log()
        var reservedResult = false
        var upperEqualBit = Data.DataNull, lowerEqualBit = Data.DataNull   //Bit Flugs 1,2,4,8,...64,65
        var upperEqual = false, lowerEqual = false
        Log()

        /*
         Check In the Range by digit, Significant Digit (Decimal[4]) First.
         */
        let indexMax = upperAddress.count >= targetNode.count ? upperAddress.count : targetNode.count
        var targetData = UInt8(0)
        var lowerData = UInt8(0)
        var upperData = UInt8(0)
        var lastIndex = 0

        for index in (0..<indexMax).reversed() {
            LogEssential("index: \(index)")
            targetData = targetNode.count <= index ? Data.DataNull[0] : targetNode[index]
            lowerData = self.count <= index ? Data.DataNull[0] : self[index]
            upperData = upperAddress.count <= index ? Data.DataNull[0] : upperAddress[index]
            lowerEqual = false
            upperEqual = false
            Log("target: \(targetData)")
            Log("start: \(lowerData)")
            Log("to: \(upperData)")

            var allBitsOnSoFar = Data.DataNull
            if index + 1 == indexMax {
            } else {
                let indexSoFar = index + 1
                Log(indexSoFar)
                allBitsOnSoFar = (indexSoFar..<indexMax).reversed().reduce(Data.DataNull) {
                    $0.add(exponent: UInt($1))
                }
            }
            Log("index: \(index)")
            Dump(allBitsOnSoFar)
            Dump(lowerEqualBit)
            Dump(upperEqualBit)
            if lowerEqualBit == allBitsOnSoFar {
                Log()
                if targetData == lowerData {
                    Log("equal lower")
                    lowerEqual = true
                    //Flagging by Bit (2^0 2^1 2^2 2^3 2^4 2^5 2^6 ... 2^65... in [UInt8])
                    lowerEqualBit = lowerEqualBit.add(exponent: UInt(index))
                    Dump(lowerEqualBit)
                }
            }
            if upperEqualBit == allBitsOnSoFar {
                Log()
                if targetData == upperData {
                    Log("equal upper")
                    upperEqual = true
                    //Flagging by Bit (2^0 2^1 2^2 2^3 2^4 2^5 2^6 ... 2^65... in [UInt8])s
                    upperEqualBit = upperEqualBit.add(exponent: UInt(index))
                    Dump(upperEqualBit)
                }
            }
            Log()
            Dump(lowerEqual)
            Dump(upperEqual)
            Dump(targetData)
            Dump(lowerData)
            Dump(upperData)
            if intervalType.contain(target: targetData, start: lowerData, end: upperData) {
                Log()
                if lowerEqual || upperEqual {
                    Log()
                    /*
                     Suspend the Decision.

                     As Same Data at the Index, Go to Next Index.
                     */
                } else {
                    Log()
                    reservedResult = true
                }
            } else {
                Log()
            }
            if lowerEqual || upperEqual {
                Log()
                /*
                 Suspend the Decision.

                 As Same Data at the Index, Go to Next Index.
                 */
            } else {
                Log()
                lastIndex = index
                break
            }
        }
        Log()

        /*
         if Same Data for Lower and Target, or Upper and Target,
            Decide whether in Range.
         */
        let allBitsOn = (0..<upperAddress.count).reversed().reduce(Data.DataNull) {
            $0.add(exponent: UInt($1))
        }

        if lowerEqualBit == allBitsOn {
            /*
             if Same All Digits for Lower so far
             */
            Log("targetData.allDigits === lowerAddress.allDigits")
            Dump(lowerEqualBit)
            Dump(allBitsOn)

            if intervalType == .include || intervalType == .includeExclude {
                Log("Equal Lower -inRange true")
                Log("InRange.")
                return true
            } else {
                Log("Equal Lower -inRange false")
                Log("OutRange.")
                return false
            }
        }
        if upperEqualBit == allBitsOn {
            /*
             if Same All Digits for Upper so far
             */
            Log("targetData.allDigits === upperAddress.allDigits")
            Dump(upperEqualBit)
            Dump(allBitsOn)
            if intervalType == .include || intervalType == .excludeInclude  {
                Log("Equal Upper -inRange true")
                Log("InRange.")
                return true
            } else {
                Log("Equal Upper -inRange false")
                Log("OutRange.")
                return false
            }
        }

        /*
         ずっと同じバイト値で
         containでない値があった場合


         ok(1) false
         1000000000000000000
         ?
         0000000000000000000
         ~
         0000000000000000000

         ok(1) true
         9000000000000000000
         ?
         8000000000000000000
         ~
         0000000000000000001

         (1')
         1000000000000003000
         ?
         2000000000000002000
         ~
         0000000000000000001

         (2)
         0000000092333333
         :
         0000000001333333
         ~
         0000000003333333

         途中でinrangeバイトがあって
         その後range外になった場合
         include
         0000000051111111
         :
         0000000081111111
         ~
         0000000003333333

         include
         0000000051111151
         :
         0000000081111111
         ~
         0000000003333353

         includeExclude
         1000000000000000000
         ?
         0000000000000000000
         ~
         0000000000000000001

         */
        Log(lastIndex)
        if reservedResult {
            Log("Be in Range.")
            Log("InRange.")
            return true
        } else {
            Log()
            if lastIndex + 1 == indexMax {
                Log("Out of Range.")
                Log("OutRange.")
                return false
            }
            let indexSoFar = lastIndex + 1
            Log(indexSoFar)
            let allBitsOnSoFar = (indexSoFar..<indexMax).reversed().reduce(Data.DataNull) {
                $0.add(exponent: UInt($1))
            }
            Dump(allBitsOnSoFar)
            Dump(lowerEqualBit)

            if lowerEqualBit == allBitsOnSoFar && upperEqualBit != allBitsOnSoFar {
                Log()
                if intervalType == .include || intervalType == .includeExclude {
                    Log()
                    Dump(targetData)
                    Dump(lowerData)
                    if targetData >= lowerData {
                        Log("Be in Range.")
                        Log("InRange.")
                        return true
                    }
                } else if intervalType == .exclude || intervalType == .excludeInclude {
                    Log()
                    Dump(targetData)
                    Dump(lowerData)
                    if targetData > lowerData {
                        Log("Be in Range.")
                        Log("InRange.")
                        return true
                    }
                }
            }
            Dump(upperEqualBit)
            if upperEqualBit == allBitsOnSoFar && lowerEqualBit != allBitsOnSoFar {
                Log()
                if intervalType == .include || intervalType == .excludeInclude  {
                    Log()
                    Dump(targetData)
                    Dump(upperData)
                    if targetData <= upperData {    //#pending この判定が間違っている
                        Log("Be in Range.")
                        Log("InRange.")
                        return true
                    }
                } else if intervalType == .exclude || intervalType == .includeExclude {
                    Log()
                    Dump(targetData)
                    Dump(upperData)
                    if targetData < upperData {
                        Log("Be in Range.")
                        Log("InRange.")
                        return true
                    }
                }
            }
            Log("Out of Range.")
            Log("OutRange.")
            return false
        }
    }

    func inRange(intervalType: Interval, to upperAddress: Node?, about targetNode: Node?) -> Bool {
        LogEssential()
        guard let targetNode = targetNode, let upperAddress = upperAddress else {
            LogEssential()
            Log("the Node OutRange.")
            return false
        }

        return self.inRange(intervalType: intervalType, to: upperAddress.binaryAddress.toData, about: targetNode.binaryAddress.toData)
    }
}
