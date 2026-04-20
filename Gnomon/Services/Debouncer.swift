//
//  Debouncer.swift
//  Gnomon
//
//  MainActor-isolated debouncer. Cancels any pending action when a new one
//  is scheduled, then runs after `delay` elapses with no further schedules.
//

import Foundation

@MainActor
public final class Debouncer {
    private let delay: Duration
    private var pending: Task<Void, Never>?

    public init(delay: Duration = .milliseconds(200)) {
        self.delay = delay
    }

    public func schedule(_ action: @escaping @MainActor () async -> Void) {
        pending?.cancel()
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }
            await action()
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }
}
