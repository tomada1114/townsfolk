import Foundation
import TownsfolkCore

enum EngineResponseFixtures {
    static func post() throws -> Post {
        try post(at: EngineFixtures.start, reply: nil)
    }

    static func post(at time: Date) throws -> Post {
        try post(at: time, reply: nil)
    }

    static func post(at time: Date, reply: Post.ID?) throws -> Post {
        try Post(
            id: Post.ID(),
            author: .you,
            text: "Bread today?",
            happenedAt: time,
            replyTarget: reply,
        )
    }

    static func answered(_ post: Post, by resident: Resident.ID) throws -> Post {
        try Post(
            id: Post.ID(),
            author: .resident(resident),
            text: "Earlier answer.",
            happenedAt: EngineFixtures.time("10:03:00"),
            replyTarget: post.id,
            origin: .response,
            sceneID: SceneID(),
        )
    }
}
