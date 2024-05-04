//
//  IpaddressV4.swift
//  blocks
//
//  Created by よういち on 2021/07/05.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

public protocol IpaddressV4Protocol {
    static var IpAddressRegionCount: Int {
        get
    }
    var regions: [String] {
        get set
    }
    
    static var null: IpaddressV4Protocol {
        get
    }
    
    init?()

    static func validIp(ipAddressString: String) -> Bool
    static func validDigit(digits: [String]) -> Bool
    func toString() -> String
}

public extension IpaddressV4Protocol {
    static var IpAddressRegionCount: Int {
        4
    }
    
    static var null: IpaddressV4Protocol {
        Self("0.0.0.0")!
    }
    
    init?(regions: [String]) {
        self.init()
        if !Self.validDigit(digits: regions) {
            return nil
        }
        
        self.regions = regions
    }
    
    init?(ipAddressString: String) {
        self.init()
        let ipDigits = ipAddressString.components(separatedBy: ".")
        guard Self.validDigit(digits: ipDigits) else {
            return nil
        }
        self.regions = ipDigits
    }

    init?(_ ipAddressString: String) {
        self.init()
        let ipDigits = ipAddressString.components(separatedBy: ".")
        guard Self.validDigit(digits: ipDigits) else {
            return nil
        }
        self.regions = ipDigits
    }
    
    static func validIp(ipAddressString: String) -> Bool {
        let ipDigits = ipAddressString.components(separatedBy: ".")
        guard Self.validDigit(digits: ipDigits) else {
            return false
        }
        return true
    }
    
    static func validDigit(digits: [String]) -> Bool {
        //数字３文字以内チェック
        let ipAddressRange = 1...3
        let validDigitCount = digits.filter {
            $0.isNumber() && ipAddressRange.contains($0.count)
        }.count
        
        guard validDigitCount == IpAddressRegionCount else {
            return false
        }
        return true
    }
    
    func toString() -> String {
        return self.regions.reduce("") {
            if self.regions.last == $1 {
                return $0 + $1
            }
            return $0 + $1 + "."
        }
    }
}

public struct IpaddressV4: IpaddressV4Protocol {
    public init?() {
        regions = ["0","0","0","0"]
    }
    
    //v4
    public var regions: [String] {
        didSet {
            if regions.count > Self.IpAddressRegionCount {regions = oldValue}
        }
    }
}
