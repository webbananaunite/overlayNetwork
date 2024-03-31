//
//  Dht.swift
//  blocks
//
//  Created by よういち on 2021/06/15.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation
import overlayNetworkObjc

open class Dht {
    /*
     実際はDNSのTXTレコードからブートノードを取得する
     in deed, fetch boot node in TXT record in webbanana.org DNS entry.
     */
    static let domain = "webbanana.org"
//    #if DEBUG
    static let txtKeyForBootNode = "stagingbootnode"
//    #else
//    static let txtKeyForBootNode = "bootnode"
//    #endif
    static let txtKeyForSignaling = "signalingServerAddress"

    /*
     inprementation of Chord
     
     Reference
     https://pdos.csail.mit.edu/papers/ton:chord/paper-ton.pdf
     Reference
     https://en.wikipedia.org/wiki/Chord_(peer-to-peer)
     Reference
     https://pdos.csail.mit.edu/papers/chord:sigcomm01/chord_sigcomm.pdf
     
     */
//
//     Address space
//     1   2   3   4   5   6   7   0(Max)
//
//     Finger Table (DHT)
//
//     start : own + 2^n
//
//     interval =範囲 [ : 以上
//     ) : 未満
//
//     successor : startの後に最初に出現するnode
//
//     |n|start|interval|successor(node)|
//     |0|  1  | [1,2)  |  1            |
//     |1|  2  | [2,4)  |  3            |
//     |2|  4  | [4,0)  |  0            |
//
    /*inprementation of Chord*/

    var ownNode: Node?
    
    /*
     (playing baby sitter node)
     Initialize value
     ownNode: base64 sha512 encoded for {IP address port number as String}
     LowerNode: A
     UpperNode: //////////////{86} (86 calacter == 512bitMAX)
     
     sha512 encode for IP address and port number
     ↓
     addressing (hash512bit)
     ↓
     x placed as binary number range (0 to 512bitMAX)
     placed as ascii code sorted ascend
         version1.compare(version2, options: .numeric)
         // .orderedAscending
     ↓
     if bigger than UpperNode, signal to UpperNode
     if smaller than LowerNode, signal to LowerNode
     if between ownNode and UpperNode, set babyNode as UpperNode, and signal to UpperNode
     if between ownNode and LowerNode, set babyNode as LowerNode, and signal to LowerNode

     Linear Model addressing spaced
     UpperNode ... ownNode ... LowerNode
     
     */

    /*
     #unused
     babyNode query to babySitterNode
     */
    class func queryNodeAddress() -> [String] {
//        guard let babySitterNode = getBabysitterNode(ownIpAddressString: nil) else {
//            return []
//        }
//        Log(babySitterNode)//192.168.11.4
        
//        signal(toNode: toNode, babyNode: babyNode, description: description)

        
        //communicate to bybySitterNode by socket
        
        
        
        
        return []
    }

    func signal(toNode: Node, babyNode: Node, description: String) {
        //#pending
        //socket communication to toAddress
        
    }
    
    /*
     How Make DHT Hash (Finger table Entry)
     
     String IP Port
     192.168.0.34:8334
     
     ↓
     Binary
     0xf87f3ce797b4fcdd28b33987751f82
     1f251b61b7f16b31dbf38888e560a2
     ec0c1492fc41332ce86b330cc98cb2
     ac8bdcf482c61703ecfdcd58d7b94f
     2ae29876
     120 + 8 hex文字
     *4bit
     480+32
     =512 bit

     ↓
     Base64 String
     +H8855e0/N0oszmHdR+DHyUbYbfxaz
     Hb84iI5WCi7AwUkvxBMyzoazMMyYyy
     rIvc9ILGFwPs/c1Y17lPKuKYdg==
     90-2文字
     88*6
     =480+48
     =520+8
     528-12
     =516 bit - trim last 4 bit as byte boundary
     =512 bit

     末尾
     Ydg
     011000 011101 100000
     ↓
     0x8_76
     0b1000 0111 0110 (0000)
     
     ↑先頭からのバイト境界で末尾を判断する
     */
    class func hash(ip: IpaddressV4Protocol, port: Int) -> (String?, Data)? {
//        let preHashData = ip.toString() + ":" + String(port)
        let preHashData = [ip.toString(), String(port), String(Int.random(in: Int.min...Int.max)), Date.now.utcTimeString].shuffled().reduce(into: "") {
            $0 += $1
        }
        
        Log("preHashData:\(preHashData)")
        // Sha512ハッシュ値（バイナリ64バイト）をHex(0-F)文字列に変換
        let (hexString, hashed512bitData) = preHashData.hash()
        Log("HexString: \(hexString)")
        Dump(hashed512bitData)

        if hexString != "" {
            return (hexString, hashed512bitData)
        }
        return nil
    }
    
    class func hash(string: String) -> (String?, Data)? {
        let preHashData = string
        Log("preHashData:\(preHashData)")
        // Sha512ハッシュ値（バイナリ64バイト）をHex(0-F)文字列に変換
        let (hexString, hashed512bitData) = preHashData.hash()
        Log("HexString: \(hexString)")
        Dump(hashed512bitData)

        if hexString != "" {
            return (hexString, hashed512bitData)
        }
        return nil
    }
    
    open class func getSignalingServer() -> (String, Int)? {
        Log()
        //get ip port from txt record.
        let signalings = getBootNodesAndStagingServerAddress().1
        guard signalings.count > 0 else {
            return nil
        }
        guard let signalingServerIpAndPort = getBootNodesAndStagingServerAddress().1.randomElement() else {
            return nil
        }
        let signalingServerIpAndPorts = signalingServerIpAndPort.components(separatedBy: ":")
        guard let portNum = Int(signalingServerIpAndPorts[1]), let ip = IpaddressV4(ipAddressString: signalingServerIpAndPorts[0])?.toString() else {
            return nil
        }

        return (ip, portNum)
    }

    open class func getBabysitterNode(ownOverlayNetworkAddress: String) -> Node? {
        //get node in bootNodes for round robin method.
        let nodes = getBootNodesAndStagingServerAddress().0
        guard nodes.count > 0 else {
            return nil
        }
        guard let babysitterOverlayNetworkAddress = nodes.randomElement() else {
            return nil
        }

        /*
         Own Overlay Network Address equal Boot node
            then return nil
         */
        Log(babysitterOverlayNetworkAddress)
        Log(ownOverlayNetworkAddress)
        if babysitterOverlayNetworkAddress == ownOverlayNetworkAddress {
            return nil
        }
        return Node(dhtAddressAsHexString: babysitterOverlayNetworkAddress)
    }

    class func getBootNodesAndStagingServerAddress() -> ([String], [String]) {
        guard let answer = Dns.fetchTXTRecords(domain) as? [String] else {
            return ([], [])
        }
        Log(answer)
        //bootnodeを取得
        let bootNodeTxtRecord = answer.filter {
            $0.components(separatedBy: "=")[0] == txtKeyForBootNode
        }.first
        let stagingServerAddressTxtRecord = answer.filter {
            $0.components(separatedBy: "=")[0] == txtKeyForSignaling
        }.first
        let bootnodes = bootNodeTxtRecord?.components(separatedBy: "=")[1].components(separatedBy: " ")
        Log(bootnodes ?? "")
        let stagingServers = stagingServerAddressTxtRecord?.components(separatedBy: "=")[1].components(separatedBy: " ")
        Log(stagingServers ?? "")
        return (bootnodes ?? [], stagingServers ?? [])
    }

    func holder(key: String) {
        Log()
        
        
    }
    
}

