/*
 レイヤー: Domain/Extension
 責任: ハッシュ生成
 */
//
//  String+.swift
//  overlayNetwork
//

#if os(macOS) || os(iOS)
import Foundation
import CommonCrypto
#elseif canImport(Glibc)
import Glibc
import Foundation
import Crypto
#elseif canImport(Musl)
import Musl
import Foundation
import Crypto
#elseif os(Windows)
import ucrt
#else
#error("UnSupported platform")
#endif

public enum HashOutputType {
    case hex
    case base64
}

public enum HashType {
    case md5
    case sha1
//    case sha224
    case sha256
    case sha384
    case sha512
    
    var length: Int32 {
#if os(Linux)
        let _ = Data(Insecure.MD5.hash(data: Data()))
#endif
        /*
         cf.
         /swift-crypto/Sources/Crypto/Digests/HashFunctions_SHA2.swift
         */
        switch self {
#if os(macOS) || os(iOS)
            case .md5: return CC_MD5_DIGEST_LENGTH
            case .sha1: return CC_SHA1_DIGEST_LENGTH
//            case .sha224: return CC_SHA224_DIGEST_LENGTH
            case .sha256: return CC_SHA256_DIGEST_LENGTH
            case .sha384: return CC_SHA384_DIGEST_LENGTH
            case .sha512: return CC_SHA512_DIGEST_LENGTH
#elseif os(Linux)
            case .md5: return Int32(Insecure.MD5.byteCount)
            case .sha1: return Int32(Insecure.SHA1.byteCount)
//            case .sha224: return Int32(SHA224.byteCount)
            case .sha256: return Int32(SHA256.byteCount)   /// The number of bytes in a ``SHA256`` digest.
            case .sha384: return Int32(SHA384.byteCount)
            case .sha512: return Int32(SHA512.byteCount)
#endif
        }
    }
}

public enum ExtendedEncoding {
    case hexadecimal
}

public extension String {
    func isNumber() -> Bool {
        return !self.isEmpty && self.rangeOfCharacter(from: NSCharacterSet.decimalDigits.inverted) == nil
    }

    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(self.count - range.lowerBound,
                                             range.upperBound - range.lowerBound))
        return String(self[start..<end])
    }

    subscript(_ range: CountablePartialRangeFrom<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
         return String(self[start...])
    }
}

public extension String {
    /*
     SHA512ハッシュ値を返す
     */
    func hash() -> (String, Data) {
        if let data = self.utf8DecodedData {
            return data.hashAsHex()
        }
        return ("", Data.DataNull)
    }
}

public extension String {
    var data: Data? {
        self.data(using: .utf8)
    }
    var utf8DecodedData: Data? {
        self.data(using: .utf8)
    }
    var base64DecodedData: Data? {
        Data(base64Encoded: self)
    }
    var hexadecimalDecodedData: Data? {
        self.data(using: .hexadecimal)
    }
    var base64DecodedJsonString: String? {
        Log(self.base64DecodedData?.utf8String ?? "")
        return self.base64DecodedData?.utf8String
    }
    
    var toCChar: [CChar]? {
        self.cString(using: .utf8)  //[CChar]
    }
}

public extension String {
    /*
     Thank:
     https://stackoverflow.com/a/56870030
     */
    func data(using encoding:ExtendedEncoding) -> Data? {
        var hexStr = self.dropFirst(self.hasPrefix("0x") ? 2 : 0)
        
        /*
         Hex String length shuld be an even number.
         */
        if hexStr.count % 2 != 0 {
            hexStr = "0" + hexStr
        }

        var newData = Data(capacity: hexStr.count/2)
        
        var indexIsEven = true
        for i in hexStr.indices {
            if indexIsEven {
                let byteRange = i...hexStr.index(after: i)
                guard let byte = UInt8(hexStr[byteRange], radix: 16) else { return nil }
                newData.append(byte)
            }
            indexIsEven.toggle()
        }
        return newData
    }
}

/*
 UTC String to Date

 UTC Formatted String:
    2023-09-06T06:16:41.600Z
 */
public extension String {
    var date: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter.date(from: self)
    }
}

public extension String {
    var removeNewLineChars: String {
        self.replacingOccurrences(of: "\n", with: "")
    }
    
    var removeSpaceCharsAsDelimiter: String {
        self.replacingOccurrences(of: " ", with: "")
    }
    /*
     Void Special Charactors
        Operand Delimiter
        Json formatted representation
     */
    var voidSpecialChars: String {
        var replacedString = self.replacingOccurrences(of: " ", with: "%20")
        replacedString = replacedString.replacingOccurrences(of: "{", with: "%7B")
        return replacedString.replacingOccurrences(of: "}", with: "%7D")
    }

    /*
     CharacterSet:
     ex.
        .newlines
        .whitespaces
     */
    func trim(chars: CharacterSet) -> String {
        self.trimmingCharacters(in: chars)
    }
}
