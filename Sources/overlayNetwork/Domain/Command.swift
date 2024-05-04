//
//  Command.swift
//  blocks
//
//  Created by よういち on 2021/08/19.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

public protocol CommandProtocol {
    func command(_ command: String) -> CommandProtocol
    func receive(node: inout any NodeProtocol, operands: String, from fromNodeOverlayNetworkAddress: OverlayNetworkAddressAsHexString, token: String) -> String?

    /*
     Replyコマンドは {COMMAND}_
     */
    var replyCommand: String {
        get
    }
    var sendCommand: String {
        get
    }

    func isReply() -> Bool
    static func rawValue(_ command: CommandProtocol) -> String
    
    func reply(node: any NodeProtocol, to overlayNetworkAddress: OverlayNetworkAddressAsHexString, operand: String?, token: String, callback: (String) -> Void) -> Void

    //run back in Local
    func runBack(node: any NodeProtocol, operand: String, token: String, callback: (String) -> Void) -> Void

    func send(node: any NodeProtocol, to overlayNetworkAddress: OverlayNetworkAddressAsHexString, operands: [String?], previousToken: String?, callback: (String) -> Void) -> Void

    //run in Local
    func run(node: any NodeProtocol, operands: [String?], previousToken: String?, callback: (String) -> Void) -> Void
    
    func operandUnification(operands: [String?]) -> String

    func operandTakeApart(operands: String) -> [String]
    
    var rawValue: String {
        get
    }
}
public extension CommandProtocol {
    /*
     Replyコマンドは {COMMAND}_
     */
    var replyCommand: String {
        return Self.rawValue(self) + "_"
    }
    var sendCommand: String {
        if Self.rawValue(self).contains("_") {
            return Self.rawValue(self).replacingOccurrences(of: "_", with: "")
        }
        return Self.rawValue(self)
    }

    func isReply() -> Bool {
        if Self.rawValue(self).contains("_") {
            return true
        }
        return false
    }

    func reply(node: any NodeProtocol, to overlayNetworkAddress: OverlayNetworkAddressAsHexString, operand: String?, token: String, callback: (String) -> Void) -> Void {
        Log("\(self.replyCommand) operand: \(String(describing: operand)) token: \(token) to: \(overlayNetworkAddress)")
        let operandValue: String = operand == nil ? "" : operand!
        Log()
        node.printQueue()
        //Enqueue the Command
        let job = Job(command: Command(rawValue: self.replyCommand) ?? Command.other, operand: operandValue, from: node.dhtAddressAsHexString, to: overlayNetworkAddress, type: .delegated, token: token)
        Log(job.token)
        if overlayNetworkAddress.equal(node.dhtAddressAsHexString) {
            Log("Switch to Loopback.")
            let job = Job(command: Command(rawValue: self.replyCommand) ?? Command.other, operand: operandValue, from: node.dhtAddressAsHexString, to: overlayNetworkAddress, type: .local, token: token)
            node.enQueue(socket: job)
        } else {
            node.enQueue(socket: job)
        }
    }

    //run back in Local
    func runBack(node: any NodeProtocol, operand: String, token: String, callback: (String) -> Void) -> Void {
        Log("\(self.rawValue) \(operand) \(token)")
        Log()
        node.printQueue()
        //Enqueue the Command
        let job = Job(command: Command(rawValue: self.replyCommand) ?? Command.other, operand: operand, from: node.dhtAddressAsHexString, to: node.dhtAddressAsHexString, type: .local, token: token)
        node.enQueue(socket: job)
    }

