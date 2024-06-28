//
//  Int32+.swift
//  overlayNetwork
//
//  Created by よういち on 2024/04/16.
//

import Foundation

public extension Int32 {
    /*
     Thank:
     https://stackoverflow.com/a/26181323
     */
    func pad(string : String, toSize: Int) -> String {
      var padded = string
      for _ in 0..<(toSize - string.count) {
        padded = "0" + padded
      }
      return padded
    }
    var binaryRepresent: String {
        let binaryString = String(self, radix: 2)
        return self.pad(string: binaryString, toSize: 32)
    }
}
