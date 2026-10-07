import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// S2, your name (ux-flows S2; REQ-002, REQ-003, REQ-009): Continue enabled only for a
/// name of 1–20 characters after trimming, "{n} over" past the limit, and a stored name
/// starting at S3.
@MainActor
@Suite("FirstRunViewModel, naming")
struct FirstRunViewModelNamingTests {
    @Test(arguments: [
        ("", false),
        ("   ", false),
        ("Tomo", true),
        ("  Tomo  ", true),
        (FirstRunFixtures.name(ofLength: 1), true),
        (FirstRunFixtures.name(ofLength: 20), true),
        ("  " + FirstRunFixtures.name(ofLength: 20) + "  ", true),
        (FirstRunFixtures.name(ofLength: 21), false),
    ])
    func `the Continue button is enabled only while the trimmed name is 1–20 characters`(
        typed: String,
        canContinue: Bool,
    ) throws {
        try withFreshDefaults { suite in
            let model = FirstRunViewModel(
                defaults: suite.defaults,
                founding: FoundingRequests().make,
            )
            model.nameEdited(typed)
            #expect(model.canContinue == canContinue)
            #expect(model.nameField == typed)
        }
    }

    @Test(arguments: [
        (FirstRunFixtures.name(ofLength: 21), "1 over"),
        (FirstRunFixtures.name(ofLength: 25), "5 over"),
        (" " + FirstRunFixtures.name(ofLength: 22) + " ", "2 over"),
    ])
    func `a name over the limit shows how far over it is and keeps the input`(
        typed: String,
        reads: String,
    ) throws {
        try withFreshDefaults { suite in
            let model = FirstRunViewModel(
                defaults: suite.defaults,
                founding: FoundingRequests().make,
            )
            model.nameEdited(typed)
            #expect(model.overLimit?.resolved(in: .english) == reads)
            #expect(model.nameField == typed)
            #expect(!model.canContinue)
        }
    }

    @Test(arguments: ["", "   ", "Tomo", FirstRunFixtures.name(ofLength: 20)])
    func `a blank or valid name shows no message`(typed: String) throws {
        try withFreshDefaults { suite in
            let model = FirstRunViewModel(
                defaults: suite.defaults,
                founding: FoundingRequests().make,
            )
            model.nameEdited(typed)
            #expect(model.overLimit == nil)
        }
    }

    @Test
    func `deleting the one character over the limit clears the message and enables Continue`(
    ) throws {
        try withFreshDefaults { suite in
            let model = FirstRunViewModel(
                defaults: suite.defaults,
                founding: FoundingRequests().make,
            )
            model.nameEdited("Bartholomew Fairweath")
            #expect(model.overLimit?.resolved(in: .english) == "1 over")
            #expect(!model.canContinue)

            model.nameEdited("Bartholomew Fairweat")
            #expect(model.overLimit == nil)
            #expect(model.canContinue)
            #expect(model.nameField == "Bartholomew Fairweat")
        }
    }

    @Test
    func `a fresh install starts on S2 with an empty field and nothing founding`() throws {
        try withFreshDefaults { suite in
            let requests = FoundingRequests()
            let model = FirstRunViewModel(defaults: suite.defaults, founding: requests.make)
            #expect(model.founding == nil)
            #expect(model.nameField.isEmpty)
            #expect(!model.canContinue)
            #expect(requests.names.isEmpty)
        }
    }

    @Test
    func `a stored name starts at S3 founding with that name, without asking again`() throws {
        try withFreshDefaults { suite in
            suite.defaults.set("Tomo", forKey: StoredKey.displayName)
            let requests = FoundingRequests()
            let model = FirstRunViewModel(defaults: suite.defaults, founding: requests.make)
            #expect(model.founding?.displayName.value == "Tomo")
            #expect(requests.names == ["Tomo"])
            #expect(model.nameField == "Tomo")
        }
    }

    @Test
    func `a stored name that is no longer valid asks for a name again`() throws {
        try withFreshDefaults { suite in
            suite.defaults.set(FirstRunFixtures.name(ofLength: 21), forKey: StoredKey.displayName)
            let requests = FoundingRequests()
            let model = FirstRunViewModel(defaults: suite.defaults, founding: requests.make)
            #expect(model.founding == nil)
            #expect(requests.names.isEmpty)
        }
    }

