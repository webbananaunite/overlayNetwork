//
//  AcceptStreaming.swift
//  blocks
//
//  Created by よういち on 2021/07/13.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

/*
 */
open class AcceptStreaming: NSObject {
    var ping = Data()//使用していない
    
    deinit {
//        if let streams = self.streams {
//            self.stop(streams: streams)
//        }
    }

    //使用していない
    open func streamStart() {
        self.start(port: 8334, tls: false, ping: "Hello Cruel World!\r\n")    //20文字(20 byte)
    }
    
    //使用していない
    open func streamTest() {
        Log()
        Log("stream start")
        self.start(port: 8334, tls: false, ping: "Hello Cruel World!\r\n")    //20文字(20 byte)
    }

    //未使用
    open func pingTest() {
            Log("stream ping")
    }
    
    open func start(port: Int, tls: Bool, rawBufferPointer: UnsafeMutableRawBufferPointer, callback: @escaping (String?, Int) -> Void) {
        Log()
        /*
         POSIX BSD Sockets
         */
        DispatchQueue.global().async {
                //Listen port
            let sockhandle = Stream.standbyListenSocket(port: port, rawBufferPointer: rawBufferPointer)
            while true {
                Log()
                Stream.acceptSocketFromPeer(sockhandle: sockhandle, rawBufferPointer: rawBufferPointer, callback: callback)
                Log()
            }
        }
    }

    //使用していない
    private func start(port: Int, tls: Bool, ping: String) {
        Log()
        self.ping = ping.utf8DecodedData!
        //Listen port
        Stream.socketListenStreams(port: port) {
            ip, string in
            Log(ip ?? "---")
            Log(string)
            
        }
    }
}
