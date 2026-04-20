//
//  AccessibilityChecker.swift
//  Gnomon
//
//  Thin wrapper around AXIsProcessTrustedWithOptions. Used to detect and
//  prompt for Accessibility permission — required for global hotkeys.
//

import ApplicationServices
import Foundation

public enum AccessibilityChecker {
    /// Returns true if Accessibility permission is granted.
    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission.
    /// Returns the current trusted state (which will be false on first call since
    /// the user must grant from System Settings — this just triggers the prompt).
    @discardableResult
    public static func requestAccess() -> Bool {
        // The constant kAXTrustedCheckOptionPrompt expands to
        // "AXTrustedCheckOptionPrompt"; we inline it here to stay clear of
        // Swift 6 strict-concurrency warnings about global mutables.
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options)
    }
}
