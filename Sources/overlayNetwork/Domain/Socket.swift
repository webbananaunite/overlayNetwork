//
//  Socket.swift
//  blocks
//
//  Created by よういち on 2024/03/17.
//  Copyright © 2024 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

/*
 Poll Socket I/O and Communicate Queue.
 */
public enum Mode: Int {
    case registerMeAndIdling = 1
    /*
     Node ←→ Signaling server
     
     c fork thread
     ↓
     c registerMe {my overlayNetworkAddress}
     ↓
     s okyours {your public ip/port}
     ↓
     c okregisterMe
     ↓
     s registerMeAck
     ↓
     c fetch next a job　→ (nothing) c Do registerMe Process again
     ↓
     (there)
     c call signaling phase
     */
    case signaling = 2
    /*
     Node ←→ Signaling server
     
     c translate {peer overlay network address}
     ↓
     s translateAck {peer public ip port} {peer private ip port}
     ↓　　　　　　　　　　　　　　 ↓
     cA create sockets pair   cB create sockets pair
     ↓
     cA call handshake phase  cB call handshake phase
     ↓
     (handshake process)
     ↓
     return from handshake phase
     ↓
     send command for fetched job
     ↓
     receive command from peer
     ↓
     callback to Node#received(from)
     ↓
     go to fetch next job
     ↓
     */
    case handshake = 3
    /*
     Node A ←→ Node B

     cA exchange token {my token} _
     ↓
     cB exchange token {my token} _
     ↓
     cA exchange token {my token} {peer token} ok
     ↓
     cB exchange token {my token} {peer token} ok
     ↓
     cA have done shake hand for nat traversable
     cB have done shake hand for nat traversable
x     ↓
x     return signaling phase
     ↓
     go to dequeueJob
     */
    
    case dequeueJob = 4
    /*
     cA send command
     ↓
     cB receive command
     ↓
     cB reply command
     ↓
     cA receive command
     */
    
    public enum Select {
        case send
        case receive
    }
    public enum SignalingCommand: String {
        case registerMe
        case okyours
        case okregisterMe
        case registerMeAck
        
        case translate
        case translateAck

        case exchangeToken
    }
    public enum PeerType {
        case signalingServer
        case peerNode
//        case both
    }
    
    /*
     return:
        [Send / Receive], Next Mode, [Do Command]
     */
    public var stack:[(selects: [Select], nextMode: Mode?, doCommands: [SignalingCommand]?, peerTypes: [PeerType])] {
        switch self {
        case .registerMeAndIdling:
            return [
                ([.send], nil, [.registerMe], [.signalingServer]),
                ([.receive], nil, [.okyours], [.signalingServer]),
                ([.send], nil, [.okregisterMe], [.signalingServer]),
                ([.receive], .signaling, [.registerMeAck], [.signalingServer]),

                ([.receive], .handshake, [.translateAck], [.signalingServer])    //be Idle
            ]
            
        case .signaling:
            return [
                ([.send], nil, [.translate], [.signalingServer]),
                ([.receive], .handshake, [.translateAck], [.signalingServer])
            ]
            
        case .handshake:
            return [
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode]),
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode]),
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode]),
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode]),
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode]),
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode]),
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode]),
                ([.send, .receive], .dequeueJob, [.exchangeToken, .translateAck], [.peerNode])
            ]
            
        case .dequeueJob:
            return [
                ([.send, .receive], .handshake, [.translateAck], [.signalingServer, .peerNode])    //Receive translateAck command from Other Nodes.
            ]
        }
    }
}

open class Socket {
    public static let MTU = 65536
//    #if DEBUG
    let avoidContaminationTime: UInt32 = UInt32(0.0 * 1024 * 1024)  //as why it be, Be under 0.5 seconds then bad BSD Socket work.
    let regularWaitTime: UInt32 = UInt32(0.0 * 1024 * 1024)
//    #else
//    let avoidContaminationTime: UInt32 = UInt32(0.5 * 1024 * 1024)
//    let regularWaitTime: UInt32 = UInt32(0.5 * 1024 * 1024)
//    #endif

    /*
     As Do handshake as NAT Traversal Operation,
     Exchanging each Token String by Local Node and Remote Nodes.
     */
    var remote_token = "_"
    var remote_knows_our_token = false
    
    var mode: Mode {
        didSet {
            if self.mode == .handshake {
                self.remote_token = "_"
            }
            self.doUpdateFdSet = true
        }
    }
    var terminateCommunicate = false
    var previousMode: Mode = .registerMeAndIdling
    var doUpdateFdSet = false
    var claimTranslate = false  //sendTranslateNode
    var inTransitionSignalingToHandshake: Int32?
    var passedGracePeriod = 0
    var sleepSeconds = 0.0
    var handshakeTimes = 0
    var nodePerformances = [TimeInterval]()    //小さい値ほど高性能
    var nodePerformance: TimeInterval?    //小さい値ほど高性能
    var diffPerformance: UInt32 = 0

    public enum AddressSpace {
        case `public`
        case `private`
    }
    var socketHandles: [Mode.PeerType: [String: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool, connectionFailCounter: Int)]]]
    
    var communicationProcess = processPhase()
    var bannedOverlayNetworkAddresses = [String: Bool]()
    
    class processPhase {
        var phase: Int
        var doneTime: Date?
        init() {
            self.phase = 0
        }
        func onceMore() {
            self.phase = 0
            self.doneTime = Date.now
        }
        func updateDoneTime() {
            self.doneTime = Date.now
        }
        func nextMode() {
            self.phase = 0
        }
        func idling() {
            self.doneTime = Date.now
            self.increment()
        }
        func increment() {
            guard self.phase < UInt8.max else {
                return
            }
            self.phase += 1
        }
        func decrement() {
            guard self.phase > 0 else {
                return
            }
            self.phase -= 1
        }
    }
    
    public init() {
        self.mode = .registerMeAndIdling
        self.socketHandles = [Mode.PeerType: [String: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool, connectionFailCounter: Int)]]]()
    }
    
    /*
     Switch Block Mode / NonBlock Mode for connect()/select()
     */
    func comfirmBlockMode(_ sockhandle: Int32) -> (Int32, String) {
        let socketStatusFlags = fcntl(sockhandle, F_GETFL)
        //        Log("\(socketStatusFlags.binaryRepresent)")
        return (socketStatusFlags, socketStatusFlags.binaryRepresent)
    }
    func restoreBlockMode(_ sockhandle: Int32, mode: Int32) -> Bool {
        let blockableStatus = fcntl(sockhandle, F_SETFL, mode)
        if (blockableStatus < 0) {
            return false
        }
        return true
    }
    func setBlock(_ sockhandle: Int32) -> (Bool, Int32) {
        Log("Set Block Mode (connect,select)")
        let socketStatusFlags = fcntl(sockhandle, F_GETFL)
        Log("--\(socketStatusFlags.binaryRepresent)")
        if socketStatusFlags & O_NONBLOCK != 0 {
            let blockableStatus = fcntl(sockhandle, F_SETFL, socketStatusFlags ^ O_NONBLOCK)
            if (blockableStatus < 0) {
                return (false, socketStatusFlags)
            }
        }
#if DEBUG
        let statusFlags = fcntl(sockhandle, F_GETFL)
        Log("++\(statusFlags.binaryRepresent)")
#endif
        return (true, socketStatusFlags)
    }
    func setNonBlock(_ sockhandle: Int32) -> (Bool, Int32) {
        Log("Set Non Block Mode (connect,select)")
        let socketStatusFlags = fcntl(sockhandle, F_GETFL)
        Log("--\(socketStatusFlags.binaryRepresent)")
        let nonBlockStatus = fcntl(sockhandle, F_SETFL, socketStatusFlags | O_NONBLOCK)
        if (nonBlockStatus < 0) {
            return (false, socketStatusFlags)
        }
#if DEBUG
        let statusFlags = fcntl(sockhandle, F_GETFL)
        Log("++\(statusFlags.binaryRepresent)")
#endif
        return (true, socketStatusFlags)
    }
    
    /*
     Deploy BSD Socket and Connect to Peer Node / Signaling Server.
     
     Socket Setting
     ↓
     (bind)
     ↓
     connect
     */
    //MARK: - Open Socket
    public func openSocket(to destination: (ip: String, port: Int), addressSpace: AddressSpace, source privateAddress: (ip: String, port: Int)?, async: Bool = false) -> (socketHandle: Int32, sourceAddress: (ip: String, port: Int), Bool) {
        Log("from: \(String(describing: privateAddress)) to: \(destination)")
        /*
         Be Comfirmation Granted Network Access.
         */
        /*
         Thank:
         https://stackoverflow.com/a/42538932
         
         Create sockaddr_in (IPV4) address for google.com
         Note: If you need to resolve DNS for a hostname, use CFHost
         */
        var remoteaddress = sockaddr_in()
        inet_pton(PF_INET,
                  destination.ip.cString(using: .utf8),
                  &remoteaddress.sin_addr)
        remoteaddress.sin_port = UInt16(destination.port).bigEndian
        remoteaddress.sin_family = sa_family_t(AF_INET)
        
        // Create native socket handle, if sockhandle < 0, error occurred, (check errno)
        Log("Do Socket()")
        errno = 0
        let sockhandle = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)
        Log(sockhandle)
        LogPosixError()
        /*
         Append Option for Reusable socket
         */
        /*
         Socket to peer's Public address, have to Reuable.
         */
        var reuseaddrValue = 1
        setsockopt(sockhandle, SOL_SOCKET, SO_REUSEADDR, &reuseaddrValue, socklen_t(MemoryLayout.stride(ofValue: reuseaddrValue)))
        var reuseportValue = 1
        setsockopt(sockhandle, SOL_SOCKET, SO_REUSEPORT, &reuseportValue, socklen_t(MemoryLayout.stride(ofValue: reuseportValue)))
        
        //        var useLoopbackValue: Int32 = 1
        //        setsockopt(sockhandle, SOL_SOCKET, SO_USELOOPBACK, &useLoopbackValue, socklen_t(MemoryLayout.stride(ofValue: useLoopbackValue)))
        //        var debugValue: Int32 = 1
        //        setsockopt(sockhandle, SOL_SOCKET, SO_DEBUG, &debugValue, socklen_t(MemoryLayout.stride(ofValue: debugValue)))
        
        //SO_NOSIGPIPE
        //Avoid process termination on send().
        var nosigpipeValue = 1
        setsockopt(sockhandle, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipeValue, socklen_t(MemoryLayout.stride(ofValue: nosigpipeValue)))
        //SO_KEEPALIVE
