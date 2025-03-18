//
//  Dns.swift
//
//
//  Created by よういち on 2024/07/23.
//

#if os(macOS) || os(iOS)
import Foundation
#elseif canImport(Glibc)
import Glibc
import Foundation
#elseif canImport(Musl)
import Musl
import Foundation
#elseif os(Windows)
import ucrt
#else
#error("UnSupported platform")
#endif

import Resolving

//class Dns {
//    
////    fileprivate var state = __res_9_state()
//    fileprivate var state = __res_state()   //extern struct __res_state _res;
//
//    public init() {
////        res_9_ninit(&state)
//        res_init()
//    }
//    
//    deinit {
////        res_9_ndestroy(&state)
//        free(state)
//    }
//
//    /*
//     __res_state._u._ext.nsaddrs
//     __res_state._u._ext.nsmap
//     
//     ns_rr_rdata()
//     ↓
//     dn_expand()
//     ↓
//     gethostbyname()
//
//     #now
//     */
////    public func getservers() -> [res_9_sockaddr_union] {
//    public func getservers() -> [__res_state]? {
//        let maxServers = 3
//        var servers = [res_9_sockaddr_union](repeating: res_9_sockaddr_union(), count: maxServers)
//        let found = Int(res_9_getservers(&state, &servers, Int32(maxServers)))
//        
//        // filter is to remove the erroneous empty entry when there's no real servers
//        return Array(servers[0 ..< found]).filter() { $0.sin.sin_len > 0 }
//    }
//
////    public func getnameinfo(_ s: res_9_sockaddr_union) -> String {
//    public func getnameinfo(_ s: sockaddr_in6) -> String {
//        var s = s
//        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
//        
//        let _ = withUnsafePointer(to: &s) {
//            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
////                Darwin.getnameinfo($0, socklen_t(s.sin.sin_len),
////                                   &hostBuffer, socklen_t(hostBuffer.count),
////                                   nil, 0,
////                                   NI_NUMERICHOST)
//                gethostbyname($0)
//            }
//        }
//        
//        return String(cString: hostBuffer)
//    }
//}
/*
 Thank:
 https://stackoverflow.com/a/26480097

 Should Set Xcode Build Setting
    Other Linker Flag
        -l resolv

 About TXT Record Length:
    Max 255 chars by TXT record String(""). And be Admitted Save Multiple String in TXT record as Separate Space.
 */
struct Dns {
    /*
     About TXT Record Length:
     Max 255 chars by TXT record String(""). And be Admitted Save Multiple String in TXT record as Separate Space.
     */
    /*
     Rewrote ObjC code(fetchTXTRecords) as Swift Code.
     */
    static func getservers(_ domain: String) -> [String]? {
        // declare buffers / return array
        var answers = [String]()
        var answer = [CUnsignedChar](repeating: 0, count: 1024)
        // initialize resolver
#if os(iOS) || os(macOS)
        var msg: res_9_ns_msg = res_9_ns_msg()
        var rr: res_9_ns_rr = res_9_ns_rr()
        
        var state = __res_9_state()   //res_9_nquery()のとき使う
        res_9_ninit(&state)
//        res_9_init()
#elseif os(Linux)
        var msg: ns_msg = ns_msg()
        var rr: ns_rr = ns_rr()
        res_init()
#endif
        // send query. res_query returns the length of the answer, or -1 if the query failed
        /*
         int res_query(const char *, int, int, unsigned char *, int);
         */
        var rlen: Int32 = 0
#if os(iOS) || os(macOS)
            rlen = res_9_nquery(&state, domain, Int32(ns_c_in.rawValue), Int32(ns_t_txt.rawValue), &answer, Int32(answer.count))
#elseif os(Linux)
        rlen = res_query(domain, Int32(ns_c_in.rawValue), Int32(ns_t_txt.rawValue), &answer, Int32(answer.count))
#endif
        Log("\(rlen)")
//        Log("\(answer)")
        if rlen == -1 {
            return nil
        }
        
        // parse the entire message
#if os(iOS) || os(macOS)
            rlen = res_9_ns_initparse(answer, rlen, &msg)
#elseif os(Linux)
        rlen = ns_initparse(answer, rlen, &msg)
#endif
        Log("\(rlen)")
        if rlen < 0 {
           return nil
        }

        // get the number of messages returned
        /*
         #define ns_msg_count(handle, section) ((handle)._counts[section] + 0)
         */
        let rrmax: Int = Int(((msg)._counts.1 + 0))

        // iterate over each message
        for i in 0..<rrmax {
            // parse the answer section of the message
            /*
             int ns_parserr(ns_msg *, ns_sect, int, ns_rr *);
             */
#if os(iOS) || os(macOS)
            if (res_9_ns_parserr(&msg, ns_s_an, Int32(i), &rr) != 0) {
                Log()
                return nil
            }
#elseif os(Linux)
            if (ns_parserr(&msg, ns_s_an, Int32(i), &rr) != 0) {
                Log()
                return nil
            }
#endif            
            // obtain the record data
            /*
             #define ns_rr_rdata(rr)    ((rr).rdata + 0)
             */
//            let rd: u_char = ns_rr_rdata(rr)
            let rd = (rr.rdata + 0)
            
            // the first byte is the length of the data
            let length: size_t = size_t(rd[0])
            Log(length)
            // create and save a string from the C string
            var record: String = String(cString: (rd+1))    //as utf8 string
//            Log(record)
            //Remove Unicode Chars \u{FFFD}\u{0C} from UTF-8 String.
            record = record.padding(toLength: length, withPad: "", startingAt: 0)   //Truncate up to __ns.rr.rdata.length
            Log(record)
            answers.append(record)
        }
        return answers
    }
}
