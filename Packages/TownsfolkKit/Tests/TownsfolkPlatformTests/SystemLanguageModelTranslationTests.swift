import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkPlatform

/// An error FoundationModels does not declare.
private struct NotFromFoundationModels: Error {}

/// The adapter's mapping of each framework value it can be handed. Constructing the values
/// needs no model, but the suite lives with the adapter's other translation tests, so it
/// runs under `just test-local` too.
@Suite("SystemLanguageModelProvider's translation", .requiresLocalMachine)
struct SystemLanguageModelTranslationTests {
    @Test(arguments: ErrorMappingCase.current + LegacyGenerationErrorCases.all)
    func `maps each SDK error to its Core case`(mapping: ErrorMappingCase) throws {
        #expect(SystemLanguageModelTranslation.translation(of: mapping.sdkError).error == mapping
            .expected)
        #expect(try SystemLanguageModelTranslation.callError(
            for: mapping.sdkError,
            during: "test",
        ) == mapping.expected)
    }

    @Test
    func `the deprecated GenerationError cases are all reached`() {
        #expect(LegacyGenerationErrorCases.all.count == 9)
    }

    @Test
    func `an error FoundationModels does not declare maps to other`() {
        #expect(SystemLanguageModelTranslation.translation(of: NotFromFoundationModels())
            .error == .other)
    }

    @Test
    func `a CancellationError passes through unmapped`() {
        #expect(throws: CancellationError.self) {
            try SystemLanguageModelTranslation.callError(for: CancellationError(), during: "test")
        }
    }

    @Test(arguments: [
        (SystemLanguageModel.Availability.available, ModelAvailability.available),
        (.unavailable(.appleIntelligenceNotEnabled), .appleIntelligenceOff),
        (.unavailable(.modelNotReady), .modelNotReady),
        (.unavailable(.deviceNotEligible), .deviceNotEligible),
    ])
    func `maps each availability to its Core case`(
        sdk: SystemLanguageModel.Availability,
        expected: ModelAvailability,
    ) {
        #expect(SystemLanguageModelTranslation.availability(of: sdk) == expected)
    }
}
