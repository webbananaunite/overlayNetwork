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
    }
    
    /*
     return:
        [Send / Receive], Next Mode, [Do Command]
     */
    public var stack:[(selects: [Select], nextMode: Mode?, doCommands: [SignalingCommand]?, peerType: PeerType)] {
        switch self {
        case .registerMeAndIdling:
            return [
                ([.send], nil, [.registerMe], .signalingServer),
                ([.receive], nil, [.okyours], .signalingServer),
                ([.send], nil, [.okregisterMe], .signalingServer),
                ([.receive], .signaling, [.registerMeAck], .signalingServer),

                ([.receive], .handshake, [.translateAck], .signalingServer)    //be Idle
            ]
            
        case .signaling:
            return [
                ([.send], nil, [.translate], .signalingServer),
                ([.receive], .handshake, [.translateAck], .signalingServer)
            ]
            
        case .handshake:
            return [
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode),
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode),
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode),
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode),
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode),
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode),
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode),
                ([.send, .receive], .dequeueJob, [.exchangeToken], .peerNode)
            ]
            
        case .dequeueJob:
            return [
                ([.send, .receive], nil, nil, .peerNode)
            ]
        }
    }
}

open class Socket {
    public static let MTU = 65536
    var peerAddressPairs: (public: (ip: String, port: Int)?, private: (ip: String, port: Int)?)?
    var mode: Mode
    public enum AddressSpace {
        case `public`
        case `private`
    }
    var socketHandles: [Mode.PeerType: [(addressSpace: Socket.AddressSpace, socketFd: Int32, connected: Bool, connectionTimeOutOccurred: Bool)?]]
    var remote_knows_our_token = false
    var communicationProcess = processPhase()

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
        self.socketHandles = [Mode.PeerType: [(addressSpace: Socket.AddressSpace, socketFd: Int32, connected: Bool, connectionTimeOutOccurred: Bool)?]]()
    }
    
    /*
     Deploy BSD Socket and Connect to Peer Node / Signaling Server.
     
     Socket Setting
     ↓
     (bind)
     ↓
     connect
     */
    public func deploySocketForConnect(to destination: (ip: String, port: Int), source privateAddress: (ip: String, port: Int)?) -> (socketHandle: Int32, sourceAddress: (ip: String, port: Int), Bool) {
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
        let sockhandle = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)
        Log(sockhandle)
        
        /*
         Append Option for Reusable socket
         */
        var reuseaddrValue = 1
        setsockopt(sockhandle, SOL_SOCKET, SO_REUSEADDR, &reuseaddrValue, socklen_t(MemoryLayout.stride(ofValue: reuseaddrValue)))
        var reuseportValue = 1
        setsockopt(sockhandle, SOL_SOCKET, SO_REUSEPORT, &reuseportValue, socklen_t(MemoryLayout.stride(ofValue: reuseportValue)))
        var useLoopbackValue = 1
        setsockopt(sockhandle, SOL_SOCKET, SO_USELOOPBACK, &useLoopbackValue, socklen_t(MemoryLayout.stride(ofValue: useLoopbackValue)))
        var debugValue = 1
        setsockopt(sockhandle, SOL_SOCKET, SO_DEBUG, &debugValue, socklen_t(MemoryLayout.stride(ofValue: debugValue)))

        /*
         Take The Socket Address and Port information for Reuse.
         */
        var retSourceAddress: (ip: String, port: Int)
        var connectionSucceeded: Bool
        if let privateAddress = privateAddress {
            /*
             Communicate with Peer Node.
             (Socket Create by After Second time)
             */
            var localaddress = sockaddr_in()
            inet_pton(PF_INET,
                      privateAddress.ip.cString(using: .utf8),
                      &localaddress.sin_addr)
            localaddress.sin_port = UInt16(privateAddress.port).bigEndian
            localaddress.sin_family = sa_family_t(AF_INET)

            var socketAddress = localaddress
            let bindStatus = withUnsafeMutablePointer(to: &socketAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sockhandle, $0, socklen_t(MemoryLayout.size(ofValue: localaddress)))
                }
            }
            Log("try bind on: \(privateAddress)")
            Log(bindStatus)
            Log(errno)
