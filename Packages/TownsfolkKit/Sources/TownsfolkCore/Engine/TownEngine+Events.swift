import Foundation

/// Events starting and ending (requirements §3.6; REQ-001–REQ-004 of #25): rules decide
/// whether one starts, which kind, and for how long; the model only writes its one line.
extension TownEngine {
    /// The kinds the rules record themselves, never drawn even if a table listed one.
    private static let fixedKinds: Set<EventKindID> = [.moveIn, .moveOut, .founding]

    /// Marks every ongoing event whose end has come as ended, each in its own
    /// transaction, before anything is drawn (REQ-001). An ended event stays in the log.
    func endEvents(at now: Date) async throws(TownStoreError) {
        let ended = try await store.ongoingEvents().filter { $0.endsAt <= now }
        for event in ended {
            try await store.endEvent(event.id)
        }
        if !ended.isEmpty {
            EngineLog.recordEventsEnded(ended.count)
        }
    }

    /// Draws whether an event starts after `running` seconds of running time, and starts
    /// one if so: a kind uniformly among the drawable kinds not ongoing, while fewer than
    /// `Tuning.events.maxOngoingEvents` are; a duration within its range; and a description
    /// from the model, stored in one transaction (REQ-002, REQ-003). A refused description
    /// is retried with another kind, at most `Tuning.generation.refusalRetriesPerTurn`
    /// times; any other failure, or a description out of bounds, starts nothing (REQ-004).
    /// - Throws: `CancellationError` when the calling task is cancelled; nothing is stored.
    func drawEvent(running: TimeInterval, at now: Date) async throws {
        guard generator.nextUnit() < rules.eventChance(running: running) else {
            return
        }
        let town: Town
        let ongoing: [TownEvent]
        do throws(TownStoreError) {
            guard let founded = try await store.town() else {
                EngineLog.recordEventDropped(.notFounded)
                return
            }
            town = founded
            ongoing = try await store.ongoingEvents()
        } catch {
            EngineLog.recordEventDropped(.storeFailed(error))
            return
        }
        guard ongoing.count < tuning.events.maxOngoingEvents else {
            EngineLog.recordEventDropped(.ongoingCap)
            return
        }
        let open = seedTables.eventKinds.filter { kind in
            !Self.fixedKinds.contains(kind.id) && !ongoing.contains { $0.kind == kind.id }
        }
        try await startOne(of: open, in: town, at: now)
    }

    /// Picks a kind of `open` uniformly and asks for its description, trying another kind
    /// after a refusal while attempts are left; starts the first one described.
    private func startOne(
        of kinds: [SeedTables.EventKind],
        in town: Town,
        at now: Date,
    ) async throws {
        var open = kinds
        let attempts = 1 + max(0, tuning.generation.refusalRetriesPerTurn)
        for _ in 0 ..< attempts {
            guard !open.isEmpty else {
                EngineLog.recordEventDropped(.everyKindOngoing)
                return
            }
            let kind = open.remove(at: generator.nextIndex(below: open.count))
            let hours = rules.hours(of: kind, using: &generator)
            let reply = try await model.foundingReply(
                EventDescriptionDraft.self,
                instructions: TownChangePrompts.eventInstructions(),
                prompt: TownChangePrompts.eventPrompt(town: town, kind: kind),
            )
            switch reply {
            case let .done(draft):
                try await start(kind.id, hours: hours, description: draft.description, at: now)
                return

            case .failed(.refused):
                EngineLog.recordEventRefused(kind.id)

            case let .failed(reason):
                EngineLog.recordEventDropped(.failed(reason))
                return

            case .unavailable:
                EngineLog.recordEventDropped(.modelUnavailable)
                return
            }
        }
        EngineLog.recordEventDropped(.retriesSpent(attempts: attempts))
    }

    /// Stores an event of `kind`, starting now and lasting `hours`, described as the
    /// model wrote — unless the description is blank, spans lines, or runs over
    /// ``TownEvent/descriptionMaxLength``.
    private func start(
        _ kind: EventKindID,
        hours: Int,
        description: String,
        at now: Date,
    ) async throws {
        let event: TownEvent
        do throws(TownValueError) {
            event = try TownEvent(
                id: TownEvent.ID(),
                kind: kind,
                description: description,
                startsAt: now,
                endsAt: rules.end(after: now, hours: hours),
            )
        } catch {
            EngineLog.recordEventDropped(.invalid(error))
            return
        }
        do throws(TownStoreError) {
            try await store.startEvent(event)
        } catch .cancelled {
            throw CancellationError()
        } catch {
            EngineLog.recordEventDropped(.storeFailed(error))
            return
        }
        EngineLog.recordEventStarted(kind, hours: hours)
    }
}
