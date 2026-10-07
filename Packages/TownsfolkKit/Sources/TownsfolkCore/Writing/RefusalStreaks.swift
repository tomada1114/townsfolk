/// Refusals in a row per item, kept in memory: they start at zero on launch, and only the
/// left-out flag is stored (#11). Only your posts and the names you brought up carry a
/// streak — the text that comes from outside the town (requirements.md:236–:238).
struct RefusalStreaks<ID: Hashable> {
    private var counts: [ID: Int] = [:]

    /// Adds one to the streak of each of `ids`, and returns those whose streak reached
    /// `threshold`.
    mutating func refused(_ ids: Set<ID>, threshold: Int) -> [ID] {
        var reached: [ID] = []
        for id in ids {
            let count = counts[id, default: 0] + 1
            counts[id] = count
            if count >= threshold {
                reached.append(id)
            }
        }
        return reached
    }

    /// Ends the streak of each of `ids`.
    mutating func reset(_ ids: Set<ID>) {
        for id in ids {
            counts[id] = nil
        }
    }
}
