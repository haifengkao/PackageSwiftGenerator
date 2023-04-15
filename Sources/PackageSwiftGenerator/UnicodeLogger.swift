//
// Created by Hai Feng Kao on 2023/4/15.
//

import Foundation

/// a logger which put strings into Package.swift
struct UnicodeLogger: TextOutputStream {
    static let header = """
    // swift-tools-version: 5.7
    // The swift-tools-version declares the minimum version of Swift required to build this package.

    import PackageDescription

    let package = 
    """
    var logged: String = Self.header
    mutating func write(_ string: String) {
        let lines = string.split(separator: "\n")
        for line in lines {
            handleLine(String(line))
        }
    }

    mutating func handleLine(_ line: String) {
        guard !line.isEmpty, line != "\n" else {
            return
        }

        logged += line + "\n"
    }
}
