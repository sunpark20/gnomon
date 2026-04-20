//
//  ProcessRunner.swift
//  Gnomon
//
//  Thin async wrapper around Foundation.Process for calling external CLIs.
//  Captures both stdout and stderr. Non-zero exit code throws.
//

import Foundation

public enum ProcessRunner {
    public enum RunError: Error, LocalizedError {
        case executableNotFound(path: String)
        case executionFailed(exitCode: Int32, stderr: String)

        public var errorDescription: String? {
            switch self {
            case let .executableNotFound(path):
                "Executable not found: \(path)"
            case let .executionFailed(code, stderr):
                "Process exited with code \(code): \(stderr)"
            }
        }
    }

    /// Run an executable and return its stdout.
    ///
    /// Uses Process.terminationHandler (declared @Sendable in Foundation) to resume the continuation.
    /// Throws `executionFailed` on non-zero exit code, passing stderr (or stdout fallback) as context.
    public static func run(
        _ executable: String,
        args: [String] = []
    ) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw RunError.executableNotFound(path: executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = args

            let outPipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = errPipe

            task.terminationHandler = { proc in
                let stdoutData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderrData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: RunError.executionFailed(
                        exitCode: proc.terminationStatus,
                        stderr: stderr.isEmpty ? stdout : stderr
                    ))
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
