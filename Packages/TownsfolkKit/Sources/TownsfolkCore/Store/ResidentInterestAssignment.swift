/// A requested uptake of an unheld name by one living resident. An excluded or
/// already held name, a full recipient, or a recipient who left is a no-op at commit.
public struct ResidentInterestAssignment: Sendable, Equatable {
    /// The resident taking up the name.
    public let resident: Resident.ID
    /// The stored name being taken up; its mention count is unchanged.
    public let interest: Interest.ID

    /// Creates one additive assignment for a scene transaction.
    public init(resident: Resident.ID, interest: Interest.ID) {
        self.resident = resident
        self.interest = interest
    }
}
