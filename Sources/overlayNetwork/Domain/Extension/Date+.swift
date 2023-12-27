//
//  Date+.swift
//  overlayNetwork
//
//  Created by よういち on 2023/09/06.
//

import Foundation

public extension Date {
    /*
     UTC String to Date
     
     Date = "2023-10-17T00:00:00.000Z".date
     
     in String extension
     */
    func date(from utcString: String) -> Date? {
        utcString.date
    }
    
    /*
     Date to UTC String as MilliSeconds

     UTC Formatted String:
        2023-09-06T06:16:41.600Z
     */
    var toUTCString: String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions.insert(.withFractionalSeconds)  //ms
        
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let utcTimeString = dateFormatter.string(from: self)
        Log(utcTimeString)  //2022-09-02T08:38:42.940Z
        return utcTimeString
    }
    var utcTimeString: String {
        toUTCString
    }
    
    static var null: Date {
        Date(timeIntervalSince1970: 0)
    }

    static func getDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, nanosecond: Int) -> Date? {
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.timeZone = TimeZone(abbreviation: "UTC")
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.nanosecond = nanosecond
        var calendar = Calendar(identifier: .gregorian)
        if let utcTimeZone = TimeZone(identifier: "UTC") {
            calendar.timeZone = utcTimeZone
            return calendar.date(from: dateComponents)
        }
        return nil
    }

    func getYMD() -> (Int,Int,Int,Int,Int,Int,Int) {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: self)     // 2022
        let month = calendar.component(.month, from: self)   // 1 origin
        let day = calendar.component(.day, from: self)       // 1 origin
        let hour = calendar.component(.hour, from: self)     // 9
        let minute = calendar.component(.minute, from: self) // 59
        let second = calendar.component(.second, from: self) // 59
        let nanosecond = calendar.component(.nanosecond, from: self)  //9桁数値: 320412020
        return (year, month, day, hour, minute, second, nanosecond)
    }
}
