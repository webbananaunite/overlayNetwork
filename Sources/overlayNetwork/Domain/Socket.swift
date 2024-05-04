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
    var mode: Mode
    public enum AddressSpace {
        case `public`
        case `private`
    }
    var socketHandles: [Mode.PeerType: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool)]]

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
        self.socketHandles = [Mode.PeerType: [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool)]]()
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
                LogPosixError()
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
            LogPosixError()
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
            if connectStatus == 0 || (connectStatus == -1 && errno == 56) {
                connectionSucceeded = true
            } else {
                connectionSucceeded = false
            }
            LogPosixError()

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
//            Log(getsocknameStatus)
            
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
            $0.value.forEach {
                if $0.value.peerAddress.ip == ip {
                    overlayNetworkAddress = $0.value.overlayNetworkAddress?.toString
                }
            }
        }
        return overlayNetworkAddress
    }
    public func findIp(socketFd: Int32) -> (ip: String, port: Int)? {
        var address: (ip: String, port: Int)?
        self.socketHandles.forEach {
            $0.value.forEach {
                if $0.value.socketFd == socketFd {
                    address = $0.value.peerAddress
                }
            }
        }
        return address
    }
    public func findIpAndConnectStatus(socketFd: Int32) -> (address: (ip: String, port: Int)?, connected: Bool?) {
        var address: (ip: String, port: Int)?
        var connected: Bool?
        self.socketHandles.forEach {
            $0.value.forEach {
                if $0.value.socketFd == socketFd {
                    address = $0.value.peerAddress
                    connected = $0.value.connected
                }
            }
        }
        return (address, connected)
    }
    public func findIpAndAddressSpace(socketFd: Int32) -> (address: (ip: String, port: Int)?, addressspace: AddressSpace?) {
        var address: (ip: String, port: Int)?
        var addressSpace: AddressSpace?
        self.socketHandles.forEach {
            $0.value.forEach {
                if $0.value.socketFd == socketFd {
                    address = $0.value.peerAddress
                    addressSpace = $0.value.addressSpace
                }
            }
        }
        return (address, addressSpace)
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
    enum ConnectionErrorNum: Int32 {
        case failed = 22        //: connection failed
        case trying = 36
        case trying2 = 37       //: start do connection as Non-Blockinng Mode
        case doneSuccess = 56   //: connected already (status == -1)
        case timeout = 60       //: timeout for 75 seconds
        case refusedPeer = 61   //: connection failed as refused by peer
        
        func description() -> String {
            String(cString: strerror(self.rawValue))

//            switch self {
//            case .failed:
//                return "...connection failed..."
//            case .trying:
//                return "...trying connect in Non-Blockinng Mode..."
//            case .trying2:
//                return "...trying connect in Non-Blockinng Mode..."
//            case .doneSuccess:
//                return "...connected already (status == -1)..."
//            case .timeout:
//                return "...timeout for 75 seconds..."
//            case .refusedPeer:
//                return "...connection failed as refused by peer..."
//            }
        }
    }

    /*
     TCP Hole Punching for communicate with Node under NAT DHCP router.
         UDP: Attempt looping data.Write (using POSIX Socket#sendto() function)
         TCP: Attempt looping tcp.flags.SYN (using POSIX Socket#connect() function)
     
     Thank:
     https://gist.github.com/somic/224795
     
     Communicate with POSIX BSD Sockets.
     
     At First, Register own's overlayNetworkAddress to Signaling Server.
     then Determine Communicaton Port in overlayNetwork.
     */
    //MARK: - Start Communication
    public func start(startMode: Mode, tls: Bool, rawBufferPointer: UnsafeMutableRawBufferPointer, node: Node, inThread: Bool, notifyOwnAddress: @escaping ((ip: String, port: Int)?) -> Void, callback: @escaping (String?, Int) -> Void) {
        Log(startMode)
        self.mode = startMode
        if inThread {
            Log()
            DispatchQueue.global().async {
                while true {
                    Log("++++++++++++++++ retry Signaling ++++++++++++++++")
                    communication()
                }
            }
        } else {
            Log()
            communication()
        }
        func communication() {
            Log()
            guard let signalingServerAddress = Dht.getSignalingServer() else {
                Log()
                return
            }
            Log(signalingServerAddress)
            /*
             Two Time
             1st: Take Local Address
             2nd: Signaling Phase
             */
            let (socketHandleForTakeAddress, sourceAddress, _) = self.openSocket(to: signalingServerAddress, addressSpace: .public, source: nil)   //Connect Syncronouslly
            close(socketHandleForTakeAddress)
            let (socketHandle, _, connectionSucceeded) = self.openSocket(to: signalingServerAddress, addressSpace: .public, source: sourceAddress) //Connect Syncronouslly

            self.socketHandles = [.signalingServer: [.public: (.public, socketHandle, signalingServerAddress, nil, connectionSucceeded)]]
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
            var remote_token = "_"
            
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
                let socketHandle = $0.value.socketFd
                __darwin_fd_set(socketHandle, &active_fd_set)
            }
            
            func catchedSocketHandles(_ fd_set: fd_set, peerType: Mode.PeerType) -> [Int32]? {
                Log(self.mode)
                Log(peerType)
                var array = [Int32]()
                var catchedSocketHandles = fd_set
                //                Log(self.socketHandles[peerType]?.count as Any)
                self.socketHandles[peerType]?.forEach {
                    let socketHandle = $0.value.socketFd
                    if __darwin_fd_isset(socketHandle, &catchedSocketHandles) != 0 {
                        array.append(socketHandle)
                    }
                }
                if array.isEmpty {
                    Log("None")
                    return nil
                }
                Log(array.count)
                return array
            }
            func isConnected(socketHandles: [(addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool)?]) -> Bool {
                let connectedSockets = socketHandles.filter {
                    if let socketHandle = $0, socketHandle.connected == true {
                        return true
                    }
                    return false
                }
                return connectedSockets.count > 0
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

            var readable_fd_set = active_fd_set
            var writable_fd_set = active_fd_set
            var exception_fd_set = active_fd_set
            /*
             timeout 0.0s is indicate pooling.
             */
            var selectTimeout: timeval = timeval(tv_sec: 5, tv_usec: 0) //5s
            let maxTimeAttemptConnection = 2
            var connectionFailCounter = 0
            while true {
                //MARK: Start While Loop
                Log(self.mode)
                /*
                 When Can NOT Connect any Socket, Try Close(), Connect() attempt.
                 (as Occurred TimeOut in select().)
                 */
                Log(self.mode.stack.first?.peerType as Any)
                Log("loop start in communication.")
                if let peerType = self.mode.stack.first?.peerType, let socketHandles = self.socketHandles[peerType], !isConnected(socketHandles: [socketHandles[.public], socketHandles[.private]]) {
                    connectionFailCounter += 1
                    Log(connectionFailCounter)
                    Log(peerType)
                    Log(socketHandles.first?.value as Any)
                    if connectionFailCounter > maxTimeAttemptConnection {
                        Log("+++++++++++++++Connection Failed Specified Max Count.+++++++++++++++")
                        Log("Once more Send registerMe to Signaling Server.")
                        self.mode = .registerMeAndIdling
                        self.communicationProcess.onceMore()
                        Log("Go to do func communication()")
                        break
                    }
                    if peerType == .peerNode {
                        /*
                         Have Connected, Close Socket for Signaling
                         */
                        Log()
                        if let connected = self.socketHandles[.signalingServer]?[.public]?.connected, connected, let signalingSocketFd = self.socketHandles[.signalingServer]?[.public]?.socketFd {
                            Log()
                            close(signalingSocketFd)
                            self.socketHandles[.signalingServer]?[.public]?.connected = false
                            self.socketHandles[.signalingServer]?[.public]?.socketFd = -1
                        }
                    }
                    Log(socketHandles)
                    socketHandles.forEach {
                        var connectStatus: ConnectionStatus?
                        let socketHandleDescription = $0.value
                        let addressSpace = socketHandleDescription.addressSpace
                        let address = socketHandleDescription.peerAddress
                        let socketFd = socketHandleDescription.socketFd
                        let overlayNetworkAddress = socketHandleDescription.overlayNetworkAddress
                        let connected = socketHandleDescription.connected
                        Log("Detect Socket whether Opened.")
                        /*
                         Check Done Connect the Sokets.
                         */
                        connectStatus = connected ? .doneSuccessfully : .failed
                        if connectStatus == .doneSuccessfully {
                            Log("Socket Have Opened")
                            /*
                             Socket Have Opened (Connected)
                             Goto Do select() async.
                             */
                            Log(self.socketHandles[peerType]?[addressSpace]?.connected as Any)
                        } else {
                            Log("Socket Not Open yet")
                            /*
                             Close Old Socket
                             */
                            if socketFd != -1 {
                                Log("Close Old Socket")
                                let closeRet = close(socketFd)
                                Log(closeRet)
                                LogPosixError()
                                self.socketHandles[peerType]?[addressSpace]?.socketFd = -1
                            }
                            /*
                             Open Socket
                             */
                            Log("Open Socket")
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
                                //                                    LogPosixError()
                                usleep(UInt32(2 * 1024 * 1024))   //wait 0.2sec til next open socket
                            }
#else
                            //Connect Asyncronouslly
                            let (socketHandle, sourceAddress, connectionSucceeded) = openSocket(to: address, addressSpace: addressSpace, source: ownNodePrivateAddress, async: true)
#endif
                            
                            self.socketHandles[peerType]?[addressSpace] = (addressSpace: addressSpace, socketFd: socketHandle, peerAddress: address, overlayNetworkAddress: overlayNetworkAddress, connected: connectionSucceeded)
                            Log(peerType)
                            Log(self.socketHandles[peerType]?[addressSpace] as Any)
                            /*
                             re-arrange fd_set for select().
                             */
                            Log("Set up fd_set")
                            bzero(&active_fd_set, MemoryLayout.size(ofValue: active_fd_set))
                            self.socketHandles[peerType]?.forEach {
                                let socketHandle = $0.value.socketFd
                                if socketHandle > 0 {
                                    Log("\(socketHandle) into fd_set.")
                                    __darwin_fd_set(socketHandle, &active_fd_set)
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
                if let peerType = self.mode.stack.first?.peerType {
                    Log(peerType)
                    self.socketHandles[peerType]?.forEach {
                        let sockhandle = $0.value.socketFd
                        maxfd = ((maxfd - 1) > sockhandle ? maxfd : sockhandle + 1)
                    }
                }
                Log("--readable_fd_set: \(readable_fd_set) writable_fd_set:\(writable_fd_set)")
                Log("Select(Detect) read/write Events for Sockets (..<\(maxfd))") // ソケットに対するイベントが発生しているかどうか検出／判定する
                //MARK: Select()
                errno = 0   //clear as select() NOT Set errno.
                let selectStatus = select(maxfd, &readable_fd_set, &writable_fd_set, &exception_fd_set, &selectTimeout)   //Block able
                Log(selectStatus) //0: timeout/no any sockets   1...: number of available sockets/done attempt connection
                Log("\(selectStatus) \(errno): \(String(cString: strerror(errno)))")
                /*
                 Get Error by Socket.
                 コネクションの確立が成功したかどうかは、ソケットオプションSO_ERRORによりソケットのエラーを調べることで確認できます。
                 ソケットのエラーが正常終了を示している(errno=0)ならコネクションの確立に成功しています。
                 */
                
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
                Log("\(mode) \(self.communicationProcess.phase) \(self.mode.stack[communicationProcess.phase].peerType)")
                Log("++readable_fd_set: \(readable_fd_set) writable_fd_set:\(writable_fd_set)")
                //for debug
                [readable_fd_set, writable_fd_set, exception_fd_set].enumerated().forEach { fds in   Log(fds.offset)
                    if let accessableSocketHandles = catchedSocketHandles(fds.element , peerType: .signalingServer) {
                        accessableSocketHandles.forEach {
                            let findipResult = self.findIp(socketFd: $0)
                            Log("\($0) \(findipResult as Any)")
                        }
                    }
                    if let accessableSocketHandles = catchedSocketHandles(fds.element , peerType: .peerNode) {
                        accessableSocketHandles.forEach {
                            let findipResult = self.findIp(socketFd: $0)
                            Log("\($0) \(findipResult as Any)")
                        }
                    }
                }
                //for debug
                Log("Exception")
                //MARK: Exception Socket (purhaps select() status: -1)
                if let exceptionSocketHandles = catchedSocketHandles(exception_fd_set, peerType: self.mode.stack[communicationProcess.phase].peerType) {
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
                    if remote_token != "_" && self.remote_knows_our_token {
                        Log("++++++++++++++++++++ NAT Traversal - Succeeded. ++++++++++++++++++++")
                        Log("++++++++++++++++++++ TCP Hole Punching We Did! ++++++++++++++++++++")
                        Log("++++++++++++++++++++ We are done handshake for NAT Traversal - Hole was punched from both ends ++++++++++++++++++++")
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
                    Log("to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
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
                if self.mode == .handshake || self.mode == .dequeueJob {
                    usleep(UInt32(0.5 * 1024 * 1024))   //wait 0.5sec til next select()
                }
            }   //while
            
            //MARK: Read Socket
            func readPhase() -> Bool {  Log()
                var returnValue = false
                if let readableSocketHandles = catchedSocketHandles(readable_fd_set, peerType: self.mode.stack[communicationProcess.phase].peerType) {
                    Log("\(self.mode) r \(self.communicationProcess.phase)")
                    Log("Socket Have Read Data as Readable.")
                    /*
                     Receive Data (Command & Operands)
                     */
                    Log(readableSocketHandles.count)
                    errno = 0
                    var readableSocketNoError = false
                    if let socketFd = readableSocketHandles.first {
                        let (findipResult, addressSpace) = self.findIpAndAddressSpace(socketFd: socketFd)
                        Log("\(socketFd): \(findipResult as Any)")
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
                    }

                    guard let readableSocketHandle = readableSocketHandles.first, let rawBufferPointerAddress = rawBufferPointer.baseAddress else {
                        return false
                    }
                    /*
                     For TCP sockets, the return value 0 means the peer has closed its half
                     side of the connection.
                     */
                    errno = 0
                    let receivedDataLength = recv(readableSocketHandle, rawBufferPointer.baseAddress, rawBufferPointer.count, 0)
                    Log(receivedDataLength as Any)  //-1: Error   0: End of File   >0: data length
                    Log(rawBufferPointer.toByte(byteLength: 4))
                    Log(rawBufferPointer.toString(byteLength: receivedDataLength == -1 ? 0 : receivedDataLength))
                    Log(rawBufferPointer.toByte(byteLength: 4))
                    LogPosixError()  //35: 受信データがない　 60: Operation timed out    61: Connection refused by peer
                    Log("\(readableSocketNoError) && \(receivedDataLength) (\(receivedDataLength <= 0 ? "Socket Receive Error Occurred." : "")")
                    if readableSocketNoError && receivedDataLength > 0 {
                        Log("[c]Received Data Successfully.")
                        let (findipResult, addressSpace) = self.findIpAndAddressSpace(socketFd: readableSocketHandle)
                        Log("\(readableSocketHandle): \(findipResult as Any)")
                        if let findipResult = findipResult, let addressSpace = addressSpace { Log("[c]Connection Successfull.")
                            self.socketHandles[self.mode.stack[communicationProcess.phase].peerType]?[addressSpace]?.connected = true
                        }
                    }
                    /*
                     Received Data Successfully.
                     */
                    Log(rawBufferPointer.toString(byteLength: receivedDataLength))
                    let receivedDataAsString = rawBufferPointer.toString(byteLength: receivedDataLength)
                    Log(receivedDataAsString)
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
                                if let firstJob = node.socketQueues.firstQueueTypeLocal() {
                                    Log("Have Command to Local Execution to First.")
                                    let _ = node.socketQueues.deQueue()
                                    Log(firstJob.token)
                                    Log(firstJob)
                                    //                                        Log(peerAddressPairs as Any)
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
                                    Log("to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
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
                                         Go to Next Process (translate).
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
                            if command == doCommand.rawValue {Log()
                                //MARK: r translateAck
                                /*
                                 Received Command for defined in Signaling.
                                 
                                 自node と peer 双方に接続要求を知らせてきた
                                 ["ack", "153.243.66.142", "1040", "192.168.0.34", "54512", "", "", "", "", "", "", "",...
                                 */
                                if let nextMode = self.mode.stack[communicationProcess.phase].nextMode, let peerType = nextMode.stack.first?.peerType {
                                    var publicIp: String? = receivedCommandOperand[1]
                                    //Log(receivedCommandOperand[2])    //public port
                                    var privateIp: String? = receivedCommandOperand[3]
                                    //Log(receivedCommandOperand[4])    //private port
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
                                        self.socketHandles[peerType] = [Socket.AddressSpace: (addressSpace: Socket.AddressSpace, socketFd: Int32, peerAddress: (ip: String, port: Int), overlayNetworkAddress: OverlayNetworkAddressAsHexString?, connected: Bool)]()
                                        if let publicAddress = publicAddress {
                                            self.socketHandles[peerType]?[.public] = (addressSpace: .public, socketFd: -1, peerAddress: publicAddress, overlayNetworkAddress: overlayNetworkAddress, connected: false)
                                        }
                                        //comment following code block, when do #test for public address only
                                        if let privateAddress = privateAddress {
                                            self.socketHandles[peerType]?[.private] = (addressSpace: .private, socketFd: -1, peerAddress: privateAddress, overlayNetworkAddress: overlayNetworkAddress, connected: false)
                                        }
                                    }
                                    var ownNodePrivateAddress: (ip: String, port: Int)? = (ip: ip.toString(), port: port)
                                    /*
                                     Go to Next Process.
                                     */
                                    Log(peerType)
                                    self.mode = nextMode
                                    communicationProcess.nextMode()
                                    self.remote_knows_our_token = false
                                    Log("---Will Change Peer to the Node-----------------------------------------------")
                                    Log(self.socketHandles[peerType] as Any)
                                    returnValue = true
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
                            Log()
                            /*
                             Received Command for defined in overlayNetwork / blocks.
                             
                             Possibility, Receive Command exchangeToken, when peer Node Not Receive Remote Token of The Node yet.
                             */
                            Log()
                            let sentDataNodeIp = clientAddress(readableSocketHandles[0])
                            Log(sentDataNodeIp as Any)
                            Log(receivedDataLength as Any)
                            if let sentDataNodeIp = sentDataNodeIp, receivedDataLength > 0, command != Mode.SignalingCommand.exchangeToken.rawValue {Log()
                                callback(sentDataNodeIp, receivedDataLength)
                            }
                        }
                    }
                }
                return returnValue
            }
            
            //MARK: Write Socket
            func writePhase() -> Bool { Log()
                if let writableSocketHandles = catchedSocketHandles(writable_fd_set, peerType: self.mode.stack[communicationProcess.phase].peerType) {
                    Log("\(mode) w \(self.communicationProcess.phase)")
                    Log("Socket being Writable.")
                    Log(writableSocketHandles.count)
                    errno = 0
                    var writableSocketNoError = false
                    if let socketFd = writableSocketHandles.first {
                        let (findipResult, addressSpace) = self.findIpAndAddressSpace(socketFd: socketFd)
                        Log("\(socketFd): \(findipResult as Any)")
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
                                Log("[c]Socket NOT Error. (as Writable socket)")
                                writableSocketNoError = true
                            }
                        }
                    }
                    if mode.stack[communicationProcess.phase].selects.contains(.send) {
                        Log()
                        if let doCommand = mode.stack[communicationProcess.phase].doCommands?.first, doCommand == .registerMe {
                            //MARK: w registerMe
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
                            Log("^_^\(sendNodeInformation?.toString as Any)")
                            guard let writableSocket = writableSocketHandles.first else {
                                Log("_ _")
                                return false
                            }
                            if let sendNodeInformation = sendNodeInformation {
                                sendNodeInformationStatus = sendNodeInformation.withUnsafeBytes {
                                    send(writableSocket, $0.baseAddress, $0.count, 0)
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
                            guard let writableSocket = writableSocketHandles.first else {
                                Log("_ _")
                                return false
                            }
                            sendAckStatus = sendAck.withUnsafeBytes {
                                send(writableSocket, $0.baseAddress, $0.count, 0)
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
                                //                                        continue
                                return false
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
                                guard let writableSocket = writableSocketHandles.first else {
                                    Log("_ _")
                                    return false
                                }
                                sendNodeInformationStatus = sendNodeInformation.withUnsafeBytes {
                                    send(writableSocket, $0.baseAddress, $0.count, 0)
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
                            var sendHandshake: ContiguousArray<CChar>?
                            if remote_token != "_" {
                                Log("have taken remote node token.")
                                sendHandshake = (doCommand.rawValue + " " + my_token + " " + remote_token + " " + "ok").utf8CString
                            } else {
                                Log("do not have remote node token yet.")
                                sendHandshake = (doCommand.rawValue + " " + my_token + " " + remote_token).utf8CString
                            }
                            Log(sendHandshake ?? "nil")
                            Log(sendHandshake?.toString as Any)
                            var sentStatus: Int?
                            guard let writableSocket = writableSocketHandles.first else {
                                Log("_ _")
                                return false
                            }
                            Log(writableSocket)
                            let address = self.findIp(socketFd: writableSocket)
                            Log(address as Any)
                            if let sendHandshake = sendHandshake, let address = address {
                                /*
                                 SO_NOSIGPIPE: NOT generate signal as broken communication pipe (must set the flag on setsockopt().)
                                 */
                                errno = 0
                                sentStatus = sendHandshake.withUnsafeBytes {
                                    Log("Will Write Length: \($0.count)")
                                    return send(writableSocket, $0.baseAddress, $0.count, 0)
                                }
                                let sendError = errno
                                Log("Wrote Length: \(String(describing: sentStatus))")
                                LogPosixError()  //57: 未接続  32: broken pipe
                                if sendError == 32 {
                                    Log("Broken Pipe - 送信もしくは受信が閉じられている")
                                }
                                if let sentStatus = sentStatus, writableSocketNoError && sentStatus >= 0 {
                                    Log("[c]Sent Data Successfully.")
                                    let (findipResult, addressSpace) = self.findIpAndAddressSpace(socketFd: writableSocket)
                                    Log("\(writableSocket): \(findipResult as Any)")
                                    if let findipResult = findipResult, let addressSpace = addressSpace { Log("[c]Connection Successfull.")
                                        self.socketHandles[self.mode.stack[communicationProcess.phase].peerType]?[addressSpace]?.connected = true
                                    }
                                }
                            }
                        } else if self.mode == .dequeueJob {
                            //MARK: w dequeueJob
                            Log()
                            node.printSocketQueue()
                            guard let firstJob = node.socketQueues.deQueue() else {
                                Log("Not Have Command to Send.")
                                return false
                            }
                            Log(firstJob.token)
                            Log(firstJob)
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
                            Log("to overlayNetworkAddress:\(firstJob.toOverlayNetworkAddress) command:\(commandInstance.rawValue) operand:\(firstJob.operand)")
                            if firstJob.type == .local {
                                Log("Send Command to oneself.")
                                let sentDataNodeIp = node.getIp
                                Log(sentDataNodeIp as Any)
                                
                                /*
                                 fetching commnad+operand+token from job in queue.
                                 
                                 Save cString ([CChar]) to UnsafeMutableRawBufferPointer's Pointee
                                 */
                                if let jobData = (commandInstance.rawValue + " " + firstJob.operand + " " + firstJob.token).toCChar {
                                    LogCommunicate("\(jobData) to local")
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
                            } else {
                                Log("Send Command to Other Node.")
                                var sentStatus: Int?
                                var sendDataAsCChar: ContiguousArray<CChar>?
                                let (transData, dataCount) = combineData(command: commandInstance, data: firstJob.operand, token: firstJob.token)
                                sendDataAsCChar = transData.utf8String?.utf8CString
//                                LogCommunicate("\(sendDataAsCChar?.toString as Any) to findipResult as Any")
                                if let sendDataAsCChar = sendDataAsCChar {
                                    guard let writableSocket = writableSocketHandles.first else {
                                        Log("_ _")
                                        return false
                                    }
                                    /*
                                     SO_NOSIGPIPE: NOT generate signal as broken communication pipe (must set the flag on setsockopt().)
                                     */
                                    let (findipResult, addressSpace) = self.findIpAndAddressSpace(socketFd: writableSocket)
//                                    Log("\(writableSocket): \(findipResult as Any)")
                                    LogCommunicate("\(sendDataAsCChar.toString as Any) to \(findipResult as Any)")
                                    sentStatus = sendDataAsCChar.withUnsafeBytes {
                                        send(writableSocket, $0.baseAddress, $0.count, 0)
                                    }
                                    LogPosixError()
                                }
                                Log(sentStatus ?? "nil")
                            }
                        }
                    }
                }
                return false
            }
        }
    }
}
