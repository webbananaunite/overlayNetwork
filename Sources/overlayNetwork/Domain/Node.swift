//
//  Node.swift
//  blocks
//
//  Created by よういち on 2020/06/11.
//  Copyright © 2020 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation
import Network
import CryptoKit

public protocol NodeProtocol: Equatable {
    /*
     Job Queue
     */
    func enQueue(job: Job)
    func deQueue(token: String) -> (Job?, Queue.Status)
    func deQueueWithType(token: String, type: [Job.`Type`]?) -> (Job?, Queue.Status)

    func setJobResult(token: String, type: [Job.`Type`]?, result: String) -> (Job?, Queue.Status)
    func setPreviousJob(token: String, previousJobToken: String) -> Queue.Status
    func fetchJob(token: String) -> Job?
    func fetchJobWithType(token: String, type: [Job.`Type`]) -> Job?
    func fetchPreviousJob(token: String) -> Job?
    func fetchPreviousJobWithType(token: String, type: [Job.`Type`]) -> Job?
    func fetchFollowingJobs(token: String) -> [Job]?

    /*
     Socket Queue (FIFO)
     */
    var socketQueues: Queue {
        get set
    }
    func enQueue(socket job: Job)
    func deQueue(for queueType: Queue.QueueType) -> Job?

    /*
     Archive to Device's Store.
     */
    func storeFingerTable()
    func callUpdateOthers()
    func fingerTableIsArchived() -> Bool

    func deployFingerTableToMemory()

    static func extractIpAndPort(_ ipAndPort: String) -> (IpaddressV4, Int)?

    init?(ownNode ip: IpaddressV4Protocol, port: Int, premiumCommand: CommandProtocol)

    init?(dhtAddressAsHexString: OverlayNetworkAddressAsHexString, premiumCommand: CommandProtocol)

    init(binaryAddress: OverlayNetworkBinaryAddress, premiumCommand: CommandProtocol)

    func received(from sentDataNodeIp: String, data: String)

    func takeCommandAndData(data: String) -> (String, String, String)?

    static func triggerLocalNetworkPrivacyAlert()
    static func addressesOfDiscardServiceOnBroadcastCapableInterfaces() -> [Data]
    func holder(of key: String) -> Node?
    
    func callForFetchResource(hashedKey: String) -> String?
    func callForFetchResource(key: String) -> String?

    func inChargedOf(node key: String) -> (Bool, String?)
    func inChargedOf(resource key: String) -> (Bool, String?, String?)
    func ownResponsibleNode(key: String) -> Bool
    func ownResponsibleResource(key: String) -> (Bool, String?)

    func fetchResource(key: String) -> (String?, String?)?
    
    func fetchResource(hashedKey: String) -> (String, String)?
    func join(babysitterNode: Node?)
    func firstNodeInitFingerTable(token: String) -> String?
    func initFingerTable(i: Int, babysitterNode: Node, token: String) -> String?
//    func findSuccessor(address: Node, token: String) -> Node?
    func findPredecessor(_ index: String, for address: Node, token: String) -> (Node, Node?)?

    func findPredecessorReply(for address: Node, token: String)
    
    func closestPrecedingFinger(address: Node, token: String) -> Node
    func have(_ node: Node, between toAddress: Node?) -> Bool
    func have(_ node: Node, between toAddress: Node, intervalType: Interval) -> Bool
    func haveBetweenWithSuccessor(about target: Node) -> Bool
    func updateOthers(i: Int, token: String) -> String?
    func updateFingerTable(node: Node, i: Int, token: String) -> String?

    func stabilize()
    func replyStabilize(candidateSuccessor: Node)

    // node thinks it might be our predecessor.
    func notify(node: Node)
    
    //periodically refresh finger table entries.
    func fixFingers(token: String)
    
    /*
     Functions for Debugging
     */
    func printQueueEssential()
    func printSocketQueue()
    func printQueue()
    func printQueue(job: Job?)
    func printFingerTable()
    func printFingerTableEssential()
    func printArchivedFingerTable()

    /*
     Properties
     */
    var premiumCommand: CommandProtocol? {
        get set
    }
    
    var binaryAddress: OverlayNetworkBinaryAddress {  //[UInt8] 512 bit - Make IP+Port into Hash Data
        get
    }
    var dhtAddressAsHexString: OverlayNetworkAddressAsHexString {  //binary address in Hexa decimal String
        get
    }
    var ip: IpaddressV4Protocol? {
        get
    }
    var port: Int? {
        get
    }
    var publicAddress: (ip: String, port: Int)? {
        get
    }

    static var validMinimumPortNumber: Int {
        get
    }
    var socketAddress :(ip: String, port: Int)? {
        get
    }
    var runAsBootNode: Bool {
        get
    }
    
    var ipAndPortString: String? {
        get
    }
    
    var hash: String {
        get
    }
    
    var fingerTableAddress: OverlayNetworkAddressAsHexString {
        get
    }
    
    var getIp: String? {
        get
    }

    /*inprementation of Chord*/
    var fingers: [Finger] {
        get set
    }
    var triggerStoreFingerTable: Bool {
        get set
    }
    var successor: Node? {           //next node in id(hash) cirlcle, == finger[0].node
        get set
    }
    var predecessor: Node? {         //previous node in id(hash) cirlcle
        get set
    }
    var babysitterNode: Node? {      //Use as Taker     //Set at join()
        get set
    }
    var queues: Queue {
        get set
    }
    var description: String {
        get
    }
    var communicatable: Bool {
        get
    }
    var inChargingOfResources: [String: String] {
        get
    }
    var doneAllFingerTableEntry: Bool {
        get set
    }
    var doneUpdateFingerTableInIndex: Bool {
        get set
    }
}

/*
 Node           通信ノード／ウォレット
 */
open class Node: ObservableObject, NodeProtocol {
    public static func == (lhs: Node, rhs: Node) -> Bool {
        if lhs.dhtAddressAsHexString.equal(rhs.dhtAddressAsHexString) {
            return true
        }
        return false
    }
    
    /*
     Custom Commands Dependency Injection
     */
    public var premiumCommand: CommandProtocol?
    /*
     OverlayNetworkAddress Can be Restorable Property.
     
     ex.
     ReUse as blocks#Node#restore() as boot node.
     */
    public var binaryAddress: OverlayNetworkBinaryAddress  //[UInt8] 512 bit - Make IP+Port into Hash Data
    public var dhtAddressAsHexString: any OverlayNetworkAddressAsHexString  //binary address As Hexa decimal String
    
    public var ip: IpaddressV4Protocol? {  //latest private address ip
        self.ips.last
    }
    public var port: Int? {                //latest private address port
        self.ports.last
    }
    public var ips = [IpaddressV4Protocol]()  //private address ips
    public var ports = [Int]()                //private address ports
    /*
     let node addresses store to Node#ips, Node#ports in every used when in communicate with signaling server.
     */

    public var publicAddress: (ip: String, port: Int)?
    
    public static let validMinimumPortNumber = 1024
    
    /*
     Communicate with overlayNetwork Address
     */
    public var socketAddress: (ip: String, port: Int)? { //private address ip & port
        get {
            if let ip = self.ip?.toString(), let port = self.port {
                return (ip: ip, port: port)
            }
            return nil
        }
    }

    public var runAsBootNode: Bool {
        return babysitterNode == nil ? true : false
    }
    
    public var ipAndPortString: String? {    //private address ip & port
        if let ip = self.ip?.toString(), let port = self.port {
            return ip + ":" + String(port)
        }
        return nil
    }
    
    public var hash: String {
        return dhtAddressAsHexString as? String ?? ""
    }
    
    public var fingerTableAddress: OverlayNetworkAddressAsHexString {
        return dhtAddressAsHexString
    }
    
    public var getIp: String? {  //private address ip & port
        return ip?.toString()
    }

