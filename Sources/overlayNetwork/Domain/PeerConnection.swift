//
//  PeerConnection.swift
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
var sharedConnection: PeerConnection?

public protocol PeerConnectionDelegate: AnyObject {
    func connectionReady()
    func connectionFailed()
    func receivedMessage(content: Data?, message: NWProtocolFramer.Message)
    func displayAdvertiseError(_ error: NWError)
}

open class PeerConnection {
    weak var delegate: PeerConnectionDelegate?
    var connection: NWConnection?
    let endpoint: NWEndpoint?
    let initiatedConnection: Bool
    
    // Create an outbound connection when the user initiates a game via DeviceDiscoveryUI.
    init(endpoint: NWEndpoint, delegate: PeerConnectionDelegate, protocolDefinition: NWProtocolDefinition) {
        self.delegate = delegate
        self.endpoint = endpoint
        self.initiatedConnection = true

        // Create the NWConnection to the supplied endpoint.
        let connection = NWConnection(to: endpoint, using: NWParameters.applicationService)
        self.connection = connection

        startConnection(protocolDefinition: protocolDefinition)
    }

    // Handle an inbound connection when the user receives a game request.
    init(connection: NWConnection, delegate: PeerConnectionDelegate, protocolDefinition: NWProtocolDefinition) {
        self.delegate = delegate
        self.endpoint = nil
        self.connection = connection
        self.initiatedConnection = false

        startConnection(protocolDefinition: protocolDefinition)
    }

    // Handle starting the peer-to-peer connection for both inbound and outbound connections.
    func startConnection(protocolDefinition: NWProtocolDefinition) {
        guard let connection = connection else {
            return
        }
        
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                print("\(connection) established")
                
                // When the connection is ready, start receiving messages.
                self?.receiveNextMessage(protocolDefinition: protocolDefinition)
                
                // Notify the delegate that the connection is ready.
                if let delegate = self?.delegate {
                    delegate.connectionReady()
                }
            case .failed(let error):
                print("\(connection) failed with \(error)")
                
                // Cancel the connection upon a failure.
                connection.cancel()
                
                if let endpoint = self?.endpoint, let initiated = self?.initiatedConnection,
                   initiated && error == NWError.posix(.ECONNABORTED) {
                    // Reconnect if the user suspends the app on the nearby device.
                    let connection = NWConnection(to: endpoint, using: NWParameters.applicationService)
                    self?.connection = connection
                    self?.startConnection(protocolDefinition: protocolDefinition)
                } else if let delegate = self?.delegate {
                    // Notify the delegate when the connection fails.
                    delegate.connectionFailed()
                }
            default:
                break
            }
        }
        
        // Start the connection establishment.
        connection.start(queue: .main)
    }

    // Receive a message, deliver it to your delegate, and continue receiving more messages.
    func receiveNextMessage(protocolDefinition: NWProtocolDefinition) {
        guard let connection = connection else {
            return
        }

        connection.receiveMessage { (content, context, isComplete, error) in
            // Extract your message type from the received context.
            if let gameMessage = context?.protocolMetadata(definition: protocolDefinition) as? NWProtocolFramer.Message {
                self.delegate?.receivedMessage(content: content, message: gameMessage)
            }
            if error == nil {
                // Continue to receive more messages until you receive an error.
                self.receiveNextMessage(protocolDefinition: protocolDefinition)
            }
        }
    }
}
