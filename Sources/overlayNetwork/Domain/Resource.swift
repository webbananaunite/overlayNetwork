//
//  Resource.swift
//  blocks
//
//  Created by よういち on 2023/07/05.
//  Copyright © 2023 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

open class Resource: Node {
    public init?(string: String) {
        Log()
        guard let (nodeAddress, _) = Dht.hash(string: string), let nodeAddress = nodeAddress else {
            return nil
        }
        super.init(dhtAddressAsHexString: nodeAddress)
        Log("dhtAddressAsHexString:\(dhtAddressAsHexString)")
        Dump(binaryAddress)
    }
    
    required public init(binaryAddress: OverlayNetworkBinaryAddress) {
        super.init(binaryAddress: binaryAddress)
    }
    
    required public init(binaryAddress: OverlayNetworkBinaryAddress, premiumCommand: CommandProtocol = Command.other) {
        super.init(binaryAddress: binaryAddress, premiumCommand: premiumCommand)
    }
    
    required public init?(dhtAddressAsHexString: OverlayNetworkAddressAsHexString, premiumCommand: CommandProtocol = Command.other) {
        super.init(dhtAddressAsHexString: dhtAddressAsHexString, premiumCommand: premiumCommand)
    }
    
    required public init?(ownNode ip: IpaddressV4Protocol, port: Int, premiumCommand: CommandProtocol = Command.other) {
        super.init(ownNode: ip, port: port, premiumCommand: premiumCommand)
    }
}
