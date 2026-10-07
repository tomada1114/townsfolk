/// A seeded generator, so a test can state the exact draws a seed produces
/// (`designing-core-logic` › Inject randomness). SplitMix64, as published by Steele, Lea,
/// and Flood (2014): the oracle for a test's expected picks is the same algorithm worked
/// out outside Swift, never the engine itself.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private static let increment: UInt64 = 0x9E37_79B9_7F4A_7C15
    private static let firstMultiplier: UInt64 = 0xBF58_476D_1CE4_E5B9
    private static let secondMultiplier: UInt64 = 0x94D0_49BB_1331_11EB
    private static let firstShift: UInt64 = 30
    private static let secondShift: UInt64 = 27
    private static let lastShift: UInt64 = 31

    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= Self.increment
        var mixed = state
        mixed = (mixed ^ (mixed >> Self.firstShift)) &* Self.firstMultiplier
        mixed = (mixed ^ (mixed >> Self.secondShift)) &* Self.secondMultiplier
        return mixed ^ (mixed >> Self.lastShift)
    }
}
