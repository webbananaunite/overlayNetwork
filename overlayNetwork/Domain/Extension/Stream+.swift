//
//  Stream+.swift
//  blocks
//
//  Created by よういち on 2021/07/13.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

public extension Stream {
    static func streamsToHost(name hostname: String, port: Int) -> (inputStream: InputStream, outputStream: OutputStream) {
        var inStream: InputStream? = nil
        var outStream: OutputStream? = nil
        Stream.getStreamsToHost(withName: hostname, port: port, inputStream: &inStream, outputStream: &outStream)
        return (inStream!, outStream!)
    }
    
    static func streams(port: Int) -> (inputStream: InputStream, outputStream: OutputStream) {
        var inStream: InputStream? = nil
        var outStream: OutputStream? = nil
        Stream.getBoundStreams(withBufferSize: 1024, inputStream: &inStream, outputStream: &outStream)
        return (inStream!, outStream!)
    }
    
    static func socketStreams(ipv4Address: String, port: Int) -> (streams: (inputStream: InputStream, outputStream: OutputStream), socketHandle: Int32) {
        Log("\(ipv4Address) \(port)")
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
                  ipv4Address.cString(using: .utf8),
                  &remoteaddress.sin_addr)
        
        remoteaddress.sin_port = UInt16(port).bigEndian
        
