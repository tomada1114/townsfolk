/// A port: "can the town window be seen, and is the app active and the Mac awake?",
/// reported as a stream rather than asked.
///
/// The observing counterpart of the pull-style ``FrontmostAppProviding``: the town has to
/// stop the moment its window can no longer be seen, so the adapter pushes every change
/// instead of waiting to be asked. Core declares the protocol,
/// `TownsfolkPlatform` holds the AppKit adapter that watches the window's occlusion, the
/// app's activation, and the Mac's sleep, tests substitute `FakeWindowPresenceProvider`,
/// and `App/` picks the real one.
///
/// Its method is `@MainActor` because every source the adapter watches is bound to the
/// main run loop; stating it on the port saves each adapter from justifying an isolation
/// assumption of its own (`integrating-system-apis` › The shape).
public protocol WindowPresenceProviding: Sendable {
    /// A stream of presence values for one observer.
    ///
    /// The promises, each checked by `WindowPresenceProvidingContract` in
    /// `TownsfolkTestSupport` against the fake (`just test`) and the real adapter
    /// (`just test-local`); a new clause is stated here first, then added there:
    ///
    /// - The first element is the current presence, yielded without waiting for anything
    ///   to change.
    /// - Every call starts an observation of its own: a second observer gets its own first
    ///   value while the first is still observing.
    ///
    /// After the first element, a complete value follows every change to any of the three
    /// facts. An implementation reports and decides nothing: it may yield a value equal to
    /// the one before, and the consumer de-duplicates. When the consumer stops — its task
    /// is cancelled or the stream is dropped — the implementation releases everything it
    /// registered for that observer.
    @MainActor
    func presenceUpdates() -> AsyncStream<WindowPresence>
}
