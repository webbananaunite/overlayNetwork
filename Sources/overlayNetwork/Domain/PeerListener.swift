//
//  PeerListener.swift
//  blocks
//
//  Created by よういち on 2023/09/11.
//  Copyright © 2023 WEB BANANA UNITE Tokyo-Yokohama LPC. All rights reserved.
//

import Foundation
import Network

/*
 Use Only iOS Network Framework, Recommend use POSIX BSD Socket.
 
 Thank:
 https://developer.apple.com/documentation/network/building_a_custom_peer-to-peer_protocol
 */
var applicationServiceListener: PeerListener?

open class PeerListener {
    enum ServiceType {
        case applicationService
    }
    
    weak var delegate: PeerConnectionDelegate?
    var listener: NWListener?
    var name: String?
    let passcode: String?
    let type: ServiceType
    
    init(delegate: PeerConnectionDelegate, protocolDefinition: NWProtocolDefinition) {
        self.type = .applicationService
        self.delegate = delegate
        self.name = nil
        self.passcode = nil
        setupApplicationServiceListener(protocolDefinition: protocolDefinition)
    }
    
    func setupApplicationServiceListener(protocolDefinition: NWProtocolDefinition) {
        do {
            // Create the listener object.
            let listener = try NWListener(using: NWParameters.applicationService)
            self.listener = listener
            
            // Set the service to advertise.
            listener.service = NWListener.Service(applicationService: "TicTacToe")
            
            startListening(protocolDefinition: protocolDefinition)
        } catch {
            print("Failed to create application service listener")
            abort()
        }
    }
    
    func applicationServiceListenerStateChanged(newState: NWListener.State) {
        switch newState {
        case .ready:
            print("Listener ready for nearby devices")
        case .failed(let error):
            print("Listener failed with \(error), stopping")
            self.delegate?.displayAdvertiseError(error)
            self.listener?.cancel()
        case .cancelled:
            applicationServiceListener = nil
        default:
            break
        }
    }
    
    func listenerStateChanged(newState: NWListener.State) {
        switch self.type {
        case .applicationService:
            applicationServiceListenerStateChanged(newState: newState)
        }
    }

    func startListening(protocolDefinition: NWProtocolDefinition) {
        self.listener?.stateUpdateHandler = listenerStateChanged

        // The system calls this when a new connection arrives at the listener.
        // Start the connection to accept it, cancel to reject it.
        self.listener?.newConnectionHandler = { newConnection in
            if let delegate = self.delegate {
                if sharedConnection == nil {
                    // Accept a new connection.
                    sharedConnection = PeerConnection(connection: newConnection, delegate: delegate, protocolDefinition: protocolDefinition)
                } else {
                    // If a game is already in progress, reject it.
                    newConnection.cancel()
                }
            }
        }

        // Start listening, and request updates on the main queue.
        self.listener?.start(queue: .main)
    }
}
