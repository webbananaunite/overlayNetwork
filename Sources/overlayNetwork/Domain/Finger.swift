//
//  Finger.swift
//  blocks
//
//  Created by よういち on 2021/07/05.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

/*
      Address space
      1   2   3   4   5   6   7   0(Max)
 
      Finger Table (DHT)
 
      start : own + 2^n
 
      interval =範囲 [ : 以上
      ) : 未満
 
      successor : startの後に最初に出現するnode

      |n|start|interval|successor(node)|
      |0|  1  | [1,2)  |  1            |
      |1|  2  | [2,4)  |  3            |
      |2|  4  | [4,0)  |  0            |

 
 Finger Table
  
  Notation           | Definition
  finger[k].start    | (n+2^(k-1))mod 2^m, 1 <= k <= m
  .interval          | [finger[k].start, finger[k+1].start); [以上、)未満
  .node              | first node >= n.finger[k].start
  successor          | the next node on the identifier circle;
    Own's successor node = finger[0].node
    ↑Next node in address(hashed string value in numerical) circle.
  predecessor        | the previous node on the identifier circle
  
 */
public class Finger: Equatable {
    public static func == (lhs: Finger, rhs: Finger) -> Bool {
//        guard let lhsNode = lhs.node, let rhsNode = rhs.node else {
        guard let lhsNode = lhs.successorNodeCandidates[0], let rhsNode = rhs.successorNodeCandidates[0] else {
            return false
        }
        if lhs.start.dhtAddressAsHexString.equal(rhs.start.dhtAddressAsHexString)
            && lhs.interval[0].dhtAddressAsHexString.equal(rhs.interval[0].dhtAddressAsHexString)
            && lhs.interval[1].dhtAddressAsHexString.equal(rhs.interval[1].dhtAddressAsHexString)
            && lhsNode.dhtAddressAsHexString.equal(rhsNode.dhtAddressAsHexString) {
            return true
        }
        return false
    }
    
