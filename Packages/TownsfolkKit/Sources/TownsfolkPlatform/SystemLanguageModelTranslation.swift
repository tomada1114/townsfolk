import FoundationModels
import TownsfolkCore

/// Reaches the deprecated `LanguageModelSession.GenerationError` without naming it.
///
/// The macOS 27 SDK still declares that type, deprecated in favour of the errors
/// ``SystemLanguageModelTranslation`` maps by name, and a framework may still throw it.
/// Naming a deprecated type from ordinary code is a deprecation warning, which this package
/// treats as an error; the conformance below is declared in an extension deprecated in the
/// same release, the one place the type may be named, and the translation reaches it
/// through this protocol with a dynamic cast.
protocol LegacyGenerationErrorTranslating {
    var translation: (error: ModelCallError, sdkCase: String) { get }
}

/// Which Core value each answer and error of the macOS 27 SDK's `FoundationModels` means —
/// translation, never a decision about what to do next.
///
/// The cases are those of the SDK the adapter builds with, each listed with its Core case in
/// `docs/architecture.md` › The on-device model. A case a later SDK adds maps to
/// ``TownsfolkCore/ModelCallError/other``, or for availability to
/// ``TownsfolkCore/ModelAvailability/modelNotReady``, until it is listed here.
package enum SystemLanguageModelTranslation {
    /// Which Core case the framework's availability means. A reason added after the macOS 27
    /// SDK reads as ``TownsfolkCore/ModelAvailability/modelNotReady``, the one case the
    /// town treats as temporary and asks about again (ux-flows S7).
    package static func availability(
        of availability: SystemLanguageModel.Availability,
    ) -> ModelAvailability {
        switch availability {
        case .available:
            .available

        case let .unavailable(reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                .appleIntelligenceOff

            case .modelNotReady:
                .modelNotReady

            case .deviceNotEligible:
                .deviceNotEligible

            @unknown default:
                .modelNotReady
            }
        }
    }

    /// The Core error `error` means, with the SDK case it came from as a log-safe label.
    ///
    /// The label is a literal chosen here, never the error's own description, which can
    /// quote the prompt or the reply.
    package static func translation(
        of error: any Error,
    ) -> (error: ModelCallError, sdkCase: String) {
        switch error {
        case let error as LanguageModelError:
            translation(of: error)

        case let error as SystemLanguageModel.Error:
            translation(of: error)

        case let error as LanguageModelSession.Error:
            translation(of: error)

        case is GeneratedContent.ParsingError:
            (.other, "GeneratedContent.ParsingError")

        case is GenerationSchema.SchemaError:
            (.other, "GenerationSchema.SchemaError")

        case is LanguageModelSession.ToolCallError:
            (.other, "LanguageModelSession.ToolCallError")

        case let legacy as any LegacyGenerationErrorTranslating:
            legacy.translation

        default:
            (.other, "an error FoundationModels does not declare")
        }
    }

    /// What the adapter throws for `error`, thrown during `call`: `CancellationError`
    /// unchanged, `CancellationError` too for any error once the calling task is cancelled
    /// — the caller no longer wants the result — and otherwise the Core case, logged with
    /// the SDK case it came from.
    package static func callError(
        for error: any Error,
        during call: StaticString,
    ) throws -> ModelCallError {
        if error is CancellationError {
            throw error
        }
        try Task.checkCancellation()
        let translated = translation(of: error)
        let sdkCase = translated.sdkCase
        let coreCase = String(describing: translated.error)
        AppLog.model.info(
            "\(call, privacy: .public) failed: \(sdkCase, privacy: .public) -> \(coreCase, privacy: .public)",
        )
        return translated.error
    }

    private static func translation(
        of error: LanguageModelError,
    ) -> (error: ModelCallError, sdkCase: String) {
        switch error {
        case .contextSizeExceeded:
            (.contextSizeExceeded, "LanguageModelError.contextSizeExceeded")

        case .guardrailViolation:
            (.refused, "LanguageModelError.guardrailViolation")

        case .refusal:
            (.refused, "LanguageModelError.refusal")

        case .rateLimited:
            (.other, "LanguageModelError.rateLimited")

        case .unsupportedCapability:
            (.other, "LanguageModelError.unsupportedCapability")

        case .unsupportedTranscriptContent:
            (.other, "LanguageModelError.unsupportedTranscriptContent")

        case .unsupportedGenerationGuide:
            (.other, "LanguageModelError.unsupportedGenerationGuide")

        case .unsupportedLanguageOrLocale:
            (.other, "LanguageModelError.unsupportedLanguageOrLocale")

        case .timeout:
            (.other, "LanguageModelError.timeout")

        @unknown default:
            (.other, "LanguageModelError, a case added after macOS 27")
        }
    }

    private static func translation(
        of error: SystemLanguageModel.Error,
    ) -> (error: ModelCallError, sdkCase: String) {
        switch error {
        case .assetsUnavailable:
            (.unavailable, "SystemLanguageModel.Error.assetsUnavailable")

        @unknown default:
            (.other, "SystemLanguageModel.Error, a case added after macOS 27")
        }
    }

    private static func translation(
        of error: LanguageModelSession.Error,
    ) -> (error: ModelCallError, sdkCase: String) {
        switch error {
        case .concurrentRequests:
            (.other, "LanguageModelSession.Error.concurrentRequests")

        case .transcriptMutationWhileResponding:
            (.other, "LanguageModelSession.Error.transcriptMutationWhileResponding")

        @unknown default:
            (.other, "LanguageModelSession.Error, a case added after macOS 27")
        }
    }
}

@available(macOS, deprecated: 27.0, message: "Translates the deprecated GenerationError only.")
extension LanguageModelSession.GenerationError: LegacyGenerationErrorTranslating {
    var translation: (error: ModelCallError, sdkCase: String) {
        switch self {
        case .exceededContextWindowSize:
            (.contextSizeExceeded, "GenerationError.exceededContextWindowSize")

        case .assetsUnavailable:
            (.unavailable, "GenerationError.assetsUnavailable")

        case .guardrailViolation:
            (.refused, "GenerationError.guardrailViolation")

        case .refusal:
            (.refused, "GenerationError.refusal")

        case .unsupportedGuide:
            (.other, "GenerationError.unsupportedGuide")

        case .unsupportedLanguageOrLocale:
            (.other, "GenerationError.unsupportedLanguageOrLocale")

        case .decodingFailure:
            (.other, "GenerationError.decodingFailure")

        case .rateLimited:
            (.other, "GenerationError.rateLimited")

        case .concurrentRequests:
            (.other, "GenerationError.concurrentRequests")

        @unknown default:
            (.other, "GenerationError, a case added after macOS 27")
        }
    }
}
