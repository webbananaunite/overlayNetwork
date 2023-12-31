//
//  OverlayNetworkBinaryAddress.swift
//  blocks
//
//  Created by よういち on 2023/12/14.
//  Copyright © 2023 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

public protocol OverlayNetworkBinaryAddress {
    func compose() -> OverlayNetworkBinaryAddress
    var isValidEmail: Bool
}

public extension Data: OverlayNetworkBinaryAddress {
    func compose() -> OverlayNetworkBinaryAddress {
        return Data.DataNull
    }
}

/*
 Using
 
 var a: OverlayNetworkBinaryAddress = "abc"
 a.compose()
 */
