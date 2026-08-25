import Foundation
import XCTest
@testable import Whisper

final class ModeSwitcherModelTests: XCTestCase {
    func testSearchIsCaseInsensitiveAndPreservesModeOrder() {
        var model = ModeSwitcherModel(modes: makeModes(), activeModeID: defaultID)

        model.query = "ENGLISH"

        XCTAssertEqual(model.filteredModes.map(\.name), ["English Translation"])
    }

    func testArrowNavigationWrapsAcrossFilteredModes() {
        var model = ModeSwitcherModel(modes: makeModes(), activeModeID: defaultID)

        model.moveSelection(.up)
        XCTAssertEqual(model.selectedMode?.name, "Concise Reply")

        model.moveSelection(.down)
        XCTAssertEqual(model.selectedMode?.name, "Default")
    }

    func testReturnActivatesSelectedMode() {
        var model = ModeSwitcherModel(modes: makeModes(), activeModeID: defaultID)
        model.moveSelection(.down)

        XCTAssertEqual(model.handle(.activate), .activate(englishID))
    }

    func testEscapeClosesWithoutChangingMode() {
        var model = ModeSwitcherModel(modes: makeModes(), activeModeID: defaultID)
        model.moveSelection(.down)

        XCTAssertEqual(model.handle(.close), .close)
        XCTAssertEqual(model.activeModeID, defaultID)
    }

    func testDisabledModesAreExcludedFromSearchAndNavigation() {
        var model = ModeSwitcherModel(modes: makeModes(), activeModeID: defaultID)

        XCTAssertEqual(model.filteredModes.map(\.name), ["Default", "English Translation", "Concise Reply"])
        model.query = "disabled"
        XCTAssertTrue(model.filteredModes.isEmpty)
        XCTAssertNil(model.selectedMode)
        XCTAssertNil(model.handle(.activate))
    }

    private let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let englishID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    private func makeModes() -> [ModeDefinition] {
        [
            mode(id: defaultID, name: "Default", languageHint: nil, enabled: true, index: 0),
            mode(id: englishID, name: "English Translation", languageHint: "ru", enabled: true, index: 1),
            mode(name: "Disabled Mode", languageHint: "en", enabled: false, index: 2),
            mode(name: "Concise Reply", languageHint: "en", enabled: true, index: 3),
        ]
    }

    private func mode(
        id: UUID = UUID(),
        name: String,
        languageHint: String?,
        enabled: Bool,
        index: Int
    ) -> ModeDefinition {
        ModeDefinition(
            id: id,
            name: name,
            instructions: "Test instructions",
            languageHint: languageHint,
            isDefault: index == 0,
            isEnabled: enabled,
            sortIndex: index,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