    private static let archivedDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first! + "/finger/"
    private static let archiveFile = "fingers.json"
    private static var archiveFilePath: String {
        archivedDirectory + archiveFile
    }
    
//    public init?(start: Node, interval: [Node], node: Node?) {
    public init?(start: Node, interval: [Node], nodes: [Node?]?) {
        self.start = start
        self.interval = interval
        
//        self.node = node
//        self.successorNodeCandidates += [node]
//        self.addSuccessorNodeAsFirstCandidates(node: node)
        if let nodes = nodes {
            self.successorNodeCandidates = nodes
        }

        if !FileManager.default.fileExists(atPath: Finger.archivedDirectory) {
            do {
                try FileManager.default.createDirectory(atPath: Finger.archivedDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Log()
            }
        }
    }
    var start: Node
    var interval = [Node]() {
        didSet {
            if interval.count > 2 {interval = oldValue}
        }
    }
//    var node: Node?
    /*
     Sortable Queue As Successor Node Candidates.
     */
//    var nodes = [Node?]()
    var successorNodeCandidates = [Node?]()

    public func addSuccessorNodeAsFirstCandidates(node: Node?) {
        Log()
        self.successorNodeCandidates.insert(node, at: 0)
    }
//    public func successorCandidateNodes(node: [Node]) {
//        Log()
//        self.successorNodeCandidates = node
//    }
    public var firstSuccessorNode: Node? {
        guard self.successorNodeCandidates.count >= 1 else {
            return nil
        }
        return self.successorNodeCandidates[0]
    }
    public var secondSuccessorNode: Node? {
        guard self.successorNodeCandidates.count >= 2 else {
            return nil
        }
        return self.successorNodeCandidates[1]
    }
    public var isThereMultipleCandidates: Bool {
        return self.successorNodeCandidates.count > 1
    }
    public func swapFirstSuccessor(dhtAddressAsHexString: OverlayNetworkAddressAsHexString) {
        LogEssential(self.successorNodeCandidates)
        if let firstSuccessorNodeDhtAddress = self.firstSuccessorNode?.dhtAddressAsHexString, dhtAddressAsHexString.equal(firstSuccessorNodeDhtAddress), self.isThereMultipleCandidates {
            self.successorNodeCandidates.insert(self.firstSuccessorNode, at: self.successorNodeCandidates.endIndex)
            self.successorNodeCandidates.remove(at: 0)
//            self.successorNodeCandidates.insert(self.secondSuccessorNode, at: 0)
//            self.successorNodeCandidates.remove(at: 2)
            LogEssential()
        }
        LogEssential(self.successorNodeCandidates)
    }

    /*
     Store Finger Table to Device's Storage.
     Format: Json
        Start, Interval stored as Hex String(dhtAddressAsHexString)
        Node#deployFingerTableToMemory()
     */
    public func storeUp(index: Int) {
        do {
            let url = URL(fileURLWithPath: Finger.archiveFilePath)
            
//            let jsonData: Data = """
//            {
//              "index": \(index),
//              "dhtAddressAsHexString": {
//                "start": "\(self.start.dhtAddressAsHexString)",
//                "interval": [
//                    "\(self.interval[0].dhtAddressAsHexString)",
//                    "\(self.interval[1].dhtAddressAsHexString)"
//                ],
//                "node": "\(self.node?.dhtAddressAsHexString ?? "")"
//              }
//            },\n
//            """.utf8DecodedData!
            var jsonData: Data = """
            {
              "index": \(index),
              "dhtAddressAsHexString": {
                "start": "\(self.start.dhtAddressAsHexString)",
                "interval": [
                    "\(self.interval[0].dhtAddressAsHexString)",
                    "\(self.interval[1].dhtAddressAsHexString)"
                ],
                "node": [
            """.utf8DecodedData!

            jsonData += self.successorNodeCandidates.enumerated().reduce("") {
                var addCharacter: String = ""
                if $1.offset != 0 {
                    addCharacter += ","
                }
                addCharacter += """
                    "\($1.element?.dhtAddressAsHexString ?? "")"
                """
                return $0 + addCharacter
            }.utf8DecodedData!
            
//            jsonData += """
//              }
//            },\n
//            """.utf8DecodedData!
            jsonData += """
                ]
              }
            },\n
            """.utf8DecodedData!

            Log("\(jsonData.utf8String ?? "")")
            try jsonData.append(to: url)
        } catch {
            LogEssential("Save Json Error \(error)")
        }
    }
    public static func storePredecessor(overlayNetworkAddress: OverlayNetworkAddressAsHexString) {
        do {
            let url = URL(fileURLWithPath: Finger.archiveFilePath)
            let jsonData: Data = """
            {
              "predecessor": {
                "dhtAddressAsHexString": "\(overlayNetworkAddress.toString)"
              }
            },\n
            """.utf8DecodedData!
            
//            Log("\(jsonData.utf8String ?? "")")
            try jsonData.append(to: url)
        } catch {
            Log("Save Json Error \(error)")
        }
    }
    public static func storeFirstLine() {
        do {
            let url = URL(fileURLWithPath: Finger.archiveFilePath)
            let initialData = "[".utf8DecodedData!
            try initialData.append(to: url, truncate: true)
        } catch {
            Log("Save Json Error \(error)")
        }
    }
    public static func storeLastLine() {
        do {
            let url = URL(fileURLWithPath: Finger.archiveFilePath)
            let initialData = "]".utf8DecodedData!
            try initialData.append(to: url)
        } catch {
            Log("Save Json Error \(error)")
        }
    }

    public func print() {
#if true
        Swift.print("---Stored-------\n")
        do {
            let result = try String(contentsOf: URL(fileURLWithPath: Finger.archiveFilePath), encoding: .utf8)
            Swift.print(result)
        } catch {
            Log("Error Occured \(error)")
        }
        Swift.print("---Stored-------\n")
#endif
    }
    
    //Cached判定
    public static func isCached() -> Bool {
//        Log()
        if !FileManager.default.fileExists(atPath: Finger.archiveFilePath) {
            Log("No Cached Finger table")
            return false
        }
        Log("Have Cached Finger table")
        return true
    }
    
    public static func fetchJson() -> [[String: Any]]? {
        Log()
        if Finger.isCached() {
            Log()
            do {
                let url = URL(fileURLWithPath: Finger.archiveFilePath)
                let data = try Data(contentsOf: url)
                Log("\(data.utf8String ?? "")")
                if let jsonData = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [Any] {
                    Log(jsonData)
                    let jsonArray = jsonData.map { (aObject) -> [String: Any] in
                        return aObject as! [String: Any]
                    }
                    return jsonArray
                }
            } catch {
                Log("Error Fetching Json Data:\(error)")
            }
        }
        return nil
    }
}