    func send(node: any NodeProtocol, to overlayNetworkAddress: OverlayNetworkAddressAsHexString, operands: [String?], previousToken: String? = nil, callback: (String) -> Void) -> Void {
        Log("\(self.rawValue) to \(overlayNetworkAddress)")
        Log(operands)
        //Enqueue the Command
        let operand = operandUnification(operands: operands)
        let job = Job(command: self, operand: operand, from: node.dhtAddressAsHexString, to: overlayNetworkAddress, type: .delegate, token: nil, previousJobToken: previousToken)
        node.enQueue(job: job)
        #if DEBUG
        let commandInstance: CommandProtocol? = Command(rawValue: self.rawValue)
        if commandInstance == nil {
            //blocks command, appendix with blocks
            Log("\(node.premiumCommand?.command(self.rawValue).rawValue) operands: \(operands) token: \(job.token) previousToken: \(String(describing: previousToken)) To: \(overlayNetworkAddress)")
        } else {
            //overlay network command
            Log("\(self.rawValue) operands: \(operands) token: \(job.token) previousToken: \(String(describing: previousToken)) To: \(overlayNetworkAddress)")
        }
        #endif
        if overlayNetworkAddress.equal(node.dhtAddressAsHexString) {
            Log("Switch to Loopback.")
            let job = Job(command: self, operand: operand, from: node.dhtAddressAsHexString, to: overlayNetworkAddress, type: .local, token: nil, previousJobToken: previousToken)
            node.enQueue(socket: job)
        } else {
            node.enQueue(socket: job)
        }
    }

    //run in Local
    func run(node: any NodeProtocol, operands: [String?], previousToken: String? = nil, callback: (String) -> Void) -> Void {
        Log(self.rawValue)
        Log(operands)
        //Enqueue the Command
        let operand = operandUnification(operands: operands)
        let job = Job(command: self, operand: operand, from: node.dhtAddressAsHexString, to: node.dhtAddressAsHexString, type: .local, token: nil, previousJobToken: previousToken)
        Log(job.token)
        node.enQueue(job: job)
        node.enQueue(socket: job)
        Log()
        node.printQueue()
        Log("\(self.rawValue) \(operands) token: \(job.token) previousToken: \(String(describing: previousToken)) to: \(node.dhtAddressAsHexString)")
        node.printSocketQueue()
    }
    
    func operandUnification(operands: [String?]) -> String {
        let unifiedOperand = operands.enumerated().reduce("") {
            if $1.offset == operands.count - 1 {
                return $0 + "\($1.element ?? "")"
            } else {
                return $0 + "\($1.element ?? ""),"
            }
        }
        return unifiedOperand
    }
    
    func operandTakeApart(operands: String) -> [String] {
        var inJsonFormatted = 0
        var operandArray = [String]()
        var sindexInt = 0
        operands.enumerated().forEach {
            if $0.element == "{" {
                inJsonFormatted += 1
            }
            if $0.element == "}" {
                inJsonFormatted -= 1
            }
//            Log("offset: \($0.offset) length: \(operands.count - 1) inJson: \(inJsonFormatted)")
            if $0.element == "," || $0.offset == operands.count - 1 {
                //Delimiter OR Last Character
                if inJsonFormatted != 0 {
//                    Log()
                    //In Json formatted Operands
                } else {
//                    Log()
                    //Usual Text Operands
                    var eindexOffsetInt = $0.offset - 1 < 0 ? 0 : $0.offset - 1
                    
                    if ($0.offset == operands.count - 1) && $0.element != "," {
                        //Last Character & Usual Character.
                        eindexOffsetInt = $0.offset
                    }

                    let sindex = operands.index(operands.startIndex, offsetBy: sindexInt)
                    let eindex = operands.index(operands.startIndex, offsetBy: eindexOffsetInt)
//                    Log("\(sindex) ... \(eindex)")
                    var aElement = ""
                    if sindex <= eindex {
                        aElement = String(operands[sindex...eindex])
                    } else {
                        aElement = ""
                    }
//                    Log(aElement)
                    operandArray.append(aElement)
                    sindexInt = $0.offset + 1
                }
            }
            if $0.element == "," && $0.offset == operands.count - 1 {
//                Log()
                //If Last Character is Delimiter,
                //  Append Blank Element.
                let aElement = ""
                operandArray.append(aElement)
            }
        }
        return operandArray
    }
}

