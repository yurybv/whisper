import XCTest
@testable import Whisper

@MainActor
final class ModesModelTests: XCTestCase {
    private var retainedControllers: [PersistenceController] = []

    func testDefaultModeCannotBeRenamedOrDeleted() throws {
        let model = try makeModel()
        let defaultMode = try XCTUnwrap(model.modes.first)

        XCTAssertTrue(defaultMode.isDefault)
        XCTAssertFalse(model.canRename(defaultMode))
        XCTAssertFalse(model.canDelete(defaultMode))
    }

    func testBlankAndDuplicateDraftsRemainUnsavable() throws {
        let model = try makeModel()
        model.beginCreate()
        let editor = try XCTUnwrap(model.editor)

        XCTAssertFalse(editor.canSave)
        XCTAssertEqual(editor.validationMessage, "Enter a mode name.")

        editor.name = "Default"
        editor.instructions = "Translate to English."

        XCTAssertFalse(editor.canSave)
        XCTAssertEqual(editor.validationMessage, "A mode with this name already exists.")
    }

    func testCreatesRenamesAndActivatesCustomMode() throws {
        let model = try makeModel()
        model.beginCreate()
        let editor = try XCTUnwrap(model.editor)
        editor.name = "English Translation"
        editor.instructions = "Translate Russian speech into natural English."
        editor.inputLanguage = .russian

        try model.saveEditor()

        let created = try XCTUnwrap(model.modes.first { $0.name == "English Translation" })
        XCTAssertEqual(created.languageHint, "ru")
        XCTAssertEqual(model.selectedModeID, created.id)

        model.beginRename(created.id)
        let renameEditor = try XCTUnwrap(model.editor)
        renameEditor.name = "Conversational English"
        try model.saveEditor()
        try model.activate(created.id)

        XCTAssertEqual(model.modes.first { $0.id == created.id }?.name, "Conversational English")
        XCTAssertEqual(model.activeModeID, created.id)
    }

    func testDuplicateGetsUniqueNameAndDeletingActiveModeFallsBackToDefault() throws {
        let model = try makeModel()
        model.beginCreate()
        let editor = try XCTUnwrap(model.editor)
        editor.name = "Technical Notes"
        editor.instructions = "Keep technical terms."
        try model.saveEditor()
        let original = try XCTUnwrap(model.modes.first { $0.name == "Technical Notes" })

        let duplicate = try model.duplicate(original.id)
        let secondDuplicate = try model.duplicate(original.id)

        XCTAssertEqual(duplicate.name, "Technical Notes Copy")
        XCTAssertEqual(secondDuplicate.name, "Technical Notes Copy 2")
        try model.activate(original.id)
        model.requestDelete(original.id)
        try model.confirmDelete()

        XCTAssertNil(model.modes.first { $0.id == original.id })
        XCTAssertEqual(model.activeModeID, ModeDefinition.defaultMode.id)
    }

    func testFailedPresentationActionShowsSafeError() throws {
        let model = try makeModel()
        model.beginCreate()
        let editor = try XCTUnwrap(model.editor)
        editor.name = "Disabled"
        editor.instructions = "Keep technical terms."
        editor.isEnabled = false
        try model.saveEditor()
        let mode = try XCTUnwrap(model.modes.first { $0.name == "Disabled" })

        model.activateForPresentation(mode.id)

        XCTAssertEqual(model.errorMessage, "The mode could not be activated.")
    }

    private func makeModel() throws -> ModesModel {
        let controller = try PersistenceController(inMemory: true)
        retainedControllers.append(controller)
        let suiteName = "ModesModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let repository = ModeRepository(
            context: controller.container.mainContext,
            userDefaults: defaults
        )
        try repository.seedDefaultMode()
        return try ModesModel(repository: repository)
    }
}