        remoteaddress.sin_family = sa_family_t(AF_INET)
        // Create native socket handle, if sockhandle < 0, error occurred, (check errno)
        let sockhandle = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)
        Log(sockhandle)
        var socketAddress = remoteaddress
        let connectStatus = withUnsafeMutablePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sockhandle, $0, socklen_t(MemoryLayout.size(ofValue: remoteaddress)))
            }
        }
        Log(connectStatus)
        var readStream :Unmanaged<CFReadStream>?
        var writeStream:Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(kCFAllocatorSystemDefault,
                                     sockhandle,
                                     &readStream, &writeStream)

        /*
         Use alternative(substitute) CFStreamCreatePairWithSocket
         can not use for socket stream??
         
         public func CFStreamCreateBoundPair(_ alloc: CFAllocator!, _ readStream: UnsafeMutablePointer<Unmanaged<CFReadStream>?>!, _ writeStream: UnsafeMutablePointer<Unmanaged<CFWriteStream>?>!, _ transferBufferSize: CFIndex)
         */
        let inputStream = readStream!.takeUnretainedValue()
        let outputStream = writeStream!.takeUnretainedValue()
        
        return ((inputStream, outputStream), sockhandle)
    }
    
    /*
     POSIX BSD Socket
     
     Tested up to received 1179 byte. 20230914
     */
    static let MTU = 65536

    static func standbyListenSocket(port: Int, rawBufferPointer: UnsafeMutableRawBufferPointer) -> Int32 {
        Log()
        // Create native socket handle, if sockhandle < 0, error occurred, (check errno)
        let sockhandle = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)
        // if connectStatus < 0, error occurred (check errno)
        if sockhandle < 0 {
            Log(sockhandle)
            Log("Error create socket info: \(errno)")
        }

        /*
         get own ip address
         */
        var hints = addrinfo(
            ai_flags: AI_PASSIVE,       // AI_PASSIVE in conjuntion with a nil node in getaddrinfo function, makes sure that the returned socket is suitable for binding a socket that accept connections.
            ai_family: AF_INET,       // Either IPv4 or IPv6
            ai_socktype: SOCK_STREAM,   // TCP
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil)

        var servinfo: UnsafeMutablePointer<addrinfo>? = nil
        let addrInfoResult = getaddrinfo(
            nil,                        // Any interface
            String(port).cString(using: .utf8),                 // The port on which will be listenend
            &hints,                     // Protocol configuration as per above
            &servinfo)    //UnsafeMutablePointer<UnsafeMutablePointer<addrinfo>?>!

        if addrInfoResult != 0 {
            Log("Error getting address info: \(errno)")
            Log(addrInfoResult)
        }

        /*
         initialize lisning port
         */
        let bindResult = bind(sockhandle, servinfo!.pointee.ai_addr, socklen_t(servinfo!.pointee.ai_addrlen))
        if bindResult == -1 {
            Log("Error binding socket to Address: \(errno)")// error occured in here.
        }

        Darwin.freeaddrinfo(servinfo)

        let listenResult = listen(sockhandle, //Socket File descriptor
                                  8         // The backlog argument defines the maximum length the queue of pending connections may grow to
        )
        if listenResult == -1 {
            Log("Error setting our socket to listen")
        }
        Log()
        return sockhandle
    }
    
    /*
     Accept and Read on Socket.
     */
    static func acceptSocketFromPeer(sockhandle: Int32, rawBufferPointer: UnsafeMutableRawBufferPointer, callback: @escaping (String?, Int) -> Void) {
        Log("Accepting Socket Communication from Peer, Sequentially.")
        Log()
        var addr = sockaddr()
        var addr_len: socklen_t = 0
        Log("Wait for accepting.")
        let clientFD = accept(sockhandle, &addr, &addr_len) //Stop at here in GDC global async thread.
        Log()
        var buffer = rawBufferPointer.baseAddress
        Log(buffer) //Optional(0x0000000161809000)
        let sentDataNodeIp = clientAddress(clientFD)
        Log("Accepted client \(String(describing: sentDataNodeIp)) file descriptor: \(clientFD)")

        if clientFD == -1 {
            Log("Error accepting connection")
            exit(0)
        }
        Log()
        var readedResult = 0
        readDataFromBindedSocket(clientFD: clientFD, buffer: buffer, amountedReadedResult: &readedResult)
        Log(buffer)
        Log(readedResult)
        Log(buffer) //Optional(0x0000000161809000)
        Log("Received form client(\(clientFD)) readedBytes: \(readedResult) readeddata: \(String(describing: buffer))")
        Darwin.shutdown(clientFD, SHUT_RDWR)
        Darwin.close(clientFD)

        callback(sentDataNodeIp, readedResult)
    }
    
    // get client IP
    private static func clientAddress(_ clientFD: Int32) -> String? {
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
    
    private static func readDataFromBindedSocket(clientFD: Int32, buffer: UnsafeMutableRawPointer!, amountedReadedResult: inout Int) {
        Log("Reading Next. \(buffer)")
        Log(buffer)
        let readResult = read(clientFD, buffer, MTU)
        amountedReadedResult += readResult
        if (readResult == 0) {
            Log("Detected End of File.")
            Log("Amounted Byte. \(amountedReadedResult) Byte")
            return
        } else if (readResult == -1) {
            Log("Occurred Error, As Reading form client\(clientFD) - \(errno)")
            amountedReadedResult = readResult
            return
        } else {
            Log("Reading Data, Currently")
            Log("\(readResult) Byte")
            /*
             Call own recursively.
             */
            let nextBufferPointer:UnsafeMutableRawPointer = buffer + readResult
            Log(nextBufferPointer)
            readDataFromBindedSocket(clientFD: clientFD, buffer: nextBufferPointer, amountedReadedResult: &amountedReadedResult)
            return
        }
    }
        
    /*
     POSIX BSD Socket
     
     Thank:
     https://rderik.com/blog/using-bsd-sockets-in-swift/

     Caution:
     As Use BSD Socket in While loop, Hung up socket in send and receive over about 1KB data in iOS 16.

     
     public func listen(_: Int32, _: Int32) -> Int32
     
     Create a socket with the socket() system call

     Bind the socket to an address using the bind() system call. For a server socket on the Internet, an address consists of a port number on the host machine.

     Listen for connections with the listen() system call

     Accept a connection with the accept() system call. This call typically blocks until a client connects with the server.

     */
    static func socketListenStreams(port: Int, callback: @escaping (String?, String) -> Void) -> Void {     //Use Task{}
        Log()
        /*
         Be Comfirmation Granted Network Access.
         */
        // Create native socket handle, if sockhandle < 0, error occurred, (check errno)
        let sockhandle = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)
        // if connectStatus < 0, error occurred (check errno)
        if sockhandle < 0 {
            Log(sockhandle)
            Log("Error create socket info: \(errno)")
        }
        
        /*
         get own ip address
         */
        var hints = addrinfo(
            ai_flags: AI_PASSIVE,       // AI_PASSIVE in conjuntion with a nil node in getaddrinfo function, makes sure that the returned socket is suitable for binding a socket that accept connections.
            ai_family: AF_INET,       // Either IPv4 or IPv6
            ai_socktype: SOCK_STREAM,   // TCP
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil)
        
        var servinfo: UnsafeMutablePointer<addrinfo>? = nil
        let addrInfoResult = getaddrinfo(
            nil,                        // Any interface
            String(port).cString(using: .utf8),                 // The port on which will be listenend
            &hints,                     // Protocol configuration as per above
            &servinfo)    //UnsafeMutablePointer<UnsafeMutablePointer<addrinfo>?>!
        
        if addrInfoResult != 0 {
            Log("Error getting address info: \(errno)")
            Log(addrInfoResult)
        }
        
        /*
         initialize lisning port
         */
        let bindResult = bind(sockhandle, servinfo!.pointee.ai_addr, socklen_t(servinfo!.pointee.ai_addrlen))
        if bindResult == -1 {
            Log("Error binding socket to Address: \(errno)")// error occured in here.
        }
        
        Darwin.freeaddrinfo(servinfo)
        
        let listenResult = listen(sockhandle, //Socket File descriptor
                                  8         // The backlog argument defines the maximum length the queue of pending connections may grow to
        )
        if listenResult == -1 {
            Log("Error setting our socket to listen")
        }
        Log()
        Log()
        while (true) {
            Log()
            DispatchQueue.global().sync {
                Log()
                var addr = sockaddr()
                var addr_len :socklen_t = 0
                Log("Wait for accepting")
                let clientFD = accept(sockhandle, &addr, &addr_len) //stop at here in GDC global async thread.
                Log()
                let MTU = 65536
                var buffer = UnsafeMutableRawPointer.allocate(byteCount: MTU,alignment: MemoryLayout<CChar>.size)
                
                let sentDataNodeIp = clientAddress(clientFD)
                Log("Accepted client \(String(describing: sentDataNodeIp)) file descriptor: \(clientFD)")
                
                if clientFD == -1 {
                    Log("Error accepting connection")
                }
                
                Log()
                while(true) {
                    Log()
                    let readResult = read(clientFD, &buffer, MTU)
                    
                    if (readResult == 0) {
                        Log("Detected End of File.")
                        break;  // end of file
                    } else if (readResult == -1) {
                        Log("Error reading form client\(clientFD) - \(errno)")
                        break;  // error
                    } else {
                        Log(readResult)
                        let commandAndOperand = withUnsafePointer(to: &buffer) {
                            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: readResult)) {
                                String(cString: $0)
                            }
                        }
                        Log("\(commandAndOperand)")
                        /*
                         commandAndOperand領域は再利用される
                         末尾にゴミが入ることがある commandAndOperand を readResultバイトでtrim
                         */
                        //check terminator
                        let cleanedCommandAndOperand = commandAndOperand.prefix(readResult)
                        Log("Received form client(\(clientFD)) readBytes: \(String(cleanedCommandAndOperand).count) readdata: \(cleanedCommandAndOperand)")
                        callback(sentDataNodeIp, String(cleanedCommandAndOperand))
                    }
                    Log()
                }
                Log()
                Darwin.shutdown(clientFD, SHUT_RDWR)
                Darwin.close(clientFD)
            }
            Log()
        }
        Log()
        
        // get client IP
        func clientAddress(_ clientFD: Int32) -> String? {
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
            Log(String(cString: hostBuffer))//192.168.11.6
            return String(cString: hostBuffer)
        }
    }
}
