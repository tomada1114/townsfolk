/// One assembled call: the instructions, the prompt, and what the prompt carries — the
/// labels a reply may name, and the items a refusal counts against.
struct ScenePrompt {
    /// The rules every scene follows.
    let instructions: String
    /// The town, the roster, the speakers, the events, the names, the seed, and the log.
    let prompt: String
    /// Each post label in the prompt, and the post it stands for.
    let labels: [String: Post.ID]
    /// How many recent posts the prompt carries.
    let postsCarried: Int
    /// Your posts in the prompt, the seed's included.
    let yourPosts: Set<Post.ID>
    /// The names you brought up that the prompt lists.
    let names: Set<Interest.ID>
}
