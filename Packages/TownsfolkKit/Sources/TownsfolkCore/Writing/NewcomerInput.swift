import Foundation

/// Axes remain the newcomer's ordinary profile; the optional name is their first interest.
struct NewcomerInput {
    let axes: ResidentSeed
    let name: Interest?

    func resident(
        from draft: NewResidentDraft,
        among living: [Resident],
        alsoTaken past: [Resident],
        at now: Date,
    ) throws(FoundingFailure) -> Resident {
        let resident = try draft.resident(
            id: Resident.ID(),
            seed: axes,
            among: living,
            alsoTaken: past,
            movedInAt: now,
        )
        guard let name else {
            return resident
        }
        do throws(TownValueError) {
            return try Resident(
                id: resident.id,
                name: resident.name,
                profile: resident.profile,
                movedInAt: resident.movedInAt,
                relationships: resident.relationships,
                interests: [name.id],
            )
        } catch { throw .invalidResident }
    }
}
