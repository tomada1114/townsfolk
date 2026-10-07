import Foundation
import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkPlatform
import TownsfolkTestSupport

/// `SystemLanguageModelProvider` against Apple's on-device model — the translation a Core
/// test with `FakeLanguageModelProvider` cannot check.
///
/// Beside it sits the adapter half of the port's contract suite:
/// `LanguageModelProvidingContract`, the same function `TownsfolkCoreTests` runs against
/// the fake on every `just test` (`.claude/rules/testing.md` › One Contract Suite per
/// Port). It needs no TCC grant, only Apple Intelligence turned on with its model
/// downloaded; serialized so the model serves one test at a time.
@Suite(
    "SystemLanguageModelProvider against the on-device model",
    .requiresLocalMachine,
    .serialized,
)
struct SystemLanguageModelProviderTests {
    private let provider = SystemLanguageModelProvider()

    /// Fails, naming Apple Intelligence, unless the model can be called — so an unavailable
    /// model reads as a missing requirement rather than a broken adapter.
    private func requireAvailable() throws {
        let availability = provider.availability
        _ = try LocalMachineTests.require(
            availability == .available ? availability : nil,
            requires: "Apple Intelligence turned on (System Settings › Apple Intelligence & Siri) "
                + "with its model downloaded; the model reported \(availability)",
            grant: false,
        )
    }

    @Test
    func `keeps the LanguageModelProviding contract the fake is held to`() async throws {
        try requireAvailable()
        await LanguageModelProvidingContract.check(provider)
    }

    /// Prints the size it read, the answer `docs/architecture.md` › The on-device model
    /// records for the Mac and OS the run was on.
    @Test
    func `reads a positive context size from the model and prints it`() throws {
        try requireAvailable()
        let size = provider.contextSize
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        print("SystemLanguageModelProvider.contextSize = \(size) on macOS \(system)")
        #expect(size > 0)
    }

    @Test
    func `a respond from a cancelled task throws CancellationError`() async throws {
        try requireAvailable()
        let task = Task { [provider] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.respond(
                instructions: LanguageModelProvidingContract.instructions,
                prompt: LanguageModelProvidingContract.prompt,
                schema: ContractReply.generationSchema,
            )
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
