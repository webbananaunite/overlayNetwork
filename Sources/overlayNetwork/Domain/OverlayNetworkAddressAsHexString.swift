//
//  OverlayNetworkAddressAsHexString.swift
//  overlayNetwork
//
//  Created by よういち on 2023/12/15.
//

import Foundation

public protocol OverlayNetworkAddressAsHexString {
    static var OverlayNetworkAddressAsHexStringNull: OverlayNetworkAddressAsHexString {
        get
    }
    static var SignalingServerMockAddress: OverlayNetworkAddressAsHexString {
        get
    }
    static var dhtAddressAsHexStringLength: Int {
        get
    }
    var toString: String {
        get
    }
    var isValid: Bool {
        get
    }
    func dataAsString(using encoding:ExtendedEncoding) -> OverlayNetworkBinaryAddress?
    func equal(_ value: OverlayNetworkAddressAsHexString) -> Bool
}

extension String : OverlayNetworkAddressAsHexString {
    public static var OverlayNetworkAddressAsHexStringNull: OverlayNetworkAddressAsHexString = "" as OverlayNetworkAddressAsHexString
//    public static var SignalingServerMockAddress = OverlayNetworkAddressAsHexStringNull
    public static var SignalingServerMockAddress: OverlayNetworkAddressAsHexString = String(repeating: "0", count: 128)
    
    public static var dhtAddressAsHexStringLength: Int = 128
    public var toString: String {
        self
    }
    public var isValid: Bool {
        get {
            self.count == String.dhtAddressAsHexStringLength
        }
    }
    public func dataAsString(using encoding:ExtendedEncoding) -> OverlayNetworkBinaryAddress? {
        self.data(using: encoding)
    }
    
    public func equal(_ value: OverlayNetworkAddressAsHexString) -> Bool {
        self.toString == value.toString
    }
}
