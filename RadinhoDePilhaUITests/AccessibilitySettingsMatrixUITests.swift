import XCTest

/// Runs the Accessibility Inspector audits under each accessibility configuration of the device,
/// switching the settings itself through the Settings app, so the whole matrix runs unattended.
///
/// Each configuration states every setting explicitly instead of relying on what the previous one
/// left behind, and the last test puts the device back to its defaults. Labels are those of the
/// Settings app in English, the language of the device used in the TCC; the app itself is in
/// Brazilian Portuguese.
///
/// Every issue is recorded and printed instead of failing the test: the point is to register the
/// state of the app as it was evaluated, not to gate a build. Results are printed as
/// `AUDIT|<configuration>|<screen>|...`, so they can be pulled out of the `xcodebuild` log.
nonisolated final class AccessibilitySettingsMatrixUITests: XCTestCase {
    private struct Configuration {
        let name: String
        var largestText = false
        var increaseContrast = false
        var reduceTransparency = false
        var boldText = false
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor func test1Padrao() { run(Configuration(name: "Padrão")) }
    @MainActor func test2TextoMaior() { run(Configuration(name: "Texto no maior tamanho", largestText: true)) }
    @MainActor func test3Contraste() { run(Configuration(name: "Aumentar Contraste", increaseContrast: true)) }
    @MainActor func test4Transparencia() { run(Configuration(name: "Reduzir Transparência", reduceTransparency: true)) }
    @MainActor func test5Negrito() { run(Configuration(name: "Texto em Negrito", boldText: true)) }

    @MainActor func test6Todos() {
        run(Configuration(
            name: "Todos juntos",
            largestText: true,
            increaseContrast: true,
            reduceTransparency: true,
            boldText: true
        ))
    }

    /// Not an audit: leaves the device as it was before the matrix.
    @MainActor func test9Restaurar() {
        apply(Configuration(name: "Restaurar"))
    }

    // MARK: - One configuration

    @MainActor
    private func run(_ configuration: Configuration) {
        apply(configuration)
        print("AUDIT-CONFIG|\(configuration.name)")

        let app = XCUIApplication()
        app.terminate()
        app.launch()
        AuditTour.visitEveryScreen(app) { screen in
            audit(app, configuration: configuration.name, screen: screen)
        }
        app.terminate()
    }

    @MainActor
    private func audit(_ app: XCUIApplication, configuration: String, screen: String) {
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) \"\($0.label)\"" } ?? "-"
                print("AUDIT|\(configuration)|\(screen)|\(issue.auditType)|\(element)|\(issue.compactDescription)")
                return true
            }
            print("AUDIT-DONE|\(configuration)|\(screen)")
        } catch {
            print("AUDIT-ERROR|\(configuration)|\(screen)|\(error)")
        }
    }

    // MARK: - Settings app

    @MainActor
    private func apply(_ configuration: Configuration) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        openDisplayAndTextSize(in: settings)

        // In the order the page lists them, top to bottom, so scrolling only ever goes down.
        setSwitch("Bold Text", on: configuration.boldText, in: settings)

        let larger = settings.cells.containing(.staticText, identifier: "Larger Text").firstMatch
        larger.tap()
        setSwitch("Larger Accessibility Sizes", on: configuration.largestText, in: settings)
        let slider = settings.sliders.firstMatch
        if slider.waitForExistence(timeout: 5) {
            // Rightmost for the largest size; the middle step is the system default.
            slider.adjust(toNormalizedSliderPosition: configuration.largestText ? 1.0 : 0.5)
        } else {
            XCTFail("Controle de tamanho do texto não encontrado")
        }
        settings.navigationBars.buttons.element(boundBy: 0).tap()

        setSwitch("Reduce Transparency", on: configuration.reduceTransparency, in: settings)
        setSwitch("Increase Contrast", on: configuration.increaseContrast, in: settings)

        settings.terminate()
    }

    /// Settings reopens on the last page it showed, so first walk back to the root.
    @MainActor
    private func openDisplayAndTextSize(in settings: XCUIApplication) {
        for _ in 0..<6 {
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            guard back.exists, back.isHittable, !settings.staticTexts["Settings"].isHittable else { break }
            back.tap()
        }

        let accessibility = settings.descendants(matching: .any)["Accessibility"].firstMatch
        scrollTo(accessibility, in: settings)
        accessibility.tap()

        let display = settings.descendants(matching: .any)["Display & Text Size"].firstMatch
        scrollTo(display, in: settings)
        display.tap()
    }

    @MainActor
    private func setSwitch(_ label: String, on: Bool, in settings: XCUIApplication) {
        let toggle = settings.switches[label].firstMatch
        scrollTo(toggle, in: settings)
        guard toggle.exists else {
            XCTFail("Chave não encontrada: \(label)")
            return
        }
        guard isOn(toggle) != on else { return }

        toggle.tap()
        if isOn(toggle) != on {
            // On some layouts the row takes the tap without flipping the switch itself.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(isOn(toggle), on, "Não foi possível mudar: \(label)")
    }

    @MainActor
    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 30 {
            app.swipeUp()
            attempts += 1
        }
    }
}

/// The path through the app that every audit run follows.
enum AuditTour {
    @MainActor
    static func visitEveryScreen(_ app: XCUIApplication, audit: (String) -> Void) {
        audit("Narração (dia de jogo)")

        tab(app, "Ajustes").tap()
        audit("Ajustes")

        // Matched by label on any element type: at the largest text sizes the row may not be
        // exposed as a button, and it sits much further down the list.
        let learning = app.descendants(matching: .any)["Aprender os sinais"].firstMatch
        scrollTo(learning, in: app)
        learning.tap()
        audit("Aprender os sinais")

        tab(app, "Modos").tap()
        audit("Modos de teste")

        let simulate = app.descendants(matching: .any)["Simular partida ao vivo"].firstMatch
        scrollTo(simulate, in: app)
        simulate.tap()
        audit("Simulação (preparo)")

        let begin = app.descendants(matching: .any)["Começar a simulação"].firstMatch
        scrollTo(begin, in: app)
        begin.tap()
        // A few simulated minutes, so the list already holds some plays.
        sleep(8)
        audit("Narração (partida simulada)")
    }

    @MainActor
    private static func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[name]
        return inTabBar.exists ? inTabBar : app.buttons[name].firstMatch
    }

    @MainActor
    private static func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 30 {
            app.swipeUp()
            attempts += 1
        }
    }
}
