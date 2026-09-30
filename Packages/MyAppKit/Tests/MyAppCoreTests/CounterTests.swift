import MyAppCore
import Testing

@Suite("Counter")
struct CounterTests {
    // MARK: - init

    @Test
    func `init defaults to 0 in -100...100`() throws {
        let counter = try Counter()
        #expect(counter.value == 0)
        #expect(counter.range == -100 ... 100)
    }

    @Test(arguments: [-100, 100])
    func `init accepts values at both boundaries`(value: Int) throws {
        let counter = try Counter(value: value)
        #expect(counter.value == value)
    }

    @Test(arguments: [-101, 101, 999])
    func `init throws valueOutOfRange with the offending payload`(value: Int) {
        #expect(throws: Counter.CounterError.valueOutOfRange(value: value, range: -100 ... 100)) {
            try Counter(value: value)
        }
    }

    @Test
    func `init accepts a custom range`() throws {
        let counter = try Counter(value: 5, range: 1 ... 10)
        #expect(counter.value == 5)
        #expect(counter.range == 1 ... 10)
    }

    // MARK: - increment / decrement

    @Test
    func `increment adds one below the upper bound`() throws {
        var counter = try Counter()
        counter.increment()
        #expect(counter.value == 1)
    }

    @Test
    func `decrement subtracts one above the lower bound`() throws {
        var counter = try Counter()
        counter.decrement()
        #expect(counter.value == -1)
    }

    @Test(arguments: [(-100, false), (100, true)])
    func `operations clamp at the bounds`(bound: Int, incrementing: Bool) throws {
        var counter = try Counter(value: bound)
        if incrementing {
            counter.increment()
        } else {
            counter.decrement()
        }
        #expect(counter.value == bound)
    }

    @Test
    func `repeated increments stay clamped at max`() throws {
        var counter = try Counter(value: 100)
        for _ in 1 ... 5 {
            counter.increment()
        }
        #expect(counter.value == 100)
        #expect(counter.isAtMax)
    }

    @Test
    func `repeated decrements stay clamped at min`() throws {
        var counter = try Counter(value: -100)
        for _ in 1 ... 5 {
            counter.decrement()
        }
        #expect(counter.value == -100)
        #expect(counter.isAtMin)
    }

    // MARK: - isAtMax / isAtMin

    @Test
    func `isAtMax and isAtMin flip only at their bound`() throws {
        let mid = try Counter()
        #expect(!mid.isAtMax)
        #expect(!mid.isAtMin)

        let max = try Counter(value: 100)
        #expect(max.isAtMax)
        #expect(!max.isAtMin)

        let min = try Counter(value: -100)
        #expect(min.isAtMin)
        #expect(!min.isAtMax)
    }

    // MARK: - reset

    @Test
    func `reset returns to 0 when the range contains 0`() throws {
        var counter = try Counter(value: 42)
        counter.reset()
        #expect(counter.value == 0)
    }

    @Test
    func `reset falls back to the lower bound when 0 is out of range`() throws {
        var counter = try Counter(value: 5, range: 1 ... 10)
        counter.reset()
        #expect(counter.value == 1)
    }

    // MARK: - Equatable

    @Test
    func `counters with equal state are equal`() throws {
        let base = try Counter(value: 3)
        let same = try Counter(value: 3)
        let other = try Counter(value: 4)
        #expect(base == same)
        #expect(base != other)

        let narrow = try Counter(value: 3, range: 0 ... 5)
        #expect(base != narrow)
    }
}
