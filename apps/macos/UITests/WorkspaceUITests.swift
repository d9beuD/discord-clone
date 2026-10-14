import XCTest

@MainActor
final class WorkspaceUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchApp(appearance: String = "light") {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["UITEST_APPEARANCE"] = appearance
        app.launch()
    }

    private func openDemo() {
        let demo = app.buttons["login.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Se connecter"].isEnabled)
        demo.click()
        XCTAssertTrue(server("L’Atelier").waitForExistence(timeout: 5))
    }

    private func channel(_ name: String) -> XCUIElement {
        // A native sidebar exposes selectable rows, rather than the SwiftUI Label's identifier.
        app.descendants(matching: .any).matching(identifier: "navigation.channels").firstMatch
            .descendants(matching: .any).matching(
                NSPredicate(format: "label == %@ OR value == %@", name, name)
            ).firstMatch
    }

    private func server(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "navigation.servers").firstMatch
            .descendants(matching: .any).matching(
                NSPredicate(format: "label == %@ OR value == %@", name, name)
            ).firstMatch
    }

    func testNativeSidebarAndInspectorToggleIndependently() {
        launchApp()
        defer { app.terminate() }
        openDemo()
        let sidebarToggle = app.checkBoxes["workspace.sidebar-toggle"]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 3))
        sidebarToggle.click()
        XCTAssertTrue(server("L’Atelier").waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["member.alex"].exists)
        app.checkBoxes["workspace.sidebar-toggle"].click()
        XCTAssertTrue(server("L’Atelier").waitForExistence(timeout: 3))
        XCTAssertTrue(channel("général").exists)
        app.checkBoxes["workspace.members-toggle"].click()
        XCTAssertTrue(app.buttons["member.alex"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.checkBoxes["workspace.sidebar-toggle"].exists)
        XCTAssertTrue(server("L’Atelier").exists)
        app.checkBoxes["workspace.members-toggle"].click()
        XCTAssertTrue(app.buttons["member.alex"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.checkBoxes["workspace.sidebar-toggle"].exists)
    }

    func testNavigationDraftKeyboardSendCopyDeleteAndProfile() {
        launchApp()
        defer { app.terminate() }
        openDemo()
        server("Rust & Friends").click()
        XCTAssertTrue(channel("discussion").exists)
        server("L’Atelier").click()
        channel("idées").click()
        let editor = app.textViews["chat.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("First line")
        editor.typeKey(.return, modifierFlags: .shift)
        editor.typeText("Second line")
        XCTAssertTrue((editor.value as? String)?.contains("\n") == true)
        channel("design").click()
        channel("idées").click()
        XCTAssertEqual(editor.value as? String, "First line\nSecond line")
        editor.click()
        editor.typeKey(.return, modifierFlags: [])
        let content = "First line\nSecond line"
        let message = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", content, content)
        ).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        XCTAssertTrue(((message.value as? String) ?? message.label).contains(content))
        XCTAssertEqual(editor.value as? String, "")
        message.rightClick()
        app.menuItems["Copier le message"].click()
        editor.click()
        editor.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "First line\nSecond line")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(.delete, modifierFlags: [])
        message.rightClick()
        app.menuItems["Supprimer le message"].click()
        XCTAssertTrue(message.waitForNonExistence(timeout: 3))
        app.buttons["workspace.profile"].click()
        XCTAssertTrue(app.staticTexts["profile.name"].waitForExistence(timeout: 3))
        app.buttons["profile.close"].click()
        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertFalse(app.buttons["member.alex"].exists)
        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["member.alex"].waitForExistence(timeout: 3))
        attachScreenshot("workspace-light")
    }

    func testSettingsDarkAppearanceAndLogout() {
        launchApp()
        defer { app.terminate() }
        openDemo()
        let editor = app.textViews["chat.editor"]
        editor.click()
        editor.typeText(" ")
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(.delete, modifierFlags: [])
        app.typeKey(",", modifierFlags: .command)
        let picker = app.popUpButtons["settings.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.click()
        app.menuItems["Sombre"].click()
        attachScreenshot("settings-dark")
        app.buttons["settings.logout"].click()
        let settingsWindow = app.windows.containing(.popUpButton, identifier: "settings.appearance").firstMatch
        if settingsWindow.exists { settingsWindow.buttons[XCUIIdentifierCloseWindow].click() }
        XCTAssertTrue(app.buttons["login.demo"].waitForExistence(timeout: 3))
    }

    func testDarkWorkspaceAndMinimumWidth() {
        launchApp(appearance: "dark")
        defer { app.terminate() }
        openDemo()
        attachScreenshot("workspace-dark")
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -280, dy: -180)))
        XCTAssertGreaterThanOrEqual(window.frame.width, 900)
        XCTAssertLessThan(window.frame.width, 1050)
        XCTAssertTrue(app.buttons["member.alex"].exists)
        XCTAssertTrue(app.textViews["chat.editor"].exists)
        attachScreenshot("workspace-compact")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