public enum Command: String, CommandProtocol {
    //Chord
    case findSuccessor = "FS"
    case findSuccessorReply = "FS_"
    case closestPrecedingFinger = "CP"
    case closestPrecedingFingerReply = "CP_"
    case queryYourSuccessor = "QS"
    case queryYourSuccessorReply = "QS_"
    case queryYourPredecessor = "QP"
    case queryYourPredecessorReply = "QP_"
    case notifyPredecessor = "NP"   //notify predecessor to successor node
    case notifyPredecessorReply = "NP_"   //notify predecessor to successor node

    case findPredecessor = "FP"
    case findPredecessorReply = "FP_"
    case initFingerTable = "IF"
    case initFingerTableReply = "IF_"
    case updateOthers = "UO"
    case updateOthersReply = "UO_"
    case updateFingerTable = "UF"
    case updateFingerTableReply = "UF_"
    case updateSuccessorsPredecessor = "US"
    case updateSuccessorsPredecessorReply = "US_"
    case updatePredecessorsSuccessor = "UP"
    case updatePredecessorsSuccessorReply = "UP_"
    
    //Resource
    case fetchResource = "FR"
    case fetchResourceReply = "FR_"
    case other = "ZZ"
    
    public func command(_ command: String) -> CommandProtocol {
        switch command {
            /*
             Chord
             */
        case "FS":
            return Command.findSuccessor
        case "FS_":
            return Command.findSuccessorReply
        case "CP":
            return Command.closestPrecedingFinger
        case "CP_":
            return Command.closestPrecedingFingerReply
        case "QS":
            return Command.queryYourSuccessor
        case "QS_":
            return Command.queryYourSuccessorReply
        case "FP":
            return Command.findPredecessor
        case "FP_":
            return Command.findPredecessorReply
        case "IF":
            return Command.initFingerTable
        case "IF_":
            return Command.initFingerTableReply
        case "UO":
            return Command.updateOthers
        case "UO_":
            return Command.updateOthersReply
        case "UF":
            return Command.updateFingerTable
        case "UF_":
            return Command.updateFingerTableReply
        case "US":
            return Command.updateSuccessorsPredecessor
        case "US_":
            return Command.updateSuccessorsPredecessorReply
        case "UP":
            return Command.updatePredecessorsSuccessor
        case "UP_":
            return Command.updatePredecessorsSuccessorReply
            
            /*
             Resource
             */
        case "FR":
            return Command.fetchResource
        case "FR_":
            return Command.fetchResourceReply
            
        default:
            return Command.other
        }
    }
    
    public static func rawValue(_ command: CommandProtocol) -> String {
        switch command {
            //Chord
        case findSuccessor:
            return "FS"
        case findSuccessorReply:
            return "FS_"
        case closestPrecedingFinger:
            return "CP"
        case closestPrecedingFingerReply:
            return "CP_"
        case queryYourSuccessor:
            return "QS"
        case queryYourSuccessorReply:
            return "QS_"
        case findPredecessor:
            return "FP"
        case findPredecessorReply:
            return "FP_"
        case initFingerTable:
            return "IF"
        case initFingerTableReply:
            return "IF_"
        case updateOthers:
            return "UO"
        case updateOthersReply:
            return "UO_"
        case updateFingerTable:
            return "UF"
        case updateFingerTableReply:
            return "UF_"
        case updateSuccessorsPredecessor:
            return "US"
        case updateSuccessorsPredecessorReply:
            return "US_"
        case updatePredecessorsSuccessor:
            return "UP"
        case updatePredecessorsSuccessorReply:
            return "UP_"
            
            //Resource
        case fetchResource:
            return "FR"
        case fetchResourceReply:
            return "FR_"
            
        case other:
            return "ZZ"
        default:
            return ""
        }
    }
    
