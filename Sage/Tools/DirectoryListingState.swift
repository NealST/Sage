//
//  DirectoryListingState.swift
//  Sage
//

import Foundation

struct DirectoryListingState {
    var url: URL
    var depth: Int
    var currentDepth: Int
    var skipHidden: Bool
    var lines: [String]
    var truncated: Bool
}