    /*inprementation of Chord*/
    public var fingers: [Finger] = [Finger]()
    public var triggerStoreFingerTable: Bool = false {
        didSet {
            if triggerStoreFingerTable == true {
                Log("Store Finger Table.")
                /*
                 Store Finger Table
                 */
                self.storeFingerTable()
            }
        }
    }
    public var successor: Node? {           //next node in id(hash) cirlcle, == finger[0].node
        get {
            if fingers.isEmpty {
                return nil
            } else {
                return fingers[0].node
            }
        }
        set {
            Log()
            if fingers.isEmpty {
                let intervalMin = self.binaryAddress.addAsData(exponent: UInt(0)).moduloAsData(exponentOf2: Data.ModuloAsExponentOf2)
                let intervalMax = self.binaryAddress.addAsData(exponent: UInt(0+1)).moduloAsData(exponentOf2: Data.ModuloAsExponentOf2)
                if let finger = Finger(start: Node(binaryAddress: intervalMin), interval: [Node(binaryAddress: intervalMin), Node(binaryAddress: intervalMax)], node: nil) {Log()
                    fingers.append(finger)
                    fingers[0].node = newValue
                    self.triggerStoreFingerTable = true
                }
            } else {
                fingers[0].node = newValue
                self.triggerStoreFingerTable = true
            }
        }
    }
    //previous node in id(hash) cirlcle
    open var predecessor: Node? {
        didSet {
            Log("predecessor: \(predecessor?.dhtAddressAsHexString.toString)")
        }
    }
    
    open var babysitterNode: Node?       //Use as Taker     //Set at join()
    
    //MARK: - Socket Queue (FIFO)
    public var socketQueues = Queue()
    /*
     Enqueue as Last Element.
     */
    open func enQueue(socket job: Job) {
        Log(job.command)
        self.socketQueues.enQueue(job: job)
    }
    /*
     Dequeue First Element.
     */
    open func deQueue(for queueType: Queue.QueueType) -> Job? {
        Log()
        if queueType == .SocketCommunication {
            return self.socketQueues.deQueue()
        } else if queueType == .CommandOperation {
            return self.queues.deQueue()
        }
        return nil
    }
    
    //MARK: - Queue
    public var queues = Queue()
    
