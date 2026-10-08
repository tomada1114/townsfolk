import Foundation
import FoundationModels
import NaturalLanguage

/// Turns the model's answer into a ``WrittenScene``, or the reason it is discarded
/// (REQ-008–REQ-010). The model only writes; whether what it wrote may be shown is
/// decided here, by rules (`docs/architecture.md` › Principles).
struct SceneValidation {
    /// The prefix of a label naming an earlier post of the same scene, "S1".
    private static let scenePostPrefix = "S"
    /// How many sentences a post may hold (requirements.md:168).
    private static let sentenceCount = 1 ... 2

    let request: SceneRequest
    let seed: SceneSeed
    /// The labels of the posts the prompt carried.
    let labels: [String: Post.ID]
    let tuning: Tuning
    let extractNames: Bool

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The sentences in `text`. `NLTokenizer` rather than Foundation's `.bySentences`,
    /// which splits after "Dr." and "Mrs." and so would discard a valid two-sentence post.
    private static func sentences(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex ..< text.endIndex).count
    }

    /// The checked scene `content` holds, or why there is none.
    func outcome(for content: GeneratedContent) -> SceneOutcome {
        let draft: SceneDraft
        do {
            draft = try SceneDraft(content)
        } catch {
            return .skipped(.malformedOutput)
        }
        guard WrittenScene.postCount.contains(draft.posts.count) else {
            return .skipped(.invalidPosts)
        }
        var speakers: [Resident.ID] = []
        for post in draft.posts {
            // Compared as the prompt shows names, folded onto one line.
            let name = ScenePromptBuilder.oneLine(Self.trimmed(post.speaker))
            guard let speaker = request.speakingResidents
                .first(where: { ScenePromptBuilder.oneLine($0.name) == name })
            else {
                return .skipped(.invalidSpeaker)
            }
            speakers.append(speaker.id)
        }
        if case let .yourPost(_, _, lead?) = seed, speakers.first != lead {
            return .skipped(.leadSpeakerMismatch)
        }
        var posts: [WrittenPost] = []
        for (index, (post, speaker)) in zip(draft.posts, speakers).enumerated() {
            let text = Self.trimmed(post.text)
            guard !text.isEmpty,
                  text.count <= tuning.timeline.residentPostMaxLength,
                  Self.sentenceCount.contains(Self.sentences(in: text))
            else {
                return .skipped(.invalidPosts)
            }
            let target = replyTarget(post.replyTo, at: index)
            posts.append(WrittenPost(speaker: speaker, text: text, replyTarget: target))
        }
        let names: [String] = if extractNames, case let .yourPost(source, true, _) = seed {
            NameTerms.validated(draft.names, in: source.text)
        } else {
            []
        }
        return .written(WrittenScene(
            seed: seed,
            posts: posts,
            topicTags: tags(draft.topicTags),
            names: names,
        ))
    }

    /// What the post at `index` replies to: your quoted seed post for the first post,
    /// whatever the model said; otherwise the post `label` names in the prompt or an
    /// earlier post of this scene, and none for a label that names neither.
    private func replyTarget(_ label: String?, at index: Int) -> WrittenPost.ReplyTarget? {
        if index == 0, case let .yourPost(post, true, _) = seed {
            return .post(post.id)
        }
        guard let named = label.map({ Self.trimmed($0).uppercased() }) else {
            return nil
        }
        if let post = labels[named] {
            return .post(post)
        }
        guard named.hasPrefix(Self.scenePostPrefix),
              let number = Int(named.dropFirst(Self.scenePostPrefix.count)),
              number >= 1, number <= index
        else {
            return nil
        }
        return .earlierInScene(number - 1)
    }

    /// The tags that are not blank and fit ``Post/topicTagMaxLength``, trimmed, each once
    /// — a repeat in any case is dropped, the first spelling kept — at most
    /// ``Post/maxTopicTags`` of them.
    private func tags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        let kept = tags.map(Self.trimmed).filter { tag in
            !tag.isEmpty && tag.count <= Post.topicTagMaxLength && seen.insert(tag.lowercased())
                .inserted
        }
        return Array(kept.prefix(Post.maxTopicTags))
    }
}
