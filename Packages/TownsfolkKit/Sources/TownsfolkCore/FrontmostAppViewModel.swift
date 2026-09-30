import Foundation
import Observation

/// Observable presentation state over a ``FrontmostAppProviding`` port.
///
/// The Core half of the worked example: it holds the port, not an adapter, so
/// `TownsfolkCoreTests` drives it with a fake and `App/` hands it the `NSWorkspace`-backed
/// adapter from `TownsfolkPlatform`. Everything a reader can observe — including the
/// "nothing is frontmost" wording — is decided here, where the coverage floor sees it.
@MainActor
@Observable
public final class FrontmostAppViewModel {
    /// The last answer the port gave, or `nil` before the first ``refresh()``.
    public private(set) var frontmostApp: FrontmostApp?

    private let provider: any FrontmostAppProviding

    /// The whole line a view renders for the current answer, from Core's String Catalog.
    ///
    /// A complete sentence per state rather than a fixed prefix around a swapped-in
    /// fragment: a translation can then reorder or reword the line around the name. The
    /// unavailable state covers both "not asked yet" and "the port answered `nil`".
    public var label: LocalizedStringResource {
        guard let name = frontmostApp?.name else {
            return LocalizedStringResource(
                "frontmostApp.unavailable",
                defaultValue: "Frontmost: —",
                bundle: .module,
                comment: "Footnote shown when no application is frontmost, or before the app has asked.",
            )
        }
        return LocalizedStringResource(
            "frontmostApp.label",
            defaultValue: "Frontmost: \(name)",
            bundle: .module,
            comment: "Footnote naming the application that is frontmost. The argument is that application's name.",
        )
    }

    /// Creates the view model over `provider`. Asking the OS in an initializer would
    /// make construction a side effect, so nothing is read until ``refresh()``.
    public init(provider: any FrontmostAppProviding) {
        self.provider = provider
    }

    /// Asks the port again and publishes whatever it answered, `nil` included.
    ///
    /// Nothing calls this for you: ``FrontmostAppProviding`` is a pull-style port, so
    /// state here is only as fresh as the last caller made it. The app refreshes when
    /// its scene becomes active; a live-updating app would observe an OS notification
    /// through a second port rather than poll this one.
    ///
    /// Also the template's worked example of a log call (``AppLog``): another
    /// application's name is data about the person using this Mac, so it is
    /// interpolated `.private` and the unified log redacts it unless someone
    /// deliberately enables private data. The part that is safe to read at a glance —
    /// that a refresh happened, and whether the port answered at all — stays public.
    public func refresh() {
        let answer = provider.currentFrontmostApp()
        frontmostApp = answer
        AppLog.frontmostApp.debug(
            """
            refresh: answered=\(answer != nil, privacy: .public) \
            name=\(answer?.name ?? "", privacy: .private)
            """,
        )
    }
}
