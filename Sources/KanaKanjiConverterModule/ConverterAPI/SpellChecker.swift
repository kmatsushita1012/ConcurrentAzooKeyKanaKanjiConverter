//
//  SpellChecker.swift
//
//
//  Created by ensan on 2023/05/20.
//

import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

actor SpellChecker {
    init() {}

    #if os(iOS) || os(tvOS) || os(visionOS)
    // UITextChecker is main-actor isolated on iOS-family platforms.
    // Use a static instance to avoid capturing `self` in main-actor closures.
    @MainActor private static let checker = UITextChecker()
    #elseif os(macOS)
    private let checker = NSSpellChecker.shared
    #endif

    func completions(forPartialWordRange range: NSRange, in string: String, language: String) async -> [String]? {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return await MainActor.run {
            Self.checker.completions(forPartialWordRange: range, in: string, language: language)
        }
        #elseif os(macOS)
        return checker.completions(forPartialWordRange: range, in: string, language: language, inSpellDocumentWithTag: 0)
        #else
        return nil
        #endif
    }
}
