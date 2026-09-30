import Foundation
import Testing
import TownsfolkCore

@MainActor
@Suite("CounterViewModel")
struct CounterViewModelTests {
    @Test
    func `default init starts at 0 with movement enabled both ways`() {
        let model = CounterViewModel()
        #expect(model.value == 0)
        #expect(model.canIncrement)
        #expect(model.canDecrement)
    }

    @Test
    func `init with a custom counter passes its value through`() throws {
        let model = try CounterViewModel(counter: Counter(value: 7))
        #expect(model.value == 7)
    }

    @Test
    func `increment and decrement move the exposed value`() {
        let model = CounterViewModel()
        model.increment()
        #expect(model.value == 1)
        model.decrement()
        model.decrement()
        #expect(model.value == -1)
    }

    @Test
    func `canIncrement flips off only at the upper bound`() throws {
        let model = try CounterViewModel(counter: Counter(value: 9, range: 0 ... 10))
        #expect(model.canIncrement)
        model.increment()
        #expect(model.value == 10)
        #expect(!model.canIncrement)
        #expect(model.canDecrement)
    }

    @Test
    func `canDecrement flips off only at the lower bound`() throws {
        let model = try CounterViewModel(counter: Counter(value: 1, range: 0 ... 10))
        #expect(model.canDecrement)
        model.decrement()
        #expect(model.value == 0)
        #expect(!model.canDecrement)
        #expect(model.canIncrement)
    }

    @Test
    func `a full walk to max stays clamped and reports the bound`() throws {
        let model = try CounterViewModel(counter: Counter(value: 0, range: 0 ... 5))
        for _ in 1 ... 8 {
            model.increment()
        }
        #expect(model.value == 5)
        #expect(!model.canIncrement)
    }

    @Test
    func `reset returns to 0 for the default range`() {
        let model = CounterViewModel()
        model.increment()
        model.increment()
        model.reset()
        #expect(model.value == 0)
    }

    @Test
    func `reset falls back to the lower bound when 0 is out of range`() throws {
        let model = try CounterViewModel(counter: Counter(value: 5, range: 1 ... 10))
        model.reset()
        #expect(model.value == 1)
    }

    @Test
    func `the reset button's title is Core's wording`() {
        #expect(CounterViewModel.resetTitle.resolved(in: .english) == "Reset")
    }

    /// The "−" and "+" buttons show a glyph, which is not a name; these are what
    /// VoiceOver reads for them instead.
    @Test
    func `the glyph buttons' accessibility labels are Core's wording`() {
        #expect(CounterViewModel.decrementLabel.resolved(in: .english) == "Decrement")
        #expect(CounterViewModel.incrementLabel.resolved(in: .english) == "Increment")
    }
}
