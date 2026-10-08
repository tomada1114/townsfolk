import Foundation

/// Failed reads keep their scope until a store change or clock tick can retry them.
struct TimelinePendingRead {
    var needsNewest = true
    var includesOlder = false
    var needsCatchup = false
    var postIDs: Set<Post.ID> = []
    var cursor: TimelineInsertionCursor?
    var isReading = false
    var revision = 0
}

/// Reading the store and keeping time: the actions that wait.
extension TimelineViewModel {
    private static let millisecondsPerSecond: Double = 1_000

    /// How many rows a page asks for.
    var pageSize: Int {
        max(1, environment.pageSize)
    }

    private static func posts(namedBy change: TownStoreChange) -> [Post.ID] {
        switch change {
        case let .sceneStored(posts):
            posts

        case let .yourPostStored(post):
            [post]

        case .eventEnded, .eventStarted, .everythingDeleted, .founded:
            []

        case .interestExcluded, .lastRanChanged, .moveRecorded:
            []

        case .nextOrdinarySceneDueChanged, .pendingResponsesChanged, .postExcluded:
            []
        }
    }

    /// Loads the newest page, then follows the store's committed steps and the clock
    /// until cancelled — the view calls it from `.task`, so it stops with the view. A
    /// timeline with no store only keeps time.
    public func run() async {
        guard let store else {
            await keepTime()
            return
        }
        let generation = loadGeneration
        let observation = await store.timelineObservation()
        guard generation == loadGeneration, !Task.isCancelled else {
            return
        }
        let retainedBoundary = pendingRead.cursor != nil
        if !retainedBoundary {
            pendingRead.cursor = observation.cursor
            pendingRead.includesOlder = observation.failedBoundary
        }
        pendingRead.needsCatchup = pendingRead.needsCatchup || retainedBoundary
            || observation.failedBoundary
        await loadNewest(from: store)
        if !pendingRead.needsNewest, pendingRead.needsCatchup {
            await catchUp(from: store)
        }
        await withDiscardingTaskGroup { group in
            group.addTask { await self.follow(observation.changes, from: store) }
            group.addTask { await self.keepTime() }
        }
    }

    /// A row came into view; the last loaded one loads the next older page, until a page
    /// comes back shorter than the page size.
    public func rowAppeared(_ id: TimelineItem.Key) async {
        guard id == items.last?.id,
              canLoadOlder,
              !isLoadingOlder,
              let store,
              let cursor = olderCursor
        else {
            return
        }
        isLoadingOlder = true
        let generation = loadGeneration
        let page: TimelinePage
        do {
            page = try await store.page(before: cursor, limit: pageSize)
        } catch {
            olderPageFailed(startedIn: generation)
            AppLog.timeline
                .error("older page failed: \(String(describing: error), privacy: .public)")
            return
        }
        // Shown, and the flag cleared, before the quotes are read, so the row that is now
        // last can ask for the next page as soon as it appears.
        olderPageRead(page, startedIn: generation)
        AppLog.timeline.debug("older page loaded: \(page.entries.count, privacy: .public) rows")
        await fetchMissingQuotes(from: store)
    }

    private func loadNewest(from store: TownStore) async {
        let generation = loadGeneration
        pendingRead.needsNewest = true
        guard !pendingRead.isReading else {
            return
        }
        pendingRead.isReading = true
        defer { pendingRead.isReading = false }
        let revision = pendingRead.revision
        do {
            let town = try await store.town()
            let residents = try await store.residents()
            var pages = try await [store.page(before: nil, limit: pageSize)]
            while pendingRead.includesOlder, let cursor = pages.last?.older {
                try Task.checkCancellation()
                try await pages.append(store.page(before: cursor, limit: pageSize))
            }
            guard generation == loadGeneration, !Task.isCancelled else {
                return
            }
            townRead(town, residents: residents)
            for page in pages {
                pageLoaded(page)
            }
            pendingRead.needsNewest = revision != pendingRead.revision
            if !pendingRead.needsNewest {
                pendingRead.includesOlder = false
            }
        } catch is CancellationError {
            return
        } catch {
            AppLog.timeline
                .error("newest page failed: \(String(describing: error), privacy: .public)")
        }
        await fetchMissingQuotes(from: store)
    }

    private func follow(_ changes: AsyncStream<TownStoreChange>, from store: TownStore) async {
        for await change in changes {
            await storeChanged(change, in: store)
        }
    }

