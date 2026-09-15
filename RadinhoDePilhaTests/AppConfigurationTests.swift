import Testing
@testable import RadinhoDePilha

@Suite("App configuration")
struct AppConfigurationTests {
    @Test("A missing value yields no key")
    func missingValueYieldsNoKey() {
        #expect(AppConfiguration.sanitizedKey(from: nil) == nil)
    }

    @Test("An empty or blank value yields no key", arguments: ["", " ", "\n", "   \t "])
    func blankValueYieldsNoKey(raw: String) {
        #expect(AppConfiguration.sanitizedKey(from: raw) == nil)
    }

    @Test("The committed placeholder is not treated as a key")
    func placeholderYieldsNoKey() {
        #expect(AppConfiguration.sanitizedKey(from: AppConfiguration.keyPlaceholder) == nil)
    }

    @Test("A real value is returned as is")
    func realValueIsReturned() {
        #expect(AppConfiguration.sanitizedKey(from: "abc123") == "abc123")
    }

    @Test("Surrounding whitespace is trimmed")
    func surroundingWhitespaceIsTrimmed() {
        #expect(AppConfiguration.sanitizedKey(from: "  abc123\n") == "abc123")
    }
}
