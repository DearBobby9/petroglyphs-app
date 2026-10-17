import XCTest
import XCUIAutomation
import UIKit
import CoreGraphics
import Foundation

/// Uses the production views and document store in a separate app sandbox.
/// The synthesized drawing input is a simulator finger, not Apple Pencil evidence.
@MainActor
final class PetroglyphsSimulatorUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.bobbyjia.petroglyphs.acceptance")

    override func tearDownWithError() throws {
        if app.state == .runningForeground { capture("End of \(name)") }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        try super.tearDownWithError()
    }

    func testInkAndFixedBackgroundSurviveNavigationAndRelaunch() {
        launch()
        openSavedWorkspace()
        clearInkIfNeeded()
        chooseBackground(hex: "F4EDDE", name: "Warm paper")
        drawStroke(from: CGVector(dx: 0.25, dy: 0.35), to: CGVector(dx: 0.6, dy: 0.48))
        assertInkPresent(true)
        capture("Simulator finger ink before navigation")

        tap(app.buttons["Home"])
        openSavedWorkspace()
        assertBackground("Warm paper")
        assertInkPresent(true)

        app.terminate()
        app.launch()
        openSavedWorkspace()
        assertBackground("Warm paper")
        assertInkPresent(true)
        capture("Saved ink and fixed background after relaunch")

        // New ink after a relaunch must remain editable using document undo.
        drawStroke(from: CGVector(dx: 0.35, dy: 0.58), to: CGVector(dx: 0.65, dy: 0.68))
        performCanvasAction("Undo")
        assertInkPresent(true)
        XCTAssertFalse(app.descendants(matching: .any)["canvas.storageError"].exists)
    }

    func testClearThenNewInkHasIndependentUndoAndRedo() {
        launch()
        openSavedWorkspace()
        clearInkIfNeeded()
        drawStroke(from: CGVector(dx: 0.2, dy: 0.3), to: CGVector(dx: 0.4, dy: 0.5))
        assertInkPresent(true)
        capture("Original ink before clear")
        performCanvasAction("Clear ink")
        assertInkPresent(false)

        drawStroke(from: CGVector(dx: 0.6, dy: 0.35), to: CGVector(dx: 0.75, dy: 0.65))
        assertInkPresent(true)
        capture("New ink after clear")
        performCanvasAction("Undo")
        assertInkPresent(false)
        performCanvasAction("Undo")
        assertInkPresent(true)
        capture("Undo clear restores original ink")
        performCanvasAction("Redo")
        assertInkPresent(false)
        performCanvasAction("Redo")
        assertInkPresent(true)
        capture("Redo restores post-clear ink")
    }

    func testSelectAllDeleteAndVisibleUndoRestoresInk() {
        launch()
        openSavedWorkspace()
        clearInkIfNeeded()
        drawStroke(from: CGVector(dx: 0.28, dy: 0.36), to: CGVector(dx: 0.62, dy: 0.5))
        assertInkPresent(true)

        tap(app.buttons["canvas.select"])
        tap(app.buttons["canvas.selectAll"])

        let delete = app.buttons["canvas.deleteSelection"]
        wait("Select all must enable the visible delete control") {
            delete.exists && delete.isHittable && delete.isEnabled
        }
        tap(delete)
        wait("Deleting the selected ink must disable the visible delete control") {
            delete.exists && !delete.isEnabled
        }
        assertInkPresent(false)

        let undo = app.buttons["Undo"]
        wait("Deleting selected ink must expose an enabled visible Undo control") {
            undo.exists && undo.isHittable && undo.isEnabled
        }
        tap(undo)
        assertInkPresent(true)

        // Selection mode remains active after Undo. Exercise the visible
        // rectangle-selection gesture before deleting and undoing it again.
        drawStroke(from: CGVector(dx: 0.2, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.6))
        wait("Dragging a selection rectangle must enable the visible delete control") {
            delete.exists && delete.isHittable && delete.isEnabled
        }
        tap(delete)
        assertInkPresent(false)
        wait("Deleting the rectangle selection must expose an enabled visible Undo control") {
            undo.exists && undo.isHittable && undo.isEnabled
        }
        tap(undo)
        assertInkPresent(true)
        capture("Select all delete and visible Undo restore ink")
    }

    func testConnectionEditsAndModeAreDiscardedOnCancel() {
        launch()
        openSavedWorkspace()
        tap(app.buttons["canvas.connectionSettings"])
        let pairedMode = app.buttons["Paired Mac"]
        let legacyMode = app.buttons["Legacy cloud"]
        XCTAssertTrue(pairedMode.waitForExistence(timeout: 5))
        let originallyPaired = pairedMode.isSelected
        if !originallyPaired { tap(pairedMode) }
        let address = app.textFields["Paired Mac URL"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let originalAddress = textFieldValue(address)
        replaceText(in: address, with: "http://127.0.0.1:9/test-a")
        let testConnection = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Test Connection")).firstMatch
        tap(testConnection)
        replaceText(in: address, with: "http://127.0.0.1:9/test-b")
        wait("Editing the address must clear the earlier connection test and its progress") {
            let staleResult = self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "✗ Not reachable")).firstMatch
            return self.textFieldValue(address) == "http://127.0.0.1:9/test-b"
                && testConnection.isEnabled && testConnection.progressIndicators.count == 0 && !staleResult.exists
        }
        capture("Test A invalidated after editing address B")
        tap(legacyMode)
        XCTAssertTrue(app.textFields["e.g. A7K2"].waitForExistence(timeout: 5))
        capture("Unsaved URL and connection mode edits")
        tap(app.buttons["Cancel"])

        tap(app.buttons["canvas.connectionSettings"])
        XCTAssertTrue(pairedMode.waitForExistence(timeout: 5))
        XCTAssertEqual(pairedMode.isSelected, originallyPaired, "Cancel must preserve the saved connection mode")
        if !originallyPaired { tap(pairedMode) }
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertEqual(textFieldValue(address), originalAddress, "Cancel must preserve the saved Mac address")
        capture("Original connection settings after Cancel")
        tap(app.buttons["Cancel"])
    }

    func testLargeTextAndRotationKeepCanvasControlsReachableAndBackgroundFixed() {
        launch(contentSize: .accessibilityExtraExtraExtraLarge)
        openSavedWorkspace()
        chooseBackground(hex: "F4EDDE", name: "Warm paper")

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation.isLandscape
            wait("Workspace should adopt the requested orientation") {
                let frame = self.app.windows.firstMatch.frame
                return landscape ? frame.width > frame.height : frame.height > frame.width
            }
            for identifier in ["canvas.background", "canvas.darkMode", "canvas.editing", "canvas.connectionSettings"] {
                assertHittable(app.buttons[identifier])
            }
            assertHittable(app.buttons["Home"])
            assertBackground("Warm paper")
            capture(landscape ? "Accessibility XXXL landscape workspace" : "Accessibility XXXL portrait workspace")
        }

        let theme = app.buttons["canvas.darkMode"]
        let previousTheme = theme.value as? String
        tap(theme)
        wait("Theme should change") { (theme.value as? String) != previousTheme }
        assertBackground("Warm paper")
        capture("Theme changed with fixed Warm paper background")
        tap(theme)
        assertBackground("Warm paper")

        tap(app.buttons["canvas.connectionSettings"])
        assertHittable(app.buttons["Cancel"])
        capture("Accessibility XXXL connection settings")
        tap(app.buttons["Cancel"])
    }

    private func launch(contentSize: UIContentSizeCategory? = nil) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        // Only the active endpoint is overridden. The saved address and mode
        // remain real persisted values so the Cancel test cannot mask writes.
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-serverURLString", ""]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        }
        app.launch()
    }

    private func openSavedWorkspace() {
        tap(app.buttons["Open saved workspace"])
        XCTAssertTrue(app.descendants(matching: .any)["canvas.workspace"].waitForExistence(timeout: 5))
        assertHittable(app.buttons["canvas.editing"])
    }

    private func chooseBackground(hex: String, name: String) {
        tap(app.buttons["canvas.background"])
        tap(app.buttons["canvas.background.\(hex)"])
        tap(app.buttons["canvas.backgroundDone"])
        assertBackground(name)
    }

    private func assertBackground(_ name: String) {
        wait("The canvas should retain its selected background") {
            (self.app.buttons["canvas.background"].value as? String) == name
        }
    }

    private func drawStroke(from start: CGVector, to end: CGVector) {
        let canvas = app.descendants(matching: .any)["canvas.surface"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: start).press(forDuration: 0.05,
            thenDragTo: canvas.coordinate(withNormalizedOffset: end), withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    private func clearInkIfNeeded() {
        openEditingMenu()
        let clear = app.buttons["Clear ink"]
        if clear.isEnabled { clear.tap() }
        else { dismissEditingMenu() }
        assertInkPresent(false)
    }

    private func assertInkPresent(_ expected: Bool) {
        openEditingMenu()
        XCTAssertEqual(app.buttons["Clear ink"].isEnabled, expected,
                       expected ? "Real simulator finger input must create editable ink" : "Undo or clear must leave no ink")
        dismissEditingMenu()
    }

    private func performCanvasAction(_ title: String) {
        openEditingMenu()
        // PencilKit also exposes Undo/Redo buttons in its separate palette.
        // The document editing actions live in the presented menu collection.
        let action = app.collectionViews.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled, "\(title) should be available for this edit sequence")
        action.tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
    }

    private func openEditingMenu() {
        tap(app.buttons["canvas.editing"])
        XCTAssertTrue(app.buttons["Clear ink"].waitForExistence(timeout: 5))
    }

    private func dismissEditingMenu() {
        // The menu covers its source button and does not handle Escape on iPad.
        // UIKit consumes this outside tap to dismiss the presented menu.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["Clear ink"].waitForNonExistence(timeout: 5))
    }

    private func textFieldValue(_ field: XCUIElement) -> String {
        let value = field.value as? String ?? ""
        return value == field.placeholderValue ? "" : value
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        tap(field)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
    }

    private func tap(_ element: XCUIElement) {
        assertHittable(element)
        element.tap()
    }

    private func assertHittable(_ element: XCUIElement) {
        wait("Control should exist and be reachable: \(element.identifier)") { element.exists && element.isHittable }
    }

    private func wait(_ description: String, timeout: TimeInterval = 5, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, description)
    }

    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
