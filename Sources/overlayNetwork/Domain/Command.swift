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
    func receive(node: inout any NodeProtocol, operands: String, from fromNodeIp: String, token: String) -> String?
    
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
    func reply(node: any NodeProtocol, to ip: String, operand: String?, token: String, callback: (String) -> Void) -> Void

    //run back in Local
    func runBack(node: any NodeProtocol, operand: String, token: String, callback: (String) -> Void) -> Void

    func send(node: any NodeProtocol, to ip: String, operands: [String?], previousToken: String?, callback: (String) -> Void) -> Void

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

    func reply(node: any NodeProtocol, to ip: String, operand: String?, token: String, callback: (String) -> Void) -> Void {
        Log("\(self.replyCommand) operand: \(String(describing: operand)) token: \(token) to: \(ip)")
        let operandValue: String = operand == nil ? "" : operand!
        Log()
        node.printQueue()
        return node.replyCommand(to: ip, command: Command(rawValue: self.replyCommand) ?? Command.other, operand: operandValue, token: token)
    }

    //run back in Local
    func runBack(node: any NodeProtocol, operand: String, token: String, callback: (String) -> Void) -> Void {
        Log("\(String(describing: Self.rawValue)) \(operand) \(token)")
        Log()
        node.printQueue()
        return node.replyCommand(to: node.ip.toString(), command: Command(rawValue: self.replyCommand) ?? Command.other, operand: operand, token: token)
    }

    func send(node: any NodeProtocol, to ip: String, operands: [String?], previousToken: String? = nil, callback: (String) -> Void) -> Void {
        Log()
        //Enqueue the Command
        let operand = operandUnification(operands: operands)
        let job = Job(command: self, operand: operand, from: node.ip.toString(), to: ip, type: .delegate, token: nil, previousJobToken: previousToken)
        //        Log(job.token)
        node.enQueue(job: job)
        #if DEBUG
        let commandInstance: CommandProtocol? = Command(rawValue: self.rawValue)
        if commandInstance == nil {
            //blocks command, appendix with blocks
            LogEssential("\(node.premiumCommand?.command(self.rawValue).rawValue) operands: \(operands) token: \(job.token) previousToken: \(String(describing: previousToken)) To: \(ip)")
        } else {
            //overlay network command
            LogEssential("\(self.rawValue) operands: \(operands) token: \(job.token) previousToken: \(String(describing: previousToken)) To: \(ip)")
        }
        #endif
        return node.sendCommand(to: ip, command: self, operand: operand, token: job.token)
    }

    //run in Local
    func run(node: any NodeProtocol, operands: [String?], previousToken: String? = nil, callback: (String) -> Void) -> Void {
        //Enqueue the Command
        let operand = operandUnification(operands: operands)
        let job = Job(command: self, operand: operand, from: node.ip.toString(), to: node.ip.toString(), type: .local, token: nil, previousJobToken: previousToken)
        Log(job.token)
        node.enQueue(job: job)
        Log()
        node.printQueue()
        Log("\(self.rawValue) \(operands) token: \(job.token) previousToken: \(String(describing: previousToken)) to: \(node.ip.toString())")
        return node.sendCommand(to: node.ip.toString(), command: self, operand: operand, token: job.token)
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
    public func receive(node: inout any NodeProtocol, operands: String, from fromNodeIp: String, token: String) -> String? {
        LogEssential("\(self.rawValue) \(operands) \(token) From: \(fromNodeIp)")
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
            node.enQueue(job: Job(command: self, operand: operands, from: fromNodeIp, to: node.ip.toString(), type: .delegated, token: token))
            node.printQueue()
        }
        Log()
        
        switch self {
            /*
             Fetch Resources
             */
        case .fetchResource :   //MARK: fetchResource
            LogEssential("Do \(self.rawValue)")
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
            LogEssential("Do \(self.rawValue)")
            /*
             Operands
             
             0: hashed key
             1: result (resource as String)
             2: responsible node ip
             */
            
            /*
             operands[0]のresultが空なら
             operands[1]のipアドレスに再度FRコマンドを送る
             resultがあれば
             リソース取得完了となる
             */
            let key = operandArray[0]
            let resultString = operandArray[1]
            let responsibleNodeIpAndPort = operandArray[2]
            if resultString != "" {
                /*
                 リソース取得完了
                 */
                Log("Have Fetched Resource: \(resultString)")
            } else if let ipAndNode = Node(ipAndPort: responsibleNodeIpAndPort) {
                //Send FR Command to retry.
                Command.fetchResource.send(node: node, to: ipAndNode.getIp, operands: [key]) { string in
                    Log(string)
                }
            }
            return nil
            
            /*
             Build Chord Finger Table
             */
        case .initFingerTable : //MARK: initFingerTable
            //#now should modify for showing message as done inited finger table.
            
            LogEssential("Do \(self.rawValue)")
            guard operandArray.count > 0, let babysitterNode = Node(ipAndPort: operandArray[0]) else {
                Log()
                return node.firstNodeInitFingerTable(token: token)
            }
            Log(node.fingers.count)
            let doneAllEntry = node.initFingerTable(i: node.fingers.count, babysitterNode: babysitterNode, token: token)
            Log(doneAllEntry)
            if let doneAllEntry = doneAllEntry, doneAllEntry == "completed" {
                LogEssential("Done All IF.")
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
                        LogEssential("Run [Update others] Command to \(node.ip.toString()).")
                    }
                }
                
                //                node.printFingerTableEssential()
                node.storeFingerTable()
                //                node.printArchivedFingerTable()
            }
            Log()
            return doneAllEntry
        case .initFingerTableReply :
            LogEssential("Do \(self.rawValue)")
            /*
             return operandUnification(operands: [String(fingerTableIndex), successorNode.ipAndPortString])
             */
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
                guard let babysitterNode = Node(ipAndPort: operandArray[1]) else {
                    Log(operandArray.count)
                    return nil
                }
                Log(babysitterNode.ipAndPortString)
                Command.initFingerTable.run(node: node, operands: [babysitterNode.ipAndPortString]) {
                    string in
                    Log(string)
                }
            }
            return nil
        case .updateOthers : //MARK: updateOthers
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            guard let index = Int(operandArray[0]) else {
                Log()
                return nil
            }
            Log(index)
            Log(token)
            return node.updateOthers(i: index, token: token)
        case .updateOthersReply :
            LogEssential("Do \(self.rawValue)")
            /*
             chained from FP_
             [fingerTableIndex, precedingNode.ipAndPortString, predecessorsSuccessorNode.ipAndPortString]
             
             chained from UF_
             [String(fingerTableIndex), "", ""]
             */
            Log(operandArray[0])    //0: finger table index
            //1: target node hex address (Not use)
            Log(operandArray[2])    //2: precedingNode's ipAndPort
            Log(operandArray[3])    //3: predecessorsSuccessorNode's ipAndPort
            //4: result (Not use)
            guard let index = Int(operandArray[0]) else {
                Log()
                return nil
            }
            if let predecessorNode = Node(ipAndPort: operandArray[2]), let successorNode = Node(ipAndPort: operandArray[3]) {
                Log()
                /*
                 Chained from find predecessor as previous command.
                 */
                //Likely 0...512
                Log("\(index) < \(node.fingers.count)")
                if (0..<node.fingers.count).contains(index) {
                    //OW: if index >= 0 && index < node.fingers.count
                    LogEssential("\(node.getIp) Call by UpdateOthers Loop (\(index)) to \(predecessorNode.getIp).")
                    Log("\(index) \(predecessorNode.ip.toString()) operands: \(node.ipAndPortString), \(String(index))")
                    Log(token)
                    Command.updateFingerTable.send(node: node, to: predecessorNode.ip.toString(), operands: [node.ipAndPortString, String(index)], previousToken: token) {
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
                    Log("Run [Update others] Command to \(node.ip.toString()).")
                }
            }
            if index == node.fingers.count - 1 {
                //                node.printFingerTableEssential()
            }
            return nil
        case .updateFingerTable :   //MARK: updateFingerTable
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: ipAndPort
            Log(operandArray[1])    //1: finger table index
            guard let sNode = Node(ipAndPort: operandArray[0]) else {
                Log()
                return nil
            }
            guard let index = Int(operandArray[1]) else {
                Log()
                return nil
            }
            Log("\(index) \(sNode.ip.toString())")
            Log(token)
            return node.updateFingerTable(node: sNode, i: index, token: token)
        case .updateFingerTableReply :
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            guard let fingerTableIndex = Int(operandArray[0]) else {
                return nil
            }
            //Go to Next Index in Finger Table.
            if (0..<node.fingers.count).contains(fingerTableIndex) {
                Log(fingerTableIndex)
                //OW: if index >= 0 && index < node.fingers.count
                if node.fingers.count - 1 == fingerTableIndex {
                    LogEssential("Done All UO.")
                    /*
                     Have Done All UO.
                     */
                    if let successor = node.successor {
                        LogEssential("\(successor.getIp)")
                        Command.updateSuccessorsPredecessor.send(node: node, to: successor.ip.toString(), operands: [node.ipAndPortString], previousToken: token) {
                            _ in
                            Log("Sent [Update Successor's Predecessor] Command to \(successor.ip.toString()).")
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
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: dhtaddress
            Command.findPredecessor.run(node: node, operands: operandArray, previousToken: token) {
                a in
                Log("Run [Find Predecessor] Command to \(node.ip.toString()).")
            }
            return nil  /*Do NOT send reply command back.*/
        case .findSuccessorReply :
            LogEssential("Do \(self.rawValue)")
            /*
             chained from FP
             [fingerTableIndex, precedingNode.ipAndPortString, predecessorsSuccessorNode.ipAndPortString]
             */
            LogEssential(operandArray[0])    //0: finger table index
            //1: target node (Not use)
            LogEssential(operandArray[2])    //2: predecessor.ipAndPortString
            LogEssential(operandArray[3])    //3: predecessorsSuccessorNode.ipAndPortString
            //4: result (Not use)
            guard let predecessorNode = Node(ipAndPort: operandArray[2]), let successorNode = Node(ipAndPort: operandArray[3]) else {
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
                LogEssential("update successor \(fingerTableIndex)")
                if fingerTableIndex == 0 {
                    Log("\(node.getIp).successor \(successorNode.getIp)")
                    Log()
                }
                
                node.fingers[fingerTableIndex].node = successorNode
                node.triggerStoreFingerTable = true
                return operandUnification(operands: [String(fingerTableIndex), successorNode.ipAndPortString])
            }
            return nil
        case .findPredecessor : //MARK: findPredecessor
            LogEssential("Do \(self.rawValue)")
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
                Log("\(fingerTableIndex), \(predecessorsSuccessorNode?.ipAndPortString)")
                return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, predecessorNode.ipAndPortString, predecessorsSuccessorNode?.ipAndPortString, "found"])
            }
            return nil
        case .findPredecessorReply :
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node ip and port
            Log(operandArray[3])    //3: preceding node's successor ip and port
            Log(operandArray[4])    //4: result "found" or "not"
            let fingerTableIndex = operandArray[0]
            LogEssential(fingerTableIndex)
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(ipAndPort: operandArray[2]), let predecessorsSuccessorNode = Node(ipAndPort: operandArray[3]) else {
                return nil
            }
            let result = operandArray[4]
            if result == "found" {
                /*
                 Chained Next Command
                 FS or FP
                 */
                LogEssential("result: Found")
                return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.ipAndPortString, predecessorsSuccessorNode.ipAndPortString, "found"])
            } else {
                LogEssential("result: Not Found")
                /*
                 Send findPredecessor Command to Preceding Node.
                 */
                Command.findPredecessor.send(node: node, to: precedingNode.getIp, operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString], previousToken: token) {
                    a in
                    Log("Run [Find Predecessor] Command to \(precedingNode.ip.toString()).")
                }
                return nil
            }
        case .closestPrecedingFinger :  //MARK: closestPrecedingFinger
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: areYouPredecessor result "true" or "false"s
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]) else {
                return nil
            }
            let precedingNode = node.closestPrecedingFinger(address: targetNode, token: token)
            Log(precedingNode.getIp)
            
            Command.queryYourSuccessor.send(node: node, to: precedingNode.getIp, operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.ipAndPortString], previousToken: token) {
                a in
                Log("Run [queryYourSuccessor] Command to \(precedingNode.ip.toString()).")
            }
            return nil
        case .closestPrecedingFingerReply :
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node ip and port
            Log(operandArray[3])    //3: preceding node's successor ip and port
            Log(operandArray[4])    //4: result: "found" or "not"
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(ipAndPort: operandArray[2]), let successorNode = Node(ipAndPort: operandArray[3]) else {
                return nil
            }
            let result = operandArray[4]
            return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.ipAndPortString, successorNode.ipAndPortString, result])
        case .queryYourSuccessor :  //MARK: queryYourSuccessor
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node ip and port
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(ipAndPort: operandArray[2]) else {
                return nil
            }
            return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.ipAndPortString, node.successor?.ipAndPortString])
        case .queryYourSuccessorReply :
            LogEssential("Do \(self.rawValue)")
            Log(operandArray[0])    //0: finger table index
            Log(operandArray[1])    //1: target node hex address
            Log(operandArray[2])    //2: preceding node ip and port
            Log(operandArray[3])    //3: successor's ip and port
            let fingerTableIndex = operandArray[0]
            guard let targetNode = Node(dhtAddressAsHexString: operandArray[1]), let precedingNode = Node(ipAndPort: operandArray[2]),  let successorNode = Node(ipAndPort: operandArray[3]) else {
                return nil
            }
            return operandUnification(operands: [fingerTableIndex, targetNode.dhtAddressAsHexString.toString, precedingNode.ipAndPortString, successorNode.ipAndPortString, ""])
            
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
            LogEssential("Do \(self.rawValue)")
            guard let predecessor = Node(ipAndPort: operandArray[0]) else {
                Log()
                return nil
            }
            Log("(US)predecessor: \(predecessor.ipAndPortString) from \(fromNodeIp)")
            var previousPredecessor: Node? = node.predecessor
            if predecessor.ipAndPortString == previousPredecessor?.ipAndPortString {
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
            Log("\(predecessor.ipAndPortString) \(previousPredecessor?.ipAndPortString)")
            return previousPredecessor?.ipAndPortString     //may be nil.
        case .updateSuccessorsPredecessorReply :
            LogEssential("Do \(self.rawValue)")
            /* Reply from Successor Node At Init Finger Table */
            guard let successorsPreviousPredecessor = Node(ipAndPort: operandArray[0]) else {
                return nil
            }
            Log("(US_)predecessor: \(successorsPreviousPredecessor.ipAndPortString) from \(fromNodeIp)")
            node.predecessor = successorsPreviousPredecessor
            node.triggerStoreFingerTable = true
            return nil
        case .updatePredecessorsSuccessor : //MARK: updatePredecessorsSuccessor
            LogEssential("Do \(self.rawValue)")
            guard let successor = Node(ipAndPort: operandArray[0]) else {
                return nil
            }
            Log("\(successor.ipAndPortString)")
            node.successor = successor
            return ""
        case .updatePredecessorsSuccessorReply :
            LogEssential("Do \(self.rawValue)")
            /* Reply from Successor Node At Init Finger Table */
            return nil
        default:
            Log()
            return ""
        }
    }
}
