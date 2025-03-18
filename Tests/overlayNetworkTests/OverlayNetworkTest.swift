//
//  OverlayNetworkTest.swift
//  
//
//  Created by よういち on 2024/07/23.
//

import XCTest
@testable import blocks
//@testable import overlayNetworkObjc

final class OverlayNetworkTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testBootOverlayNetwork() throws {
        /*
         Communication with Using POSIX BSD Sockets.
         */
        let socket = Socket()
        let rawbuf: UnsafeMutableRawBufferPointer = UnsafeMutableRawBufferPointer.allocate(byteCount: Socket.MTU, alignment: MemoryLayout<CChar>.alignment)
        guard let ownNode = Node(ownNode: IpaddressV4.null, port: 0, premiumCommand: blocks.Command.other) else {
            return
        }
        socket.start(startMode: .registerMeAndIdling, tls: false, rawBufferPointer: rawbuf, node: ownNode, inThread: true, notifyOwnAddress: {
            ownAddress in
            /*
             Done Making Socket
             */
            LogCommunicate(ownAddress as Any)
        }) {
            sentDataNodeIp, dataRange in
            /*
             Received Data on Listening Bound Port.
             */
            Log(sentDataNodeIp as Any)
            Log(dataRange.count)
            Log(rawbuf) //UnsafeMutableRawBufferPointer(start: 0x000000014980be00, count: 1024)
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