//            Log("from: \(String(describing: privateAddress)) to: \(destination)")
            retSourceAddress = privateAddress
            
            /*
             Set timeout 5s
             */
            var timeOutValue = timeval()
            timeOutValue.tv_sec = 5
            timeOutValue.tv_usec = 0 //Unit: μs 1/1000000.0s
            setsockopt(sockhandle, SOL_SOCKET, SO_SNDTIMEO, &timeOutValue, socklen_t(MemoryLayout.stride(ofValue: timeOutValue)))
            setsockopt(sockhandle, SOL_SOCKET, SO_RCVTIMEO, &timeOutValue, socklen_t(MemoryLayout.stride(ofValue: timeOutValue)))
            /*
             Set blocking false
             */
            //let nonBlockStatus = fcntl(sockhandle, F_SETFL, O_NONBLOCK);    //no delay
            let socketStatusFlags = fcntl(sockhandle, F_GETFL)
            let nonBlockStatus = fcntl(sockhandle, F_SETFL, socketStatusFlags | O_NONBLOCK)
            LogEssential(nonBlockStatus)
            LogEssential(errno)
            if (nonBlockStatus < 0) {
                LogEssential("Could not change socket to non-blocking ( \(String(cString: strerror(errno)!)) (\(errno)).")
            }

            /*
             Connect Remote address with Transform sockaddr_in POSIX structure to sockaddr POSIX structure
             */
            var socketAddressRemote = remoteaddress
            let connectStatus = withUnsafeMutablePointer(to: &socketAddressRemote) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sockhandle, $0, socklen_t(MemoryLayout.stride(ofValue: remoteaddress)))
                }
            }
            LogEssential("try connect to: \(destination)")
            LogEssential(connectStatus)
            if connectStatus == 0 || (connectStatus == -1 && errno == 56) {
                connectionSucceeded = true
            } else {
                connectionSucceeded = false
            }
            LogEssential(errno)
            /*
             errno on connect()
             22: socket connect failed as bad setting   
             36: 処理開始(ノンブロッキング設定で、かつ接続がすぐに完了しない)
             56: 接続済みソケット指定
             60: timeout for 75s
             61: connection failed as refused by peer
             */
