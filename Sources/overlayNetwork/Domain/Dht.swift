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
    static let txtKey = "stagingbootnode"
//    #else
//    static let txtKey = "bootnode"
//    #endif
    
    public init?() {
        ownNode = Node(ip: IpaddressV4.null, port: 40)
    }

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

    //#unused
    open class func getNodeDhtAddress(ip: IpaddressV4, port: Int) -> [Any] {
        return queryNodeAddress()
    }

    var UpperNode = Node(ip: IpaddressV4.null, port: 1)
    var LowerNode = Node(ip: IpaddressV4.null, port: 0)
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
        let preHashData = ip.toString() + ":" + String(port)
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
    
    open class func getBabysitterNode(ownIpAddressString: String) -> Node? {
        //get node in bootNodes for round robin method.
        let nodes = getBootNodes()
        guard nodes.count > 0 else {
            return nil
        }
        guard let babysitterIpAndPort = getBootNodes().randomElement() else {
            return nil
        }
        let babysitterIpAndPorts = babysitterIpAndPort.components(separatedBy: ":")
        guard let portNum = Int(babysitterIpAndPorts[1]), let ip = IpaddressV4(ipAddressString: babysitterIpAndPorts[0]) else {
            return nil
        }
        
        /*
         Own IP Address equal Boot node
            then return nil
         */
        if babysitterIpAndPorts[0] == ownIpAddressString {
            return nil
        }
        return Node(ip: ip, port: portNum)
    }

    class func getBootNodes() -> [String] {
        guard let answer = Dns.fetchTXTRecords(domain) as? [String] else {
            return []
        }
        Log(answer)
        //bootnodeを取得
        let bootNodeTxtRecord = answer.filter {
            $0.components(separatedBy: "=")[0] == txtKey
        }.first
        #if DEBUG
        /*
         #debug
         You Have to Modify {bootnodes}' IP Address at following Line.
         */
        let bootnodes = ["192.168.0.34:8334"]
        #else
        let bootnodes = bootNodeTxtRecord?.components(separatedBy: "=")[1].components(separatedBy: " ")
        #endif
        Log(bootnodes ?? "")
        
        return bootnodes ?? []
    }

    func holder(key: String) {
        Log()
        
        
    }
    
}