    /*
     Received Command
     
     Abstruct:
     Called in Node.received()
     
     Return:
     if Delegate Command(Normal command):
     nil:
     Don't throw reply command.
     != nil:
     Use return value as reply command operand.
     if Reply Command:
     nil:
     Don't throw previous command's Reply.
     != nil:
     Throw previous command with job result as operand.
     */
    public func receive(node: inout any NodeProtocol, operands: String, from fromNodeOverlayNetworkAddress: OverlayNetworkAddressAsHexString, token: String) -> String? {
        LogCommunicate("\(self.rawValue) \(operands) \(token) From: \(fromNodeOverlayNetworkAddress)")
        let operandArray = operandTakeApart(operands: operands)
        Log(operandArray)
        
        var doneAllFollowingJobs = true /* Use Only Reply Command */
        node.doneAllFingerTableEntry = false
        if self.isReply(), let _ = Command(rawValue: self.sendCommand) { Log()
            //Mark dequeue flag on it's status.
            let (_, _) = node.deQueueWithType(token: token, type: [.local, .delegate])
            let (updatedJob, _) = node.setJobResult(token: token, type: [.local, .delegate], result: operands) // **job result is overwritten following code possibly.
            
            /*
             Detect done ALL following(Chained) jobs.
             */
            if let chainedJobs = node.fetchFollowingJobs(token: token) {
                Log()
                let runningJob = chainedJobs.filter {
                    $0.status != .dequeued
                }.first
                doneAllFollowingJobs = runningJob == nil ? true : false
            }
            Log(node.doneAllFingerTableEntry)
            Log(doneAllFollowingJobs)
            node.printQueue(job: updatedJob)
        } else { Log()
            /*
             New Job
             
             Delegated by a node(other or own).
             Token use received token, the job token is not generated anew.
             */
            node.enQueue(job: Job(command: self, operand: operands, from: fromNodeOverlayNetworkAddress, to: node.dhtAddressAsHexString, type: .delegated, token: token))
            node.printQueue()
        }
        Log()
        
        switch self {
            /*
             Fetch Resources
             */
        case .fetchResource :   //MARK: fetchResource
            Log("Do \(self.rawValue)")
            //See over finger table, then Confirm be in charged of the resource.
            /*
             0: Hashed Key
             
             if in charged of it,
             return resource
             
             if other node's responsible,
             return node's ip address
             */
            let key = operandArray[0]
            if key == "" {
                Log()
                return nil
            }
            if let (resourceString, responsibleNodeIpAndPort) = node.fetchResource(hashedKey: key) {
                /*
                 0: result (resource as String)
                 1: responsible node ip
                 */
                return operandUnification(operands: [key, resourceString, responsibleNodeIpAndPort])
            }
            return nil
        case .fetchResourceReply :
            Log("Do \(self.rawValue)")
            /*
             Operands
             
             0: hashed key
             1: result (resource as String)
             2: responsible node overlayNetwork Address
             */
            Log(operandArray[0])    //0: hashed key
            Log(operandArray[1])    //1: result (resource as String)
            Log(operandArray[2])    //2: responsible node overlayNetwork Address

            /*
             operands[0]のresultが空なら
             operands[1]のipアドレスに再度FRコマンドを送る
             resultがあれば
             リソース取得完了となる
             */
            let key = operandArray[0]
            let resultString = operandArray[1]
            let responsibleNodeOverlayNetworkAddress = operandArray[2]
            if resultString != "" {
                /*
                 リソース取得完了
                 */
                Log("Have Fetched Resource: \(resultString)")
            } else if let ipAndNode = Node(dhtAddressAsHexString: responsibleNodeOverlayNetworkAddress) {
                //Send FR Command to retry.
                Command.fetchResource.send(node: node, to: ipAndNode.dhtAddressAsHexString, operands: [key]) { string in
                    Log(string)
                }
            }
            return nil
            
            /*
             Build Chord Finger Table
             */
        case .initFingerTable : //MARK: initFingerTable
            Log("Do \(self.rawValue)")
            guard operandArray.count > 0, let babysitterNode = Node(dhtAddressAsHexString: operandArray[0]) else {
                Log()
                return node.firstNodeInitFingerTable(token: token)
            }
            Log(node.fingers.count)
            let doneAllEntry = node.initFingerTable(i: node.fingers.count, babysitterNode: babysitterNode, token: token)
            Log(doneAllEntry)
            if let doneAllEntry = doneAllEntry, doneAllEntry == "completed" {
                Log("Done All IF.")
                node.doneAllFingerTableEntry = true
                
                /*
                 Detect done get ALL table entries's successor(node entry).
                 */
                Log(doneAllFollowingJobs)
                Log(node.doneAllFingerTableEntry)
                if node.doneAllFingerTableEntry && doneAllFollowingJobs {
                    Log()
                    /*
                     Done ALL follwing jobs.
                     Detect done getting ALL table entries's successor(node entry).
                     */
                    Command.updateOthers.run(node: node, operands: [String(0)]) {
                        a in
                        Log("Run [Update others] Command to \(node.ip?.toString()).")
                    }
                }
                
                //                node.printFingerTableEssential()
                node.storeFingerTable()
                //                node.printArchivedFingerTable()
            }
            Log()
            return doneAllEntry
        case .initFingerTableReply :
            Log("Do \(self.rawValue)")
            Log(operands)
            guard operandArray.count >= 2 else {
                Log(operandArray.count)
                return nil
            }
            /*
             Detect done get ALL table entries's successor(node entry).
             
             Notice:
             *Boot Node Don't Send Reply Command(Init finger table).
             */
            Log(doneAllFollowingJobs)
            Log(node.doneAllFingerTableEntry)
            if node.doneAllFingerTableEntry && doneAllFollowingJobs {
                Log()
                /*
                 Move to .initFingerTable
                 ↓
                 Done ALL follwing jobs.
                 Detect done getting ALL table entries's successor(node entry).
                 */
            } else {
                guard let babysitterNode = Node(dhtAddressAsHexString: operandArray[1]) else {
                    Log(operandArray.count)
                    return nil
                }
                Log(babysitterNode.dhtAddressAsHexString)
                Command.initFingerTable.run(node: node, operands: [babysitterNode.dhtAddressAsHexString.toString]) {
                    string in
                    Log(string)
                }
            }
            return nil
        case .updateOthers : //MARK: updateOthers
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            guard let index = Int(operandArray[0]) else {
                Log()
                return nil
            }
            Log(index)
            Log(token)
            return node.updateOthers(i: index, token: token)
        case .updateOthersReply :
            Log("Do \(self.rawValue)")
            /*
             chained from FP_
             [fingerTableIndex, precedingNode.ipAndPortString, predecessorsSuccessorNode.ipAndPortString]
             
             chained from UF_
             [String(fingerTableIndex), "", ""]
             */
            Log(operandArray[0])    //0: finger table index
            //1: target node hex address (Not use)
            Log(operandArray[2])    //2: precedingNode's overlayNetwork Address
            Log(operandArray[3])    //3: predecessorsSuccessorNode's overlayNetwork Address
            //4: result (Not use)
            guard let index = Int(operandArray[0]) else {
                Log()
                return nil
            }
            if let predecessorNode = Node(dhtAddressAsHexString: operandArray[2]), let successorNode = Node(dhtAddressAsHexString: operandArray[3]) {
                Log()
                /*
                 Chained from find predecessor as previous command.
                 */
                //Likely 0...512
                Log("\(index) < \(node.fingers.count)")
                if (0..<node.fingers.count).contains(index) {
                    //OW: if index >= 0 && index < node.fingers.count
                    Log("\(node.getIp) Call by UpdateOthers Loop (\(index)) to \(predecessorNode.getIp).")
//                    Log("\(index) \(predecessorNode.ip?.toString()) operands: \(node.ipAndPortString), \(String(index))")
                    Log("\(index) \(predecessorNode.ip?.toString()) operands: \(node.dhtAddressAsHexString.toString), \(String(index))")
                    Log(token)
                    Command.updateFingerTable.send(node: node, to: predecessorNode.dhtAddressAsHexString, operands: [node.dhtAddressAsHexString.toString, String(index)], previousToken: token) {
                        string in
                        Log(string)
                    }
                } else {
                }
            } else {
                Log()
                /*
                 Chained from update finger table as previous command.
                 */
                /*
                 Increment index on finger table.
                 */
                let nextIndex = index + 1
                Log("NextIndex: \(nextIndex)")
                Command.updateOthers.run(node: node, operands: [String(nextIndex)]) {
                    a in
                    Log("Run [Update others] Command to \(node.dhtAddressAsHexString).")
                }
            }
            if index == node.fingers.count - 1 {
                //                node.printFingerTableEssential()
            }
            return nil
        case .updateFingerTable :   //MARK: updateFingerTable
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: overlayNetworkAddress
            Log(operandArray[1])    //1: finger table index
            guard let sNode = Node(dhtAddressAsHexString: operandArray[0]) else {
                Log()
                return nil
            }
            guard let index = Int(operandArray[1]) else {
                Log()
                return nil
            }
            Log("\(index) \(sNode.ip?.toString())")
            Log(token)
            return node.updateFingerTable(node: sNode, i: index, token: token)
        case .updateFingerTableReply :
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            guard let fingerTableIndex = Int(operandArray[0]) else {
                return nil
            }
            //Go to Next Index in Finger Table.
            if (0..<node.fingers.count).contains(fingerTableIndex) {
                Log(fingerTableIndex)
                //OW: if index >= 0 && index < node.fingers.count
                if node.fingers.count - 1 == fingerTableIndex {
                    Log("Done All UO.")
                    /*
                     Have Done All UO.
                     */
                    if let successor = node.successor {
                        Log("\(successor.getIp)")
                        Command.updateSuccessorsPredecessor.send(node: node, to: successor.dhtAddressAsHexString, operands: [node.dhtAddressAsHexString.toString], previousToken: token) {
                            _ in
                            Log("Sent [Update Successor's Predecessor] Command to \(successor.dhtAddressAsHexString).")
                        }
                    }
                }
                /*
                 Log(operandArray[0])    //0: finger table index
                 //1: target node hex address (Not use)
                 Log(operandArray[2])    //2: precedingNode's ipAndPort
                 Log(operandArray[3])    //3: predecessorsSuccessorNode's ipAndPort
                 //4: result (Not use)
                 */
                return operandUnification(operands: [String(fingerTableIndex), "", "", "", ""])
            }
            if fingerTableIndex == node.fingers.count {
                Log(node.fingers.count)
                /*
                 Have Done All.
                 */
                //                node.printFingerTableEssential()
            }
            Log()
            return nil
        case .findSuccessor :   //MARK: findSuccessor
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: dhtaddress
            Command.findPredecessor.run(node: node, operands: operandArray, previousToken: token) {
                a in
                Log("Run [Find Predecessor] Command to \(node.dhtAddressAsHexString).")
            }
            return nil  /*Do NOT send reply command back.*/
        case .findSuccessorReply :
            Log("Do \(self.rawValue)")
            /*
             chained from FP
             [fingerTableIndex, precedingNode.ipAndPortString, predecessorsSuccessorNode.ipAndPortString]
             */
            Log(operandArray[0])    //0: finger table index
            //1: target node (Not use)
            Log(operandArray[2])    //2: predecessor.overlayNetwork Address
            Log(operandArray[3])    //3: predecessorsSuccessorNode.overlayNetwork Address
            //4: result (Not use)
            guard let predecessorNode = Node(dhtAddressAsHexString: operandArray[2]), let successorNode = Node(dhtAddressAsHexString: operandArray[3]) else {
                /*
                 Not found Successor node. Such as Operand == ""
                 
                 Always in query findSuccessor command.
                 */
                return nil
            }
            /*
             set successorNode to finger table on index
             */
            Log(operandArray[0])
            if let fingerTableIndex = Int(operandArray[0]) {
                Log("update successor \(fingerTableIndex)")
                if fingerTableIndex == 0 {
                    Log("\(node.getIp).successor \(successorNode.getIp)")
                    Log()
                }
                
                node.fingers[fingerTableIndex].node = successorNode
                node.triggerStoreFingerTable = true
                return operandUnification(operands: [String(fingerTableIndex), successorNode.dhtAddressAsHexString.toString])
            }
            return nil
        case .findPredecessor : //MARK: findPredecessor
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node dhtaddress
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]) else {
                return nil
            }
            Log(targetNode.description)
            /*
             if id ∉ (n', n'.successor]
             Get Next Closest Preceding Finger
             */
            if let (predecessorNode, predecessorsSuccessorNode) = node.findPredecessor(fingerTableIndex, for: targetNode, token: token) {
                Log("Found Predecessor Node")
                Log("\(fingerTableIndex), \(predecessorsSuccessorNode?.dhtAddressAsHexString)")
                return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, predecessorNode.dhtAddressAsHexString.toString, predecessorsSuccessorNode?.dhtAddressAsHexString.toString, "found"])
            }
            return nil
        case .findPredecessorReply :
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node overlayNetwork Address
            Log(operandArray[3])    //3: preceding node's successor overlayNetwork Address
            Log(operandArray[4])    //4: result "found" or "not"
            let fingerTableIndex = operandArray[0]
            Log(fingerTableIndex)
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(dhtAddressAsHexString: operandArray[2]), let predecessorsSuccessorNode = Node(dhtAddressAsHexString: operandArray[3]) else {
                return nil
            }
            let result = operandArray[4]
            if result == "found" {
                /*
                 Chained Next Command
                 FS or FP
                 */
                Log("result: Found")
                return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.dhtAddressAsHexString.toString, predecessorsSuccessorNode.dhtAddressAsHexString.toString, "found"])
            } else {
                Log("result: Not Found")
                /*
                 Send findPredecessor Command to Preceding Node.
                 */
                Command.findPredecessor.send(node: node, to: precedingNode.dhtAddressAsHexString, operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString], previousToken: token) {
                    a in
                    Log("Run [Find Predecessor] Command to \(precedingNode.dhtAddressAsHexString).")
                }
                return nil
            }
        case .closestPrecedingFinger :  //MARK: closestPrecedingFinger
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: areYouPredecessor result "true" or "false"
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]) else {
                return nil
            }
            let precedingNode = node.closestPrecedingFinger(address: targetNode, token: token)
            Log(precedingNode.getIp)
            Command.queryYourSuccessor.send(node: node, to: precedingNode.dhtAddressAsHexString, operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.dhtAddressAsHexString.toString], previousToken: token) {
                a in
                Log("Run [queryYourSuccessor] Command to \(precedingNode.dhtAddressAsHexString).")
            }
            return nil
        case .closestPrecedingFingerReply :
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node overlayNetwork Address
            Log(operandArray[3])    //3: preceding node's successor overlayNetwork Address
            Log(operandArray[4])    //4: result: "found" or "not"
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(dhtAddressAsHexString: operandArray[2]), let successorNode = Node(dhtAddressAsHexString: operandArray[3]) else {
                return nil
            }
            let result = operandArray[4]
            return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.dhtAddressAsHexString.toString, successorNode.dhtAddressAsHexString.toString, result])
        case .queryYourSuccessor :  //MARK: queryYourSuccessor
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node overlayNetwork Address
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(dhtAddressAsHexString: operandArray[2]) else {
                return nil
            }
            return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.dhtAddressAsHexString.toString, node.successor?.dhtAddressAsHexString.toString])
        case .queryYourSuccessorReply :
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node overlayNetwork Address
            Log(operandArray[3])    //3: successor's overlayNetwork Address
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(dhtAddressAsHexString: operandArray[2]),  let successorNode = Node(dhtAddressAsHexString: operandArray[3]) else {
                return nil
            }
            return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.dhtAddressAsHexString.toString, successorNode.dhtAddressAsHexString.toString, ""])
        case .queryYourPredecessor :  //MARK: queryYourPredecessor
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index (Optional)
            let fingerTableIndex = operandArray[0]
            guard let predecessorNode = node.predecessor else {
                return nil
            }
            return operandUnification(operands: [fingerTableIndex, predecessorNode.dhtAddressAsHexString.toString])
        case .queryYourPredecessorReply :
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: predecessor node hex address
            let fingerTableIndex = operandArray[0]
            guard let predecessorNode = Node(dhtAddressAsHexString: operandArray[1]) else {
                return nil
            }
            if operandArray[1] == node.dhtAddressAsHexString.toString {
                Log("In Stable: Successor's Predecessor is Own Node.")
            } else {
                Log("")
                node.replyStabilize(candidateSuccessor: predecessorNode)
            }
            return nil
            
            //notify predecessor to successor node
        case .notifyPredecessor : //MARK: notifyPredecessor
            
            //#now
            return nil
        case .notifyPredecessorReply :
            return nil
            
        /*
         updateSuccessorsPredecessor & updateSuccessorsPredecessorReply

            Successor Node's Predecessor Node
            Successor Node
         
            ↓ Join a Node

            Successor Node's Predecessor Node
         →  Join Node
            Successor Node
         */
        case .updateSuccessorsPredecessor : //MARK: updateSuccessorsPredecessor
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //1: dht address on Predecessor
            guard let predecessor = Node(dhtAddressAsHexString: operandArray[0]) else {
                Log()
                return nil
            }
            Log("(US)predecessor: \(predecessor.dhtAddressAsHexString) from \(fromNodeOverlayNetworkAddress)")
            var previousPredecessor: Node? = node.predecessor
            if let previousPredecessorDhtAddressAsHexString = previousPredecessor?.dhtAddressAsHexString, predecessor.dhtAddressAsHexString.equal(previousPredecessorDhtAddressAsHexString) {
                /*
                 As Predecessor is No Change, Do NOT Reply command.
                 */
                previousPredecessor = nil
            } else {
                node.predecessor = predecessor
                node.triggerStoreFingerTable = true
            }

            /*
             Reply Previous Predecessor IP in Own Node to Node Sent updateSuccessorsPredecessor Command.
             */
            Log("\(predecessor.dhtAddressAsHexString) \(previousPredecessor?.dhtAddressAsHexString)")
            return operandUnification(operands: [previousPredecessor?.dhtAddressAsHexString.toString])
        case .updateSuccessorsPredecessorReply :
            Log("Do \(self.rawValue)")
            Log(operandArray[0])    //1: dht address on Predecessor
            /* Reply from Successor Node At Init Finger Table */
            guard let successorsPreviousPredecessor = Node(dhtAddressAsHexString: operandArray[0]) else {
                return nil
            }
            Log("(US_)predecessor: \(successorsPreviousPredecessor.dhtAddressAsHexString) from \(fromNodeOverlayNetworkAddress)")
            node.predecessor = successorsPreviousPredecessor
            node.triggerStoreFingerTable = true
            return nil
        case .updatePredecessorsSuccessor : //MARK: updatePredecessorsSuccessor
            Log("Do \(self.rawValue)")
            guard let successor = Node(dhtAddressAsHexString: operandArray[0]) else {
                return nil
            }
            Log("\(successor.dhtAddressAsHexString)")
            node.successor = successor
            return ""
        case .updatePredecessorsSuccessorReply :
            Log("Do \(self.rawValue)")
            /* Reply from Successor Node At Init Finger Table */
            return nil
        default:
            Log()
            return ""
        }
    }
}