//            Log("from: \(String(describing: privateAddress)) to: \(destination)")
        } else {
            /*
             Communicate with Signaling Server.
             (Socket Create by First time)
             */
            /*
             Connect Remote address with Transform sockaddr_in POSIX structure to sockaddr POSIX structure
             */
            var socketAddress = remoteaddress
            let connectStatus = withUnsafeMutablePointer(to: &socketAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sockhandle, $0, socklen_t(MemoryLayout.size(ofValue: remoteaddress)))
                }
            }
            Log("try connect to: \(destination)")
            Log(connectStatus)
            if connectStatus == 0 || (connectStatus == -1 && errno == 56) {
                connectionSucceeded = true
            } else {
                connectionSucceeded = false
            }
            Log(errno)
            Log("from: \(String(describing: privateAddress)) to: \(destination)")

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
            Log(getsocknameStatus)
            
            var sourceIpAddress = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            inet_ntop(
                AF_INET,
                &ownPrivateAddress.sin_addr,
                &sourceIpAddress,
                socklen_t(INET_ADDRSTRLEN))
            let port: UInt16 = ownPrivateAddress.sin_port
            Log("socket: \(sockhandle) ip: \(String(cString: sourceIpAddress)) port: \(Int(port))")
            retSourceAddress = (ip: String(cString: sourceIpAddress), port: Int(port))
        }
        Log("socket: \(sockhandle) ip: \(retSourceAddress.ip) port: \(retSourceAddress.port)")
        return (socketHandle: sockhandle, sourceAddress: retSourceAddress, connectionSucceeded)
    }
    
    private struct SocketReferredOverlayNetworkAddress {
        let socketFd: Int32
        let overlayNetworkAddress: OverlayNetworkAddressAsHexString?
        let ipAndPort: (ip: String, port: Int)
        let addressSpaceType: AddressSpace
        let peerType: Mode.PeerType
        
        init(socketFd: Int32, overlayNetworkAddress: OverlayNetworkAddressAsHexString?, ipAndPort: (ip: String, port: Int), addressSpaceType: AddressSpace, peerType: Mode.PeerType) {
            self.socketFd = socketFd
            self.overlayNetworkAddress = overlayNetworkAddress
            self.ipAndPort = ipAndPort
            self.addressSpaceType = addressSpaceType
            self.peerType = peerType
        }
    }
    private var socketReferences = [SocketReferredOverlayNetworkAddress]()
    public func addSocketReferences(socketFd: Int32, overlayNetworkAddress: OverlayNetworkAddressAsHexString?, ipAndPort: (ip: String, port: Int), addressSpaceType: AddressSpace, peerType: Mode.PeerType) {
        self.socketReferences.append(SocketReferredOverlayNetworkAddress(socketFd: socketFd, overlayNetworkAddress: overlayNetworkAddress, ipAndPort: ipAndPort, addressSpaceType: addressSpaceType, peerType: peerType))
    }
    public func findOverlayNetworkAddress(ip: String, node: Node) -> String? {
        LogEssential(ip)
        if ip == node.getIp {
            return node.dhtAddressAsHexString.toString
        }
        return socketReferences.filter {
            $0.ipAndPort.ip == ip
        }.first?.overlayNetworkAddress?.toString
    }
    public func findIp(socketFd: Int32) -> String? {
        Log(socketFd)
        return socketReferences.filter {
            $0.socketFd == socketFd
        }.first?.ipAndPort.ip
    }

    // get client IP
    private func clientAddress(_ clientFD: Int32) -> String? {
        var addr = sockaddr(), len: socklen_t = socklen_t(SOCK_MAXADDRLEN)
        guard getpeername(clientFD, &addr, &len) == 0 else {
            Log("getpeername() failed.")
            return nil
        }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(&addr, len, &hostBuffer, socklen_t(hostBuffer.count),
                          nil, 0, NI_NUMERICHOST) == 0 else {
            Log("getnameinfo() failed.")
            return nil
        }
        Log(String(cString: hostBuffer))
        return String(cString: hostBuffer)
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
        Log(regulatedData.utf8String)
        return (regulatedData, dataCount)
    }

    /*
     Communicate with POSIX BSD Sockets.
     
     At First, Register own's overlayNetworkAddress to Signaling Server.
     then Determine Communicaton Port in overlayNetwork.
     */
    public func start(startMode: Mode, tls: Bool, rawBufferPointer: UnsafeMutableRawBufferPointer, node: Node, peerSocketHandles: [Mode.PeerType: [(addressSpace: Socket.AddressSpace, socketFd: Int32, connected: Bool, connectionTimeOutOccurred: Bool)?]], inThread: Bool, callback: @escaping (String?, Int) -> Void) {
        Log(startMode)
        self.mode = startMode
        self.socketHandles = peerSocketHandles
        
        if inThread {
            Log()
            DispatchQueue.global().async {
                communication()
            }
        } else {
            Log()
            communication()
        }
        func communication() {
            Log()
            guard let signalingServerAddress = node.signalingServerAddress else {
                LogEssential("Could Not Take Signaling Server Address.")
                return
            }
            if let signalingServerAddress = node.signalingServerAddress, let ip = node.ip, let port = node.port {
                let ownNodePrivateAddress = (ip: ip.toString(), port: port)
                
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
                guard let peerType = self.mode.stack.first?.peerType else {
                    Log()
                    return
                }
                Log(peerType)
                Log(socketHandles[peerType]?.count as Any)
                self.socketHandles[peerType]?.forEach {
                    if let socketHandleDescription = $0, !socketHandleDescription.connectionTimeOutOccurred {
                        let socketHandle = socketHandleDescription.socketFd
                        __darwin_fd_set(socketHandle, &active_fd_set)
                    }
                }

                func catchedSocketHandles(_ fd_set: fd_set, peerType: Mode.PeerType) -> [Int32]? {
                    Log(self.mode)
                    Log(peerType)
                    var array = [Int32]()
                    var catchedSocketHandles = fd_set
                    Log(self.socketHandles[peerType]?.count as Any)
                    self.socketHandles[peerType]?.forEach {
                        if let socketHandle = $0?.1 {
                            if __darwin_fd_isset(socketHandle, &catchedSocketHandles) != 0 {
                                array.append(socketHandle)
                            }
                        }
                    }
                    if array.isEmpty {
                        Log()
                        return nil
                    }
                    Log(array.count)
                    return array
                }
                func rearrangeFdSet(peerType: Mode.PeerType, active_fd_set: inout fd_set, readable_fd_set: inout fd_set, writable_fd_set: inout fd_set, exception_fd_set: inout fd_set) {
                    Log(peerType)
                    active_fd_set = fd_set()
                    self.socketHandles[peerType]?.forEach {
                        Log()
                        if let socketHandleDescription = $0, !socketHandleDescription.connectionTimeOutOccurred {
                            let socketHandle = socketHandleDescription.socketFd
                            __darwin_fd_set(socketHandle, &active_fd_set)
                        }
                    }
                    Log(active_fd_set)
                    readable_fd_set = active_fd_set
                    writable_fd_set = active_fd_set
                    exception_fd_set = active_fd_set
                    Log(readable_fd_set)
                    Log(writable_fd_set)
                }
                func isConnected(socketHandles: [(addressSpace: Socket.AddressSpace, socketFd: Int32, connected: Bool, connectionTimeOutOccurred: Bool)?]) -> Bool {
                    let connectedSockets = socketHandles.filter {
                        if let socketHandle = $0, socketHandle.connected == true {
                            return true
                        }
                        return false
                    }
                    return connectedSockets.count > 0
                }
                let my_token = Dht.hash(string: node.dhtAddressAsHexString.toString)?.0 ?? "token"
                Log("my_token =\(my_token)")
                var remote_token = "_"
                
                //Move cause Memory Leak issue.
                var sentStatus: Int?
                var sendHandshake: ContiguousArray<CChar>?
                var readable_fd_set = active_fd_set
                var writable_fd_set = active_fd_set
                var exception_fd_set = active_fd_set
                /*
                 timeout 0.0s is indicate pooling.
                 */
                var timeout: timeval = timeval(tv_sec: 0, tv_usec: 0)

                while true {
                    Log(self.mode)
                    /*
                     Connect Remote address with Transform sockaddr_in POSIX structure to sockaddr POSIX structure
                     */
                    if let peerType = self.mode.stack.first?.peerType, peerType == .peerNode, let peerAddressPairs = self.peerAddressPairs, let socketHandles = self.socketHandles[peerType], !isConnected(socketHandles: socketHandles) {
                        Log()
                        for addressElement in [peerAddressPairs.private, peerAddressPairs.public].enumerated() {
                            let address = addressElement.element
                            let index = addressElement.offset
                            Log(index)
                            Log(address as Any)
                            if let destination = address {
                                var remoteaddress = sockaddr_in()
                                inet_pton(PF_INET,
                                          destination.ip.cString(using: .utf8),
                                          &remoteaddress.sin_addr)
                                remoteaddress.sin_port = UInt16(destination.port).bigEndian
                                remoteaddress.sin_family = sa_family_t(AF_INET)
                                var socketAddressRemote = remoteaddress
                                
                                let socketHandles = socketHandles.filter {
                                    $0?.0 == (index == 0 ? .private : .public)
                                }
                                if let socket = socketHandles.first, let sockhandle = socket?.1 {
                                    Log()
                                    let connectStatus = withUnsafeMutablePointer(to: &socketAddressRemote) {
                                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                                            //                    connect(sockhandle, $0, socklen_t(MemoryLayout.size(ofValue: remoteaddress)))
                                            connect(sockhandle, $0, socklen_t(MemoryLayout.stride(ofValue: remoteaddress)))
                                        }
                                    }
                                    Log("try connect to: \(destination)")
                                    Log(connectStatus)
                                    Log(errno)
                                    /*
                                     errno on connect()
                                     22: connection failed
                                     36: start do connection as Non-Blockinng Mode
                                     56: connected already (status == -1)
                                     60: timeout for 75 seconds
                                     61: connection failed as refused by peer
                                     */
                                    let addressSpace: [AddressSpace] = [.private, .public]
                                    
                                    //debug
                                    let _ = self.socketHandles[Mode.PeerType.peerNode].map {
                                        Log($0)
                                        return true
                                    }
                                    //update connect status
                                    if let socketHandlesCount = self.socketHandles[.peerNode]?.count, socketHandlesCount > 0 {
                                        Log(socketHandlesCount)
                                        for i in 0...(socketHandlesCount - 1) {
                                            Log(i)
                                            if self.socketHandles[.peerNode]?[i]?.0 == (index == 0 ? .private : .public) {
                                                self.socketHandles[.peerNode]?[i]?.2 = connectStatus == 0 ? true : false
                                                self.socketHandles[.peerNode]?[i]?.2 = connectStatus == -1 && errno == 56 ? true : false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    /*
                     selectsocket()により対象のソケットの受信可能/不可と送信可能/ 不可を検査することでコネクションの試みの終了を確認することができます。
                     コネクションの確立が成功したかどうかは、ソケットオプションSO_ERRORによりソケットのエラーを 調べることで確認できます。ソケットのエラーが正常終了を示している(errno=0)ならコネクションの確 立に成功しています。
                     */
                    LogEssential(self.mode.stack[communicationProcess.phase].peerType)
                    self.socketHandles[self.mode.stack[communicationProcess.phase].peerType]?.enumerated().forEach {
                        if let socketHandle = $0.element?.socketFd {
                            LogEssential(socketHandle)
                            let ip = self.findIp(socketFd: socketHandle)
                            LogEssential(ip as Any)
                            var errorValue: Int = 100
                            var errorValueLength: socklen_t = 200
                            let succeeded = getsockopt(socketHandle, SOL_SOCKET, SO_ERROR, &errorValue, &errorValueLength)  //SOL_SOCKET, IPPROTO_IP
                            LogEssential("\(succeeded) \(errorValue)")
                            if errorValue == 60 {
                                LogEssential()
                                /*
                                 Connection TimeOut Occurred
                                 */
                                let index = $0.offset
                                self.socketHandles[self.mode.stack[communicationProcess.phase].peerType]?[index]?.connectionTimeOutOccurred = true
                            }
                        }
                    }
                    rearrangeFdSet(peerType: self.mode.stack[communicationProcess.phase].peerType, active_fd_set: &active_fd_set, readable_fd_set: &readable_fd_set, writable_fd_set: &writable_fd_set, exception_fd_set: &exception_fd_set)

                    Log(active_fd_set)
                    Log(readable_fd_set)
                    Log(writable_fd_set)
                    readable_fd_set = active_fd_set
                    writable_fd_set = active_fd_set
                    exception_fd_set = active_fd_set
                    /*
                     select return:
                         -1: error occurred
                         0: timeout occurred
                         1: writable
                         2: readable
                         3: read/write
                         4: write/read
                     */
                    Log(readable_fd_set)
                    Log(writable_fd_set)
                    let status = select(Int32(1024), &readable_fd_set, &writable_fd_set, &exception_fd_set, &timeout)
                    LogEssential(status) //1: writable, 2: readable, 3: read/write, 4: read/write
                    LogEssential(errno)
                    LogEssential("\(mode) \(self.communicationProcess.phase) \(self.mode.stack[communicationProcess.phase].peerType)")
                    self.socketHandles[self.mode.stack[communicationProcess.phase].peerType]?.forEach {
                        if let socketHandle = $0?.1 {
                            LogEssential(socketHandle)
                            let ip = self.findIp(socketFd: socketHandle)
                            LogEssential(ip as Any)
                            var errorValue: Int = 100
                            var errorValueLength: socklen_t = 200
                            //get the socket inner variable named so_error.
                            let succeeded = getsockopt(socketHandle, SOL_SOCKET, SO_ERROR, &errorValue, &errorValueLength)
                            LogEssential("\(succeeded) \(errorValue)")
                        }
                    }
                    //MARK: Exception Socket
                    if let exceptionSocketHandles = catchedSocketHandles(exception_fd_set, peerType: self.mode.stack[communicationProcess.phase].peerType) {
                        LogEssential("\(self.mode) e \(self.communicationProcess.phase)")
                        Log("Socket Occurred Exception.")
                        Log(exceptionSocketHandles.first)
                    }
                    //MARK: Read Socket
                    if let readableSocketHandles = catchedSocketHandles(readable_fd_set, peerType: self.mode.stack[communicationProcess.phase].peerType) {
                        LogEssential("\(self.mode) r \(self.communicationProcess.phase)")
                        Log("Socket Have Read Data as Readable.")
                        /*
                         Receive Data (Command & Operands)
                         */
                        Log(rawBufferPointer.count)
                        let receivedDataLength: Int? = recv(readableSocketHandles[0], rawBufferPointer.baseAddress, rawBufferPointer.count, 0)
                        Log(receivedDataLength as Any)
                        if let receivedDataLength = receivedDataLength, receivedDataLength <= 0 {   //when status: 4
                            Log()
                            continue
                        }
                        Log(rawBufferPointer.toString(byteLength: receivedDataLength ?? 0))
                        let receivedDataAsString = rawBufferPointer.toString(byteLength: receivedDataLength ?? 0)
                        Log(receivedDataAsString)
                        let receivedCommandOperand = receivedDataAsString.components(separatedBy: " ")
                        Log(receivedCommandOperand)
                        let command = receivedCommandOperand[0]
                        if self.mode.stack[communicationProcess.phase].selects.contains(.receive) {
                            Log()
                            if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .okyours {
                                if command == doCommand.rawValue {
                                    //MARK: r okyours
                                    Log()
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
                                    if let firstJob = node.socketQueues.firstQueueTypeLocal() {
                                        Log("Have Command to Local Execution to First.")
                                        let _ = node.socketQueues.deQueue()
                                        Log(firstJob.token)
                                        Log(firstJob)
                                        Log(peerAddressPairs as Any)
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
                                        LogCommunicate("to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
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
                                                    callback(sentDataNodeIp, receivedDataLength)
                                                }
                                            }
                                        }
                                    } else {
                                        Log("Not Have Command to Local Execution to First.")
                                        if let job = node.socketQueues.queues.first {
                                            Log("Have Command to Send Remote Node cause goto Next Mode.")
                                            /*
                                             Go to Next Process.
                                             */
                                            Log(job.token)
                                            Log(job)
                                            if let nextMode = self.mode.stack[communicationProcess.phase].nextMode, let peerType = nextMode.stack.first?.peerType {
                                                Log()
                                                self.mode = nextMode
                                                communicationProcess.updateDoneTime()
                                                communicationProcess.nextMode()
                                            }
                                        } else {
                                            Log("Empty Queue cause do once more registerMe.")
                                            communicationProcess.idling()
                                        }
                                    }
                                }
                            } else if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .translateAck {
                                if command == doCommand.rawValue {
                                    //MARK: r translateAck
                                    /*
                                     Received Command for defined in Signaling.
                                     
                                     自node と peer 双方に接続要求を知らせてきた
                                     ["ack", "153.243.66.142", "1040", "192.168.0.34", "54512", "", "", "", "", "", "", "",...
                                     */
                                    var publicIp: String? = receivedCommandOperand[1]
                                    var privateIp: String? = receivedCommandOperand[3]
                                    Log(receivedCommandOperand[2])
                                    Log(receivedCommandOperand[4])
                                    Log(Int(receivedCommandOperand[2]) as Any)
                                    Log(Int(receivedCommandOperand[4]) as Any)
                                    let overlayNetworkAddress = receivedCommandOperand[5]
                                    if let publicPort = Int(receivedCommandOperand[2]), let privatePort = Int(receivedCommandOperand[4]) {
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
                                        self.peerAddressPairs = (public: publicAddress, private: privateAddress)
                                    }
                                    Log(self.peerAddressPairs as Any)
                                    var ownNodePrivateAddress: (ip: String, port: Int)? = (ip: ip.toString(), port: port)
                                    /*
                                     Go to Next Process.
                                     */
                                    if let nextMode = self.mode.stack[communicationProcess.phase].nextMode, let peerType = nextMode.stack.first?.peerType {
                                        Log()
                                        self.mode = nextMode
                                        communicationProcess.nextMode()
                                        self.remote_knows_our_token = false

                                        socketHandles[peerType] = [(addressSpace: Socket.AddressSpace, socketFd: Int32, connected: Bool, connectionTimeOutOccurred: Bool)?]()
                                        Log(socketHandles[peerType]?.count as Any)
                                        //#test #debug
                                        for address in [self.peerAddressPairs?.private, self.peerAddressPairs?.public].enumerated() {
//                                        for address in [self.peerAddressPairs?.private].enumerated() {
                                            let index = address.offset
                                            Log(address.element as Any)
                                            if let address = address.element {
                                                let addressSpaceType = index == 0 ? AddressSpace.private : AddressSpace.public
                                                let (socketHandle, sourceAddress, connectionSucceeded) = deploySocketForConnect(to: address, source: ownNodePrivateAddress)
                                                socketHandles[peerType]?.append((addressSpaceType, socketHandle, connectionSucceeded, false))
                                                addSocketReferences(socketFd: socketHandle, overlayNetworkAddress: overlayNetworkAddress, ipAndPort: address, addressSpaceType: addressSpaceType, peerType: .signalingServer)
                                            }
                                        }
                                        Log(socketHandles[peerType]?.count as Any)
                                        /*
                                         re-arrange fd_set for select().
                                         */
                                        rearrangeFdSet(peerType: peerType, active_fd_set: &active_fd_set, readable_fd_set: &readable_fd_set, writable_fd_set: &writable_fd_set, exception_fd_set: &exception_fd_set)
                                    }
                                }
                            } else if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .exchangeToken {
                                if command == doCommand.rawValue {
                                    //MARK: r exchangeToken
                                    Log()
                                    if remote_token == "_" {
                                        remote_token = receivedCommandOperand[1]
                                        Log("remote_token is now \(remote_token)")
                                    }
                                    if receivedCommandOperand.count == 4 {
                                        Log("remote end signals it knows our token")
                                        self.remote_knows_our_token = true
                                    }
                                }
                            } else if self.mode == .dequeueJob {
                                //MARK: r dequeueJob
                                LogCommunicate()
                                /*
                                 Received Command for defined in overlayNetwork / blocks.
                                 
                                 Possibility, Receive Command exchangeToken, when peer Node Not Receive Remote Token of The Node yet.
                                 */
                                Log()
                                let sentDataNodeIp = clientAddress(readableSocketHandles[0])
                                LogCommunicate(sentDataNodeIp as Any)
                                Log(receivedDataLength as Any)
                                if let sentDataNodeIp = sentDataNodeIp, let receivedDataLength = receivedDataLength, receivedDataLength > 0, command != Mode.SignalingCommand.exchangeToken.rawValue {
                                    callback(sentDataNodeIp, receivedDataLength)
                                }
                            }
                        }
                    }

                    //MARK: Write Socket
                    if let writableSocketHandles = catchedSocketHandles(writable_fd_set, peerType: self.mode.stack[communicationProcess.phase].peerType) {
                        LogEssential("\(mode) w \(self.communicationProcess.phase)")
                        Log("Socket being Writable.")
                        if mode.stack[communicationProcess.phase].selects.contains(.send) {
                            Log()
                            if let doCommand = mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .registerMe {
                                //MARK: w registerMe
                                if let doneTime = communicationProcess.doneTime, doneTime.timeIntervalSinceNow < 4 * 60 {   //Not Over 4min since Done the process.
                                    Log(doneTime.timeIntervalSinceNow)
                                    continue
                                }
                                Log()
                                /*
                                 registerMe
                                 
                                 Send Node Informations{privateaddress, port, nat_type_id, pool_length, pool} to Signaling server.
                                 
                                 data format:
                                 {private ip} {private port} {nat type id} {address length} {overlayNetworkAddress}null
                                 
                                 length:
                                 {7~15 char variable} {4~5 number variable} {1 number fix} {3 number fix 0fill} {128 char fix}null
                                 
                                 ex.
                                 '192.168.0.34 1402 0 128 8d3a6c0be806ba24b319f088a45504ea7d601970e0f820ca6965eeca1af2d8747d5bdf0ab68a30612004d54b88fe32a654fb7b300568acf8f3e8c6be439c20b9\x00'
                                 */
                                var sendNodeInformationStatus: Int?
                                var sendNodeInformation: ContiguousArray<CChar>?
                                let overlayNetworkAddress = node.dhtAddressAsHexString
                                if overlayNetworkAddress.isValid {
                                    if let ip = node.ip, let port = node.port {
                                        sendNodeInformation = (doCommand.rawValue + " " + ip.toString() + " " + String(port) + " " + "0" + " " + String(overlayNetworkAddress.toString.count) + " " + overlayNetworkAddress.toString).utf8CString
                                    }
                                }
                                Log(sendNodeInformation ?? "nil")
                                Log(sendNodeInformation?.toString as Any)
                                if let sendNodeInformation = sendNodeInformation {
                                    sendNodeInformationStatus = sendNodeInformation.withUnsafeBytes {
                                        send(writableSocketHandles[0], $0.baseAddress, $0.count, 0)
                                    }
                                }
                                Log(sendNodeInformationStatus ?? "nil")
                                communicationProcess.increment()
                            } else if let doCommand = mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .okregisterMe {
                                //MARK: w okregisterMe
                                Log()
                                /*
                                 "okregisterMe"
                                 */
                                var sendAckStatus: Int?
                                let sendAck = doCommand.rawValue.utf8CString  //null terminated string.
                                Log(sendAck)
                                Log(sendAck.toString)
                                sendAckStatus = sendAck.withUnsafeBytes {
                                    send(writableSocketHandles[0], $0.baseAddress, $0.count, 0)
                                }
                                Log(sendAckStatus ?? "nil")
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
                                    continue
                                }
                                Log(firstJob.token)
                                Log(firstJob)
                                let toOverlayNetworkAddress = firstJob.toOverlayNetworkAddress.toString
                                var sendNodeInformationStatus: Int?
                                var sendNodeInformation: ContiguousArray<CChar>?
                                sendNodeInformation = (doCommand.rawValue + " " + String(toOverlayNetworkAddress.count) + " " + toOverlayNetworkAddress.toString).utf8CString
                                Log(sendNodeInformation ?? "nil")
                                Log(sendNodeInformation?.toString as Any)
                                if let sendNodeInformation = sendNodeInformation {
                                    sendNodeInformationStatus = sendNodeInformation.withUnsafeBytes {
                                        send(writableSocketHandles[0], $0.baseAddress, $0.count, 0)
                                    }
                                }
                                Log(sendNodeInformationStatus ?? "nil")
                                communicationProcess.increment()
                            } else if let doCommand = self.mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .exchangeToken {
                                //MARK: w exchangeToken
                                Log()
                                /*
                                 Should Shake Hand For Nat Traversable.
                                 */
                                if remote_token != "_" {
                                    Log("have taken remote node token.")
                                    sendHandshake = (doCommand.rawValue + " " + my_token + " " + remote_token + " " + "ok").utf8CString
                                } else {
                                    Log("do not have remote node token yet.")
                                    sendHandshake = (doCommand.rawValue + " " + my_token + " " + remote_token).utf8CString
                                }
                                Log(sendHandshake ?? "nil")
                                Log(sendHandshake?.toString as Any)
                                if let sendHandshake = sendHandshake {
                                    sentStatus = sendHandshake.withUnsafeBytes {
                                        send(writableSocketHandles[0], $0.baseAddress, $0.count, 0)
                                    }
                                }
                                Log(sentStatus ?? "nil")
                            } else if self.mode == .dequeueJob {
                                //MARK: w dequeueJob
                                LogCommunicate()
                                node.printSocketQueue()
                                guard let firstJob = node.socketQueues.deQueue() else {
                                    LogCommunicate("Not Have Command to Send.")
                                    continue
                                }
                                LogCommunicate(firstJob.token)
                                LogCommunicate(firstJob)
                                /*
                                 overlayNetworkAddress →ip address pair への翻訳が済んでいたら
                                 ↓
                                 相互に送信してシェイクハンドする（shouldShakeHandForNatTraversable
                                 ↓
                                 firstJobのコマンドを送信（Send Command）
                                 ↓
                                 firstJob, peerAddressPairs をnilクリアする
                                 */
                                LogCommunicate(peerAddressPairs as Any)
                                var commandInstance: CommandProtocol = firstJob.command
                                if firstJob.command.rawValue == "", let command = node.premiumCommand {
                                    LogCommunicate()
                                    /*
                                     Won't be Use this.
                                     
                                     if Nothing in overlayNetwork Command,
                                     Use Appendix Premium Command.
                                     */
                                    commandInstance = node.premiumCommand?.command(command.rawValue) ?? command
                                    commandInstance = command
                                }
                                LogCommunicate("to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
                                if firstJob.type == .local {
                                    LogCommunicate("Send Command to oneself.")
                                    let sentDataNodeIp = node.getIp
                                    LogCommunicate(sentDataNodeIp as Any)
                                    
                                    /*
                                     fetching commnad+operand+token from job in queue.
                                     
                                     Save cString ([CChar]) to UnsafeMutableRawBufferPointer's Pointee
                                     */
                                    if let jobData = (commandInstance.rawValue + " " + firstJob.operand + " " + firstJob.token).toCChar {
                                        LogCommunicate(jobData)
                                        jobData.withUnsafeBytes {
                                            rawBufferPointer.copyMemory(from: $0)
                                        }
                                        let receivedDataLength = jobData.count
                                        LogCommunicate(receivedDataLength as Any)
                                        if let sentDataNodeIp = sentDataNodeIp, receivedDataLength > 0 {
                                            LogCommunicate()
                                            callback(sentDataNodeIp, receivedDataLength)
                                        }
                                    }
                                } else {
                                    LogCommunicate("Send Command to Other Node.")
                                    var sentStatus: Int?
                                    var sendDataAsCChar: ContiguousArray<CChar>?
                                    let (transData, dataCount) = combineData(command: commandInstance, data: firstJob.operand, token: firstJob.token)
                                    sendDataAsCChar = transData.utf8String?.utf8CString
                                    LogCommunicate(sendDataAsCChar?.toString as Any)
                                    if let sendDataAsCChar = sendDataAsCChar {
                                        sentStatus = sendDataAsCChar.withUnsafeBytes {
                                            send(writableSocketHandles[0], $0.baseAddress, $0.count, 0)
                                        }
                                    }
                                    LogCommunicate(sentStatus ?? "nil")
                                }
                                self.peerAddressPairs = nil
                            }
                        }
                    }
                    Log()
                    if self.mode == .handshake {
                        //MARK: r/w handshake
                        Log()
                        if remote_token != "_" && self.remote_knows_our_token {
                            Log("we are done handshake for NAT Traverse - hole was punched from both ends")
                            /*
                             Go to Next Process.
                             */
                            Log()
                            if let nextMode = self.mode.stack[communicationProcess.phase].nextMode {
                                Log()
                                self.mode = nextMode
                                communicationProcess.nextMode()
                            }
                        }
                    }
                    node.printSocketQueue()
                    if let firstJob = node.socketQueues.firstQueueTypeLocal() {
                        LogCommunicate("Have Command to Local Execution to First.")
                        let _ = node.socketQueues.deQueue()
                        Log(firstJob.token)
                        Log(firstJob)
                        Log(peerAddressPairs as Any)
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
                        LogCommunicate("to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
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
                                    callback(sentDataNodeIp, receivedDataLength)
                                }
                            }
                        }
                    } else {
                        Log("Not Have Command to Local Execution to First.")
                    }
                    usleep(UInt32(0.5 * 1024 * 1024))   //wait 0.5sec til next select()
                }   //while
            }
            Log("Missed Signaling Server.")
        }
    }
}
