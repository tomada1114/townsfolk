extension RandomNumberGenerator {
    /// A uniform draw in `0 ..< 1`: the top 53 bits of one `next()`, scaled. Spelled out
    /// rather than left to `Double.random(in:using:)`, so a seeded test's expected values
    /// can be worked out by hand from the generator's raw output.
    mutating func nextUnit() -> Double {
        let precision = Double.significandBitCount + 1
        let scale = Double(sign: .plus, exponent: -precision, significand: 1)
        return Double(next() >> (UInt64.bitWidth - precision)) * scale
    }

    /// A uniform draw in `range`, from one ``nextUnit()``.
    mutating func nextFraction(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
    }

    /// A uniform index in `0 ..< count`, from one ``nextUnit()``; `count` is at least 1.
    mutating func nextIndex(below count: Int) -> Int {
        min(count - 1, Int(nextUnit() * Double(count)))
    }
}
