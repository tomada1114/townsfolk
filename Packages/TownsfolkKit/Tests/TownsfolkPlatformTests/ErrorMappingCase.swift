import Foundation
import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkPlatform
import TownsfolkTestSupport

/// Where the deprecated `LanguageModelSession.GenerationError` cases are built: naming
/// that type outside a declaration deprecated in the same release is a deprecation
/// warning, which this package treats as an error. The adapter reaches it the same way
/// (`SystemLanguageModelErrorMapping.swift`).
protocol LegacyErrorMappingCases {
    static var cases: [ErrorMappingCase] { get }
}

enum LegacyGenerationErrorCases {
    /// The deprecated cases, read through the protocol so no non-deprecated code names them.
    static var all: [ErrorMappingCase] {
        let source: Any = Self.self
        return (source as? any LegacyErrorMappingCases.Type)?.cases ?? []
    }
}

/// One SDK error and the Core case it must map to.
struct ErrorMappingCase: Sendable, CustomTestStringConvertible {
    private static let documentedContextSize = 4_096

    /// Every error case of the macOS 27 SDK a test can construct, beside the Core case
    /// `docs/architecture.md` › The on-device model records for it.
    static let current: [Self] = [
        Self(
            sdkError: LanguageModelError.contextSizeExceeded(
                .init(
                    contextSize: documentedContextSize,
                    tokenCount: documentedContextSize + 1,
                    debugDescription: "",
                ),
            ),
            expected: .contextSizeExceeded,
            label: "LanguageModelError.contextSizeExceeded",
        ),
        Self(
            sdkError: LanguageModelError.guardrailViolation(.init(debugDescription: "")),
            expected: .refused,
            label: "LanguageModelError.guardrailViolation",
        ),
        Self(
            sdkError: LanguageModelError.refusal(.init(explanation: "", debugDescription: "")),
            expected: .refused,
            label: "LanguageModelError.refusal",
        ),
        Self(
            sdkError: LanguageModelError.rateLimited(.init(
                resetDate: nil,
                debugDescription: "",
            )),
            expected: .other,
            label: "LanguageModelError.rateLimited",
        ),
        Self(
            sdkError: LanguageModelError.unsupportedCapability(
                .init(capability: .toolCalling, debugDescription: ""),
            ),
            expected: .other,
            label: "LanguageModelError.unsupportedCapability",
        ),
        Self(
            sdkError: LanguageModelError.unsupportedTranscriptContent(
                .init(unsupportedContent: [], debugDescription: ""),
            ),
            expected: .other,
            label: "LanguageModelError.unsupportedTranscriptContent",
        ),
        Self(
            sdkError: LanguageModelError.unsupportedGenerationGuide(
                .init(schemaName: nil, debugDescription: ""),
            ),
            expected: .other,
            label: "LanguageModelError.unsupportedGenerationGuide",
        ),
        Self(
            sdkError: LanguageModelError.unsupportedLanguageOrLocale(
                .init(languageCode: .english, debugDescription: ""),
            ),
            expected: .other,
            label: "LanguageModelError.unsupportedLanguageOrLocale",
        ),
        Self(
            sdkError: LanguageModelError.timeout(.init(debugDescription: "")),
            expected: .other,
            label: "LanguageModelError.timeout",
        ),
        Self(
            sdkError: SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "")),
            expected: .unavailable,
            label: "SystemLanguageModel.Error.assetsUnavailable",
        ),
        Self(
            sdkError: LanguageModelSession.Error.concurrentRequests,
            expected: .other,
            label: "LanguageModelSession.Error.concurrentRequests",
        ),
        Self(
            sdkError: LanguageModelSession.Error.transcriptMutationWhileResponding,
            expected: .other,
            label: "LanguageModelSession.Error.transcriptMutationWhileResponding",
        ),
        Self(
            sdkError: GeneratedContent.ParsingError(rawContent: "", debugDescription: ""),
            expected: .other,
            label: "GeneratedContent.ParsingError",
        ),
        Self(
            sdkError: GenerationSchema.SchemaError.duplicateType(
                schema: nil,
                type: "T",
                context: .init(debugDescription: ""),
            ),
            expected: .other,
            label: "GenerationSchema.SchemaError",
        ),
    ]

    let sdkError: any Error
    let expected: ModelCallError
    let label: String

    var testDescription: String {
        "\(label) -> \(expected)"
    }
}

@available(macOS, deprecated: 27.0, message: "Builds the deprecated GenerationError only.")
extension LegacyGenerationErrorCases: LegacyErrorMappingCases {
    static var cases: [ErrorMappingCase] {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "")
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        return [
            legacy(
                .exceededContextWindowSize(context),
                .contextSizeExceeded,
                "exceededContextWindowSize",
            ),
            legacy(.assetsUnavailable(context), .unavailable, "assetsUnavailable"),
            legacy(.guardrailViolation(context), .refused, "guardrailViolation"),
            legacy(.refusal(refusal, context), .refused, "refusal"),
            legacy(.unsupportedGuide(context), .other, "unsupportedGuide"),
            legacy(.unsupportedLanguageOrLocale(context), .other, "unsupportedLanguageOrLocale"),
            legacy(.decodingFailure(context), .other, "decodingFailure"),
            legacy(.rateLimited(context), .other, "rateLimited"),
            legacy(.concurrentRequests(context), .other, "concurrentRequests"),
        ]
    }

    private static func legacy(
        _ error: LanguageModelSession.GenerationError,
        _ expected: ModelCallError,
        _ name: String,
    ) -> ErrorMappingCase {
        ErrorMappingCase(sdkError: error, expected: expected, label: "GenerationError.\(name)")
    }
}
