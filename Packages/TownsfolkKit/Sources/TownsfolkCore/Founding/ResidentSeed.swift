/// One combination of the four resident axes a resident is seeded from (requirements
/// §3.1): what the model is told the resident is, before it invents the rest.
struct ResidentSeed: Equatable {
    /// The combination's number among every combination the tables allow, so two seeds
    /// are the same combination exactly when their indexes are equal.
    let index: Int
    let occupation: SeedTables.Entry
    let personality: SeedTables.Entry
    let lifeStage: SeedTables.Entry
    let hobby: SeedTables.Entry
}
