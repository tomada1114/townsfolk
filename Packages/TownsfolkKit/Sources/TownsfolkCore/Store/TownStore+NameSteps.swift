import Foundation

extension TownStore {
    /// Exclusion while generation is held withdraws the scene, preserving its due time.
    func storeNameScene(
        _ scene: SceneStep,
        seededBy name: Interest.ID,
    ) throws(TownStoreError) -> Bool {
        guard !Task.isCancelled else { throw .cancelled }
        let connection = try liveConnection()
        var stored = false
        try connection.transaction { () throws(TownStoreError) in
            guard try connection.includedName(name) else {
                return
            }
            try connection.insert(scene)
            stored = true
        }
        if stored {
            announce(.sceneStored(posts: scene.posts.map(\.id)))
        }
        return stored
    }

    /// A generated newcomer may only keep the seed they were invented from. A race
    /// withdraws the entire move, leaving the bounded attempt loop to redraw.
    func recordNameMove(
        _ move: MoveStep,
        seededBy name: Interest.ID,
    ) throws(TownStoreError) -> Bool {
        guard !Task.isCancelled else { throw .cancelled }
        let connection = try liveConnection()
        var stored = false
        try connection.transaction { () throws(TownStoreError) in
            guard try connection.unheldName(name) else {
                return
            }
            try connection.upsert(move.resident)
            try connection.insert(move.event)
            stored = true
        }
        if stored {
            announce(.moveRecorded(move.resident.id))
        }
        return stored
    }
}
