//
//  DesignTokens.swift
//  Sage
//

import SwiftUI

enum SageDesign {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Raycast AI–style floating panel.
    enum Panel {
        static let width: CGFloat = 920
        static let height: CGFloat = 580
        static let sidebarWidth: CGFloat = 240
        static let cornerRadius: CGFloat = 16
        static let topOffset: CGFloat = 96
        static let shadowPad: CGFloat = 16
    }

    /// Legacy aliases used by spring helpers during transition.
    enum HUD {
        static let width = Panel.width
        static let minHeight = Panel.height
        static let maxHeight = Panel.height
        static let cornerRadius = Panel.cornerRadius
        static let horizontalInset: CGFloat = 14
        static let verticalInset: CGFloat = 12
        static let topOffset = Panel.topOffset
    }

    enum Typography {
        static let inputSize: CGFloat = 15
        static let bodySize: CGFloat = 13
        static let captionSize: CGFloat = 12
        static let titleSize: CGFloat = 15
    }

    enum Motion {
        static let expandResponse: CGFloat = 0.32
        static let expandDampingRatio: CGFloat = 1.0
        static let contentCrossFade: Animation = .easeOut(duration: 0.18)
        static let reducedCrossFade: Animation = .easeOut(duration: 0.12)
    }

    enum Symbol {
        static let brand = "leaf.fill"
        static let returnKey = "return"
        static let settings = "gearshape"
        static let newChat = "square.and.pencil"
        static let search = "magnifyingglass"
        static let stepPending = "circle"
        static let stepRunning = "circle.dotted"
        static let stepSuccess = "checkmark.circle.fill"
        static let stepFailed = "xmark.circle.fill"
        static let tools = "wrench.and.screwdriver"
        static let skills = "book.closed"
        static let mcp = "server.rack"
    }
}
