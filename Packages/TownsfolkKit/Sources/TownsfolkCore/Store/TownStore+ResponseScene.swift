import Foundation
import os

extension TownStore {
    func storeResponseScene(_ scene: SceneStep) throws(TownStoreError) -> Bool {
        try storeResponseScene(scene, extractedNames: [])
    }

    /// A generated response can have been withdrawn while the model was running. Check
    /// its exact pending row and source inside the scene transaction, before any write.
    func storeResponseScene(
        _ scene: SceneStep,
        extractedNames: [String],
    ) throws(TownStoreError) -> Bool {
        guard !Task.isCancelled else { throw .cancelled }
        guard let response = scene.deliveredResponse else {
            return false
        }
        let connection = try liveConnection()
        var stored = false
        var touched = 0
        try connection.transaction { () throws(TownStoreError) in
            let eligible = try connection.rows(
                """
                SELECT pending_responses.post_id FROM pending_responses
                JOIN posts ON posts.id = pending_responses.post_id
                WHERE post_id = ? AND due_at = ? AND posts.excluded = 0 LIMIT 1
                """,
                [.id(response.post.rawValue), .date(response.dueAt)],
            ) { row throws(TownStoreError) in try row.uuid() }
            guard !eligible.isEmpty else {
                return
            }
            var effective = scene
            if let source = try connection.post(response.post.rawValue, tuning: tuning) {
                let interests = try connection.extractedInterests(extractedNames, source: source)
                effective.interests += interests
                touched = interests.count
            }
            try connection.insert(effective)
            stored = true
        }
        if stored {
            announce(.sceneStored(posts: scene.posts.map(\.id)))
            AppLog.scenes.info("names recorded or touched: \(touched, privacy: .public)")
        }
        return stored
    }
}
