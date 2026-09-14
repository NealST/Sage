//
//  ComposerSpellCheck.swift
//  Sage
//
//  Continuous spell checking for the composer's SwiftUI TextField. macOS 26
//  SwiftUI has no public spell-check API for TextField, so a zero-size
//  introspection view finds the backing NSTextView and flips the AppKit
//  toggles. Policy mirrors the skill editor: check spelling + grammar, never
//  auto-replace — prompts are full of identifiers, paths, and code.
//

import AppKit
import SwiftUI

extension View {
    /// Enables spell checking on the nearest vertical-axis TextField in the
    /// receiver's view tree. `isFocused` re-triggers the lookup so a text
    /// view mounted lazily on focus is still caught.
    func sageComposerSpellChecking(isFocused: Bool) -> some View {
        background(ComposerSpellCheckIntrospector(isFocused: isFocused))
    }
}

private struct ComposerSpellCheckIntrospector: NSViewRepresentable {
    let isFocused: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.applied
            || isFocused != context.coordinator.appliedForFocus
        else { return }
        context.coordinator.appliedForFocus = isFocused
        DispatchQueue.main.async {
            guard let scope = nsView.superview,
                  let textView = Self.firstTextView(in: scope)
            else { return }
            context.coordinator.applied = true
            textView.isContinuousSpellCheckingEnabled = true
            textView.isGrammarCheckingEnabled = true
            textView.isAutomaticSpellingCorrectionEnabled = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var applied = false
        var appliedForFocus: Bool?
    }

    /// The introspector sits directly behind the field, so the shared
    /// superview's subtree contains exactly the field's backing text view —
    /// the composer row hosts no other text views.
    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) { return textView }
        }
        return nil
    }
}
