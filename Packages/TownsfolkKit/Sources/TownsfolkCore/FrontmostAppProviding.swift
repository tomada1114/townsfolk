/// The frontmost application, as a value Core can reason about.
///
/// A port answers in types Core owns, never in the OS type the adapter used
/// (`NSRunningApplication` here): that is what keeps Core testable with a fake and
/// free of AppKit.
public struct FrontmostApp: Equatable, Sendable {
    /// The application's display name.
    public let name: String
    /// Its bundle identifier, when it has one — some processes do not.
    public let bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

/// A port: "which application is frontmost right now?", asked in Core's own vocabulary.
///
/// This is the template's worked example of the ports-and-adapters boundary
/// (`docs/architecture.md`). Core declares the protocol, `TownsfolkPlatform` holds the
/// adapter that answers it with `NSWorkspace`, tests substitute a fake, and `App/` —
/// the composition root — decides which one a view model gets. Nothing below `App/`
/// knows which implementation it is talking to.
///
/// Ports are `Sendable` and take and return value types, so an adapter can be handed
/// across actors and a Core caller never has to reason about the OS object behind it.
///
/// This one is deliberately **pull-style**: it answers with a snapshot of the moment it
/// is asked and pushes nothing, so a caller that wants a current answer asks again (the
/// app does so whenever its scene becomes active). An app that needs live updates —
/// following every app switch, not just its own activations — adds a second,
/// observing port whose adapter subscribes to `NSWorkspace`'s activation notifications
/// and hands Core a stream; it does not turn this one into a publisher.
public protocol FrontmostAppProviding: Sendable {
    /// The application frontmost at the moment of the call, or `nil` when there is none
    /// or the OS declines to say (a sandboxed or background process may get no answer).
    ///
    /// A non-`nil` answer always names the application: its `name` is never empty. An
    /// implementation that finds no usable name answers `nil` rather than inventing one,
    /// so Core alone decides what "unavailable" reads like. Every call answers afresh
    /// and keeps this promise, the first and every later one alike.
    ///
    /// `FrontmostAppProvidingContract` in `TownsfolkTestSupport` checks these clauses against
    /// the fake (`just test`) and the real adapter (`just test-local`); a new clause is
    /// stated here first, then added there.
    func currentFrontmostApp() -> FrontmostApp?
}
