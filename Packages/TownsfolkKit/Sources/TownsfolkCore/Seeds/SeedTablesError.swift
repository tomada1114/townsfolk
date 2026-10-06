/// Why a language's seed tables could not be loaded. Each case names only the language
/// (and a version number): a seed file is shipped text, and an error reaches logs and test
/// output, so none carries an id or a line from the file (`designing-errors`).
public enum SeedTablesError: Error, Equatable, Sendable {
    /// The file is there but does not decode as a seed table.
    case malformed(TownLanguage)
    /// The language's file is not in the bundle, or could not be read.
    case missing(TownLanguage)
    /// The file declares a format version this build does not read.
    case unsupportedVersion(TownLanguage, version: Int)
}
