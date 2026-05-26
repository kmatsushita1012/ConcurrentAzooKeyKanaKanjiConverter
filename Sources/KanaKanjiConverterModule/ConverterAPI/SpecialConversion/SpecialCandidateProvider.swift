public protocol SpecialCandidateProvider: Sendable {
    func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options: ConvertRequestOptions) async -> [Candidate]
}

public struct CalendarSpecialCandidateProvider: SpecialCandidateProvider {
    public init() {}
    public func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options _: ConvertRequestOptions) async -> [Candidate] {
        (await converter.toWarekiCandidates(inputData)) + (await converter.toSeirekiCandidates(inputData))
    }
}

public struct EmailAddressSpecialCandidateProvider: SpecialCandidateProvider {
    public init() {}
    public func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options _: ConvertRequestOptions) async -> [Candidate] {
        await converter.toEmailAddressCandidates(inputData)
    }
}

public struct TypographySpecialCandidateProvider: SpecialCandidateProvider {
    public init() {}
    public func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options _: ConvertRequestOptions) async -> [Candidate] {
        await converter.typographicalCandidates(inputData)
    }
}

public struct UnicodeSpecialCandidateProvider: SpecialCandidateProvider {
    public init() {}
    public func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options _: ConvertRequestOptions) async -> [Candidate] {
        await converter.unicodeCandidates(inputData)
    }
}

public struct VersionSpecialCandidateProvider: SpecialCandidateProvider {
    public init() {}
    public func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options: ConvertRequestOptions) async -> [Candidate] {
        await converter.toVersionCandidate(inputData, options: options)
    }
}

public struct TimeExpressionSpecialCandidateProvider: SpecialCandidateProvider {
    public init() {}
    public func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options _: ConvertRequestOptions) async -> [Candidate] {
        await converter.convertToTimeExpression(inputData)
    }
}

public struct CommaSeparatedNumberSpecialCandidateProvider: SpecialCandidateProvider {
    public init() {}
    public func provideCandidates(converter: KanaKanjiConverter, inputData: ComposingText, options _: ConvertRequestOptions) async -> [Candidate] {
        await converter.commaSeparatedNumberCandidates(inputData)
    }
}

public extension SpecialCandidateProvider where Self == CalendarSpecialCandidateProvider {
    static var calendar: Self { .init() }
}

public extension SpecialCandidateProvider where Self == EmailAddressSpecialCandidateProvider {
    static var emailAddress: Self { .init() }
}

public extension SpecialCandidateProvider where Self == TypographySpecialCandidateProvider {
    static var typography: Self { .init() }
}

public extension SpecialCandidateProvider where Self == UnicodeSpecialCandidateProvider {
    static var unicode: Self { .init() }
}

public extension SpecialCandidateProvider where Self == VersionSpecialCandidateProvider {
    static var version: Self { .init() }
}

public extension SpecialCandidateProvider where Self == TimeExpressionSpecialCandidateProvider {
    static var timeExpression: Self { .init() }
}

public extension SpecialCandidateProvider where Self == CommaSeparatedNumberSpecialCandidateProvider {
    static var commaSeparatedNumber: Self { .init() }
}
