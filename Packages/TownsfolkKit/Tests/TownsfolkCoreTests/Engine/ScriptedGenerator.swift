/// A generator whose first draws are the fractions a test lists, so a test states "the
/// event chance draws 0.02" as written; once they run out it answers SplitMix64 seeded
/// 42, for the draws a test does not care about. Each fraction comes back as the top 53
/// bits of one `next()`, which is how the engine turns a draw into a fraction.
struct ScriptedGenerator: RandomNumberGenerator, Sendable {
    private static let fractionBits = 53

    private var script: [Double]
    private var rest = SplitMix64(seed: EngineSetup.seed)

    init(_ fractions: [Double]) {
        script = fractions
    }

    mutating func next() -> UInt64 {
        guard !script.isEmpty else {
            return rest.next()
        }
        let fraction = script.removeFirst()
        let scale = Double(sign: .plus, exponent: Self.fractionBits, significand: 1)
        return UInt64(fraction * scale) << (UInt64.bitWidth - Self.fractionBits)
    }
}
