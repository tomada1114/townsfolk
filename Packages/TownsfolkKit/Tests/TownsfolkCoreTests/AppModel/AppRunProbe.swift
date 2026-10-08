import Foundation
import Observation

/// An engine lifecycle observed through its real cancellable wait, without a new port.
@MainActor
@Observable
final class AppRunProbe {
    private static let waitSeconds = 60
    private static let wait = Duration.seconds(waitSeconds)
    let clock = EngineClock()
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var speedChanges = 0
    private(set) var isCancelling = false
    var holdsCancellation = false
    private var cancellation: CheckedContinuation<Void, Never>?

    func run() async throws {
        starts += 1
        do { try await clock.sleep(for: Self.wait) } catch {
            isCancelling = true
            if holdsCancellation {
                await withCheckedContinuation { cancellation = $0 }
            }
            stops += 1
            isCancelling = false
            throw error
        }
    }

    func speedChanged() {
        speedChanges += 1
    }

    func finishCancellation() {
        cancellation?.resume()
        cancellation = nil
    }
}