    /// Re-reads what a committed step may have changed: the posts it names, and the
    /// new insertions for anything else — an event, a move, a founding — since a step
    /// announces itself, not each thing it wrote (``TownStoreChange``).
    private func storeChanged(_ change: TownStoreChange, in store: TownStore) async {
        // Last, so the clock's next wait counts any post that now waits for its time.
        defer { sleeper?.cancel() }
        if change == .everythingDeleted {
            everythingDeleted()
            return
        }
        if case .yourPostStored = change {
            yourPostStored()
        }
        pendingRead.revision += 1
        if change == .founded {
            pendingRead.includesOlder = true
            await loadNewest(from: store)
            return
        }
        if pendingRead.needsNewest || log.isEmpty {
            pendingRead.postIDs.formUnion(Self.posts(namedBy: change))
            pendingRead.needsCatchup = true
            await loadNewest(from: store)
            return
        }
        await catchUp(from: store, posts: Self.posts(namedBy: change))
    }

    private func catchUp(from store: TownStore, posts: [Post.ID] = []) async {
        let generation = loadGeneration
        pendingRead.needsCatchup = true
        pendingRead.postIDs.formUnion(posts)
        pendingRead.revision += 1
        guard !pendingRead.isReading else {
            return
        }
        pendingRead.isReading = true
        let revision = pendingRead.revision
        await readChanges(from: store, generation: generation)
        pendingRead.isReading = false
        if generation == loadGeneration, revision != pendingRead.revision, !Task.isCancelled {
            await catchUp(from: store)
        }
    }

    private func readChanges(from store: TownStore, generation: Int) async {
        let revision = pendingRead.revision
        let requestedPosts = pendingRead.postIDs
        do {
            let town = try await store.town()
            let residents = try await store.residents()
            var entries: [TimelineEntry] = []
            for id in requestedPosts {
                if let post = try await store.post(id) {
                    entries.append(.post(post))
                }
            }
            guard let cursor = pendingRead.cursor else {
                return
            }
            try Task.checkCancellation()
            let inserted = try await store.timelineInsertions(after: cursor)
            entries += inserted.entries
            guard generation == loadGeneration, !Task.isCancelled else {
                return
            }
            townRead(town, residents: residents)
            entriesArrived(entries)
            pendingRead.cursor = inserted.cursor
            pendingRead.postIDs.subtract(requestedPosts)
            pendingRead.needsCatchup = revision != pendingRead.revision
        } catch is CancellationError {
            return
        } catch {
            AppLog.timeline
                .error("change read failed: \(String(describing: error), privacy: .public)")
        }
        await fetchMissingQuotes(from: store)
    }

    /// Your post shows at once, at the top (requirements.md:224): scrolled away, the
    /// timeline goes back to the top first, showing what waited, so the post arrives there
    /// rather than counting in the pill.
    private func yourPostStored() {
        guard !isAtTop else {
            return
        }
        scrollToLatestChosen()
    }

    /// Sleeps until the next post is due or the times need refreshing, whichever is
    /// sooner, then reveals what is due — until cancelled. A post that starts to wait
    /// meanwhile cancels the sleep, so it is counted in the next one.
    private func keepTime() async {
        while !Task.isCancelled {
            let wait = nextWait()
            let clock = environment.clock
            // A cancelled sleep is the early wake, not a failure, so its error is dropped.
            let nap = Task<Void, Never> { try? await clock.sleep(for: wait) }
            sleeper = nap
            await withTaskCancellationHandler {
                await nap.value
            } onCancel: {
                nap.cancel()
            }
            sleeper = nil
            guard !Task.isCancelled else {
                return
            }
            clockTicked()
            if let store {
                if pendingRead.needsNewest {
                    await loadNewest(from: store)
                }
                if !pendingRead.needsNewest, pendingRead.needsCatchup {
                    await catchUp(from: store)
                }
                await fetchMissingQuotes(from: store)
            }
        }
    }

    private func nextWait() -> Duration {
        guard let due = log.nextDue else {
            return Self.refreshInterval
        }
        let milliseconds = max(0, due.timeIntervalSince(environment.now())) * Self
            .millisecondsPerSecond
        return min(.milliseconds(Int64(milliseconds.rounded(.up))), Self.refreshInterval)
    }

    private func fetchMissingQuotes(from store: TownStore) async {
        let wanted = missingQuotes
        guard !wanted.isEmpty else {
            return
        }
        let generation = loadGeneration
        var found: [Post] = []
        for id in wanted {
            do {
                if let post = try await store.post(id) {
                    found.append(post)
                }
            } catch {
                AppLog.timeline
                    .error("quote read failed: \(String(describing: error), privacy: .public)")
            }
        }
        quotesFetched(found, asked: wanted, startedIn: generation)
    }
}
