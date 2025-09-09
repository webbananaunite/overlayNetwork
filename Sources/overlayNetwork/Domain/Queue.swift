//
//  Queue.swift
//  blocks
//
//  Created by よういち on 2021/08/24.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

open class Job {
    private var _token: String = ""
    var token: String {
        set {
            if newValue != "" {
                self._token = newValue
            } else {
                self.time = Time.utcTimeString
                let seed = [self.command.rawValue, self.fromOverlayNetworkAddress.toString, self.toOverlayNetworkAddress.toString, self.type.rawValue, self.time].reduce("") {
                    $0 + $1
                }
                Log(seed)
                self._token = seed.hash().0
                Log(_token)
            }
        }
        get {
            return self._token
        }
    }
    var time: String
    
    var command: CommandProtocol
    
    var operand: String
    
    var fromOverlayNetworkAddress: OverlayNetworkAddressAsHexString
    var toOverlayNetworkAddress: OverlayNetworkAddressAsHexString

    var type: Type
    
    public enum `Type`: String {
        case local = "LO"       //SEND the Job oneself in local.
        case delegate = "DE"    //SEND the Job by Socket.
        case delegated = "DD"   //RECEIVED the Job by Socket.
        
        case signaling = "SI"   //SEND the Job to Signaling Server by Socket.
    }
    
    var result: String?
    /*
     Socket Queue:
        Remove From Queue if be Sent.
     Command Queue:
        Set status .dequeued if be Sent.
        Set result value if be Received Reply.
     HeartBeat Queue:
        Set status .waitingForReply if be Sent.
        Set result value if be Received Reply.
     */
    public var status: Status = .running
    public enum Status: Int {
        case running = 0        //Initial Status
        case dequeued = 1       //representation for Completed Queue, Use Command Queue Only.
        case undefined = 2
        case waitingForReply = 3 //Use HeartBeat Queue Only.
    }

    var nextJobToken: String?
    var previousJobToken: String?

//    public init(command: CommandProtocol, operand: String, from fromOverlayNetworkAddress: OverlayNetworkAddressAsHexString, to toOverlayNetworkAddress: OverlayNetworkAddressAsHexString, type: Type, token: String? = nil, previousJobToken: String? = nil) {
    public init(command: CommandProtocol, operand: String, from fromOverlayNetworkAddress: OverlayNetworkAddressAsHexString, to toOverlayNetworkAddress: OverlayNetworkAddressAsHexString, type: Type, token: String? = nil, previousJobToken: String? = nil) {
        Log(token)
        self.time = Time.utcTimeString  //will update at setting token.
        self.command = command
        self.operand = operand
        self.fromOverlayNetworkAddress = fromOverlayNetworkAddress
        self.toOverlayNetworkAddress = toOverlayNetworkAddress
        self.type = type
        
        self.previousJobToken = previousJobToken
        if let token = token {
            self.token = token
        } else {
            self.token = ""
        }
    }
    public enum CommandType {
        case overlayNetwork  //overlayNetwork#Command
        case premium         //blocks#Command
        case signaling       //SignalingCommand
        case unknown
    }
    public func commandType(premiumCommand: CommandProtocol?) -> (CommandType, CommandProtocol?) {
        var commandType: CommandType = .unknown
        var commandInstance: CommandProtocol?
        if let command = Command(rawValue: self.command.rawValue) {
            commandType = .overlayNetwork
            commandInstance = command
        } else if let command = premiumCommand?.command(self.command.rawValue), command.rawValue != Command.other.rawValue {
            commandType = .premium
            commandInstance = command
        } else if let command = Mode.SignalingCommand(rawValue: self.command.rawValue) {
            commandType = .signaling
            commandInstance = command
        }
        Log(commandInstance as Any)
        return (commandType, commandInstance)
    }
    public func isSignalingCommand(node: Node) -> Bool {
        let (commandType, _)  = commandType(premiumCommand: node.premiumCommand)
        return commandType == .signaling
    }
}

open class Queue {
    var queues = [Job]()
    
