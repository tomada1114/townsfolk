/// Draws resident seeds from the seed tables' axes, one combination at a time, uniformly
/// among the combinations not excluded — so each axis is still drawn at random, and a
/// combination already taken is never drawn again however unlikely a repeat.
struct ResidentSeedDraw {
    let axes: SeedTables.ResidentAxes

    /// How many different combinations the axes allow.
    var combinations: Int {
        axes.occupations.count * axes.personalities.count * axes.lifeStages.count
            * axes.hobbies.count
    }

    /// The combination numbered `index`; the occupation varies fastest.
    func seed(at index: Int) -> ResidentSeed {
        var rest = index
        func next(_ entries: [SeedTables.Entry]) -> SeedTables.Entry {
            defer { rest /= entries.count }
            return entries[rest % entries.count]
        }
        let occupation = next(axes.occupations)
        let personality = next(axes.personalities)
        let lifeStage = next(axes.lifeStages)
        let hobby = next(axes.hobbies)
        return ResidentSeed(
            index: index,
            occupation: occupation,
            personality: personality,
            lifeStage: lifeStage,
            hobby: hobby,
        )
    }

    /// One entry of each axis, each drawn uniformly on its own — a newcomer's axes
    /// (requirements.md:259) — or `nil` when an axis is empty.
    func drawEachAxis(using generator: inout some RandomNumberGenerator) -> ResidentSeed? {
        let sizes = [
            axes.occupations.count, axes.personalities.count, axes.lifeStages.count,
            axes.hobbies.count,
        ]
        guard !sizes.contains(0) else {
            return nil
        }
        // The combination number `seed(at:)` reads back, the occupation varying fastest.
        var index = 0
        var stride = 1
        for size in sizes {
            index += generator.nextIndex(below: size) * stride
            stride *= size
        }
        return seed(at: index)
    }

    /// A combination in none of `excluded`, or `nil` when every combination is.
    func draw(
        excluding excluded: Set<Int>,
        using generator: inout some RandomNumberGenerator,
    ) -> ResidentSeed? {
        let blocked = excluded.filter { (0 ..< combinations).contains($0) }.sorted()
        let open = combinations - blocked.count
        guard open > 0 else {
            return nil
        }
        // The draw counts open combinations only; stepping past each blocked one at or
        // below it turns that count into a combination number.
        var index = Int.random(in: 0 ..< open, using: &generator)
        for taken in blocked where taken <= index {
            index += 1
        }
        return seed(at: index)
    }

    /// A combination outside `taken` and, while any is left, outside `tried` too — a
    /// retry prefers combinations not yet tried; `nil` when every combination is taken.
    func draw(
        avoiding taken: Set<Int>,
        preferablyAlso tried: Set<Int>,
        using generator: inout some RandomNumberGenerator,
    ) -> ResidentSeed? {
        draw(excluding: taken.union(tried), using: &generator)
            ?? draw(excluding: taken, using: &generator)
    }
}
