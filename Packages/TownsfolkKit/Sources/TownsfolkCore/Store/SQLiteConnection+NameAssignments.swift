import Foundation

extension SQLiteConnection {
    func includedName(_ id: Interest.ID) throws(TownStoreError) -> Bool {
        try !rows(
            "SELECT id FROM interests WHERE id = ? AND excluded = 0",
            [.id(id.rawValue)],
        ) { row throws(TownStoreError) in
            try row.uuid()
        }.isEmpty
    }

    func unheldName(_ id: Interest.ID) throws(TownStoreError) -> Bool {
        guard try includedName(id) else {
            return false
        }
        return try rows(
            """
            SELECT resident_interests.resident_id FROM resident_interests
            JOIN residents ON residents.id = resident_interests.resident_id
            WHERE interest_id = ? AND residents.moved_out_at IS NULL LIMIT 1
            """,
            [.id(id.rawValue)],
        ) { row throws(TownStoreError) in try row.uuid() }.isEmpty
    }

    /// Rechecks each assignment after the scene's name writes, while the transaction owns
    /// the write lock. Only the child row changes; no stale resident snapshot is written.
    func assign(_ assignment: ResidentInterestAssignment) throws(TownStoreError) {
        guard try unheldName(assignment.interest) else {
            return
        }
        let residents = try residents()
        guard let resident = residents.first(where: { $0.id == assignment.resident }),
              resident.status == .living, resident.interests.count < Resident.maxInterests,
              !resident.interests.contains(assignment.interest)
        else {
            return
        }
        let position = try firstRow(
            "SELECT COALESCE(MAX(position), -1) + 1 FROM resident_interests WHERE resident_id = ?",
            [.id(resident.id.rawValue)],
        ) { row throws(TownStoreError) in try row.count() } ?? 0
        try run(
            "INSERT INTO resident_interests (resident_id, position, interest_id) VALUES (?, ?, ?)",
            [
                .id(resident.id.rawValue),
                .integer(Int64(position)),
                .id(assignment.interest.rawValue),
            ],
        )
    }
}