    /*
     Queue FIFO (Append at Last) or Dequeue by matched token.
     
     Ordinally, let use the functions enQueue(), deQueue().
     */
    open func enQueue(job: Job) {
        Log()
        self.queues.append(job)
        
//        self.queues.forEach { aJob in
//            Log("\(aJob.token)")
//            Log("\(aJob.operand)")
//            Log("\(aJob.command)")
//            Log("\(String(describing: aJob.result))")
//            Log("\(String(describing: aJob.previousJobToken))")
//            Log("\(aJob.status)")
//        }
    }
    open func enQueueAsFirst(job: Job) {
        Log()
        self.queues.insert(job, at: 0)
    }

    /*
     If the Job Status is .succeeded, dequeued queue.
     return:
         Not nil, .succeeded →(Found the Job, dequeue succeeded)
         Not nil, .failed →(Found the Job, dequeue failed)
            failed for previous queue on running.
         Nil, .failed →(Not found, dequeue failed)
     */
    public enum Status: Int {
        case succeeded = 1
        case failed = 2
        case notFound = 3
    }
    /*
     Make the Job Status to Dequeued.
     Then Replace the job in queue.
     */
    open func deQueue(token: String, type: [Job.`Type`]?) -> (Job?, Status) {
        Log()
        var matchedJob: Job?
        if let type = type {
            matchedJob = fetchJobWithType(token: token, type: type)
        } else {
            matchedJob = fetchJob(token: token)
        }
        Log(matchedJob?.token)
        Log(matchedJob?.time)
        Log(matchedJob?.command)
        if let matchedJob = matchedJob {
            matchedJob.status = .dequeued
            self.replace(before: matchedJob, after: matchedJob)
            Log(matchedJob.command)
            return (matchedJob, .notFound)
        }
        Log(matchedJob?.command)

        return (nil, .notFound)
    }
    open func removeQueue(token: String) {
        Log()
        self.queues = self.queues.filter {
            $0.token != token
        }
    }
    /*
     Queue FIFO, Dequeue at First.
     */
    public enum QueueType: Int {
        case SocketCommunication = 1
        case CommandOperation = 2
        case HeartBeat = 3
        
        public func queueName() -> String {
            switch self {
            case .SocketCommunication:
                return "Socket Queue"
            case .CommandOperation:
                return "Command Queue"
            case .HeartBeat:
                return "HeartBeat Queue"
            }
        }
    }
    open func deQueue() -> Job? {
        Log()
        guard let firstElement = self.queues.first else {
            return nil
        }
        self.queues.removeFirst()
        return firstElement
    }
    open func deQueue(toOverlayNetworkAddress: OverlayNetworkAddressAsHexString, token: String) -> Job? {
        Log()
        var index: Int?
        var deQueuedElement: Job?
        self.queues.enumerated().forEach {
            if $0.element.toOverlayNetworkAddress.equal(toOverlayNetworkAddress) && $0.element.token == token {
                index = $0.offset
            }
        }
        if let index = index {
            deQueuedElement = self.queues[index]
            self.queues.remove(at: index)
        }
        return deQueuedElement
    }
    open func firstQueueTypeLocal() -> Job? {
        Log()
        guard let firstElement = self.queues.first else {
            return nil
        }
        if firstElement.type == .local {
            self.queues.removeFirst()
            return firstElement
        }
        return nil
    }

    open func setStatus(token: String, type: [Job.`Type`]?, status: Job.Status) -> (Job?, Job.Status) {
        Log()
        var matchedJob: Job?
        if let type = type {
            matchedJob = fetchJobWithType(token: token, type: type)
        } else {
            matchedJob = fetchJob(token: token)
        }
        Log(matchedJob?.token)
        Log(matchedJob?.time)
        if let matchedJob = matchedJob {
            matchedJob.status = status
            self.replace(before: matchedJob, after: matchedJob)
            return (matchedJob, status)
        }
        return (nil, .undefined)
    }

