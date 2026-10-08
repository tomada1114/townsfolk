/// Names held only by former residents are free for the living town to take up.
enum NameInterestRules {
    static func unheld(_ names: [Interest], among residents: [Resident]) -> [Interest] {
        let held = Set(residents.filter { $0.status == .living }.flatMap(\.interests))
        return names.filter { !held.contains($0.id) }
    }

    static func uptake(
        of scene: WrittenScene,
        among residents: [Resident],
        using generator: inout some RandomNumberGenerator,
    ) -> [ResidentInterestAssignment] {
        guard case let .name(name) = scene.seed,
              !residents.contains(where: { $0.status == .living && $0.interests.contains(name.id) })
        else {
            return []
        }
        var seen: Set<Resident.ID> = []
        let candidates = scene.posts.map(\.speaker).filter { speaker in
            guard seen.insert(speaker).inserted,
                  let resident = residents.first(where: { $0.id == speaker })
            else {
                return false
            }
            return resident.status == .living && resident.interests.count < Resident.maxInterests
        }
        guard !candidates.isEmpty else {
            return []
        }
        return [
            .init(
                resident: candidates[generator.nextIndex(below: candidates.count)],
                interest: name.id,
            ),
        ]
    }
}
