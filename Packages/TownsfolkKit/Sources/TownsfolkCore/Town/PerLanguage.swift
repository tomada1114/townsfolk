/// One value per ``TownLanguage`` — a limit that differs by language, such as the length
/// of a resident's post. A struct rather than a dictionary so a lookup can never miss.
public struct PerLanguage<Value: Sendable & Equatable>: Sendable, Equatable {
    /// The value for ``TownLanguage/english``.
    public var english: Value
    /// The value for ``TownLanguage/japanese``.
    public var japanese: Value

    /// Creates one value per language; a test builds a smaller one to reach a boundary.
    public init(english: Value, japanese: Value) {
        self.english = english
        self.japanese = japanese
    }

    /// The value for `language`.
    public subscript(language: TownLanguage) -> Value {
        switch language {
        case .english:
            english

        case .japanese:
            japanese
        }
    }
}
