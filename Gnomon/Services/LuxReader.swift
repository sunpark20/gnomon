//
//  LuxReader.swift
//  Gnomon
//
//  Reads the MacBook's ambient light sensor value by invoking
//  `/usr/libexec/corebrightnessdiag status-info` and parsing
//  the `AggregatedLux` key from its plist output.
//

import Foundation

public struct LuxReader: Sendable {
    public enum ReadError: Error, LocalizedError {
        case valueNotFound
        case invalidOutput

        public var errorDescription: String? {
            switch self {
            case .valueNotFound: "AggregatedLux key not found in corebrightnessdiag output"
            case .invalidOutput: "corebrightnessdiag returned invalid output"
            }
        }
    }

    public static let defaultPath = "/usr/libexec/corebrightnessdiag"

    public let executablePath: String

    public init(executablePath: String = LuxReader.defaultPath) {
        self.executablePath = executablePath
    }

    /// Returns the most recent aggregated lux reading from the built-in ALS.
    ///
    /// Uses the `AggregatedLux` key which macOS itself uses for auto-brightness
    /// decisions. Value is in lux (physical illuminance).
    public func currentLux() async throws -> Double {
        let stdout = try await ProcessRunner.run(executablePath, args: ["status-info"])
        return try Self.extractAggregatedLux(from: stdout)
    }

    /// Parses the textual output and pulls out the `AggregatedLux` number.
    ///
    /// The output mixes XML-plist and Objective-C description dumps. We first
    /// try the Objective-C dictionary form (`AggregatedLux = 109.17;`) because
    /// it's simpler and stable; fall back to the XML form.
    static func extractAggregatedLux(from output: String) throws -> Double {
        if let value = extractObjCStyle(key: "AggregatedLux", from: output) {
            return value
        }
        if let value = extractXMLPlistStyle(key: "AggregatedLux", from: output) {
            return value
        }
        throw ReadError.valueNotFound
    }

    private static func extractObjCStyle(key: String, from text: String) -> Double? {
        // Matches `  AggregatedLux = "109.17";` or `  AggregatedLux = 109.17;`
        let pattern = #"\b\#(key)\s*=\s*"?(-?[0-9]+(?:\.[0-9]+)?)"?\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[numberRange])
    }

    private static func extractXMLPlistStyle(key: String, from text: String) -> Double? {
        // Matches `<key>AggregatedLux</key>\s*<real>109.17</real>`
        let pattern = #"<key>\#(key)</key>\s*<real>(-?[0-9]+(?:\.[0-9]+)?)</real>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[numberRange])
    }
}
