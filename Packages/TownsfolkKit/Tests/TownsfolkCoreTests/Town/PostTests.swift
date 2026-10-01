import Testing
import TownsfolkCore

@Suite("Post")
struct PostTests {
    let june = Resident.ID()
    let scene = SceneID()

    private func residentPost(
        _ text: String,
        language: TownLanguage = .english,
        topicTags: [String] = [],
        tuning: Tuning = .default,
    ) throws(TownValueError) -> Post {
        try Post(
            id: Post.ID(),
            author: .resident(june),
            text: text,
            happenedAt: TownFixtures.movedIn,
            language: language,
            topicTags: topicTags,
            origin: .ordinary,
            sceneID: scene,
            tuning: tuning,
        )
    }

    private func yourPost(_ text: String) throws(TownValueError) -> Post {
        try Post(
            id: Post.ID(),
            author: .you,
            text: text,
            happenedAt: TownFixtures.movedIn,
            language: .english,
        )
    }

    // MARK: - Fields

    @Test
    func `a resident's post keeps every field it was given`() throws {
        let id = Post.ID()
        let earlier = Post.ID()
        let post = try Post(
            id: id,
            author: .resident(june),
            text: "  Told you. Get there before eight. ",
            happenedAt: TownFixtures.movedIn,
            language: .english,
            replyTarget: earlier,
            topicTags: ["bakery", " bread "],
            origin: .response,
            sceneID: scene,
        )
        #expect(post.id == id)
        #expect(post.author == .resident(june))
        #expect(post.text == "Told you. Get there before eight.")
        #expect(post.happenedAt == TownFixtures.movedIn)
        #expect(post.language == .english)
        #expect(post.replyTarget == earlier)
        #expect(post.topicTags == ["bakery", "bread"])
        #expect(post.origin == .response)
        #expect(post.sceneID == scene)
    }

    @Test
    func `your post carries no origin and no scene`() throws {
        let post = try yourPost("Learning Rust today.")
        #expect(post.author == .you)
        #expect(post.origin == nil)
        #expect(post.sceneID == nil)
        #expect(post.replyTarget == nil)
        #expect(post.topicTags.isEmpty)
    }

    @Test
    func `every origin the requirements list exists`() {
        #expect(Post.Origin.allCases == [.catchUp, .event, .ordinary, .response])
    }

    // MARK: - A resident's text, per language

    @Test(arguments: [(TownLanguage.english, 280), (.japanese, 140)])
    func `a resident's post at its language's limit is accepted`(
        language: TownLanguage,
        limit: Int,
    ) throws {
        let post = try residentPost(TownFixtures.text(limit), language: language)
        #expect(post.text.count == limit)
    }

    @Test(arguments: [(TownLanguage.english, 280), (.japanese, 140)])
    func `a resident's post one past its language's limit is too long`(
        language: TownLanguage,
        limit: Int,
    ) {
        #expect(throws: TownValueError.tooLong(.postText, limit: limit)) {
            try residentPost(TownFixtures.text(limit + 1), language: language)
        }
    }

    @Test
    func `a Japanese post of 280 characters is too long`() {
        #expect(throws: TownValueError.tooLong(.postText, limit: 140)) {
            try residentPost(TownFixtures.text(280), language: .japanese)
        }
    }

    @Test
    func `a resident's blank post is empty`() {
        #expect(throws: TownValueError.empty(.postText)) {
            try residentPost("  ")
        }
    }

    @Test
    func `a resident's post of one character is accepted`() throws {
        #expect(try residentPost(TownFixtures.hiragana, language: .japanese).text.count == 1)
    }

    @Test
    func `a resident's limit comes from the Tuning`() throws {
        var tuning = Tuning.default
        tuning.timeline.residentPostMaxLength = PerLanguage(english: 5, japanese: 2)
        #expect(try residentPost("abcde", tuning: tuning).text == "abcde")
        #expect(throws: TownValueError.tooLong(.postText, limit: 2)) {
            try residentPost("abc", language: .japanese, tuning: tuning)
        }
    }

    // MARK: - Your text

    @Test
    func `your post of 140 characters is accepted and 141 is too long`() throws {
        #expect(try yourPost(TownFixtures.text(140)).text.count == 140)
        #expect(throws: TownValueError.tooLong(.postText, limit: 140)) {
            try yourPost(TownFixtures.text(141))
        }
    }

    @Test
    func `your post with an inner newline is rejected`() {
        #expect(throws: TownValueError.multipleLines(.postText)) {
            try yourPost("one\ntwo")
        }
    }

    // MARK: - Topic tags

    @Test(arguments: [0, 3])
    func `zero to three topic tags are accepted`(count: Int) throws {
        let tags = (0 ..< count).map { "tag\($0)" }
        #expect(try residentPost("Hi.", topicTags: tags).topicTags == tags)
    }

    @Test
    func `four topic tags are too many`() {
        #expect(throws: TownValueError.tooMany(.topicTags, limit: 3)) {
            try residentPost("Hi.", topicTags: ["a", "b", "c", "d"])
        }
    }

    @Test
    func `a tag of 40 characters is accepted and 41 is too long`() throws {
        let forty = TownFixtures.text(40)
        #expect(try residentPost("Hi.", topicTags: [forty]).topicTags == [forty])
        #expect(throws: TownValueError.tooLong(.topicTag, limit: 40)) {
            try residentPost("Hi.", topicTags: [TownFixtures.text(41)])
        }
    }

    @Test
    func `a blank tag is empty`() {
        #expect(throws: TownValueError.empty(.topicTag)) {
            try residentPost("Hi.", topicTags: ["rain", " "])
        }
    }

    // MARK: - Author, origin, and scene

    @Test
    func `a resident's post without an origin is rejected`() {
        #expect(throws: TownValueError.required(.origin)) {
            try Post(
                id: Post.ID(),
                author: .resident(june),
                text: "Hi.",
                happenedAt: TownFixtures.movedIn,
                language: .english,
                sceneID: scene,
            )
        }
    }

    @Test
    func `a resident's post without a scene is rejected`() {
        #expect(throws: TownValueError.required(.sceneID)) {
            try Post(
                id: Post.ID(),
                author: .resident(june),
                text: "Hi.",
                happenedAt: TownFixtures.movedIn,
                language: .english,
                origin: .ordinary,
            )
        }
    }

    @Test
    func `your post with an origin is rejected`() {
        #expect(throws: TownValueError.notAllowed(.origin)) {
            try Post(
                id: Post.ID(),
                author: .you,
                text: "Hi.",
                happenedAt: TownFixtures.movedIn,
                language: .english,
                origin: .ordinary,
            )
        }
    }

    @Test
    func `your post with a scene is rejected`() {
        #expect(throws: TownValueError.notAllowed(.sceneID)) {
            try Post(
                id: Post.ID(),
                author: .you,
                text: "Hi.",
                happenedAt: TownFixtures.movedIn,
                language: .english,
                sceneID: scene,
            )
        }
    }

    // MARK: - Equatable

    @Test
    func `posts built from the same values are equal`() throws {
        let id = Post.ID()
        func make(_ text: String) throws(TownValueError) -> Post {
            try Post(
                id: id,
                author: .you,
                text: text,
                happenedAt: TownFixtures.movedIn,
                language: .english,
            )
        }
        let hello = try make("Hi.")
        let sameHello = try make("Hi.")
        let bye = try make("Bye.")
        #expect(hello == sameHello)
        #expect(hello != bye)
    }
}
