/// Why the seed tables could not be loaded. No case carries an id or a line from the file:
/// a seed file is shipped text, and an error reaches logs and test output
/// (`designing-errors`).
public enum SeedTablesError: Error, Equatable, Sendable {
    /// The file is there but does not decode as a seed table.
    case malformed
    /// The file is not in the bundle, or could not be read.
    case missing
    /// The file declares a format version this build does not read.
    case unsupportedVersion(Int)
}
