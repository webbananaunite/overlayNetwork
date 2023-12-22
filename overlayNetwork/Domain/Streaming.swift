//
//  Streaming.swift
//  blocks
//
//  Created by よういち on 2021/07/13.
//  Copyright © 2021 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation

/*
 Thank:
 https://developer.apple.com/forums/thread/84472
 */
open class Streaming: NSObject, StreamDelegate {
    var streams: (inputStream: InputStream, outputStream: OutputStream)? = nil
    var ping = Data()//使用していない
    
    var commandData = Data()
    var transData = Data()
    var tokenData = Data()

    deinit {
        if self.streams != nil {
            self.stop()
        }
    }

    //#test
    public func streamTest(ip: String) {
        Log(ip)
        Log("stream start")
        self.start(ip: ip, port: 8334, tls: false, ping: "Hello Cruel World!\r\n")    //20文字(20 byte)
    }

    public func pingTest() {
        if let streams = self.streams {
            Log("stream ping")
            self.ping(streams: streams)
        } else {
            Log("stream ping while not connected")
        }
    }

    public func start(ip: String, port: Int, tls: Bool, callback: (_ socketHandle: Int32) -> Void) {
        Log()
        let streams = Stream.socketStreams(ipv4Address: ip, port: port)

        self.streams = streams.streams
        if tls {
            let success = streams.streams.inputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL as AnyObject, forKey: Stream.PropertyKey.socketSecurityLevelKey)
            precondition(success)
        }
        streams.streams.inputStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as Stream.PropertyKey)
        streams.streams.outputStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as Stream.PropertyKey)
        
        for s in [streams.streams.inputStream, streams.streams.outputStream] {
            s.schedule(in: .current, forMode: .default)
            s.delegate = self
            s.open()
        }
        
        callback(streams.socketHandle)
    }

    //x使用していない
    private func start(ip: String, port: Int, tls: Bool, ping: String) {
        Log()
        self.ping = ping.utf8DecodedData!

        //Connect port
        let streams = Stream.socketStreams(ipv4Address: ip, port: port)
        Log()
        self.streams = streams.streams
        if tls {
            let success = streams.streams.inputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL as AnyObject, forKey: Stream.PropertyKey.socketSecurityLevelKey)
            precondition(success)
        }
        streams.streams.inputStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as Stream.PropertyKey)
        streams.streams.outputStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as Stream.PropertyKey)
        
        Log()
        for s in [streams.streams.inputStream, streams.streams.outputStream] {
            s.schedule(in: .current, forMode: .default)
            s.delegate = self
            s.open()
        }
    }
    
    /*
     送信データ生成
     */
    public static let communicationTerminatorChar = "\n"
    public static let operandDelimiterChar = " "
    
    private func combineData(command: CommandProtocol, data: String, token: String) -> (Data, Int) {
        Log("command: \(command.rawValue) data: \(data) token: \(token)")
        //"FS 38298382,288392,2983,2893,2892\n"
        let data = data.removeNewLineChars
        Log(data)
        self.commandData = command.rawValue.utf8DecodedData!
        self.transData = data.utf8DecodedData!
        self.tokenData = token.utf8DecodedData!

        let spacer = Streaming.operandDelimiterChar.utf8DecodedData!
        let terminator = Streaming.communicationTerminatorChar.utf8DecodedData!
        let regulatedData = self.commandData + spacer + self.transData + spacer + self.tokenData + terminator
        let dataCount = regulatedData.count
        Log(regulatedData.utf8String)
        return (regulatedData, dataCount)
    }
    
    /*
     データ通信
     */
    public func communication(command: CommandProtocol, operand: String, token: String) -> Bool {
        Log("command: \(command) operand: \(operand) token: \(token)")
        guard let streams = self.streams else {
            Log("stream while not connected")
            return false
        }
        
        let (transData, dataCount) = combineData(command: command, data: operand, token: token)
        Log("\(dataCount) - \(transData.utf8String)")
        let bytesWritten = transData.withUnsafeBytes { bytes -> Int in
            Log(bytes.baseAddress)
            let p = (bytes.baseAddress?.assumingMemoryBound(to: UInt8.self))!
            Log(p)
            Log(dataCount)
            return streams.outputStream.write(p, maxLength: dataCount)
        }
        Log(bytesWritten)
        if bytesWritten < 0 {
            Log("stream write error")
            return false
        } else if bytesWritten < transData.count {
            Log("stream written succeeded short \(bytesWritten) / \(transData.count)")
        } else {
            Log("stream written succeeded \(bytesWritten) / \(transData.count)")
            Log("stream written succeeded \(transData as NSData)")
            Log("stream written succeeded \(String(describing: transData.utf8String))")
        }
        return true
    }

    /*
     送信
     */
    public func send(command: CommandProtocol, operand: String, token: String) -> Bool {
        Log()
        return communication(command: command, operand: operand, token: token)
    }

    /*
     応答
     */
    public func reply(command: CommandProtocol, operand: String, token: String) -> Bool {
        Log()
        return communication(command: command, operand: operand, token: token)
    }

    //x使用していない
    private func ping(streams: (inputStream: InputStream, outputStream: OutputStream)) {
        let data = self.ping
        let dataCount = data.count
        let bytesWritten = data.withUnsafeBytes { bytes -> Int in
            let p = (bytes.baseAddress?.assumingMemoryBound(to: UInt8.self))!
            return streams.outputStream.write(p, maxLength: dataCount)
        }
        
        if bytesWritten < 0 {
            Log("stream write error")
        } else if bytesWritten < data.count {
            Log("stream write short \(bytesWritten) / \(data.count)")
        } else {
            Log("stream task write \(data as NSData)")
            Log("stream task write \(String(describing: data.utf8String))")
        }
    }

    public func stop() {
        guard let inputStream = self.streams?.inputStream, let outputStream = self.streams?.outputStream else {
            return
        }
        for s in [inputStream, outputStream] {
            s.delegate  = nil
            s.close()
        }
        self.streams = nil
    }

    var timer: Timer? = nil
    var canWrite: Bool = false

    /*
     MARK: - StreamDelegate
     */
    public func stream(_ thisStream: Stream, handle eventCode: Stream.Event) async {
        Log(thisStream)
        Log(eventCode)
        guard let streams = self.streams else { fatalError() }
        let streamName = thisStream == streams.inputStream ? " input" : "output"
        switch eventCode {
            case [.openCompleted]:
                Log("\(streamName as NSString) stream did open")
                break
            case [.hasBytesAvailable]:
                Log("\(streamName as NSString) stream has bytes")

                var buffer = [UInt8](repeating: 0, count: 2048)
                let bytesRead = streams.inputStream.read(&buffer, maxLength: buffer.count)
                if bytesRead > 0 {
                    Log("\(streamName) stream read \(NSData(bytes: &buffer, length: bytesRead))")
                    let recieveData = (NSData(bytes: &buffer, length: bytesRead) as Data).utf8String
                    Log("\(streamName) stream read \(String(describing: recieveData))")
                }
            case [.hasSpaceAvailable]:
                Log("\(streamName as NSString) stream has space")
                
                self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
                    [weak self] timer in
                    guard let self = self else { return }

                    if self.canWrite {
                        let message = "*** \(Date())\r\n"
                        guard let messageData = message.utf8DecodedData else { return }
                        let messageCount = messageData.count
                        let bytesWritten: Int = messageData.withUnsafeBytes() { bytes in
                            let buffer = (bytes.baseAddress?.assumingMemoryBound(to: UInt8.self))!
                            self.canWrite = false
                            
                            if let streams = self.streams {
                                return streams.outputStream.write(buffer, maxLength: messageCount)
                            } else {
                                return 0
                            }
                        }
                        if bytesWritten < messageCount {
                            // Handle writing less data than expected.
                        }
                    }
                }
                
                
            case [.endEncountered]:
                Log("\(streamName) stream end")
                self.stop()
            case [.errorOccurred]:
                let error = thisStream.streamError! as NSError
                Log("\(streamName) stream error \(error.domain) / \(error.code)")
                self.stop()
            default:
                fatalError()
        }
    }
}
