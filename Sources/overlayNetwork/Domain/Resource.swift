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
    
    required public convenience init?(ipAndPort: String) {
        if let (ip, portNum) = Node.extractIpAndPort(ipAndPort) {
            Log("\(ip), \(portNum)")
            self.init(ip: ip, port: portNum)
        } else {
            return nil
        }
    }
    required public init?(ip: IpaddressV4Protocol, port: Int = Node.myPort, premiumCommand: CommandProtocol = Command.other) {
        Log()
        super.init(ip: ip, port: port, premiumCommand: premiumCommand)
    }
    
    /*
     Nodeとしては使えない
     DHT address保存のために使う
     */
    required public init?(dhtAddressAsHexString: OverlayNetworkAddressAsHexString) {
        super.init(dhtAddressAsHexString: dhtAddressAsHexString)
    }
    
    required public init(binaryAddress: OverlayNetworkBinaryAddress) {
        super.init(binaryAddress: binaryAddress)
    }

    required public init?(binaryAddress: OverlayNetworkBinaryAddress, ip: IpaddressV4, port: Int = Node.myPort) {
        super.init(binaryAddress: binaryAddress, ip: ip, port: port)
    }
    
    required public init?(binaryAddress: OverlayNetworkBinaryAddress, ip: IpaddressV4, port: Int = Node.myPort, premiumCommand: CommandProtocol = Command.other) {
        super.init(binaryAddress: binaryAddress, ip: ip, port: port, premiumCommand: premiumCommand)
    }
    
}