    open func enQueue(job: Job) {
        Log(job.command)
        self.queues.enQueue(job: job)
    }
    open func deQueue(token: String) -> (Job?, Queue.Status) {
        Log()
        return self.queues.deQueue(token: token, type: nil)
    }
    open func deQueueWithType(token: String, type: [Job.`Type`]?) -> (Job?, Queue.Status) {
        Log()
        return self.queues.deQueue(token: token, type: type)
    }
    open func printQueueEssential() {
        #if false
        let className = (#file as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("PQ \(dateString) \(className) \(#function) l.\(#line)\n")
        print("[PrintQueue]Essential")
        print("Node: \(self.getIp)")
        print("Queues: \(queues.queues.count)")
        queues.queues.enumerated().forEach { queue in
            print("\n")
            print("[\(queue.offset)]")
            print("time:\(queue.element.time)")
            print("command:\(queue.element.command)")
            print("fromOverlayNetworkAddress:\(queue.element.fromOverlayNetworkAddress)")
            print("operand:\(queue.element.operand)")
            print("type:\(queue.element.type)")
            print("result:\(queue.element.result)")
            print("status:\(queue.element.status)")
            print("token:\(queue.element.token)")
            print("previousJobToken:\(queue.element.previousJobToken)")
            print("nextJobToken:\(queue.element.nextJobToken)")
            print("\n")
        }
        #endif
    }
    open func printSocketQueueEssential() {
        #if false
        let className = (#file as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("PQ \(dateString) \(className) \(#function) l.\(#line)\n")
        print("[PrintSocketQueue]")
        print("Node: \(self.getIp)")
        print("Queues: \(socketQueues.queues.count)")
        socketQueues.queues.enumerated().forEach { queue in
            print("\n")
            print("[\(queue.offset)]")
            print("time:\(queue.element.time)")
            print("command:\(queue.element.command)")
            print("fromOverlayNetworkAddress:\(queue.element.fromOverlayNetworkAddress)")
            print("operand:\(queue.element.operand)")
            print("type:\(queue.element.type)")
            print("result:\(queue.element.result)")
            print("status:\(queue.element.status)")
            print("token:\(queue.element.token)")
            print("previousJobToken:\(queue.element.previousJobToken)")
            print("nextJobToken:\(queue.element.nextJobToken)")
            print("\n")
        }
        #endif
    }
    open func printSocketQueue() {
        #if false
        let className = (#file as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("PQ \(dateString) \(className) \(#function) l.\(#line)\n")
        print("[PrintSocketQueue]")
        print("Node: \(self.getIp)")
        print("Queues: \(socketQueues.queues.count)")
        socketQueues.queues.enumerated().forEach { queue in
            print("\n")
            print("[\(queue.offset)]")
            print("time:\(queue.element.time)")
            print("command:\(queue.element.command)")
            print("fromOverlayNetworkAddress:\(queue.element.fromOverlayNetworkAddress)")
            print("operand:\(queue.element.operand)")
            print("type:\(queue.element.type)")
            print("result:\(queue.element.result)")
            print("status:\(queue.element.status)")
            print("token:\(queue.element.token)")
            print("previousJobToken:\(queue.element.previousJobToken)")
            print("nextJobToken:\(queue.element.nextJobToken)")
            print("\n")
        }
        #endif
    }
    open func printQueue() {
//        #if DEBUG
//        print("[PrintQueue]")
//        print("Node: \(self.getIp)")
//        print("Queues: \(queues.queues.count)")
//        queues.queues.enumerated().forEach { queue in
//            if queue.offset == queues.queues.count - 1 {
//            print("\n")
//            print("[\(queue.offset)]")
//            print("time:\(queue.element.time)")
//            print("command:\(queue.element.command)")
//            print("fromOverlayNetworkAddress:\(queue.element.fromOverlayNetworkAddress)")
//            print("operand:\(queue.element.operand)")
//            print("type:\(queue.element.type)")
//            print("result:\(queue.element.result)")
//            print("status:\(queue.element.status)")
//            print("token:\(queue.element.token)")
//            print("previousJobToken:\(queue.element.previousJobToken)")
//            print("nextJobToken:\(queue.element.nextJobToken)")
//            print("\n")
//            }
//        }
//        #endif
    }
    open func printQueue(job: Job?) {
        #if false
        let className = (#file as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("PQ \(dateString) \(className) \(#function) l.\(#line)\n")
        print("[PrintQueue]Job")
        guard let job = job else {
            print("Job is nil.")
            return
        }
        print("Node: \(self.getIp)")
        print("time:\(job.time)")
        print("command:\(job.command)")
        print("fromOverlayNetworkAddress:\(job.fromOverlayNetworkAddress)")
        print("operand:\(job.operand)")
        print("type:\(job.type)")
        print("result:\(job.result)")
        print("status:\(job.status)")
        print("token:\(job.token)")
        print("previousJobToken:\(job.previousJobToken)")
        print("nextJobToken:\(job.nextJobToken)")
        print("\n")
        #endif
    }
    open func setJobResult(token: String, type: [Job.`Type`]?, result: String) -> (Job?, Queue.Status) {
        Log()
        return self.queues.setResult(token: token, type: type, result: result)
    }
    open func setPreviousJob(token: String, previousJobToken: String) -> Queue.Status {
        Log()
        return self.queues.setPreviousJob(token: token, previousJobToken: previousJobToken)
    }
    open func fetchJob(token: String) -> Job? {
        Log()
        return self.queues.fetchJob(token: token)
    }
    open func fetchJobWithType(token: String, type: [Job.`Type`]) -> Job? {
        Log(token)
        Log(type)
//        printQueueEssential()
        return self.queues.fetchJobWithType(token: token, type: type)
    }
    open func fetchPreviousJob(token: String) -> Job? {
        Log()
        return self.queues.fetchPreviousJob(token: token)
    }
    open func fetchPreviousJobWithType(token: String, type: [Job.`Type`]) -> Job? {
        Log()
        return self.queues.fetchPreviousJobWithType(token: token, type: type)
    }
    open func fetchFollowingJobs(token: String) -> [Job]? {
        Log()
        return self.queues.fetchFollowingJobs(previousJobToken: token)
    }

    // MARK: - Finger Table
    open func printFingerTable() {
#if DEBUG
        print("Successor: \(self.successor?.dhtAddressAsHexString.toString) Predecessor: \(self.predecessor?.dhtAddressAsHexString.toString)")
#endif
#if false
        print("Finger Table \(ip) own:\(dhtAddressAsHexString)\n")
        print("[start]     [interval]     [node]\n")
        var i: Int = 0
        fingers.forEach { finger in
            print("row \(i)")
            print("own+2^\(i) to own+2^\(i+1))")
            print("[\(finger.start.dhtAddressAsHexString)] [\(finger.interval[0].dhtAddressAsHexString) - \(finger.interval[1].dhtAddressAsHexString)] [\(finger.node?.dhtAddressAsHexString.toString)]\n")
            print("----------\n")
            i += 1
        }
#endif
    }
    open func printFingerTableEssential() {
#if true
        print("Successor: \(self.successor?.dhtAddressAsHexString.toString) Predecessor: \(self.predecessor?.dhtAddressAsHexString.toString)")
        print("Finger Table \(ip) own:\(dhtAddressAsHexString)\n")
        print("[start]     [interval]     [node]\n")
        var i: Int = 0
        fingers.forEach { finger in
            print("row \(i)")
            print("own+2^\(i) to own+2^\(i+1))")
            print("[\(finger.start.dhtAddressAsHexString)] [\(finger.interval[0].dhtAddressAsHexString) - \(finger.interval[1].dhtAddressAsHexString)] [\(finger.node?.dhtAddressAsHexString.toString)]\n")
            print("----------\n")
            i += 1
        }
#endif
    }
    /*
     Archive to Device's Store.
     Predecessor & Finger Table.
     */
    open func storeFingerTable() {
        var i = 0
        Finger.storeFirstLine()
        if let predecessor = self.predecessor {
            Finger.storePredecessor(overlayNetworkAddress: predecessor.dhtAddressAsHexString)
        }
        fingers.forEach { finger in
            finger.storeUp(index: i)
            i += 1
        }
        Finger.storeLastLine()
    }
    open func printArchivedFingerTable() {
        #if false
        print("Successor: \(self.successor?.dhtAddressAsHexString.toString) Predecessor: \(self.predecessor?.dhtAddressAsHexString.toString)")
        Log(fingers.count)
        if let finger = fingers.first {
            finger.print()
        }
        #endif
    }
    open func callUpdateOthers() {
        #if DEBUG
        Log()
        Command.updateOthers.run(node: self, operands: [String(0)]) {
            a in
            Log("Run [Update others] Command to \(self.ip?.toString()).")
        }
        #endif
    }
    open func fingerTableIsArchived() -> Bool {
        Log()
        if Finger.isCached() {
            Log("Have Archived")
            return true
        }
        Log("Have NOT Archived")
        return false
    }
    
    /*
     Deploy Finger Table from Device's Storage.
     
     Format: Json
        Start, Interval stored as Hex String(dhtAddressAsHexString)
        Stored by Finger#storeUp()
     */
    open func deployFingerTableToMemory() {
        Log()
        guard let jsonData = Finger.fetchJson(), jsonData.count == (Node.FINGER_TABLE_INDEX_MAX + 1) else {
            Log("Broken Cached data.")
            return
        }
        Log(jsonData[0])  //["predecessor": 192.168.0.3:8334]
        Log(jsonData[1])  //[ {Object},... ]
        Log(jsonData.count)
        jsonData.forEach {
#if true
            print($0)
            print("---\n")
#endif
            let rows = $0 as [String: Any]
            Log(rows)
            if let predecessor = rows["predecessor"] as? [String: Any], let dhtAddressAsHexString = predecessor["dhtAddressAsHexString"] as? String {
                Log()
                if let predecessorNode = Node(dhtAddressAsHexString: dhtAddressAsHexString) {
                    Log(predecessorNode.dhtAddressAsHexString)
                    self.predecessor = predecessorNode
                }
            } else if let dhtAddressAsHexString = rows["dhtAddressAsHexString"] as? [String: Any], let start = dhtAddressAsHexString["start"] as? String, let interval = dhtAddressAsHexString["interval"] as? [String], let node = dhtAddressAsHexString["node"] as? String {
                
                Log()
                if let start = Node(dhtAddressAsHexString: start), let intervalStart = Node(dhtAddressAsHexString: interval[0]), let intervalEnd = Node(dhtAddressAsHexString: interval[1]) {
                    if let finger = Finger(start: start, interval: [intervalStart, intervalEnd], node: Node(dhtAddressAsHexString: node)) {
                        fingers.append(finger)
                    }
                }
            }
        }
        Log("\(fingers.count) End deploy.")
    }

    open var description: String {
        return ("dhtAddressAsHexString:\(dhtAddressAsHexString) ip:\(ip) port:\(port)")
    }
    
    /*
     transform dhtAddress(String) to chunks([Decimal](5)).
     
     base64 1文字=6ビット
     Decimalは128bit
     dhtAddress=86文字 Sha512 なので
     ↓
     20文字ごとにbase64 to Decial変換する
     5 chunksに変換する
    */

    // MARK: - Constructors
    public static func extractIpAndPort(_ ipAndPort: String) -> (IpaddressV4, Int)? {
        let ipAndPorts = ipAndPort.components(separatedBy: ":")
        guard ipAndPorts.count == 2 else {
            return nil
        }
        guard IpaddressV4.validIp(ipAddressString: ipAndPorts[0]), let portNum = Int(ipAndPorts[1]), portNum > Node.validMinimumPortNumber else {
            return nil
        }

        guard let portNum = Int(ipAndPorts[1]), let ip = IpaddressV4(ipAddressString: ipAndPorts[0]) else {
            return nil
        }
        return (ip, portNum)
    }

    public func reProduct(ownNode ip: IpaddressV4Protocol, port: Int) {
        Log()
        if !self.dhtAddressAsHexString.isValid {
            if ip.toString() == IpaddressV4.null.toString() {
                let nodeAddress = "00"   //initial value for lower node
                self.dhtAddressAsHexString = nodeAddress
                self.binaryAddress = Data.DataNull
            } else {
                guard let (nodeAddress, hashed512Data) = Dht.hash(ip: ip, port: port), let nodeAddress = nodeAddress else {
                    return
                }
                /*
                 Test Mode
                 When Run As Boot Node, Set {RunAsBootNode} as Run Argument / Environment Variable on Edit Scheme on Xcode.
                 */
                let setArgv = ProcessInfo.processInfo.arguments.contains("RunAsBootNode")
                let envVar = ProcessInfo.processInfo.environment["RunAsBootNode"] ?? ""
                if setArgv || envVar != "" {
                    Log()
                    /*
                     behavior as Boot Node.
                     */
                    self.dhtAddressAsHexString = "988637f394e5c291fb7448a9e53bfc5f5fba73feb9ea57703d77b046ed20bab7a0d9f6b41467376ee0dfd25b48cd9a04ed81f0eb197dcfd6ef2532cf84e0f71c"
                    guard let binaryAddress = self.dhtAddressAsHexString.dataAsString(using: .hexadecimal) else {
                        return
                    }
                    self.binaryAddress = binaryAddress
                } else {
                    Log()
                    self.dhtAddressAsHexString = nodeAddress
                    self.binaryAddress = hashed512Data
                }
            }
        }
        
//        self.ip = ip
//        self.port = port
        self.ips += [ip]
        self.ports += [port]
        
//        self.premiumCommand = premiumCommand
        
        Log("dhtAddressAsHexString:\(dhtAddressAsHexString) ip:\(ip) port:\(port)")
        Dump(binaryAddress)
    }
    /*
     Construct New Node for Own Node with Generating New DhtAddress.
     
     Parameter 'command' for Extended Command.
     overlayNetwork.Command Normally
     */
    required public init?(ownNode ip: IpaddressV4Protocol, port: Int, premiumCommand: CommandProtocol = Command.other) {
        Log()
        if ip.toString() == IpaddressV4.null.toString() {
            let nodeAddress = "00"   //initial value for lower node
            self.dhtAddressAsHexString = nodeAddress
            self.binaryAddress = Data.DataNull
        } else {
            guard let (nodeAddress, hashed512Data) = Dht.hash(ip: ip, port: port), let nodeAddress = nodeAddress else {
                return nil
            }
            /*
             Test Mode
             When Run As Boot Node, Set {RunAsBootNode} as Run Argument / Environment Variable on Edit Scheme on Xcode.
             */
            let setArgv = ProcessInfo.processInfo.arguments.contains("RunAsBootNode")
            let envVar = ProcessInfo.processInfo.environment["RunAsBootNode"] ?? ""
            if setArgv || envVar != "" {
                Log()
                /*
                 behavior as Boot Node.
                 */
                self.dhtAddressAsHexString = "988637f394e5c291fb7448a9e53bfc5f5fba73feb9ea57703d77b046ed20bab7a0d9f6b41467376ee0dfd25b48cd9a04ed81f0eb197dcfd6ef2532cf84e0f71c"
                guard let binaryAddress = self.dhtAddressAsHexString.dataAsString(using: .hexadecimal) else {
                    return nil
                }
                self.binaryAddress = binaryAddress
            } else {
                Log()
                self.dhtAddressAsHexString = nodeAddress
                self.binaryAddress = hashed512Data
            }
        }
//        self.ip = ip
//        self.port = port
        self.ips += [ip]
        self.ports += [port]

        self.premiumCommand = premiumCommand
        
        Log("dhtAddressAsHexString:\(dhtAddressAsHexString) ip:\(ip) port:\(port)")
        Dump(binaryAddress)
    }
    
    required public init?(dhtAddressAsHexString: OverlayNetworkAddressAsHexString, premiumCommand: CommandProtocol = Command.other) {
        guard dhtAddressAsHexString.isValid else {
            return nil
        }
        self.dhtAddressAsHexString = dhtAddressAsHexString
        if let binary = dhtAddressAsHexString.dataAsString(using: .hexadecimal) {
            self.binaryAddress = binary
        } else {
            self.binaryAddress = Data.DataNull
        }
        self.premiumCommand = premiumCommand
    }
    
    required public init(binaryAddress: OverlayNetworkBinaryAddress, premiumCommand: CommandProtocol = Command.other) {
        self.dhtAddressAsHexString = binaryAddress.hexAsData()
        self.binaryAddress = binaryAddress
        self.premiumCommand = premiumCommand
        Log("dhtAddressAsHexString:\(dhtAddressAsHexString) ip:\(ip) port:\(port)")
    }
    
    public var communicatable: Bool {
        if !self.dhtAddressAsHexString.isValid {
            return false
        }
        return true
    }

    /*
     MARK: - Callback Function Socket Received
     ノードが受信した
     */
    open func received(from sentOverlayNetworkAddress: String, data: String) {
        LogEssential("from: \(sentOverlayNetworkAddress) data: \(data)")
        guard let (command, operand, token) = takeCommandAndData(data: data) else {
            return
        }
        /*
         Carry out each Command
         ex.
         fetch baby(node sent me the data)'s successor node address
         
         Apply Dependency Injeciton for Premium Command
         */
        Log(command)
        var commandInstance: CommandProtocol? = Command(rawValue: command)
        Log(commandInstance == nil ? "received premium Command" : "received overlayNetwork Command")
        if commandInstance == nil {
            Log()
            /*
             if Nothing in overlayNetwork Command,
             Use Appendix Premium Command.
             */
            commandInstance = self.premiumCommand?.command(command)
            Log(commandInstance)
        }
        var nodeProtocolSelf: any NodeProtocol = self
        let nextOperand = commandInstance?.receive(node: &nodeProtocolSelf, operands: operand, from: sentOverlayNetworkAddress, token: token)
        
        guard let nextOperand = nextOperand else {Log()
            return
        }
        
        /*
         if self is 'Reply command'
         if have previous job
         Send reply command to previous command sender.
         
         if self is 'Normal command'
         Send reply command to sender.
         */
        Log(command)
        if (Command(rawValue: command) ?? Command.other).isReply() {
            Log(command)
            /*
             Check having previous job
             */
            Log("token: \(token)")
            Log("type: [.delegate, .local]")
            guard let job = self.fetchJobWithType(token: token, type: [.delegate, .local]), let _ = job.result else { Log()
                self.printQueueEssential()
                return
            }
            
            if let previousJob = self.fetchPreviousJobWithType(token: token, type: [.delegate, .local, .delegated]) {
                Log("PreviousJob: \(previousJob.command) - \(previousJob.command.rawValue)")
                Log("fromOverlayNetworkAddress: \(previousJob.fromOverlayNetworkAddress) - \(nextOperand) - \(previousJob.token)")
                //Send reply PREVIOUS command
                previousJob.command.reply(node: self, to: previousJob.fromOverlayNetworkAddress, operand: nextOperand, token: previousJob.token) {
                    a in
                    Log("Sent reply to \(sentOverlayNetworkAddress)")
                }
            } else {
                Log("No PreviousJobs")
            }
        } else {
            Log(command)
            /*
             Make .delegated type job's status to .dequeued
             */
            let (updatedJob, _) = self.deQueueWithType(token: token, type: [.delegated])
            Log(command)
            self.printQueue(job: updatedJob)
            //Send reply command
//            (Command(rawValue: command) ?? Command.other).reply(node: self, to: sentOverlayNetworkAddress, operand: nextOperand, token: token) {
//                a in
//                Log("Sent reply to \(sentOverlayNetworkAddress)")
//            }
            var commandInstance: CommandProtocol? = Command(rawValue: command)
            LogEssential(commandInstance == nil ? "received premium Command" : "received overlayNetwork Command")
            if commandInstance == nil {
                Log()
                /*
                 if Nothing in overlayNetwork Command,
                 Use Appendix Premium Command.
                 */
                commandInstance = self.premiumCommand?.command(command)
                LogEssential(commandInstance)
            }
            commandInstance?.reply(node: self, to: sentOverlayNetworkAddress, operand: nextOperand, token: token) {
                a in
                Log("Sent reply to \(sentOverlayNetworkAddress)")
            }
        }
    }

    /*
     Received communication data to (Command, Operands, Token)
        "{command} {operands,,} {token}\n"
            Data Terminator: {\n}   Delimiter: {space}   Operand Delimiter: {,}
     Operands will be take apart(,) in Command.receive()
     */
    public func takeCommandAndData(data: String) -> (String, String, String)? {
        Log()
        //check terminator
        Log(data)
        let datas = data.components(separatedBy: Socket.communicationTerminatorChar)
        Log(datas)
        guard datas[0].count >= 2 else {
            Log("Bad Data Terminator. \(datas[0].count)")
            return nil
        }
        let data = datas[0]
        let commandAndData = data.components(separatedBy: " ")
        Log(commandAndData)
        guard commandAndData.count == 3 else {  //3 fields: {Command} {Operands1st,2nd,3rd...} {Token}
            Log("Bad Operands \(commandAndData.count)")
            return nil
        }
        Log()
        return (commandAndData[0], commandAndData[1], commandAndData[2])
    }

    //Thank: https://developer.apple.com/forums/thread/663768
    /// Does a best effort attempt to trigger the local network privacy alert.
    ///
    /// It works by sending a UDP datagram to the discard service (port 9) of every
    /// IP address associated with a broadcast-capable interface. This should
    /// trigger the local network privacy alert, assuming the alert hasn’t already
    /// been displayed for this app.
    ///
    /// This code takes a ‘best effort’. It handles errors by ignoring them. As
    /// such, there’s guarantee that it’ll actually trigger the alert.
    ///
    /// - note: iOS devices don’t actually run the discard service. I’m using it
    /// here because I need a port to send the UDP datagram to and port 9 is
    /// always going to be safe (either the discard service is running, in which
    /// case it will discard the datagram, or it’s not, in which case the TCP/IP
    /// stack will discard it).
    ///
    /// There should be a proper API for this (r. 69157424).
    ///
    /// For more background on this, see [Triggering the Local Network Privacy Alert](https://developer.apple.com/forums/thread/663768).
    public static func triggerLocalNetworkPrivacyAlert() {
        Log()
        let sock4 = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock4 >= 0 else { return }
        defer { close(sock4) }
        let sock6 = socket(AF_INET6, SOCK_DGRAM, 0)
        guard sock6 >= 0 else { return }
        defer { close(sock6) }
        
        let addresses = addressesOfDiscardServiceOnBroadcastCapableInterfaces()
        var message = [UInt8]("!".utf8)
        for address in addresses {
            address.withUnsafeBytes { buf in
                let sa = buf.baseAddress!.assumingMemoryBound(to: sockaddr.self)
                let saLen = socklen_t(buf.count)
                let sock = sa.pointee.sa_family == AF_INET ? sock4 : sock6
                _ = sendto(sock, &message, message.count, MSG_DONTWAIT, sa, saLen)
            }
        }
    }
    
    /// Returns the addresses of the discard service (port 9) on every
    /// broadcast-capable interface.
    ///
    /// Each array entry is contains either a `sockaddr_in` or `sockaddr_in6`.
    public static func addressesOfDiscardServiceOnBroadcastCapableInterfaces() -> [Data] {
        Log()
        var addrList: UnsafeMutablePointer<ifaddrs>? = nil
        let err = getifaddrs(&addrList)
        guard err == 0, let start = addrList else { return [] }
        defer { freeifaddrs(start) }
        return sequence(first: start, next: { $0.pointee.ifa_next })
            .compactMap { i -> Data? in
                guard
                    (i.pointee.ifa_flags & UInt32(bitPattern: IFF_BROADCAST)) != 0,
                    let sa = i.pointee.ifa_addr
                else { return nil }
                var result = Data(UnsafeRawBufferPointer(start: sa, count: Int(sa.pointee.sa_len)))
                switch CInt(sa.pointee.sa_family) {
                case AF_INET:
                    result.withUnsafeMutableBytes { buf in
                        let sin = buf.baseAddress!.assumingMemoryBound(to: sockaddr_in.self)
                        sin.pointee.sin_port = UInt16(9).bigEndian
                    }
                case AF_INET6:
                    result.withUnsafeMutableBytes { buf in
                        let sin6 = buf.baseAddress!.assumingMemoryBound(to: sockaddr_in6.self)
                        sin6.pointee.sin6_port = UInt16(9).bigEndian
                    }
                default:
                    return nil
                }
                return result
            }
    }
    
    /*
     MARK: - Chord Custom Method
     
     |n|start|interval|successor(node)|
     |0|  1  | [1,2)  |  1            |
     |1|  2  | [2,4)  |  3            |
     |2|  4  | [4,0)  |  0            |
     */
    public func holder(of key: String) -> Node? {
        Log(key)
        guard let address = Resource(string: key) else {
            return nil
        }
        var matchedFinger: Finger?
        for finger in self.fingers {
            Log(finger.start.dhtAddressAsHexString)
            if finger.interval[0].have(address, between: finger.interval[1]) {  //includeExclude [...) : half-open
                Log()
                matchedFinger = finger
                break
            }
        }
        Log(matchedFinger?.start.dhtAddressAsHexString)
        return matchedFinger?.node
    }
    
    public let inChargingOfResources = [
        "099f3ce797b4fcdd28b33987751f821f251b61b7f16b31dbf38888e560a2ec0c1492fc41332ce86b330cc98cb2ac8bdcf482c61703ecfdcd58d7b94f2ae29876": "This is Key: 099f3ce797b4fcdd28b33987751f821f251b61b7f16b31dbf38888e560a2ec0c1492fc41332ce86b330cc98cb2ac8bdcf482c61703ecfdcd58d7b94f2ae29876 Resource Data String."
    ]

    open func callForFetchResource(hashedKey: String) -> String? {
        let (isOwn, resourceString) = ownResponsibleResource(key: hashedKey)
        if isOwn {
            Log()
            return resourceString
        }
        
        if let holder = holder(of: hashedKey) {
            if holder.getIp == self.getIp {
                Log()
                //if Self Responsible Resource,
//                return inChargingOfResources[hashedKey]
            } else {
                Log()
                Command.fetchResource.send(node: self, to: holder.dhtAddressAsHexString, operands: [hashedKey]) { string in
                    Log(string)
                }
            }
        }
        return nil
    }
    
    open func callForFetchResource(key: String) -> String? {
        let hashedKeyString = key.hash().0
        Log(hashedKeyString)
        return callForFetchResource(hashedKey: hashedKeyString)
    }

    open func inChargedOf(node key: String) -> (Bool, String?) {
        //See over finger table, Confirm be in charged of the resource.
        let isOwn = ownResponsibleNode(key: key)
        if isOwn {
            Log()
            return (isOwn, self.dhtAddressAsHexString.toString)
        }
        
        if let holder = holder(of: key) {
            Log()
            return (false, holder.dhtAddressAsHexString.toString)
        }
        Log()
        return (false, nil)
    }
    open func inChargedOf(resource key: String) -> (Bool, String?, String?) {
        //See over finger table, Confirm be in charged of the resource.
        let (isOwn, resourceString) = ownResponsibleResource(key: key)
        if isOwn {
            Log()
            return (isOwn, nil, resourceString)
        }
        
        if let holder = holder(of: key) {
            Log()
            return (false, holder.dhtAddressAsHexString.toString, nil)
        }
        Log()
        return (false, nil, nil)
    }
    open func ownResponsibleNode(key: String) -> Bool {
        /*
         if (predecessor, own]
            return resourceString
         else
            return nil
         */
        if let node = Node(dhtAddressAsHexString: key), let predecessor = self.predecessor {
            if predecessor.have(node, between: self, intervalType: .excludeInclude) {
                Log()
//                //space to %20
//                var resourceString = inChargingOfResources[key]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                return true
            }
        }
        return false
    }
    open func ownResponsibleResource(key: String) -> (Bool, String?) {
        /*
         if (predecessor, own]
            return resourceString
         else
            return nil
         */
        if let resource = Resource(string: key), let predecessor = self.predecessor {
            if predecessor.have(resource, between: self, intervalType: .excludeInclude) {
                Log()
                //space to %20
                var resourceString = inChargingOfResources[key]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                return (true, resourceString)
            }
        }
        return (false, nil)
    }

    public func fetchResource(key: String) -> (String?, String?)? {
        let hashedKey = key.hash().0
        return fetchResource(hashedKey: hashedKey)
    }
    
    public func fetchResource(hashedKey: String) -> (String, String)? {
        Log()
        let (inChargingOfIt, responsibleNodeIp, resourceString) = inChargedOf(resource: hashedKey)
        if inChargingOfIt {
            Log()
            /*
             自ノードが所持しているリソース
             */
//            resourceString = "ThisisitthatYouRequested."
            return (resourceString ?? "", "")
        } else if let responsibleNode = responsibleNodeIp, responsibleNode != "" {
            Log()
            /*
             他ノードが管理しているリソース
             */
            return ("", responsibleNode)
        }
        return nil
    }
    
    /*
     MARK: - Chord Construction
     */
    
    /*
     Paper:
     node n joins the network;
     n' is an arbitrary node in the network
     
     n': babysitterNode
     
     */
    open func join(babysitterNode: Node?) {
        Log(babysitterNode?.dhtAddressAsHexString as Any)
        guard let babysitterNode = babysitterNode else {
            Log("Boot node")
            /*
             if self is First Node(Boot Node)
             */
            Command.initFingerTable.run(node: self, operands: [""]) {
                string in
                Log(string)
            }
            return
        }
        
        /*
         <Normal Node> =Ordinary Node
         babysitterNode is Exist.
         */
        Log("Normal node")
        self.babysitterNode = babysitterNode
        let dhtAddressAsHexString = babysitterNode.dhtAddressAsHexString.toString
        Log(dhtAddressAsHexString)
        Command.initFingerTable.run(node: self, operands: [dhtAddressAsHexString]) {
            string in
            Log(string)
        }
    }
    
    /*
     if Node was Replied Successor, initialize finger table.

     <Finger Table>
     
     Notation           | Definition
     finger[k].start    | (n+2^(k-1))mod 2^m, 1 <= k <= m
     .interval          | [finger[k].start, finger[k+1].start); [以上、)未満
     .node              | first node >= n.finger[k].start
     successor          | the next node on the identifier circle; =finger[1].node
     predecessor        | the previous node on the identifier circle
     
     */
    //使用していない
    open func appendNodeToFingerTable(node: Node, token: String) -> Void {
        Log()
        fingers[0].node = node
        self.triggerStoreFingerTable = true
    }
    
    /*
     <Boot Node (First Node in the Network)>
     Init finger table if self is boot node(first node) in the network

     #Finger Table#
        7   0   1
     6             2
        5   4   3

     Notation           | Definition
     finger[k].start    | (n+2^(k-1))mod 2^m, 1 <= k <= m
     .interval          | [finger[k].start, finger[k+1].start); [以上、)未満
     .node              | first node >= n.finger[k].start
                            first node: interval.start以上で、かつ時計回りの最初のノード
     successor          | the next node on the identifier circle; =finger[1].node
                            finger table 配列の最初の .node
     predecessor        | the previous node on the identifier circle
                            interval.startより小さく、かつ反時計回りの最初のノード
     */
    static let FINGER_TABLE_INDEX_MAX = 512   //2^512   sha512 [2^(128 * 4)]
    open func firstNodeInitFingerTable(token: String) -> String? {
        Log()
        defer { //Put Off to Later.
            self.triggerStoreFingerTable = true
        }
        for i in 0..<Node.FINGER_TABLE_INDEX_MAX {
            Log(i)
            let i = Int(i)
            /*
             Make adding exponent power of 2 into Data{binaryAddress}.
             */
            Log(self.dhtAddressAsHexString)
            Dump(self.binaryAddress)
            let intervalMin = self.binaryAddress.addAsData(exponent: UInt(i)).moduloAsData(exponentOf2: Data.ModuloAsExponentOf2)
            let intervalMax = self.binaryAddress.addAsData(exponent: UInt(i+1)).moduloAsData(exponentOf2: Data.ModuloAsExponentOf2)
            Dump(intervalMin)
            Dump(intervalMax)
            if let finger = Finger(start: Node(binaryAddress: intervalMin), interval: [Node(binaryAddress: intervalMin), Node(binaryAddress: intervalMax)], node: self) {
                fingers.append(finger)
            }
        }
        self.predecessor = self
        return nil  //Don't send reply command.
    }
        
    /*
     <Baby Node (Normal Node)>
     
     Initialize finger table with Babysitter Node.
        Ask babysitternode for some node's successor in the network.

     #Finger Table#
        7   0   1
     6             2
        5   4   3

     Notation           | Definition
     finger[k].start    | (n+2^(k-1))mod 2^m, 1 <= k <= m
     .interval          | [finger[k].start, finger[k+1].start); [以上、)未満
     .node              | first node >= n.finger[k].start
                            first node: interval.start以上で、かつ時計回りの最初のノード
     successor          | Clockwise, the next node on the identifier circle; =finger[1].node
                            First {node} in finger table.
     predecessor        | CounterClockwise, the next node on the identifier circle.
     */
    public var doneAllFingerTableEntry: Bool = false
    public var doneUpdateFingerTableInIndex: Bool = false
    open func initFingerTable(i: Int, babysitterNode: Node, token: String) -> String? {
        Log()
        guard i < Node.FINGER_TABLE_INDEX_MAX else {
            Log("exceeded finger table range \(Node.FINGER_TABLE_INDEX_MAX): \(i)")
            return nil
        }
        Log(babysitterNode.dhtAddressAsHexString.toString)
        guard babysitterNode.communicatable else {
            return nil
        }
        Log(i)
        /*
         Make adding exponent power of 2 into Data(binaryAddress).
         */
        let intervalMin = self.binaryAddress.addAsData(exponent: UInt(i)).moduloAsData(exponentOf2: Data.ModuloAsExponentOf2)
        let intervalMax = self.binaryAddress.addAsData(exponent: UInt(i+1)).moduloAsData(exponentOf2: Data.ModuloAsExponentOf2)
        Log(intervalMin.hexAsData())
        Log(intervalMax.hexAsData())

        if let finger = Finger(start: Node(binaryAddress: intervalMin), interval: [Node(binaryAddress: intervalMin), Node(binaryAddress: intervalMax)], node: nil) {Log()
            fingers.append(finger)
        }
        
        /*
         Set Successor in Finger Table Entry.
         
         if finger[i+1].start ∈ [n, finger[i].node)
            finger[i+1].node = finger[i].node
         else
            finger[i+1].node = n'.findSuccessor(finger[i+1].start)

         As This Implementation,
            As i > 0,
            if finger[i].start ∈ [self, finger[i-1].node)
                finger[i].node = finger[i-1].node
         */
        var startBetweenSelfToPreIndexSuccessor: Bool = false
        if i > 0 {
            Log(fingers[i-1].node?.dhtAddressAsHexString ?? "fingers.node(Successor) is nil.")
            if let node = fingers[i-1].node {
                Log("Have Successor in Pre Entry: \(i)")
                /*
                 If ONLY have got Successor{node in pre finger table entry}
                 */
                Log("finger- from: \(self.binaryAddress.hexAsData())")
                Log("finger- to: \(node.binaryAddress.hexAsData())")
                Log("finger- target: \(fingers[i].start.binaryAddress.hexAsData())")
                if self.have(fingers[i].start, between: node) {
                    Log("finger- Be Contained.")
                    /*
                     finger[i].start ∈ [self, finger[i-1].node)
                     */
                    startBetweenSelfToPreIndexSuccessor = true
                } else {
                    Log("finger- Be Excepted.")
                    /*
                     start ∉ [self, finger[i-1].node)
                     */
                    startBetweenSelfToPreIndexSuccessor = false
                }
            }
        }
        Log(startBetweenSelfToPreIndexSuccessor)
        if startBetweenSelfToPreIndexSuccessor {
            /*
             finger[i].start ∈ [self, finger[i-1].node)
                then Set finger[i-1].node to finger[i].node
             */
            Log("start ∈ [self, finger[i-1].node) then Set Node to Finger Entry. \(i) ")
            Log(fingers[i].node?.getIp)
            Log(fingers[i-1].node?.getIp)
            fingers[i].node = fingers[i-1].node
            Log(i)
            if i >= Node.FINGER_TABLE_INDEX_MAX - 1 {
                Log()
            } else {
                Log()
                Command.initFingerTable.run(node: self, operands: [babysitterNode.dhtAddressAsHexString.toString]) {
                    string in
                    Log(string)
                }
            }
        } else {
            /*
             start ∉ [self, finger[i-1].node)
             */
            Log("start ∉ [self, finger[i-1].node) then Send FS Command to Babysitter Node.")
            Command.findSuccessor.send(node: self, to: babysitterNode.dhtAddressAsHexString, operands: [String(i), fingers[i].start.dhtAddressAsHexString.toString], previousToken: token) {
                a in
                Log("Sent [Find Successor \(i)] Command to \(babysitterNode.ip?.toString()).")
            }
        }
        
        /*
         Update Predecessor on self and Successor.
         
         self.predecessor = successor.predecessor
         self.successor?.predecessor = self
         */
        if i >= Node.FINGER_TABLE_INDEX_MAX - 1 {
            Log()
            Log(self.successor?.predecessor?.dhtAddressAsHexString ?? "nil")
            /*
             Have Done All.
             */
            self.triggerStoreFingerTable = true
            return "completed"
        }
        return nil
    }
    
    /*
     Not Use
     
     Argument address's Successor
     
     "Successor" is next node in DHT circle by clockwise.
     
     Paper:
     n' = find_predecessor(id);
     return n',successor;
     
     address: id
     
     Return:
     Always return nil
     */
//    public func findSuccessor(address: Node, token: String) -> Node? {
//        Log()
//        /*
//         address NOT belog between self and self.successor
//         Be querying another node.
//         */
//        return nil
//    }
    
    /*
     ask node n to find id's predecessor
     if address is contained in predecessorNode to predecessorNode.successor
     
     "Predecessor" is previous node in DHT circle by counter clockwise.


     Paper:
     n' = n;
     while (id ∉ (n', n'.successor])
        n' = n'.closest_preceding_finger(id);
     return n';

     
     id: address
     n: self
     
     
     Return:
     (Predecessor node, predecessor node's Successor node)
     */
    open func findPredecessor(_ index: String, for address: Node, token: String) -> (Node, Node?)? {
        Log()
        if self.haveBetweenWithSuccessor(about: address) {
            Log(true)
            return (self, self.successor)
        }
        Log(false)
        /*
         Get Next Closest Preceding Finger
         */
        Command.closestPrecedingFinger.run(node: self, operands: [index, address.dhtAddressAsHexString.toString, ""], previousToken: token) {
            a in
            Log("Run [Closest Preceding Finger] Command to \(self.ip?.toString() ?? "").")
        }
        return nil
    }

    open func findPredecessorReply(for address: Node, token: String) {
        Log()
        //what do nothing
    }
    
    /*
     return closest finger preceding id
     
     Paper:
     for i = m downto 1
        if (finger[i].node ∈ (n, id))   //if n < node < id
            return finger[i].node;
     return n;
     
     address: id
     self: n
     */
    public func closestPrecedingFinger(address: Node, token: String) -> Node {
        Log()
        var matchedFinger: Finger? = nil
        var i = self.fingers.count - 1
        for finger in self.fingers.reversed() {
            Log("closestPrecedingFinger - inRange(intervalType: .exclude)")
            Log("about: \(finger.node?.binaryAddress.hexAsData()))")
            Log("from: \(self.binaryAddress.hexAsData())")
            Log("to: \(address.binaryAddress.hexAsData())")
            /*
             whether $0.node belongs between self and address.
             */
            if let node = finger.node {
                if self.have(node, between: address, intervalType: .exclude) {
                    matchedFinger = finger
                    break
                }
            }
            i -= 1
        }
        Log(i)
        Log(matchedFinger?.node?.dhtAddressAsHexString ?? "Missed matching")

        /*
         Query successor to matchedFinger?.node
            findPredecessor()で while(id ∉ (n', n'.successor]) するため
             (a, b] は {x : a < x ≦ b} を表す
         
         */
        if let closestPrecedingNode = matchedFinger?.node {
            /*
             Found Closest Preceding node in self's finger table.
             */
            return closestPrecedingNode
        } else {
            /*
             Not Found Closest Preceding node in self's finger table.
             */
            return self
        }
    }
    
    //使用していない
    func areYouPredecessor(address: Node, token: String) -> Bool {
        Log()
        if self.haveBetweenWithSuccessor(about: address) {
            Log(true)
            return true
        }
        Log(false)
        /*
         if id ∉ (n', n'.successor]
         */
        return false
    }
    
    //使用していない
    func queryYourSuccessorReply(yourSuccessor: Node, token: String) {
        Log()
//        if let delegateJob = self.fetchJob(token: token), let previousJob = fetchPreviousJob(token: token) {
//            if delegateJob.status == .dequeued {
//                if previousJob.command == .closestPrecedingFinger {
//                    if let previousJobResult = previousJob.result {
//                        let operand = previousJobResult + "," + yourSuccessor.dhtAddress
////                        Command.closestPrecedingFinger.reply(node: self, to: previousJob.fromOverlayNetworkAddress, operand: operand, token: token) {
////                            a in
////                            Log("Sent [Closest Preceding Finger Reply] Command to \(previousJob.fromOverlayNetworkAddress).")
////                        }
//                        _ = self.setJobResult(token: previousJob.token, result: operand)
//                    }
//                }
//            }
//        }
    }
    
    //使用していない
//    func closestPrecedingFingerReply(precedingNode: Node, token: String) {
//        Log()
//        guard precedingNode.communicatable else {
//            return
//        }
//
//        if let job = self.fetchJob(token: token) {
//            let targetNodeDhtAddress = job.operand
//            if let targetNode = Node(ipAndPort: targetNodeDhtAddress) {
//                if precedingNode.haveBetweenWithSuccessor(about: targetNode) {   // if id ∈ (precedingNode, precedingNode.successor]
//                    //Found targetNode's predecessor == precedingNode
//                } else {
//                    //Retry
//                    // precedingNode was NOT targetNode's predecessor
//                    let (updatedJob,_) = self.deQueueWithType(token: token, type: nil)
//                    self.printQueue(job: updatedJob)
//                    //re delegate
//                    Command.closestPrecedingFinger.send(node: self, to: precedingNode.ip.toString(), operands: [job.operand], previousToken: job.previousJobToken) {
//                        a in
//                        Log("Sent [Closest Preceding Finger] Command to \(precedingNode.ip.toString()).")
//                    }
//                }
//            }
//        }
//    }
    
    /*
     Check Having between {self} and {toAddress} in Clockwise in Finger Table.
     
     Paper:
     if (finger[i+1].start ∈ [n, finger[i].node)
     
     n: self
     finger[i].node: address
     finger[i+1].start: node

     */
    public func have(_ node: Node, between toAddress: Node?) -> Bool {
        Log()
        Log("have between - inRange(intervalType: .includeExclude")
        Log("about: \(node.binaryAddress.hexAsData()))")
        Log("from: \(self.binaryAddress.hexAsData())")
        Log("to: \(toAddress?.binaryAddress.hexAsData())")
        /*
         範囲の中にModuloを含んでいる場合
         if lower < 0 < upper
         範囲の中にModuloを含んでいない場合
         else
         */
        guard let toAddress = toAddress else {
            return false
        }
        return have(node, between: toAddress, intervalType: .includeExclude)
    }
    public func have(_ node: Node, between toAddress: Node, intervalType: Interval) -> Bool {
        if self.binaryAddress.greaterEqual(toAddress.binaryAddress) {
            Log("Range Get Over Modulo, then Divide Detecting range into 2.")
            var firstIntervalType: Interval = .include
            var secondIntervalType: Interval = .includeExclude
            if intervalType == .includeExclude {
                firstIntervalType = .include
                secondIntervalType = .includeExclude
            } else if intervalType == .include {
                firstIntervalType = .include
                secondIntervalType = .include
            } else if intervalType == .exclude {
                firstIntervalType = .excludeInclude
                secondIntervalType = .includeExclude
            } else if intervalType == .excludeInclude {
                firstIntervalType = .excludeInclude
                secondIntervalType = .include
            }
            let rangeFirst = self.binaryAddress.inRangeAsData(intervalType: firstIntervalType, to: Data.Modulo.subtract(exponent: 0), about: node.binaryAddress)
            let rangeSecond = Data.DataNull.inRangeAsData(intervalType: secondIntervalType, to: toAddress.binaryAddress, about: node.binaryAddress)
            Log("\(rangeFirst) || \(rangeSecond)")
            if rangeFirst || rangeSecond {
                Log("the Node InRange.")
                return true
            } else {
                Log("the Node OutRange.")
                return false
            }
        } else {
            Log("Regular Range.")
            return self.binaryAddress.inRangeAsData(intervalType: intervalType, to: toAddress, about: node)
        }
    }

    /*
     Paper:
     while (id ∉ (n', n'.successor])    // if n' < id <= n'.succesor
         target: id
         self: n'
         self.successor: n'.successor
     */
    public func haveBetweenWithSuccessor(about target: Node) -> Bool {
        guard let successor = self.successor else {
            Log()
            return false
        }
        Log("haveBetweenWithSuccessor - inRange(intervalType: .excludeInclude")
        Log("about: \(target.binaryAddress.hexAsData()))")
        Log("from: \(self.binaryAddress.hexAsData())")
        Log("to: \(successor.binaryAddress.hexAsData())")
        return have(target, between: successor, intervalType: .excludeInclude)
    }

    /*
     update all nodes whose finger tables should refer to n
     
     n: self
     i: 0 orign (0 to 512)
     */
    public func updateOthers(i: Int, token: String) -> String? {
        Log()
        Log("2^\(i)")    //power(2,i)
        
        defer {
//            self.printFingerTable()
        }
        
        /*
         find last node p whose i^th finger might be n
         
         p = find_predecessor(Modulo(n - 2^(i-1)));
         */
        let newBinaryAddress = self.binaryAddress.subtractAsData(exponent: UInt(i))
        let moduloedBinaryAddress = newBinaryAddress.moduloAsData(exponentOf2: Data.ModuloAsExponentOf2)
        Log(self.binaryAddress.hexAsData())
        Log(moduloedBinaryAddress.hexAsData())
        Command.findPredecessor.run(node: self, operands: [String(i), moduloedBinaryAddress.hexAsData()], previousToken: token) {
            string in
            Log(string)
        }
        return nil
    }
    
    /*
     Paper:
     if node is i th finger of self, update self's finger table with node
        ex. finger[i].node = node

        n.update_finger_table(s, i)

     n: self
     s: node
     i: i
     */
    public func updateFingerTable(node: Node, i: Int, token: String) -> String? {
        Log(i)
        guard (0..<self.fingers.count).contains(i) else {
            return ""
        }
        defer {
            //#debug
//            if i == self.fingers.count - 1 {
//                self.printFingerTable()
//            }
//            if i == 0 {
//                self.printFingerTable()
//                Log()
//            }
        }
        Log("updateFingerTable have between .includeExclude")
        Log("about: \(node.binaryAddress.hexAsData()))")
        Log("from: \(fingers[i].interval[0].binaryAddress.hexAsData())")
        Log("to: \(fingers[i].node?.binaryAddress.hexAsData())")
        
        /*
         if s ∈ [n, finger[i].node)     //IntervalType: .includeExclude
           finger[i].node = s;
         */
        /*
         x if node = [self, fingers[i].node)
         ↓
         ⚪︎ if node = [fingers[i].interval.start, fingers[i].node)
         */
        let intervalStartNode = fingers[i].interval[0]
        Log("intervalStartNode: \(intervalStartNode.binaryAddress.hexAsData())")
        if intervalStartNode.have(node, between: fingers[i].node) {
            
            Log("have \(i)")
            if i == 0 {
                Log("\(self.getIp).successor \(node.getIp)")
                Log()
            }
            /*
             if update finger table by own node,
                pass.
             */
            if node.binaryAddress.hexAsData() == self.binaryAddress.hexAsData() {
                Log("Trying to Update finger table by own node.")
            } else {
                Log()
                fingers[i].node = node
                self.triggerStoreFingerTable = true
            }
            /*
             get first node preceding n
             */
            if let p = self.predecessor, p.getIp != self.getIp {
//                Log("\(self.getIp ?? "nil") Call as my Predecessor to \(p.getIp ?? "nil").")
//                Log("\(p.getIp ?? "nil") != \(self.getIp ?? "nil")")
                Command.updateFingerTable.send(node: self, to: p.dhtAddressAsHexString, operands: [node.dhtAddressAsHexString.toString, String(i)], previousToken: token) {
                    string in
                    Log(string)
                }
                return nil
            }
        } else {
            Log("have NOT \(i)")
        }
        return String(i)
    }

    /*
     Detect Newcomer Node, and Reflect New Node to own Finger Table.
     
     Periodically verify self’s immediate successor,
     and tell the successor about self.
     
     Do every boot up.
     */
    public func stabilize() {
        LogCommunicate()
//        guard let x = self.successor?.predecessor else {
//            return
//        }
//        guard let successorNodeIp = self.successor?.getIp else {
//            return
//        }
//        Command.queryYourPredecessor.send(node: self, to: successorNodeIp, operands: [""]) { a in
//            Log("Run [queryYourPredecessor] Command to \(successorNodeIp).")
//        }
        guard let successorNodeOverlayAddress = self.successor?.dhtAddressAsHexString else {
            Log()
            return
        }
        Command.queryYourPredecessor.send(node: self, to: successorNodeOverlayAddress, operands: [""]) { a in
            Log("Run [queryYourPredecessor] Command to \(successorNodeOverlayAddress).")
        }
    }
    public func replyStabilize(candidateSuccessor: Node) {
        LogEssential()
        if haveBetweenWithSuccessor(about: candidateSuccessor) {
            LogEssential()
            /*
             There is New Node for Own Node's Successor.
             */
            self.successor = candidateSuccessor
        }
//        self.successor?.notify(node: self)
        guard let successorNodeOverlayNetworkAddress = self.successor?.dhtAddressAsHexString else {
            LogEssential()
            return
        }
        Command.notifyPredecessor.send(node: self, to: successorNodeOverlayNetworkAddress, operands: [self.dhtAddressAsHexString.toString]) { a in
            Log("Run [notifyPredecessor] Command to \(successorNodeOverlayNetworkAddress).")
        }
        LogEssential()
    }
    
    // node thinks it might be our predecessor.
    public func notify(node: Node) {
        LogCommunicate()
        guard let predecessor = self.predecessor else {
            LogCommunicate()
            self.predecessor = node
            self.triggerStoreFingerTable = true
            return
        }
        if have(node, between: predecessor) {
            LogCommunicate()
            self.predecessor = node
            self.triggerStoreFingerTable = true
        }
        LogCommunicate()
    }
    
    //periodically refresh finger table entries.
//    public func fixFingers(token: String) {
//        let i = Int.random(in: 0..<self.fingers.count)
//        if let successor = findSuccessor(address: fingers[i].start, token: token) {
//            self.fingers[i].node = successor
//            self.triggerStoreFingerTable = true
//        }
//    }
    
    public func fixFingers(token: String) {
        Log()
        let i = Int.random(in: 0..<self.fingers.count)
        if let currentSuccessor = self.fingers[i].node {
            Log()
            Command.findSuccessor.send(node: self, to: currentSuccessor.dhtAddressAsHexString, operands: [String(i), fingers[i].start.dhtAddressAsHexString.toString], previousToken: token) {
                a in
                Log("Sent [Find Successor \(i)] Command to \(currentSuccessor.dhtAddressAsHexString.toString).")
            }
        }
    }
    public func replyFixFingers(i: Int, newSuccessor: Node, token: String) {
        Log()
        self.fingers[i].node = newSuccessor
        self.triggerStoreFingerTable = true
    }
    /*inprementation of Chord*/
}
