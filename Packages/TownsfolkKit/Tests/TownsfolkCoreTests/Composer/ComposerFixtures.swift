import Foundation
import TownsfolkCore

/// What a composer test posts with: a fixed now, a text of a given length, and a store's
/// posts of yours read back.
enum ComposerFixtures {
    /// 2026-09-30T10:00:00Z, when every test's post is stored.
    static let now = StoreFixtures.date("2026-09-30T10:00:00Z")

    /// `count` characters of text with no spaces, so trimming leaves it whole.
    static func text(length count: Int) -> String {
        String(repeating: "a", count: count)
    }

    /// A composer over `store` that stores every post at ``now``.
    @MainActor
    static func composer(store: TownStore) -> ComposerViewModel {
        ComposerViewModel(store: store) { now }
    }

    /// Every post of yours `store` holds, newest first.
    static func yourPosts(in store: TownStore) async throws -> [Post] {
        let pageSize = 100
        return try await store.page(before: nil, limit: pageSize).entries.compactMap { entry in
            if case let .post(post) = entry, post.author == .you {
                return post
            }
            return nil
        }
    }

    /// Mika's post a reply may target, as the composer's chip shows it.
    static func mikasOven() -> ReplyTarget {
        ReplyTarget(
            postID: Post.ID(),
            author: .resident(name: "Mika"),
            text: "The oven made a goose noise again.",
        )
    }
}