    @Test
    func `the words on S2 read as ux-flows S2 writes them`() throws {
        try withFreshDefaults { suite in
            let model = FirstRunViewModel(
                defaults: suite.defaults,
                founding: FoundingRequests().make,
            )
            #expect(model.welcome.resolved(in: .english) == "A small town is waiting for you.")
            #expect(model.namePrompt.resolved(in: .english) == "What should the town call you?")
            #expect(model.nameHelp
                .resolved(in: .english) == "Residents see this name on your posts.")
            #expect(
                model.machineryNote.resolved(in: .english)
                    == "Its residents are written by Apple's on-device model, right on this Mac.",
            )
            #expect(model.continueTitle.resolved(in: .english) == "Continue")
        }
    }
}

/// Continue on S2 (REQ-004): a valid name is stored trimmed and founding starts with it;
/// an invalid one changes nothing.
@MainActor
@Suite("FirstRunViewModel, Continue")
struct FirstRunViewModelContinueTests {
    @Test
    func `pressing Continue stores the trimmed name and starts founding with it`() throws {
        try withFreshDefaults { suite in
            let requests = FoundingRequests()
            let model = FirstRunViewModel(defaults: suite.defaults, founding: requests.make)
            model.nameEdited("  Tomo  ")
            model.continuePressed()
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
            #expect(model.founding?.displayName.value == "Tomo")
            #expect(requests.names == ["Tomo"])
        }
    }

    @Test(arguments: ["", "   ", FirstRunFixtures.name(ofLength: 21)])
    func `pressing Continue on an invalid name stores nothing and stays on S2`(
        typed: String,
    ) throws {
        try withFreshDefaults { suite in
            let requests = FoundingRequests()
            let model = FirstRunViewModel(defaults: suite.defaults, founding: requests.make)
            model.nameEdited(typed)
            model.continuePressed()
            #expect(suite.stored(StoredKey.displayName) == nil)
            #expect(model.founding == nil)
            #expect(requests.names.isEmpty)
            #expect(model.nameField == typed)
        }
    }

    @Test
    func `pressing Continue twice, as Return and the default button can, founds once`() throws {
        try withFreshDefaults { suite in
            let requests = FoundingRequests()
            let model = FirstRunViewModel(defaults: suite.defaults, founding: requests.make)
            model.nameEdited("Tomo")
            model.continuePressed()
            model.nameEdited("Hana")
            model.continuePressed()
            #expect(requests.names == ["Tomo"])
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
            #expect(model.nameField == "Tomo")
        }
    }
}

/// The whole first run over #20's founder and the fake model (REQ-004, and the boundary
/// on cancelling): the stored name is the one founding writes into the town's first
/// scene, and a cancelled founding keeps the name and stores no town.
@MainActor
@Suite("FirstRunViewModel, founding")
struct FirstRunViewModelTests {
    @Test
    func `the trimmed name typed on S2 is the one founding writes the town for`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let name = "FirstRunViewModelFoundingTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let model = FirstRunViewModel(defaults: defaults) { name in
                // A throwing factory is not the port's shape; a fixture failure surfaces
                // as the missing founding screen below.
                (try? FirstRunFixtures.founding(fake, store: store, name: name))
                    ?? FirstRunFixtures.idleFounding(name)
            }
            model.nameEdited("  Tomo  ")
            model.continuePressed()
            let founding = try #require(model.founding)

            try await founding.run()

            #expect(founding.phase == .founded)
            #expect(fake.prompts.last?.contains("You: Tomo") == true)
            #expect(defaults.string(forKey: StoredKey.displayName) == "Tomo")
            #expect(try await store.town()?.name == "Maplewood")
        }
    }

    @Test
    func `a cancelled founding stores no town and keeps your name`() async throws {
        try await withStore { store, _ in
            let fake = FirstRunFixtures.heldFake(FoundingFixtures.happyPath)
            let name = "FirstRunViewModelFoundingTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let model = FirstRunViewModel(defaults: defaults) { name in
                (try? FirstRunFixtures.founding(fake, store: store, name: name))
                    ?? FirstRunFixtures.idleFounding(name)
            }
            model.nameEdited("Tomo")
            model.continuePressed()
            let founding = try #require(model.founding)
            let running = Task { try await founding.run() }
            await fake.waitUntilHeld(count: 1)

            running.cancel()

            await #expect(throws: CancellationError.self) { try await running.value }
            try await expectEmpty(store)
            #expect(defaults.string(forKey: StoredKey.displayName) == "Tomo")
            #expect(founding.phase == .founding)
        }
    }
}