//        var keepaliveValue = 1
//        setsockopt(sockhandle, SOL_SOCKET, SO_KEEPALIVE, &keepaliveValue, socklen_t(MemoryLayout.stride(ofValue: keepaliveValue)))
        
        /*
         Take The Socket Address and Port information for Reuse.
         */
        var retSourceAddress: (ip: String, port: Int)
        var connectionSucceeded: Bool
        if let privateAddress = privateAddress {    Log()
            /*
             Communicate with Peer Node.
             (Socket Create by After Second time)
             */
            Log("Do Bind()")
            var localaddress = sockaddr_in()
            inet_pton(PF_INET, privateAddress.ip.cString(using: .utf8), &localaddress.sin_addr)
            localaddress.sin_port = UInt16(privateAddress.port).bigEndian
            localaddress.sin_family = sa_family_t(AF_INET)
            var socketAddress = localaddress
            let bindStatus = withUnsafeMutablePointer(to: &socketAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sockhandle, $0, socklen_t(MemoryLayout.size(ofValue: localaddress)))
                }
            }
            if bindStatus != 0 {
                LogPosixErrorEssential()
            }
            retSourceAddress = privateAddress
            
            /*
             Set timeout 5s
             */
            Log("Set Timeout 5s for send() recv()")
            var timeOutValue = timeval()
            timeOutValue.tv_sec = 5
            timeOutValue.tv_usec = 0 //Unit: μs 1/1000000.0s
            let retSetOpt = setsockopt(sockhandle, SOL_SOCKET, SO_SNDTIMEO, &timeOutValue, socklen_t(MemoryLayout.stride(ofValue: timeOutValue)))
            if retSetOpt < 0 {
                LogPosixError()
            }
            let retSetOpt2 = setsockopt(sockhandle, SOL_SOCKET, SO_RCVTIMEO, &timeOutValue, socklen_t(MemoryLayout.stride(ofValue: timeOutValue)))
            if retSetOpt2 < 0 {
                LogPosixError()
            }
            
            if async {
                /*
                 Set blocking false
                 */
                Log("Connect Asynchronously")
                let _ = setNonBlock(sockhandle)
                //            Log(comfirmBlockMode(sockhandle))
            } else {
                Log("Connect Synchronously")
            }
            
            /*
             Connect Remote address with Transform sockaddr_in POSIX structure to sockaddr POSIX structure
             */
            Log("Do Connect")
            var socketAddressRemote = remoteaddress
            let connectStatus = withUnsafeMutablePointer(to: &socketAddressRemote) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sockhandle, $0, socklen_t(MemoryLayout.stride(ofValue: remoteaddress)))
                }
            }
            Log("\(connectStatus) \(errno)")
            if connectStatus == 0 || (connectStatus == -1 && errno == 56) {
                Log("connection Succeeded.")
                connectionSucceeded = true
            } else {
                Log("Connection Failed / Async Connecting...")
                connectionSucceeded = false
            }
            LogPosixErrorEssential(description: destination.ip)
        } else {
            Log("Connect to Signaling Server for Take Local Address in Synchronouslly.")
            Log(comfirmBlockMode(sockhandle))
            /*
             Communicate with Signaling Server.
             (Socket Create by First time)
             */
            /*
             Set timeout 5s
             */
            Log("Set Timeout 5s for send() recv()")
            var timeOutValue = timeval()
            timeOutValue.tv_sec = 5
            timeOutValue.tv_usec = 0 //Unit: μs 1/1000000.0s
            let retSetOpt = setsockopt(sockhandle, SOL_SOCKET, SO_SNDTIMEO, &timeOutValue, socklen_t(MemoryLayout.stride(ofValue: timeOutValue)))
            if retSetOpt < 0 {
                LogPosixError()
            }
            let retSetOpt2 = setsockopt(sockhandle, SOL_SOCKET, SO_RCVTIMEO, &timeOutValue, socklen_t(MemoryLayout.stride(ofValue: timeOutValue)))
            if retSetOpt2 < 0 {
                LogPosixError()
            }
            
            /*
             Connect Remote address with Transform sockaddr_in POSIX structure to sockaddr POSIX structure
             */
            var socketAddress = remoteaddress
            let connectStatus = withUnsafeMutablePointer(to: &socketAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sockhandle, $0, socklen_t(MemoryLayout.size(ofValue: remoteaddress)))
                }
            }
            Log("\(connectStatus) \(errno)")
            if connectStatus == 0 || (connectStatus == -1 && errno == 56) {
                connectionSucceeded = true
            } else {
                connectionSucceeded = false
            }
            LogPosixErrorEssential()
            
            /*
             Get Own Node's Socket Used Address (IP and Port)
             */
            var ownPrivateAddress = sockaddr_in()
            var ownPrivateAddressLength = socklen_t(MemoryLayout.size(ofValue: ownPrivateAddress))
            let getsocknameStatus = withUnsafeMutablePointer(to: &ownPrivateAddress) { ownPrivateAddressPointer in
                withUnsafeMutablePointer(to: &ownPrivateAddressLength) { ownPrivateAddressLengthPointer in
                    ownPrivateAddressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getsockname(sockhandle, $0, UnsafeMutablePointer(ownPrivateAddressLengthPointer))
                    }
                }
            }
            //Log(getsocknameStatus)
            var sourceIpAddress = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            inet_ntop(
                AF_INET,
                &ownPrivateAddress.sin_addr,
                &sourceIpAddress,
                socklen_t(INET_ADDRSTRLEN))
            let port: UInt16 = ownPrivateAddress.sin_port
            Log("^_^socket: \(sockhandle) nip: \(ownPrivateAddress.sin_addr) ip: \(String(cString: sourceIpAddress)) port: \(Int(port))")
            retSourceAddress = (ip: String(cString: sourceIpAddress), port: Int(port))
        }
        return (socketHandle: sockhandle, sourceAddress: retSourceAddress, connectionSucceeded)
    }
    public func findOverlayNetworkAddress(ip: String, node: Node) -> String? {
        Log(ip)
        if ip == node.getIp {
            return node.dhtAddressAsHexString.toString
        }
        var overlayNetworkAddress: String?
        self.socketHandles.forEach {
            $0.value.values.forEach {
                $0.values.forEach {
                    if $0.peerAddress.ip == ip {
                        overlayNetworkAddress = $0.overlayNetworkAddress?.toString
                    }
                }
            }
        }
        return overlayNetworkAddress
    }
    public func findOverlayNetworkAddress(socket: Int32) -> OverlayNetworkAddressAsHexString? {
        Log(socket)
        var overlayNetworkAddress: OverlayNetworkAddressAsHexString?
        self.socketHandles.forEach {
            $0.value.values.forEach {
                $0.values.forEach {
                    if $0.socketFd == socket {
                        overlayNetworkAddress = $0.overlayNetworkAddress
                    }
                }
            }
        }
        return overlayNetworkAddress
    }
    public func findIp(socketFd: Int32) -> (ip: String, port: Int)? {
        var address: (ip: String, port: Int)?
        self.socketHandles.forEach {
            $0.value.values.forEach {
                $0.values.forEach {
                    if $0.socketFd == socketFd {
                        address = $0.peerAddress
                    }
                }
            }
        }
        return address
    }
    public func findIpAndConnectStatus(socketFd: Int32) -> (address: (ip: String, port: Int)?, connected: Bool?) {
        var address: (ip: String, port: Int)?
        var connected: Bool?
        self.socketHandles.forEach {
            $0.value.values.forEach {
                $0.values.forEach {
                    if $0.socketFd == socketFd {
                        address = $0.peerAddress
                        connected = $0.connected
                    }
                }
            }
        }
        return (address, connected)
    }
    public func findIpAndAddressSpace(socketFd: Int32) -> (address: (ip: String, port: Int)?, addressspace: AddressSpace?, overlayNetwork: OverlayNetworkAddressAsHexString?) {
        var address: (ip: String, port: Int)?
        var addressSpace: AddressSpace?
        var overlayNetwork: OverlayNetworkAddressAsHexString?
        self.socketHandles.forEach {
            $0.value.values.forEach {
                $0.values.forEach {
                    if $0.socketFd == socketFd {
                        address = $0.peerAddress
                        addressSpace = $0.addressSpace
                        overlayNetwork = $0.overlayNetworkAddress
                    }
                }
            }
        }
        return (address, addressSpace, overlayNetwork)
    }
    public func didTranslate(_ overlayNetworkAddress: OverlayNetworkAddressAsHexString) -> (Int32?, Bool)? {
        Log(overlayNetworkAddress)
        Log(self.socketHandles)
        var socketFd: Int32?
        var connected = false
        self.socketHandles.forEach {    //each peer types
            $0.value.forEach {
                if $0.key == overlayNetworkAddress.toString {   //each overlay network addresses
                    if let socket = $0.value[.public] {
                        if socket.connected {
                            socketFd = socket.socketFd
                            connected = socket.connected
                        }
                    }
                    if let socket = $0.value[.private] {
                        if socket.connected {
                            socketFd = socket.socketFd
                            connected = socket.connected
                        }
                    }
                    if socketFd == nil {
                        if let socket = $0.value[.public] {
                            socketFd = socket.socketFd
                            connected = socket.connected
                        }
                    }
                }
            }
        }
        if socketFd != nil {
            return (socketFd, connected)
        } else {
            return nil
        }
    }
    
    /*
     送信データ生成
     */
    static let communicationTerminatorChar = "\n"
    static let operandDelimiterChar = " "
    let communicationTerminatorChar = "\n"
    let operandDelimiterChar = " "
    
    private func combineData(command: CommandProtocol, data: String, token: String) -> (Data, Int) {
        Log("command: \(command.rawValue) data: \(data) token: \(token)")
        //"FS 38298382,288392,2983,2893,2892\n"
        var commandData = Data()
        var transData = Data()
        var tokenData = Data()
        let data = data.removeNewLineChars
        Log(data)
        commandData = command.rawValue.utf8DecodedData!
        transData = data.utf8DecodedData!
        tokenData = token.utf8DecodedData!
        
        let spacer = operandDelimiterChar.utf8DecodedData!
        let terminator = communicationTerminatorChar.utf8DecodedData!
        let regulatedData = commandData + spacer + transData + spacer + tokenData + terminator
        let dataCount = regulatedData.count
        Log(regulatedData.utf8String as Any)
        return (regulatedData, dataCount)
    }
    enum ConnectionErrorNum: Int32 {
        case failed = 22        //: connection failed
        case trying = 36
        case trying2 = 37       //: start do connection as Non-Blockinng Mode
        case doneSuccess = 56   //: connected already (status == -1)
        case timeout = 60       //: timeout for 75 seconds
        case refusedPeer = 61   //: connection failed as refused by peer
        
        func description() -> String {
            String(cString: strerror(self.rawValue))
        }
    }

    /*
     Thank:
     https://stackoverflow.com/a/42764026
     */
    //Thank: https://stackoverflow.com/a/28075467
    var random: Double {
        return Double(arc4random()) / 0xFFFFFFFF
    }
    func random(min: Double, max: Double) -> Double {
        return self.random * (max - min) + min
    }
    
    /*
     TCP Hole Punching for communicate with Node under NAT DHCP router.
     UDP: Attempt looping data.Write (using POSIX Socket#sendto() function)
     TCP: Attempt looping tcp.flags.SYN (using POSIX Socket#connect() function)
     
     POSIX select() function bring up to Multiplexing Socket Communication.
     
     Thank:
     https://gist.github.com/somic/224795
     
     Communicate with POSIX BSD Sockets.
     
     At First, Register own's overlayNetworkAddress to Signaling Server.
     then Determine Communicaton Port in overlayNetwork.
     */
    //MARK: - Start Communication
