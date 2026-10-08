import Foundation

/// Residents moving in and away (requirements §3.6; REQ-005–REQ-008 of #25): rules decide
/// whether someone moves, which way, and who leaves; the model only invents a newcomer.
/// Each move is one transaction — the resident with its event — and becomes the next
/// scene's news.
extension TownEngine {
    /// Draws whether someone moves after `running` seconds of running time, and moves them
    /// if so: in or away with the chance ``TownChangeRules/direction(living:roll:)`` gives,
    /// never past `Tuning.residents.population` (REQ-005).
    /// - Throws: `CancellationError` when the calling task is cancelled; nothing is stored.
    func drawMove(running: TimeInterval, at now: Date) async throws {
        let chance = rules.moveChance(running: running, using: &generator)
        guard generator.nextUnit() < chance else {
            return
        }
        let roll = generator.nextUnit()
        let town: Town
        let residents: [Resident]
        do throws(TownStoreError) {
            guard let founded = try await store.town() else {
                EngineLog.recordMoveDropped(.notFounded)
                return
            }
            town = founded
            residents = try await store.residents()
        } catch {
            EngineLog.recordMoveDropped(.storeFailed(error))
            return
        }
        let living = residents.filter { $0.status == .living }
        switch rules.direction(living: living.count, roll: roll) {
        case .moveIn:
            try await moveIn(to: town, among: residents, at: now)

        case .moveOut:
            try await moveOut(one: living, at: now)

        case nil:
            EngineLog.recordMoveDropped(.populationFixed)
        }
    }

    /// Invents a newcomer from one entry per axis and stores them, living and moved in
    /// now, with their move-in row (REQ-006). A refused or failed call, a newcomer out of
    /// bounds, or a name a current or past resident has is retried with redrawn axes, at
    /// most `Tuning.generation.refusalRetriesPerTurn` times; then the move is dropped
    /// (REQ-007).
    private func moveIn(to town: Town, among residents: [Resident], at now: Date) async throws {
        let living = residents.filter { $0.status == .living }
        let past = residents.filter { $0.status == .movedOut }
        let attempts = 1 + max(0, tuning.generation.refusalRetriesPerTurn)
        for _ in 0 ..< attempts {
            guard let seed = residentDraw.drawEachAxis(using: &generator) else {
                EngineLog.recordMoveDropped(.noAxes)
                return
            }
            let reply = try await newcomerReply(town: town, seed: seed, residents: residents)
            let newcomer: Resident
            switch reply {
            case let .done(draft):
                do throws(FoundingFailure) {
                    newcomer = try draft.resident(
                        id: Resident.ID(),
                        seed: seed,
                        among: living,
                        alsoTaken: past,
                        movedInAt: now,
                    )
                } catch {
                    EngineLog.recordNewcomerFailed(error)
                    continue
                }

            case let .failed(reason):
                EngineLog.recordNewcomerFailed(reason)
                continue

            case .unavailable:
                EngineLog.recordMoveDropped(.modelUnavailable)
                return
            }
            let wording = EngineWording.movedIn(name: newcomer.name)
            try await storeMove(newcomer, kind: .moveIn, wording: wording, at: now)
            return
        }
        EngineLog.recordMoveDropped(.retriesSpent(attempts: attempts))
    }

    /// Fits each draw separately: redrawn axes can have different token lengths.
    private func newcomerReply(
        town: Town,
        seed: ResidentSeed,
        residents: [Resident],
    ) async throws -> FoundingAttempt<NewResidentDraft> {
        let fitted = try await NewcomerPromptBudget.fit(
            town: town, seed: seed, residents: residents, model: model, tuning: tuning,
        )
        switch fitted {
        case let .done(prompt):
            return try await model.foundingReply(
                NewResidentDraft.self,
                instructions: TownChangePrompts.newcomerInstructions(),
                prompt: prompt,
            )

        case let .failed(reason):
            return .failed(reason)

        case .unavailable:
            return .unavailable
        }
    }

    /// Moves one of `living`, picked uniformly, away now; their posts stay, and they are
    /// never a speaker again (REQ-008).
    private func moveOut(one living: [Resident], at now: Date) async throws {
        let leaving = living[generator.nextIndex(below: living.count)]
        let moved: Resident
        do throws(TownValueError) {
            moved = try Resident(
                id: leaving.id,
                name: leaving.name,
                profile: leaving.profile,
                movedInAt: leaving.movedInAt,
                status: .movedOut,
                movedOutAt: now,
                relationships: leaving.relationships,
                interests: leaving.interests,
            )
        } catch {
            EngineLog.recordMoveDropped(.invalid(error))
            return
        }
        let wording = EngineWording.movedAway(name: moved.name)
        try await storeMove(moved, kind: .moveOut, wording: wording, at: now)
    }

    /// Stores `resident` as they are after the move, with its row of `kind` — one
    /// instant, already ended, about them — in one transaction, and makes the move the
    /// next scene's news (REQ-009).
    private func storeMove(
        _ resident: Resident,
        kind: EventKindID,
        wording: LocalizedStringResource,
        at now: Date,
    ) async throws {
        let event: TownEvent
        do throws(TownValueError) {
            event = try TownEvent(
                id: TownEvent.ID(),
                kind: kind,
                description: String(localized: wording),
                startsAt: now,
                endsAt: now,
                status: .ended,
                relatedResident: resident.id,
            )
        } catch {
            EngineLog.recordMoveDropped(.invalid(error))
            return
        }
        do throws(TownStoreError) {
            try await store.recordMove(TownStore.MoveStep(resident: resident, event: event))
        } catch .cancelled {
            throw CancellationError()
        } catch {
            EngineLog.recordMoveDropped(.storeFailed(error))
            return
        }
        news = SceneCasting.News(event: event, newcomer: kind == .moveIn ? resident.id : nil)
        EngineLog.recordMove(kind)
    }
}
