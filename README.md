# BlockChain Library Suite
[日本語](READMEjp.md)

## about blocks
blocks is a iOS library as introduce BlockChain System to your Apps, based on Satoshi Nakamoto's Paper,
for various purpose (*** Exclude exchangeable digital currency in cryptocurrency exchange ***) iOS App.  

Characteristically, blocks is pre-contained Activities in Social System (Government, Public, Private Sectors) as Birth Registration, Residential Record, Guarantor.

It is depend on overlayNetwork library.

## about overlayNetwork
overlayNetwork is a iOS library as Peer-to-Peer Overlay Network Communicate System, based on Distributed Hash Table Lookup Protocol MIT Laboratory's Paper named Chord.  

Nothing depending other libraries.

## about Testy
Testy is alternative to Basic Resident Register Card.  

It is made as Reference iOS App based on blocks and overlayNetwork libraries.

## download
blocks - BlockChain Library α version  
[download](https://github.com/webbananaunite/blocks)  
https://github.com/webbananaunite/blocks  
 
overlayNetwork - Peer-to-Peer Overlay Network Communicate Library α version  
[download](https://github.com/webbananaunite/overlayNetwork)  
https://github.com/webbananaunite/overlayNetwork  
 
Testy - Basic Resident Register Application α version  
[download](https://github.com/webbananaunite/Testy)  
https://github.com/webbananaunite/Testy  

## How to Use
### Swift Package (Recommended)
1) Open Testy Project or Your App Project in Xcode.  
2) File - Add Packages
3) Input following blocks URL to Search or Enter Package URL Box on UpRight.
https://github.com/webbananaunite/blocks
4) You see blocks library's README.md.
5) Tap Add Package Button on DownRight.
6) Make Sure there Added blocks library in Project - Frameworks, Libraries and Embeded Content.
7) Make Sure there Added The BlockChain Library Suite(blocks and overlayNetwork libraries) at Package Dependencies in Project Navigator in Xcode.
8) Modify {bootnodes} to First Booting Device's IP depending your local network in overlayNetwork/Domain/Dht.swift l.227  
* Alpha Version cause Runnable in Your Local Network Only.  
9) Xcode Build and Install Devices or Simulators.  
10) Open App and Tap "生体認証" Button.  
11) Wait Around 8 min. up to Done Initialize DHC table.  
### Carthage
- $ cd your project directory
- $ echo 'github "webbananaunite/blocks" "carthage"' > Cartfile
- $ carthage update --use-xcframeworks
### CocoaPods
- $ cd your project directory
- $ pod init
- $ vi Podfile
```
target 'target name in your App proj' do
  use_frameworks!
	pod 'blocks-blockchain'
end
```
- $ pod install
- Open your app.xcworkspace created by pod.

## limitations
Alpha Version cause Runnable in Your Local Network Only.  

## license
blocks library & overlayNetwork library & Testy is published under MIT License,  
as embedding your apps, any who can use any purpuse (*** Exclude exchangeable digital currency in cryptocurrency exchange ***). by free.

## prohibited matter
Use as exchangeable digital currency in cryptocurrency exchange is PROHIBITED.

## description
### language:  
- SwiftUI (Protocol Oriented) 
- C++ (Metal) 
- objc (DNS resolv)

### using 3rd party libraries
Nothing, but program include other one copyrights.  
- QuadKey - Microsoft Corporation  
- SHA-512 - Aaron D. Gifford

### programming architecture:  
around DDD, Onion (Protocol Oriented)

### byteOrder:  
- Distributed Hash Table (Finger table) address  
Little Endian

- nonce  
Little Endian

### cpu, gpu
nonce calculator is choosable cpu or gpu.

## status
Alpha  

Have NOT all done functions implementation.  
- ex. Leaving and returning from DHT Network in overlayNetwork.  

All implemented version is planned Release at May 2024.  

Interested in Building Social Infrastructure by Peer-to-Peer Overlay Network, Block-chain System, On volunteer, please join my Project.  

but, Don't accept application from one related to Cryptocurrency Exchange.  

Let's Have fun!