//    public func start(startMode: Mode, tls: Bool, rawBufferPointer: UnsafeMutableRawBufferPointer, node: Node, inThread: Bool, notifyOwnAddress: @escaping ((ip: String, port: Int)?) -> Void, callback: @escaping (String?, Int) -> Void) {
    public func start(startMode: Mode, tls: Bool, rawBufferPointer: UnsafeMutableRawBufferPointer, node: Node, inThread: Bool, notifyOwnAddress: @escaping ((ip: String, port: Int)?) -> Void, callback: @escaping (String?, Range<Int>) -> Void) {
        Log(startMode)
        self.mode = startMode
        if inThread {
            Log()
            DispatchQueue.global().async { [self] in
                while true {
                    Log("++++++++++++++++ try Signaling (for communication) ++++++++++++++++")
                    communication()
                    if self.terminateCommunicate {
                        /*
                         Socket Communication Terminate as Signaling Server UnAvailable.
                         */
                        self.terminateCommunicate = false
                        break
                    }
                }
            }
        } else {
            Log()
            communication()
        }
        /*
         TCP/IP BSD Socket Multiplexing Communication Mode Flow (Implement TCP Hole Punching as NAT Traversal)
         
         Mode (send/receive details)
         registerMeAndIdling (send registerMe & receive okyours & send okregisterMe & receive translateAck.)
         ↓
         dequeueJob (send & receive data to any peer nodes / receive translateAck from signaling server as Another nodes.)
         ↓
         signaling (send translate & receive translateAck to signaling server.) *Synchronize handshake timing.
         ↓
         handshake (send & receive exchangeToken to A peer node.) *Open socket connect & send, recv.
         ↓
         dequeueJob (send & receive data to any peer nodes / receive translateAck from signaling server as Another nodes.)
         */
        func communication() {
            Log()
            guard let signalingServerAddress = Dht.getSignalingServer() else {
                Log()
                return
            }
            Log(signalingServerAddress)
            /*
             Connet to Sygnaling Server Two Time. (Syncronouslly)
             
             1st: Take Device's Private Address (IP and Port Number).
             ↓
             2nd: Use for Signaling Phase.
             */
            let (socketHandleForTakeAddress, sourceAddress, connectionStatus) = self.openSocket(to: signalingServerAddress, addressSpace: .public, source: nil)   //Connect Syncronouslly
            Log(connectionStatus)
            if !connectionStatus {
                Log()
                notifyOwnAddress(nil)
                self.terminateCommunicate = true
                return
            }
            close(socketHandleForTakeAddress)
            let (socketHandle, _, connectionSucceeded) = self.openSocket(to: signalingServerAddress, addressSpace: .public, source: sourceAddress) //Connect Syncronouslly
            Log(connectionSucceeded)
            if !connectionSucceeded {
                Log()
                notifyOwnAddress(nil)
                self.terminateCommunicate = true
                return
            }

            self.socketHandles = [.signalingServer: ["": [.public: (.public, socketHandle, signalingServerAddress, nil, connectionSucceeded, 0)]]]
            guard let ip = IpaddressV4(sourceAddress.ip) else {
                Log()
                return
            }
            let port = sourceAddress.port
            let ownNodePrivateAddress = (ip: sourceAddress.ip, port: port)
            node.reProduct(ownNode: ip, port: port)
            notifyOwnAddress(ownNodePrivateAddress)
            
            let my_token = Dht.hash(string: node.dhtAddressAsHexString.toString)?.0 ?? "token"
            Log("my_token =\(my_token)")
//            var remote_token = "_"

            Log("Wait time: \(self.avoidContaminationTime) \(self.regularWaitTime)")
            /*
             socket connet signaling server
             ↓
             select r, w
             w) Queueを見て、実行する
             ・接続要求（send command）
             translate commandをsignalingに送る
             ↓
             signalingからthe nodeとanother peer双方に接続要求きたことを知らせる
             ↓
             双方で接続
             ↓
             自nodeからpeerへ送信（send command）
             ・4分経過ごとにregisterMe commandを送る
             r) 受信する
             別スレッドで受信手続きをする
             0.5秒ごとにselectを繰り返す
             */
            var active_fd_set = fd_set()
            guard let peerTypes = self.mode.stack.first?.peerTypes else {
                Log()
                return
            }
            Log(peerTypes)
            peerTypes.forEach { peerType in
                self.socketHandles[peerType]?.forEach {
                    $0.value.values.forEach {
                        let socketHandle = $0.socketFd
                        __darwin_fd_set(socketHandle, &active_fd_set)
                    }
                }
            }
            
            func catchedSocketHandles(_ fd_set: fd_set, peerTypes: [Mode.PeerType]) -> [Int32]? {
//                Log(self.mode)
//                Log(peerTypes)
                var array = [Int32]()
                var catchedSocketHandles = fd_set
                //Log(self.socketHandles[peerType]?.count as Any)
                peerTypes.forEach {
                    self.socketHandles[$0]?.forEach {
                        $0.value.values.forEach {
                            let socketHandle = $0.socketFd
                            if __darwin_fd_isset(socketHandle, &catchedSocketHandles) != 0 {
                                array.append(socketHandle)
                            }
                        }
                    }
                }
                if array.isEmpty {
//                    Log("None")
                    return nil
                }
//                Log(array.count)
                return array
            }
            
            /*
             Detect UnConnected Socket Both Public and Private.
             */
            func isThereUnConnectedSocket(socketHandles: [String: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool, connectionFailCounter: Int)]]) -> (OverlayNetworkAddressAsHexString?, Mode.PeerType?)? {
                Log(socketHandles)
                let disConnectedSockets = socketHandles.filter {
                    let socketHandlePair = $0.value
                    if let publicOk = socketHandlePair[.public]?.connected, publicOk {
                        Log("This Address is Connected.")
                        return false
                    } else {
                        if let privateOk = socketHandlePair[.private]?.connected, privateOk {
                            Log("This Address is Connected.")
                            return false
                        } else {
                            Log("This Address is UnConnected yet.")
                            return true
                        }
                    }
                }
                Log(disConnectedSockets.first?.key as Any)
                var peerType: Mode.PeerType? = nil
                if let overlayNetworkAddress = disConnectedSockets.first?.key {
                    peerType = overlayNetworkAddress != "" ? .peerNode : .signalingServer
                }
                return (disConnectedSockets.first?.key, peerType)
            }
            func findSocketMatched(overlayNetworkAddress: OverlayNetworkAddressAsHexString, writableOrReadableSocketHandles: [Int32], peerType: Mode.PeerType) -> Int32? {
                Log(overlayNetworkAddress)
                Log(writableOrReadableSocketHandles)
                Log(peerType)
                var theSocket: Int32?
                writableOrReadableSocketHandles.forEach { socket in
                    self.socketHandles[peerType]?.forEach {
                        $0.value.values.forEach {
                            if $0.socketFd == socket {
                                if let overlayAddress = $0.overlayNetworkAddress, overlayAddress.equal(overlayNetworkAddress) && $0.connected {
                                    theSocket = socket
                                }
                            }
                        }
                    }
                }
                return theSocket
            }
            
            enum ConnectionStatus {
                case doneSuccessfully
                case failed
                case severeFailed
            }
#if ConnectSynchronously
            Log("Connect Synchronously (Remove -DConnectSynchronously to Build Setting - Swift Custum Flags if wanna Connect Asynchronous.)")
            func connectionStatus(sockhandle: Int32, address: (ip: String, port: Int)) -> (status: ConnectionStatus, errorNum: Int32) {
                Log(sockhandle)
                Log(address)
                if sockhandle == -1 {
                    Log()
                    return (.failed, 0)
                }
                let destination = address
                var remoteaddress = sockaddr_in()
                inet_pton(PF_INET,
                          destination.ip.cString(using: .utf8),
                          &remoteaddress.sin_addr)
                remoteaddress.sin_port = UInt16(destination.port).bigEndian
                remoteaddress.sin_family = sa_family_t(AF_INET)
                var socketAddressRemote = remoteaddress
                let connectStatus = withUnsafeMutablePointer(to: &socketAddressRemote) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(sockhandle, $0, socklen_t(MemoryLayout.stride(ofValue: remoteaddress)))
                    }
                }
                Log("try connect to: \(destination)")
                Log(connectStatus)
                let connectErrorNum = errno
                LogPosixError()
                if connectStatus == 0 || (connectStatus == -1 && connectErrorNum == 56) {
                    //56: Socket is already connected
                    return (.doneSuccessfully, connectErrorNum)
                }
                if connectStatus == -1 && (connectErrorNum == 61 || connectErrorNum == 22) {
                    return (.severeFailed, connectErrorNum)
                }
                return (.failed, connectErrorNum)
            }
