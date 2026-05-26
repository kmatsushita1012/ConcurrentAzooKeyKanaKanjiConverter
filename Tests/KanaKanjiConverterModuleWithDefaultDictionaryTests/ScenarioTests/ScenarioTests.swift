import Foundation
@testable import KanaKanjiConverterModule
@testable import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

final class ScenarioTests: XCTestCase {
    private func makeSession() -> AncoSession {
        let requestOptions = ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: .autoMix,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: false,
            halfWidthKanaCandidate: false,
            learningType: .nothing,
            memoryDirectoryURL: URL(fileURLWithPath: ""),
            sharedContainerURL: URL(fileURLWithPath: ""),
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: .init(versionString: "scenario test")
        )
        return AncoSession(defaultDictionaryRequestOptions: requestOptions)
    }

    private func prepareSession(
        predictionMode: String = "automix",
        view: String? = nil
    ) async throws -> AncoSession {
        let romanSequenceToStablePrediction = ["a", "i", "u", "e", "o", "k", "a", "k", "i", "k", "u", "k", "e"]
        var session = self.makeSession()
        _ = try await session.execute(.setConfig(key: "inputStyle", value: "roman2kana"))
        if predictionMode != "automix" {
            _ = try await session.execute(.setConfig(key: "predictionMode", value: predictionMode))
        }
        for input in romanSequenceToStablePrediction {
            _ = try await session.execute(.input(input))
        }
        if let view {
            _ = try await session.execute(.setConfig(key: "view", value: view))
        }
        return session
    }

    private func assertStablePredictionPresent(
        _ session: AncoSession,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let stablePredictionTarget = "あいうえおかきくけこ"
        XCTAssertTrue(
            session.lastCandidates.contains(where: { $0.text == stablePredictionTarget }),
            "\(message), got: \(session.lastCandidates.map { $0.text })",
            file: file,
            line: line
        )
    }

    func testRoman2KanaPredictionStabilityKeepsKekoThroughUnresolvedSuffix() async throws {
        let stablePredictionTarget = "あいうえおかきくけこ"
        var session = try await self.prepareSession()

        XCTAssertEqual(session.composingText.convertTarget, "あいうえおかきくけ")
        XCTAssertEqual(session.lastCandidates.first?.text, stablePredictionTarget)

        _ = try await session.execute(.input("k"))

        XCTAssertEqual(session.composingText.convertTarget, "あいうえおかきくけk")
        self.assertStablePredictionPresent(session, message: "expected stable prediction candidate to survive for unresolved suffix")
    }

    func testPredictionViewKeepsStablePredictionResultsThroughUnresolvedSuffix() async throws {
        var session = try await self.prepareSession(view: "prediction")

        self.assertStablePredictionPresent(session, message: "expected prediction view to include stable prediction candidate")

        _ = try await session.execute(.input("k"))

        XCTAssertEqual(session.composingText.convertTarget, "あいうえおかきくけk")
        self.assertStablePredictionPresent(session, message: "expected prediction view to keep stable prediction candidate through unresolved suffix")
    }

    func testManualMixPredictionViewKeepsStablePredictionResultsThroughUnresolvedSuffix() async throws {
        var session = try await self.prepareSession(predictionMode: "manualmix", view: "prediction")

        self.assertStablePredictionPresent(session, message: "expected manualmix prediction view to include stable prediction candidate")

        _ = try await session.execute(.input("k"))

        XCTAssertEqual(session.composingText.convertTarget, "あいうえおかきくけk")
        self.assertStablePredictionPresent(session, message: "expected manualmix prediction view to keep stable prediction candidate through unresolved suffix")
    }

}