    open func setResult(token: String, type: [Job.`Type`]?, result: String) -> (Job?, Status) {
        Log()
        var matchedJob: Job?
        if let type = type {
            matchedJob = fetchJobWithType(token: token, type: type)
        } else {
            matchedJob = fetchJob(token: token)
        }
        Log(matchedJob?.token)
        Log(matchedJob?.time)
        if let matchedJob = matchedJob {
            matchedJob.result = result
            self.replace(before: matchedJob, after: matchedJob)
            return (matchedJob, .succeeded)
        }
        return (nil, .notFound)
    }
    open func setPreviousJob(token: String, previousJobToken: String) -> Status {
        Log()
        if let matchedJob = fetchJob(token: token), let previousJob = fetchJob(token: previousJobToken) {
            matchedJob.previousJobToken = previousJob.token
            self.replace(before: matchedJob, after: matchedJob)
            previousJob.nextJobToken = matchedJob.token
            self.replace(before: previousJob, after: previousJob)

            return .succeeded
        }
        return .notFound
    }
    open func fetchJob(token: String) -> Job? {
        Log()
        let matchedJob = self.queues.enumerated().filter {
            $0.element.token == token
        }.first
        return matchedJob?.element
    }
    open func fetchJobWithType(token: String, type: [Job.`Type`]) -> Job? {
        Log()
        Log(type)
        Log(token)
        let conditions: [(Job) -> Bool] = [ // Functions(Conditions) array
            {$0.token == token},
            {type.contains($0.type)}
        ]
//        printQueueEssential()
        Log(self.queues.count)
        let matchedJobs = self.queues.filter {
            queue in
            return conditions.reduce(true) {
//                Log($1(queue))
                return $0 && $1(queue)
            }
        }
        Log(matchedJobs.count)
        Log(matchedJobs)
        /*
         if have same token jobs, will adopt the type .delegate or .local.
         */
        if matchedJobs.count > 1 {
            let matchedJob = matchedJobs.filter {
                $0.type != .delegated
            }.first
            return matchedJob
        }
        let matchedJob = matchedJobs.first
        return matchedJob
    }
    open func fetchPreviousJob(token: String) -> Job? {
        Log()
        if let delegateJob = self.fetchJob(token: token), let previousJobToken = delegateJob.previousJobToken, let previousJob = self.fetchJob(token: previousJobToken) {
            return previousJob
        }
        return nil
    }
    open func fetchPreviousJobWithType(token: String, type: [Job.`Type`]) -> Job? {
        Log()
        if let delegateJob = self.fetchJobWithType(token: token, type: type), let previousJobToken = delegateJob.previousJobToken, let previousJob = self.fetchJobWithType(token: previousJobToken, type: type) {
            return previousJob
        }
        return nil
    }
    open func fetchFollowingJobs(previousJobToken: String) -> [Job]? {
        Log()
        let matchedJob = self.queues.enumerated().filter {
            $0.element.previousJobToken == previousJobToken
        }.map {
            $0.element
        }
        return matchedJob
    }

    private func replace(before: Job, after: Job) {
        Log(before.command)
        Log("\(before.token) && \(before.type) && \(before.time) && \(before.command)")
        self.queues = self.queues.map { ($0.token == before.token && $0.type == before.type && $0.time == before.time) ? after : $0 }
        Log(before.command)
    }
    
    /*
     Stack
     If you use by LILO
     */
    open func pop() -> Job? {
        return self.queues.popLast()
    }

    open func push(queue: Job) {
        self.push(queue: queue)
    }
    
    open func printQueueEssential() {
        #if DEBUG
        print("Queue [PrintQueue]Essential")
        print("Queues: \(queues.count)")
        queues.enumerated().forEach { queue in
            print("\n")
            print("[\(queue.offset)]")
            print("time:\(queue.element.time)")
            print("command:\(queue.element.command)")
            print("fromOverlayNetworkAddress:\(queue.element.fromOverlayNetworkAddress)")
            print("toOverlayNetworkAddress:\(queue.element.toOverlayNetworkAddress)")
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
}
