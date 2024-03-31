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

    static func getIFAddresses() -> [String]
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
    
    /*
     Thank:
     https://stackoverflow.com/a/25627545
     */
    static func getIFAddresses() -> [String] {
        var addresses = [String]()

        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        guard let firstAddr = ifaddr else { return [] }

        // For each interface ...
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let name = String(cString:ptr.pointee.ifa_name)
            let addr = ptr.pointee.ifa_addr.pointee

            // Check for running IPv4, IPv6 interfaces. Skip the loopback interface.
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {   //if addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) {
                    Log(name)
                    if(name == "en0" || name == "en3") { //wifi     //macos13.3: en3
                        // Convert interface address to a human readable string:
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if (getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count),
                                        nil, socklen_t(0), NI_NUMERICHOST) == 0) {
                            let address = String(cString: hostname)
                            addresses.append(address)
                        }
                    }
                }
            }
        }

        freeifaddrs(ifaddr)
        #if DEBUG
//        addresses = ["100.1.1.255"] //test hashed text
        #endif
        Log(addresses)
        return addresses
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