#else
#endif
            func socketHandlesBy(peerTypes: [Mode.PeerType]?) -> [String: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool, connectionFailCounter: Int)]]? {
                var socketHandlesByPeerType = [String: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool, connectionFailCounter: Int)]]()
                peerTypes?.forEach { peerType in
                    Log(self.socketHandles[peerType])
                    socketHandlesByPeerType = socketHandlesByPeerType.merging(self.socketHandles[peerType] ?? [:]) { (current, new) in current }
                }
                Log(socketHandlesByPeerType)
                if socketHandlesByPeerType.isEmpty {
                    return nil
                }
                return socketHandlesByPeerType
            }
            
            var readable_fd_set = active_fd_set
            var writable_fd_set = active_fd_set
            var exception_fd_set = active_fd_set
            /*
             timeout 0.0s is indicate pooling.
             */
            var selectTimeout: timeval = timeval(tv_sec: 1, tv_usec: 0) //usec unit: μs ... 0.3s ... 0.3 * 1000.0 * 1000.0
            let maxTimeAttemptConnection = 10   // 10 ←connect成立しない場合がある
            var attemptingConnectSocket: (OverlayNetworkAddressAsHexString, Mode.PeerType)?
            var takeTimeForNodePerformance = Date()
            while true {
                if self.mode == .registerMeAndIdling {
                    takeTimeForNodePerformance = Date.now
                }
                //MARK: Start While Loop
                Log("Start Loop in Socket Communication.")
                if self.mode != self.previousMode {
                    Log(self.mode)
                    self.sleepSeconds = 0.0
                } else {
                    if self.mode == .handshake {
                        self.sleepSeconds += Double.random(in: 0...0.01)
                    }
                }
                self.previousMode = self.mode
                Log(self.mode.stack.first?.peerTypes as Any)
                /*
                 when it have done Connect then handshaking,
                 Wait exchangeToken Command from Peer Node until 10 times looping.
                 */
                if self.mode == .handshake, let writableSocket = self.inTransitionSignalingToHandshake {
//                    self.passedGracePeriod = self.passedGracePeriod > 0 ? self.passedGracePeriod - 1 : 0
                    self.passedGracePeriod += 1
                    if self.passedGracePeriod > 10 {
                        let (findipResult, addressSpace, overlayNetworkAddress) = self.findIpAndAddressSpace(socketFd: writableSocket)
                        if let overlayNetworkAddress = overlayNetworkAddress?.toString {
                            Log("\(writableSocket): \(findipResult as Any)")
                            if let findipResult = findipResult, let addressSpace = addressSpace {
                                self.socketHandles[Mode.PeerType.peerNode]?[overlayNetworkAddress]?[addressSpace]?.connected = false
                            }
                        }
                        self.inTransitionSignalingToHandshake = nil
                        self.passedGracePeriod = 0
                    }
                }
                /*
                 If there any Socket NOT Connect yet, Try Close(), Connect() attempt.
                 
                 Attempt Connect to A translated Address first one.
                 
                 Try 10 time.
                 */
                if let peerTypes = self.mode.stack.first?.peerTypes,
                   let socketHandlesByPeerType = socketHandlesBy(peerTypes: peerTypes),
                   let (unConnectedOverlayNetworkAddress, unConnectedPeerType) = isThereUnConnectedSocket(socketHandles: socketHandlesByPeerType),
                   let unConnectedOverlayNetworkAddress = unConnectedOverlayNetworkAddress,
                   let unConnectedPeerType = unConnectedPeerType,
                   let sokcetHandlePairByOverlayNetwork = self.socketHandles[unConnectedPeerType]?[unConnectedOverlayNetworkAddress.toString] {
                    LogCommunicate("Find UnConnect Node cause Try Connect to A Node.")
                    attemptingConnectSocket = (unConnectedOverlayNetworkAddress, unConnectedPeerType)
                    Log(peerTypes)
                    Log(socketHandlesByPeerType as Any)
                    let socketHandles = [sokcetHandlePairByOverlayNetwork[.public], sokcetHandlePairByOverlayNetwork[.private]]
                    let peerType = unConnectedPeerType
                    let overlayNetworkAddress = unConnectedOverlayNetworkAddress.toString
                    self.socketHandles[peerType]?[overlayNetworkAddress]?[.public]?.connectionFailCounter += 1
                    self.socketHandles[peerType]?[overlayNetworkAddress]?[.private]?.connectionFailCounter += 1
                    var connectionFailCounter = self.socketHandles[peerType]?[overlayNetworkAddress]?[.public]?.connectionFailCounter
                    Log(connectionFailCounter as Any)
                    Log(peerType)
                    Log(socketHandles)
                    if let connectionFailCounter = connectionFailCounter, connectionFailCounter > maxTimeAttemptConnection {
                        LogEssential("+++++++++++++++ Connection Failed up to Specified Max Count. \(String(describing: sokcetHandlePairByOverlayNetwork[.public]?.peerAddress)) +++++++++++++++")
                        /*
                         When Detected Connection Failed,
                         
                         the Node Sent translate command & Received translateAck:
                         Go to dequeueJob mode as Once more Detect Job Queue and Send translate command to Signaling Server.
                         (Do NOT re-registerMe)
                         
                         the Node Received translateAck:
                         Go to dequeueJob mode as Wait Until Receive translateAck command.
                         (Do NOT re-registerMe)
                         */
                        /*
                         Close Old Socket
                         */
                        var alreadyOpenSocket = false
                        socketHandles.forEach {
                            if let socketFd = $0?.socketFd, socketFd != -1 {
//                                LogEssential("Close Old Socket")
//                                let closeRet = close(socketFd)
//                                Log(closeRet)
                                /*
                                 Check Soket whether Connected to Peer, Already.
                                 */
                                if let socketHandleDescription = $0 {
                                    let addressSpace = socketHandleDescription.addressSpace
                                    let address = socketHandleDescription.peerAddress
                                    let socketFd = socketHandleDescription.socketFd
                                    let overlayNetworkAddress = socketHandleDescription.overlayNetworkAddress
                                    let connected = socketHandleDescription.connected
                                    let sendHandshake: ContiguousArray<CChar> = " ".utf8CString
                                    var sentStatus: Int?
                                    errno = 0
                                    sentStatus = sendHandshake.withUnsafeBytes {
                                        Log("Will Write Length: \($0.count)")
                                        return send(socketFd, $0.baseAddress, $0.count, 0)
                                    }
                                    if let sentStatus = sentStatus, sentStatus >= 0 {
                                        Log("Already Open Socket.")
                                        alreadyOpenSocket = true
                                    } else {
                                        LogEssential("Close Old Socket")
                                        let closeRet = close(socketFd)
                                        Log(closeRet)
                                    }
                                }
                            }
                        }
                        if !alreadyOpenSocket {
                            /*
                             Clear Socket description for overlayNetworkAddress as up to Max Fail Count.
                             */
                            Log("Clear the Socket description. (socketHandles)")
                            self.socketHandles[peerType]?[overlayNetworkAddress] = nil
                            /*
                             Claimed Node for Translate, Run from beginning.
                             */
                            if self.claimTranslate {
                                self.claimTranslate = false
                                LogEssential("------------- Once more Send registerMe to Signaling Server. ------------- (the Node claimed translate.)")
                                Log(self.socketHandles)
                                if let haveCommunicatedSignalingServers = socketHandlesBy(peerTypes: [.signalingServer]) {
                                    haveCommunicatedSignalingServers.forEach {
                                        $0.value.values.forEach {
                                            if $0.connected {
                                                if $0.socketFd != -1 {
                                                    Log("Close Old Socket")
                                                    let closeRet = close($0.socketFd)
                                                    Log(closeRet)
                                                }
                                            }
                                        }
                                    }
                                }
                                Log("Clear the Socket description. (signalingServer)")
                                self.socketHandles[.signalingServer]?[""] = nil
                                self.mode = .registerMeAndIdling
                                self.communicationProcess.onceMore()
                                break
                            } else {
                                LogEssential("Back to dequeueJob mode (the node NOT claimed Translate).")
                                self.mode = .dequeueJob
                                self.communicationProcess.onceMore()
                            }
                        }
                    } else {
                        LogCommunicate("Attempt Connect to A Unconnect Node first one.")
                        Log(socketHandles)
                        socketHandles.forEach {
                            var connectStatus: ConnectionStatus?
                            if let socketHandleDescription = $0 {
                                let addressSpace = socketHandleDescription.addressSpace
                                let address = socketHandleDescription.peerAddress
                                let socketFd = socketHandleDescription.socketFd
                                let overlayNetworkAddress = socketHandleDescription.overlayNetworkAddress
                                let connected = socketHandleDescription.connected
                                Log("Detect Socket whether Opened.")
                                /*
                                 Check Done Connect the Sokets.
                                 */
                                if let overlayNetworkAddressAsString = overlayNetworkAddress?.toString {
                                    let connectionFailCounter = self.socketHandles[peerType]?[overlayNetworkAddressAsString]?[addressSpace]?.connectionFailCounter ?? 0
                                    connectStatus = connected ? .doneSuccessfully : .failed
                                    if connectStatus == .doneSuccessfully {
                                        Log("Socket Have Opened")
                                        /*
                                         Socket Have Opened (Connected)
                                         Goto Do select() async.
                                         */
                                        Log(self.socketHandles[peerType]?[overlayNetworkAddressAsString]?[addressSpace]?.connected as Any)
                                    } else {
                                        Log("Socket Not Open yet")
                                        /*
                                         Close Old Socket
                                         */
                                        if socketFd != -1 {
                                            /*
                                             Check Soket whether Connected to Peer.
                                             */
                                            let sendHandshake: ContiguousArray<CChar> = " ".utf8CString
                                            var sentStatus: Int?
                                            errno = 0
                                            sentStatus = sendHandshake.withUnsafeBytes {
                                                Log("Will Write Length: \($0.count)")
                                                return send(socketFd, $0.baseAddress, $0.count, 0)
                                            }
                                            if let sentStatus = sentStatus, sentStatus >= 0 {
                                                Log("Already Open Socket.")
                                            } else {
                                                Log("Close Old Socket")
                                                let closeRet = close(socketFd)
                                                Log(closeRet)
                                                //LogPosixError()
                                                self.socketHandles[peerType]?[overlayNetworkAddressAsString]?[addressSpace]?.socketFd = -1
                                            }
                                        }
                                        if let connected = self.socketHandles[peerType]?[overlayNetworkAddressAsString]?[addressSpace]?.connected, connected {
                                            LogCommunicate("Already Open Socket.")
                                        } else {
                                            /*
                                             Open Socket
                                             */
                                            LogCommunicate("Open Socket")
#if ConnectSynchronously
                                            Log("Connect Synchronously (Remove -DConnectSynchronously to Build Setting - Swift Custum Flags if wanna Connect Asynchronous.)")
                                            var connectionSucceeded = false
                                            var connectionTime = 0
                                            while !connectionSucceeded {
                                                connectionTime += 1
                                                Log(connectionTime)
                                                let (socketHandle, sourceAddress, connectionSucceeded) = openSocket(to: address, addressSpace: addressSpace, source: ownNodePrivateAddress)
                                                shutdown(socketHandle, SHUT_RDWR)   //Connect Syncronouslly
                                                close(socketHandle)
                                            }
#else
                                            //MARK: - Connect
                                            Log(address)
                                            let (socketHandle, sourceAddress, connectionSucceeded) = openSocket(to: address, addressSpace: addressSpace, source: ownNodePrivateAddress, async: true)
#endif
                                            self.socketHandles[peerType]?[overlayNetworkAddressAsString]?[addressSpace] = (addressSpace: addressSpace, socketFd: socketHandle, peerAddress: address, overlayNetworkAddress: overlayNetworkAddress, connected: connectionSucceeded, connectionFailCounter: connectionFailCounter)
                                            Log("Append a Socket.")
                                            Log(peerType)
                                            Log(self.socketHandles[peerType]?[overlayNetworkAddressAsString]?[addressSpace] as Any)
                                            self.doUpdateFdSet = true   //for handshake
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                /*
                 Update FdSet as Mode Changed.
                 Sockets Updated cause re-arrange fd_set for Detect select() read/write.
                 */
                if self.doUpdateFdSet {
                    self.doUpdateFdSet = false
                    Log("Set up fd_set as Sockets Updated")
                    Log(self.mode.stack.first?.peerTypes)
                    if let socketHandlesByPeerType = socketHandlesBy(peerTypes: self.mode.stack.first?.peerTypes) {
                        //Log(socketHandlesByPeerType)
                        /*
                         when handshake mode, Add UnConnect Peer Node Only to fd_set.
                         */
                        if self.mode == .handshake, let (unConnectedOverlayNetworkAddress, unConnectedPeerType) = isThereUnConnectedSocket(socketHandles: socketHandlesByPeerType), let unConnectedOverlayNetworkAddress = unConnectedOverlayNetworkAddress, let unConnectedPeerType = unConnectedPeerType {
                            self.handshakeTimes += 1
                            Log(self.handshakeTimes)
                            if self.handshakeTimes % 2 == 0 {
                                Log()
                                /*
                                 Communicate with Signaling Server.
                                 */
                                if let sokcetHandlePairSignalingServer = self.socketHandles[.signalingServer]?[""]?[.public] {
                                    bzero(&active_fd_set, MemoryLayout.size(ofValue: active_fd_set))
                                    let socketHandle = sokcetHandlePairSignalingServer.socketFd
                                    if socketHandle > 0 {
                                        __darwin_fd_set(socketHandle, &active_fd_set)
                                    }
                                }
                            } else {
                                Log()
                                /*
                                 Handshaking with Peer Node.
                                 */
                                if let sokcetHandlePairByOverlayNetwork = self.socketHandles[unConnectedPeerType]?[unConnectedOverlayNetworkAddress.toString] {
                                    bzero(&active_fd_set, MemoryLayout.size(ofValue: active_fd_set))
                                    sokcetHandlePairByOverlayNetwork.values.forEach {
                                        let socketHandle = $0.socketFd
                                        if socketHandle > 0 {
                                            //Log("\(socketHandle) (\($0.peerAddress)) into fd_set.")
                                            __darwin_fd_set(socketHandle, &active_fd_set)
                                        }
                                    }
                                }
                            }
                        } else {
                            bzero(&active_fd_set, MemoryLayout.size(ofValue: active_fd_set))
                            socketHandlesByPeerType.forEach {
                                $0.value.values.forEach {
                                    let socketHandle = $0.socketFd
                                    if socketHandle > 0 {
                                        //Log("\(socketHandle) (\($0.peerAddress)) into fd_set.")
                                        __darwin_fd_set(socketHandle, &active_fd_set)
                                    }
                                }
                            }
                        }
                    }
                }
                Log("Set up fd_set for Detect select() read/write")
                readable_fd_set = active_fd_set
                writable_fd_set = active_fd_set
                exception_fd_set = active_fd_set
                Log()
                /*
                 Find Max file descriptor number.
                 */
                var maxfd: Int32 = 0
                self.mode.stack.first?.peerTypes.forEach { peerType in
                    //                    Log(peerType)
                    self.socketHandles[peerType]?.forEach {
                        $0.value.values.forEach {
                            let sockhandle = $0.socketFd
                            maxfd = ((maxfd - 1) > sockhandle ? maxfd : sockhandle + 1)
                        }
                    }
                }
                Log("--readable_fd_set: \(readable_fd_set) writable_fd_set:\(writable_fd_set)")
                Log("Select(Detect) read/write Events for Sockets (..<\(maxfd))")
                //MARK: Select()
                errno = 0   //clear as select() NOT Set errno.
                let selectStatus = select(maxfd, &readable_fd_set, &writable_fd_set, &exception_fd_set, &selectTimeout)   //Block able
                Log(selectStatus) //0: timeout/no any sockets   1...: number of available sockets/done attempt connection
                Log("\(selectStatus) \(errno): \(String(cString: strerror(errno)))")
                /*
                 select return:
                 -1: Error occurred (Set `errno` posix global valiable)
                 0: Timeout occurred / Not Available any Sockets
                 1...: Available Sockets Count (Amount of r w e)
                 
                 - Attempting Connect: Not Be Available Read&Write.
                 ・コネクション中のTCPソケットを検査すると、受信不可かつ送信不可の状態という結果になります。
                 
                 - Done Attempting Connect (Regardless Succeeded/Failed): Be Availabele Read/Write.
                 errno 0: Connection Succeeded
                 errno Non 0: Connection Failed
                 ・コネクションの試みが終了すると(正常、異常とわず)、受信可能や送信可能(あるいは、両方とも可能)になります。
                 */
                Log("\(mode) \(self.communicationProcess.phase) \(self.mode.stack[communicationProcess.phase].peerTypes)")
                Log("++readable_fd_set: \(readable_fd_set) writable_fd_set:\(writable_fd_set)")
                Log("Exception")
                //MARK: Exception Socket (purhaps select() status: -1)
                if let exceptionSocketHandles = catchedSocketHandles(exception_fd_set, peerTypes: self.mode.stack[communicationProcess.phase].peerTypes) {
                    Log("\(self.mode) e \(self.communicationProcess.phase)")
                    Log("Socket Occurred Exception. continue next")
                    Log(exceptionSocketHandles.first as Any)
                    continue
                }
                Log(selectStatus)
                /*
                 read
                 ↓
                 write
                 */
                if readPhase() {
                    /*
                     ReNew Peer Sockets
                     */
                    continue
                }
                if writePhase() {
                    /*
                     ReNew Peer Sockets
                     */
                    continue
                }
                Log()
                if self.mode == .handshake {
                    //MARK: r/w handshake
                    Log()
                    if self.remote_token != "_" && self.remote_knows_our_token {
                        LogEssential("++++++++++++++++++++ NAT Traversal - Succeeded. ++++++++++++++++++++")
                        Log("++++++++++++++++++++ TCP Hole Punching We Did! ++++++++++++++++++++")
                        Log("++++++++++++++++++++ We are done handshake for NAT Traversal - Hole was punched from both ends ++++++++++++++++++++")
                        self.inTransitionSignalingToHandshake = nil
                        self.passedGracePeriod = 0
                        self.remote_token = "_"
                        
                        /*
                         Go to Next Process.
                         */
                        Log()
                        attemptingConnectSocket = nil
                        if let nextMode = self.mode.stack[communicationProcess.phase].nextMode {
                            Log()
                            self.mode = nextMode
                            communicationProcess.nextMode()
                        }
                    }
                }
                Log(node.ipAndPortString)
                node.printSocketQueue() //MARK: r/w dequeue
                if let firstJob = node.socketQueues.firstQueueTypeLocal() {
                    Log("Have Command to Local Execution to First.")
                    let _ = node.socketQueues.deQueue()
                    Log(firstJob.token)
                    Log(firstJob)
                    //                    Log(peerAddressPairs as Any)
                    var commandInstance: CommandProtocol = firstJob.command
                    if firstJob.command.rawValue == "", let command = node.premiumCommand {
                        Log()
                        /*
                         Won't be Use this.
                         
                         if Nothing in overlayNetwork Command,
                         Use Appendix Premium Command.
                         */
                        commandInstance = node.premiumCommand?.command(command.rawValue) ?? command
                        commandInstance = command
                    }
                    LogEssential("from \(node.dhtAddressAsHexString) to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
                    if firstJob.type == .local {
                        Log("Send Command to oneself.")
                        let sentDataNodeIp = node.getIp
                        Log(sentDataNodeIp as Any)
                        /*
                         fetching commnad+operand+token from job in queue.
                         Save cString ([CChar]) to UnsafeMutableRawBufferPointer's Pointee
                         */
                        if let jobData = (firstJob.command.rawValue + " " + firstJob.operand + " " + firstJob.token).toCChar {
                            Log(jobData)
                            jobData.withUnsafeBytes {
                                rawBufferPointer.copyMemory(from: $0)
                            }
                            let receivedDataLength = jobData.count
                            Log(receivedDataLength as Any)
                            if let sentDataNodeIp = sentDataNodeIp, receivedDataLength > 0 {
                                Log()
//                                callback(sentDataNodeIp, receivedDataLength)
                                let startRange = 0
                                let dataRange = startRange..<(startRange + receivedDataLength)
                                callback(sentDataNodeIp, dataRange)
                            }
                        }
                    }
                } else {
                    Log("Not Have Command to Local Execution to First.")
                }
                if self.mode == .registerMeAndIdling && self.nodePerformance == nil {
                    self.nodePerformances += [Date().timeIntervalSince(takeTimeForNodePerformance)]  //小さければ高パフォーマンス
                    Log(self.nodePerformances as Any)
                }
                if self.mode == .handshake {            //be needed critical time managing when Do NAT hole punching.
                    usleep(UInt32(self.sleepSeconds * 1024 * 1024) + self.diffPerformance)    //Peer Node lower Performance than the Node cause wait more.
                } else if self.mode == .dequeueJob {    //Connect when as Received Node
                    usleep(self.avoidContaminationTime)   //wait 0.5 seconds as avoid contamination socket data.
                } else {                                //when as regular mode
                    usleep(self.regularWaitTime)
                }
            }   //while
            
//            func readDataFromBoundSocket(_ socketFd: Int32, rawPointer: UnsafeMutableRawPointer, amountedReadedResult: inout Int) {
//                Log("Reading Next. \(String(describing: rawPointer)) + \(amountedReadedResult)")
//                var readResult = 0
//
//                errno = 0
//                readResult = recv(socketFd, rawPointer, Socket.MTU, 0)  //public func recv(_: Int32, _: UnsafeMutableRawPointer!, _: Int, _: Int32) -> Int
//                
//                amountedReadedResult += readResult
//                if readResult == 0 {
//                    Log("Detected End of File.")
//                    Log("Amounted Byte. \(amountedReadedResult) Byte")
//                    return
//                } else if readResult == -1 {
//                    if errno == EAGAIN {
//                        /*
//                         Indicate Detected End of File in nonBlocking socket.
//                         
//                         EAGAIN: 35 Resource temporarily unavailable
//                         */
//                    } else {
//                        Log("Occurred Error, As Reading from \(socketFd) - \(errno) \(String(cString: strerror(errno)))")
//                        amountedReadedResult = readResult
//                    }
//                    return
//                } else {
//                    Log("Reading Data.")
//                    Log("\(readResult) Byte")
//                    Log(rawBufferPointer.toString(byteLength: readResult))
//                    /*
//                     Call recursively.
//                     */
//                    let nextBufferPointer: UnsafeMutableRawPointer = rawPointer + readResult
//                    readDataFromBoundSocket(socketFd, rawPointer: nextBufferPointer, amountedReadedResult: &amountedReadedResult)
//                    return
//                }
//            }
            //MARK: Read Socket
            func readPhase() -> Bool {  Log()
                var returnValue = false
                if let readableSocketHandles = catchedSocketHandles(readable_fd_set, peerTypes: self.mode.stack[communicationProcess.phase].peerTypes) {
                    LogCommunicate("\(self.mode) r \(self.communicationProcess.phase)")
                    Log("Socket Have Read Data as Readable.")
                    /*
                     Receive Data (Command & Operands)
                     */
                    Log(readableSocketHandles)
                    for aReadableSocketHandle in readableSocketHandles.enumerated() {
                        let socketFd = aReadableSocketHandle.element
                        Log("\(aReadableSocketHandle.offset) \(socketFd)")
                        errno = 0
                        var readableSocketNoError = false
                        let (findipResult, addressSpace, _) = self.findIpAndAddressSpace(socketFd: socketFd)
                        LogCommunicate("\(socketFd): \(findipResult as Any)")
                        if let findipResult = findipResult, let addressSpace = addressSpace { Log()
                            Log(socketFd)
                            // Check the socket
                            var errnoBySocket: Int = 0
                            var resultLength = socklen_t(MemoryLayout<Int>.size)
                            if getsockopt(socketFd, SOL_SOCKET, SO_ERROR, &errnoBySocket, &resultLength) < 0 {
                                LogPosixError()
                            }
                            Log("socketFd:\(socketFd) errno:\(errnoBySocket) \(String(cString: strerror(Int32(errnoBySocket))))")
                            if errnoBySocket == 0 {
                                /*
                                 Perhaps... Connection Successfull.
                                 */
                                Log("[c]Socket NOT Error. (as Readable socket)")
                                readableSocketNoError = true
                            }
                        }
                        
                        let readableSocketHandle = socketFd
                        guard let rawBufferPointerAddress = rawBufferPointer.baseAddress else {
                            Log()
                            returnValue = false
                            break
                        }
                        /*
                         For TCP sockets, the return value 0 means the peer has closed its half
                         side of the connection.
                         */
                        errno = 0
                        let receivedDataLength = recv(readableSocketHandle, rawBufferPointer.baseAddress, rawBufferPointer.count, 0)
                        Log(receivedDataLength as Any)  //-1: Error   0: End of File   >0: data length
                        LogPosixError()  //35: 受信データがない　 60: Operation timed out    61: Connection refused by peer
//                        Log("\(readableSocketNoError) && \(receivedDataLength) (\(receivedDataLength <= 0 ? "Socket Receive Error Occurred." : "")")
                        if readableSocketNoError && receivedDataLength > 0 {
                            Log("[c]Received Data Successfully.")
                            let (findipResult, addressSpace, overlayNetworkAddress) = self.findIpAndAddressSpace(socketFd: readableSocketHandle)
                            if let overlayNetworkAddress = overlayNetworkAddress?.toString {
                                Log("\(readableSocketHandle): \(findipResult as Any)")
                                if let findipResult = findipResult, let addressSpace = addressSpace { LogEssential("[c]Connection Successfull.")
                                    self.mode.stack[communicationProcess.phase].peerTypes.forEach { peerType in
                                        if (overlayNetworkAddress != "" && peerType == .peerNode) || (overlayNetworkAddress == "" && peerType == .signalingServer) {
                                            self.socketHandles[peerType]?[overlayNetworkAddress]?[addressSpace]?.connected = true
                                        }
                                    }
                                }
                            }
                        }
                        /*
                         Received Data Successfully.
                         */
                        let receivedByte = rawBufferPointer.toByte(byteLength: receivedDataLength == -1 ? 0 : receivedDataLength)
                        Log(receivedByte)
                        //divide as Bytes
                        let receivedBytes = receivedByte.split(separator: Int8.zero)
                        Log(receivedBytes.count)
//                        Log(rawBufferPointer.toString(byteLength: receivedDataLength == -1 ? 0 : receivedDataLength))
//                        let receivedDataAsString = rawBufferPointer.toString(byteLength: receivedDataLength == -1 ? 0 : receivedDataLength)
//                        LogEssential(receivedDataAsString)
                        
                        /*
                         Divide Received Data as think for Contamination.
                         
                         Terminator:
                         exchangeToken
                         null 00
                         
                         FS
                         \n 0a00
                         */
                        var startRange = 0
                        receivedBytes.enumerated().forEach {
                            //Bytes to String
                            let receivedDataAsString: String = $0.element.withUnsafeBufferPointer { ccharbuffer in
                                String(cString: ccharbuffer.baseAddress!)
                            }
                            LogCommunicate(receivedDataAsString)
                            let dataRange = startRange..<(startRange + $0.element.count)
                            Log("\(dataRange.lowerBound) - \(dataRange.upperBound)")
                            startRange += ($0.element.count + 1)
                            let receivedCommandOperand = receivedDataAsString.components(separatedBy: " ")
                            Log(receivedCommandOperand)
                            let command = receivedCommandOperand[0]
                            if self.mode.stack[communicationProcess.phase].selects.contains(.receive) {
                                Log()
                                if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .okyours {
                                    if command == doCommand.rawValue {
                                        //MARK: r okyours
                                        Log("^_^\(receivedDataAsString)")
                                        /*
                                         Receive Ack from SygnalingServer.
                                         
                                         data format:
                                         okyours {public ip/port}null
                                         
                                         ex.
                                         okyours 49.212.211.165:3478
                                         */
                                        let ownPublicAddress = receivedCommandOperand[1].components(separatedBy: ":")
                                        if let port = Int(ownPublicAddress[1]) {
                                            node.publicAddress = (ip: ownPublicAddress[0], port: port)
                                        }
                                        communicationProcess.increment()
                                    }
                                } else if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .registerMeAck {
                                    if command == doCommand.rawValue {
                                        //MARK: r registerMeAck
                                        Log()
                                        /*
                                         Receive registerMeAck
                                         */
                                        node.printSocketQueue()
                                        guard let firstJob = node.socketQueues.queues.first else {
                                            //                                        Log("Not Have Command to Send.")
                                            Log("Empty Queue then be idling mode.")
                                            communicationProcess.idling()
                                            returnValue = false
                                            return
                                        }
                                        var commandInstance: CommandProtocol = firstJob.command
                                        if firstJob.command.rawValue == "", let command = node.premiumCommand {
                                            Log()
                                            /*
                                             Won't be Use this.
                                             
                                             if Nothing in overlayNetwork Command,
                                             Use Appendix Premium Command.
                                             */
                                            commandInstance = node.premiumCommand?.command(command.rawValue) ?? command
                                            commandInstance = command
                                        }
                                        Log("from \(node.dhtAddressAsHexString) to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
                                        if firstJob.type == .local || firstJob.toOverlayNetworkAddress.equal(node.dhtAddressAsHexString) {
                                            Log("Local Job")
                                            /*
                                             Local Queue
                                             */
                                            //                                        Log("Have a Command as Local Execution in First Queue.")
                                            //                                        let _ = node.socketQueues.deQueue()
                                            let _ = node.socketQueues.deQueue(toOverlayNetworkAddress: firstJob.toOverlayNetworkAddress, token: firstJob.token)
                                            //                                        Log("Send Command to oneself.")
                                            Log(firstJob.token)
                                            Log(firstJob)
                                            //Log(peerAddressPairs as Any)
                                            Log("Send Command to oneself.")
                                            let sentDataNodeIp = node.getIp
                                            Log(sentDataNodeIp as Any)
                                            /*
                                             fetching commnad+operand+token from job in queue.
                                             
                                             Save cString ([CChar]) to UnsafeMutableRawBufferPointer's Pointee
                                             */
                                            if let jobData = (firstJob.command.rawValue + " " + firstJob.operand + " " + firstJob.token).toCChar {
                                                Log("\(jobData) to local")
                                                jobData.withUnsafeBytes {
                                                    rawBufferPointer.copyMemory(from: $0)
                                                }
                                                let receivedDataLength = jobData.count
                                                Log(receivedDataLength as Any)
                                                if let sentDataNodeIp = sentDataNodeIp, receivedDataLength > 0 {
                                                    Log()
                                                    callback(sentDataNodeIp, dataRange)
                                                }
                                            }
                                        } else {
                                            Log("Remote Job")
                                            //                                        Log("Not Have a Command as Local Execution in First Queue.")
                                            //                                        if let job = node.socketQueues.queues.first {
                                            /*
                                             Remote Queue
                                             */
                                            Log("Have a Command as Send Remote Node, go to Signaling Mode.")
                                            /*
                                             Go to Next Process (signaling mode).
                                             
                                             Did translate already
                                             ↓Y     ↓N
                                             　　　　go to next signaling mode
                                             go to dequeueJob mode
                                             
                                             */
                                            if let (writableSocket, connected) = didTranslate(firstJob.toOverlayNetworkAddress) {
                                                //                                                Log("Have translated cause Go to dequeueJob mode.")
                                                LogEssential("Translated - the OverlayNetworkAddress \(firstJob.toOverlayNetworkAddress) was entered to {socketHaneles}.")
                                                self.mode = .dequeueJob
                                                communicationProcess.nextMode()
                                            } else {
                                                //                                                Log("----------- Not translate cause Go to signaling mode -----------")
                                                LogEssential("----------- Did NOT Translate cause Go to signaling mode for Ask Addresses to Signaling Server. \(firstJob.toOverlayNetworkAddress) -----------")
                                                Log(firstJob.toOverlayNetworkAddress)
                                                Log(firstJob)
                                                if let nextMode = self.mode.stack[communicationProcess.phase].nextMode, let peerTypes = nextMode.stack.first?.peerTypes {
                                                    Log()
                                                    self.mode = nextMode
                                                    communicationProcess.updateDoneTime()
                                                    communicationProcess.nextMode()
                                                }
                                            }
                                            //                                        } else {
                                            //                                            Log("Empty Queue then be idling mode.")
                                            //                                            communicationProcess.idling()
                                            //                                        }
                                        }
                                    }
                                } else if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.contains(.exchangeToken), doCommand {
                                    let doCommand = Mode.SignalingCommand.exchangeToken
                                    if command == doCommand.rawValue {
                                        //MARK: r exchangeToken
                                        Log()
                                        if self.remote_token == "_" {
                                            self.remote_token = receivedCommandOperand[1]
                                            Log("remote_token is now \(self.remote_token)")
                                        }
                                        if receivedCommandOperand.count == 4 {
                                            Log("remote end signals it knows our token")
                                            self.remote_knows_our_token = true
                                        }
                                    }
                                }
                                if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.contains(.translateAck), doCommand {
                                    if command == Mode.SignalingCommand.translateAck.rawValue {Log("++++++++ Received translateAck ++++++++")
                                        Log(receivedCommandOperand)
                                        //MARK: r translateAck
                                        /*
                                         Received Command for defined in Signaling.
                                         
                                         自node と peer 双方に接続要求を知らせてきた
                                         ["ack", "153.243.66.142", "1040", "192.168.0.34", "54512", "", "", "", "", "", "", "",...
                                         */
                                        if let nextMode = self.mode.stack[communicationProcess.phase].nextMode, let peerTypes = nextMode.stack.first?.peerTypes {Log()
                                            /*
                                             sendBuff = "translateAck {0} {1} {2} {3} {4} {5}".format(publicip, publicport, privateip, privateport, node_performance, overlayNetworkAddress)
                                             */
                                            let publicIp: String? = receivedCommandOperand[1]
                                            //Log(receivedCommandOperand[2])    //public port
                                            let privateIp: String? = receivedCommandOperand[3]
                                            //Log(receivedCommandOperand[4])    //private port
                                            let nodePerformance = receivedCommandOperand[5]
                                            let peerNodePerformance = Double(nodePerformance) ?? 0.0
                                            
                                            let overlayNetworkAddress = receivedCommandOperand[6]
                                            if let publicPort = Int(receivedCommandOperand[2]), let privatePort = Int(receivedCommandOperand[4]) {Log()
                                                var publicAddress: (ip: String, port: Int)?
                                                var privateAddress: (ip: String, port: Int)?
                                                if let publicIp = publicIp {
                                                    publicAddress = (ip: publicIp, port: publicPort)
                                                } else {
                                                    publicAddress = nil
                                                }
                                                if let privateIp = privateIp {
                                                    privateAddress = (ip: privateIp, port: privatePort)
                                                } else {
                                                    privateAddress = nil
                                                }
                                                /*
                                                 Clear Socket description for overlayNetworkAddress as up to Max Fail Count.
                                                 */
                                                Log("Clear the Socket description. (socketHandles)")
                                                if let attemptingConnectSocket = attemptingConnectSocket {
                                                    self.socketHandles[attemptingConnectSocket.1]?[attemptingConnectSocket.0.toString] = nil
                                                }
                                                attemptingConnectSocket = nil
                                                peerTypes.forEach { peerType in
                                                    if let sockets = socketHandlesBy(peerTypes: [peerType]), sockets.count > 0 {
                                                        //Already made
                                                    } else {
                                                        //when Empty
                                                        self.socketHandles[peerType] = [String: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool, connectionFailCounter: Int)]]()
                                                    }
                                                    if (peerType == .signalingServer && overlayNetworkAddress == "") || (peerType == .peerNode && overlayNetworkAddress != "") {
                                                        var socketElement = [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool, connectionFailCounter: Int)]()
                                                        if let publicAddress = publicAddress {
                                                            socketElement[.public] = (addressSpace: .public, socketFd: -1, peerAddress: publicAddress, overlayNetworkAddress: overlayNetworkAddress, connected: false, connectionFailCounter: 0)
                                                        }
                                                        if let privateAddress = privateAddress {
                                                            socketElement[.private] = (addressSpace: .private, socketFd: -1, peerAddress: privateAddress, overlayNetworkAddress: overlayNetworkAddress, connected: false, connectionFailCounter: 0)
                                                        }
                                                        self.socketHandles[peerType]?[overlayNetworkAddress] = socketElement
                                                    }
                                                }
                                                Log(self.socketHandles)
                                            }
                                            /*
                                             Go to Next Process.
                                             */
                                            Log(peerTypes)
                                            self.mode = nextMode
                                            communicationProcess.nextMode()
                                            self.remote_knows_our_token = false
//                                            self.inTransitionSignalingToHandshake = true
                                            self.handshakeTimes = 0
                                            var diff = self.nodePerformance?.distance(to: peerNodePerformance) ?? 0.0
                                            diff = diff * 1024 * 1024
                                            self.diffPerformance = UInt32(exactly: diff.rounded()) ?? 0
                                            Log("\(self.nodePerformance) - \(peerNodePerformance) = \(diff) ..rounded. \(self.diffPerformance)")
                                            Log("--- Will Add Socket for New Handshake as New Peer Communication -----------------------------------------------")
                                            Log(socketHandlesBy(peerTypes: peerTypes) as Any)
                                            returnValue = true
                                        }
                                    }
                                }
                                if self.mode == .dequeueJob || self.mode == .handshake {
                                    //MARK: r dequeueJob
                                    Log()
                                    /*
                                     Receivable translateAck command from Other Nodes.
                                     
                                     translateAck受信した場合
                                     ↓
                                     socketHandlesにpeer追加してconnect
                                     ↓
                                     handShake　＊この間は他nodeとの通信はしない
                                     ↓
                                     select socketsに2nodeめを追加
                                     ↓
                                     複数nodeと通信　←selectで有効なsocketと通信する
                                     */
                                    Log()
                                    /*
                                     Received Command for defined in overlayNetwork / blocks.
                                     
                                     Possibility, Receive Command exchangeToken, when peer Node Not Receive Remote Token of The Node yet.
                                     */
                                    let sentDataNodeIp = findIp(socketFd: socketFd)?.ip
                                    Log(sentDataNodeIp as Any)
                                    Log(receivedDataLength as Any)
                                    if let sentDataNodeIp = sentDataNodeIp, sentDataNodeIp != signalingServerAddress.0, receivedDataLength > 0, command != Mode.SignalingCommand.exchangeToken.rawValue {Log()
                                        //tell app range(start index, end index)
                                        callback(sentDataNodeIp, dataRange)
                                    }
                                }
                            }
                        }
                    }
                }
                return returnValue
            }
            
            //MARK: Write Socket
            func writePhase() -> Bool { Log()
                if let writableSocketHandles = catchedSocketHandles(writable_fd_set, peerTypes: self.mode.stack[communicationProcess.phase].peerTypes) {
                    Log("\(mode) w \(self.communicationProcess.phase)")
                    Log("Socket being Writable.")
//                    Log(writableSocketHandles.count)
                    errno = 0
                    if mode.stack[communicationProcess.phase].selects.contains(.send) {
                        Log()
                        if let doCommand = mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .registerMe {
                            //MARK: w registerMe
                            if self.nodePerformances.count >= 10 {
                                self.nodePerformance = self.nodePerformances.last
                                Log(self.nodePerformance)
                                if let nodePerformance = self.nodePerformance {
                                    //#pending
                                    //                            if let doneTime = communicationProcess.doneTime, doneTime.timeIntervalSinceNow < 4 * 60 {   //Not Over 4min since Done the process.
                                    //                                Log(doneTime.timeIntervalSinceNow)
                                    //                                //                                        continue
                                    //                                return false
                                    //                            }
                                    Log()
                                    /*
                                     registerMe
                                     
                                     Send Node Informations{privateaddress, port, nat_type_id, pool_length, pool} to Signaling server.
                                     
                                     data format:
                                     x {private ip} {private port} {nat type id} {address length} {overlayNetworkAddress}null
                                     {private ip} {private port} {node performance} {address length} {overlayNetworkAddress}null
                                     
                                     length:
                                     x {7~15 char variable} {4~5 number variable} {1 number fix} {3 number fix 0fill} {128 char fix}null
                                     {7~15 char variable} {4~5 number variable} {10 number variable} {3 number fix 0fill} {128 char fix}null
                                     
                                     ex.
                                     '192.168.0.34 1402 0 128 8d3a6c0be806ba24b319f088a45504ea7d601970e0f820ca6965eeca1af2d8747d5bdf0ab68a30612004d54b88fe32a654fb7b300568acf8f3e8c6be439c20b9\x00'
                                     */
                                    var sendNodeInformationStatus: Int?
                                    var sendNodeInformation: ContiguousArray<CChar>?
                                    let overlayNetworkAddress = node.dhtAddressAsHexString
                                    if overlayNetworkAddress.isValid {
                                        if let ip = node.ip, let port = node.port {
                                            Log(nodePerformance)
                                            sendNodeInformation = (doCommand.rawValue + " " + ip.toString() + " " + String(port) + " " + nodePerformance.formatted() + " " + String(overlayNetworkAddress.toString.count) + " " + overlayNetworkAddress.toString).utf8CString
                                        }
                                    }
                                    Log(sendNodeInformation ?? "nil")
                                    LogCommunicate("^_^\(sendNodeInformation?.toString as Any)")
                                    guard let writableSocket = writableSocketHandles.first else {
                                        Log("_ _")
                                        return false
                                    }
                                    if let sendNodeInformation = sendNodeInformation {
                                        sendNodeInformationStatus = sendNodeInformation.withUnsafeBytes {
                                            send(writableSocket, $0.baseAddress, $0.count, 0)
                                        }
                                    }
                                    LogCommunicate(sendNodeInformationStatus ?? "nil")
                                    communicationProcess.increment()
                                }
                            }
                        } else if let doCommand = mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .okregisterMe {
                            //MARK: w okregisterMe
                            Log()
                            /*
                             "okregisterMe"
                             */
                            var sendAckStatus: Int?
                            let sendAck = doCommand.rawValue.utf8CString  //null terminated string.
                            Log(sendAck)
                            LogCommunicate(sendAck.toString)
                            guard let writableSocket = writableSocketHandles.first else {
                                Log("_ _")
                                return false
                            }
                            sendAckStatus = sendAck.withUnsafeBytes {
                                send(writableSocket, $0.baseAddress, $0.count, 0)
                            }
                            LogCommunicate(sendAckStatus ?? "nil")
                            communicationProcess.increment()
                        } else if let doCommand = mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .translate {
                            //MARK: w translate
                            Log()
                            /*
                             Send translate {address length} {overlay network address}
                             */
                            node.printSocketQueue()
                            guard let firstJob = node.socketQueues.queues.first else {
                                Log("Not Have to Send Command.")
                                return false
                            }
                            Log(firstJob.token)
                            Log(firstJob)
                            let toOverlayNetworkAddress = firstJob.toOverlayNetworkAddress.toString
                            var sendNodeInformationStatus: Int?
                            var sendNodeInformation: ContiguousArray<CChar>?
                            sendNodeInformation = (doCommand.rawValue + " " + String(toOverlayNetworkAddress.count) + " " + toOverlayNetworkAddress.toString).utf8CString
                            Log(sendNodeInformation ?? "nil")
                            LogCommunicate(sendNodeInformation?.toString as Any)
                            if let sendNodeInformation = sendNodeInformation {
                                guard let writableSocket = writableSocketHandles.first else {
                                    Log("_ _")
                                    return false
                                }
                                sendNodeInformationStatus = sendNodeInformation.withUnsafeBytes {
                                    send(writableSocket, $0.baseAddress, $0.count, 0)
                                }
                            }
                            LogCommunicate(sendNodeInformationStatus ?? "nil")
                            self.claimTranslate = true
                            communicationProcess.increment()
                        } else if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.contains(.exchangeToken), doCommand {
                            let doCommand = Mode.SignalingCommand.exchangeToken
                            //MARK: w exchangeToken
                            Log(doCommand.rawValue)
                            /*
                             Should Shake Hand For Nat Traversable.
                             */
                            var sendHandshake: ContiguousArray<CChar>?
                            if self.remote_token != "_" {
                                Log("have taken remote node token.")
                                sendHandshake = (doCommand.rawValue + " " + my_token + " " + self.remote_token + " " + "ok").utf8CString
                            } else {
                                Log("do not have remote node token yet.")
                                sendHandshake = (doCommand.rawValue + " " + my_token + " " + self.remote_token).utf8CString
                            }
                            Log(sendHandshake ?? "nil")
                            LogCommunicate(sendHandshake?.toString as Any)
                            var sentStatus: Int?
                            let peerType = Mode.PeerType.peerNode
                            self.socketHandles[.peerNode]?.forEach {
                                $0.value.values.forEach {
                                    Log($0.socketFd)
                                    if writableSocketHandles.contains($0.socketFd) {
                                        Log($0.peerAddress)
                                        let writableSocket = $0.socketFd
                                        Log(writableSocket)
                                        if let sendHandshake = sendHandshake {
                                            /*
                                             SO_NOSIGPIPE: NOT generate signal as broken communication pipe (must set the flag on setsockopt().)
                                             */
                                            errno = 0
                                            sentStatus = sendHandshake.withUnsafeBytes {
                                                Log("Will Write Length: \($0.count)")
                                                return send(writableSocket, $0.baseAddress, $0.count, 0)
                                            }
                                            let sendError = errno
                                            LogCommunicate("Wrote Length: \(String(describing: sentStatus))")
                                            LogPosixError()  //57: 未接続  32: broken pipe
                                            if sendError == 32 {
                                                Log("Broken Pipe - 送信もしくは受信が閉じられている")
                                            }
                                            if let sentStatus = sentStatus, sentStatus >= 0 {
                                                Log("[c]Sent Data Successfully.")
                                                let (findipResult, addressSpace, overlayNetworkAddress) = self.findIpAndAddressSpace(socketFd: writableSocket)
                                                if let overlayNetworkAddress = overlayNetworkAddress?.toString {
                                                    Log("\(writableSocket): \(findipResult as Any)")
                                                    if let findipResult = findipResult, let addressSpace = addressSpace { LogEssential("[c]Connection Successfull. \(findipResult)")
                                                        self.socketHandles[peerType]?[overlayNetworkAddress]?[addressSpace]?.connected = true
                                                        self.inTransitionSignalingToHandshake = writableSocket
//                                                        self.passedGracePeriod = 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if self.mode == .dequeueJob {
                            //MARK: w dequeueJob
                            Log()
                            node.printSocketQueueEssential()
                            guard let firstJob = node.socketQueues.queues.first else {
                                Log("Not Have Command to Send.")
                                return false
                            }
                            LogEssential("\(firstJob.command) \(firstJob.operand)")
                            /*
                             overlayNetworkAddress →ip address pair への翻訳が済んでいたら
                             ↓
                             相互に送信してシェイクハンドする（shouldShakeHandForNatTraversable
                             ↓
                             firstJobのコマンドを送信（Send Command）
                             ↓
                             firstJob, peerAddressPairs をnilクリアする
                             */
                            var commandInstance: CommandProtocol = firstJob.command
                            if firstJob.command.rawValue == "", let command = node.premiumCommand {
                                Log()
                                /*
                                 Won't be Use this.
                                 
                                 if Nothing in overlayNetwork Command,
                                 Use Appendix Premium Command.
                                 */
                                commandInstance = node.premiumCommand?.command(command.rawValue) ?? command
                                commandInstance = command
                            }
                            LogEssential("from \(node.dhtAddressAsHexString) to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
                            if firstJob.type == .local || firstJob.toOverlayNetworkAddress.equal(node.dhtAddressAsHexString) {
                                Log("Local Job")
                                let _ = node.socketQueues.deQueue(toOverlayNetworkAddress: firstJob.toOverlayNetworkAddress, token: firstJob.token)
                                Log("Send Command to oneself.")
                                let sentDataNodeIp = node.getIp
                                Log(sentDataNodeIp as Any)
                                
                                /*
                                 fetching commnad+operand+token from job in queue.
                                 
                                 Save cString ([CChar]) to UnsafeMutableRawBufferPointer's Pointee
                                 */
                                if let jobData = (commandInstance.rawValue + " " + firstJob.operand + " " + firstJob.token).toCChar {
                                    Log("\(jobData) to local")
                                    jobData.withUnsafeBytes {
                                        rawBufferPointer.copyMemory(from: $0)
                                    }
                                    let receivedDataLength = jobData.count
                                    Log(receivedDataLength as Any)
                                    if let sentDataNodeIp = sentDataNodeIp, receivedDataLength > 0 {
                                        Log()
//                                        callback(sentDataNodeIp, receivedDataLength)
                                        let startRange = 0
                                        let dataRange = startRange..<(startRange + receivedDataLength)
                                        callback(sentDataNodeIp, dataRange)
                                    }
                                }
                            } else {
                                Log("Remote Job")
                                /*
                                 Job#toOverlayNetworkAddress
                                 がtranslate済みかチェックする
                                 ↓
                                 まだだったら
                                 ↓
                                 signaling
                                 ↓
                                 translate
                                 ↓
                                 handshake する
                                 */
                                Log(firstJob.toOverlayNetworkAddress)
                                Log(self.socketHandles)
                                if let (writableSocket, connected) = didTranslate(firstJob.toOverlayNetworkAddress) {
                                    LogEssential("Translated - the OverlayNetworkAddress \(firstJob.toOverlayNetworkAddress) was entered to {socketHaneles}.")
                                    if let writableSocket = writableSocket, writableSocket > 0, connected {
                                        Log("\(firstJob.toOverlayNetworkAddress) Have translated & connected to \(writableSocket).")
                                        LogEssential("Will Send Command to Other Node. \(writableSocket)")
                                        var sentStatus: Int?
                                        var sendDataAsCChar: ContiguousArray<CChar>?
                                        let (transData, dataCount) = combineData(command: commandInstance, data: firstJob.operand, token: firstJob.token)
                                        sendDataAsCChar = transData.utf8String?.utf8CString
                                        //Log("\(sendDataAsCChar?.toString as Any) to findipResult as Any")
                                        if let sendDataAsCChar = sendDataAsCChar {
                                            Log(writableSocketHandles)
                                            if !writableSocketHandles.contains(writableSocket) {
                                                Log("The Destination overlayNetworkAddress No There in Writable Sockets (writableSocketHandles).")
                                                return false
                                            }
                                            Log(writableSocket)
                                            LogEssential("Dequeue \(firstJob.command.rawValue) in socketQueues")
                                            let _ = node.socketQueues.deQueue(toOverlayNetworkAddress: firstJob.toOverlayNetworkAddress, token: firstJob.token)
                                            /*
                                             SO_NOSIGPIPE: NOT generate signal as broken communication pipe (must set the flag on setsockopt().)
                                             */
                                            let (findipResult, addressSpace, _) = self.findIpAndAddressSpace(socketFd: writableSocket)
                                            LogCommunicate("\(sendDataAsCChar.toString as Any) to \(findipResult as Any)")
                                            //TCP_NODELAY: don't delay send to coalesce packets
                                            sentStatus = sendDataAsCChar.withUnsafeBytes {
                                                send(writableSocket, $0.baseAddress, $0.count, 0)
                                            }
                                            LogPosixError()
                                        }
                                        LogCommunicate(sentStatus ?? "nil")
                                    }
                                } else {
                                    LogEssential("----------- Did NOT Translate cause Go to signaling mode for Ask Addresses to Signaling Server. -----------")
                                    Log(firstJob.toOverlayNetworkAddress)
                                    Log(firstJob)
                                    /*
                                     dequeueJob
                                     ↓
                                     signaling (send translate & receive translateAck to signaling server.)
                                     ↓
                                     handshake (send & receive exchangeToken to A peer node.)
                                     ↓
                                     dequeueJob (send & receive data to any peer nodes.)
                                     */
                                    self.mode = .signaling
                                    communicationProcess.nextMode()
                                    return true
                                }
                            }//if remote
                        }
                    }
                }
                return false
            }
        }
    }
    
    /*
     MARK: - Switch Omit/Emit Log
     Caution:
     TCP Hole Punching should be on Critical Timing in NAT Traversal in Scoket.
     Cause must Omit Log() Dump().
     */
    private func Log(_ object: Any = "", functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        #if false
        let className = (fileName as NSString).lastPathComponent
        /*
         Disable Logging in following Classes.
         */
    //    if className == "Node.swift" || className == "Command.swift" {
    //    } else {
    //        return
    //    }
    //    if className == "Socket.swift" {
    //        return
    //    }
        if className == "Data+.swift" {
            return
        }
        if className == "Queue.swift" {
            return
        }
        if className == "Time.swift" {
            return
        }
        let formatter = DateFormatter()
        //    formatter.dateFormat = "HH:mm:ss"
        formatter.dateFormat = "HH:mm:ss.SSSS"
        let dateString = formatter.string(from: Date())
        print("\(dateString) \(className) \(functionName) l.\(lineNumber) \(object)\n")
        #endif
    }
    private func LogPosixError(functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        #if false
        let className = (fileName as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("\(dateString) \(className) \(functionName) l.\(lineNumber) \(errno) \(errno == 0 ? "No errors" : String(cString: strerror(errno)))\n")
        #endif
        errno = 0   //clear error number
    }
    private func LogPosixErrorEssential(description: String = "", functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        #if false
        let className = (fileName as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("\(dateString) \(className) \(functionName) l.\(lineNumber) \(errno) \(errno == 0 ? "No errors" : String(cString: strerror(errno))) \(description)\n")
        #endif
        errno = 0   //clear error number
    }
    private func LogEssential(_ object: Any = "", functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        #if true
        let className = (fileName as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("\(dateString) \(className) \(functionName) l.\(lineNumber) \(object) ***\n")
        #endif
    }

    private func LogCommunicate(_ object: Any = "", functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        #if true
        let className = (fileName as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("\(dateString) \(className) \(functionName) l.\(lineNumber) \(object) ***\n")
        #endif
    }

    private func Dump(_ object: Any = "", functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        #if false
        let className = (fileName as NSString).lastPathComponent
        /*
         Disable Logging in following Classes.
         */
    //    if className == "Node.swift" || className == "Command.swift" {
    //    } else {
    //        return
    //    }
    //    if className == "Socket.swift" {
    //        return
    //    }
        if className == "Data+.swift" {
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("\(dateString) \(className) \(functionName) l.\(lineNumber)\n")
        //    print((object as! Data).count)
        if object is Data {
            dump((object as! NSData))
        } else {
            dump(object)
        }
        #endif
    }

    private func DumpEssential(_ object: Any = "", functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
        #if false
        let className = (fileName as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateString = formatter.string(from: Date())
        print("DE \(dateString) \(className) \(functionName) l.\(lineNumber)\n")
        //    print((object as! Data).count)
        if object is Data {
            dump((object as! NSData))
        } else {
            dump(object)
        }
        #endif
    }

}
