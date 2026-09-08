import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clipwise

/// Pins the "Hide passwords & secrets" heuristic. `ClipboardItem.looksLikePassword(_:)`
/// is the pure decision; the instance property just feeds it the item's plain text.
/// Every exclusion here (URL, email, path, domain, prose) exists because it once
/// produced a false positive in real use, so a change that flips one of these is a
/// regression, not a simplification.
final class PasswordDetectionTests: XCTestCase {

    private func isPassword(_ text: String) -> Bool {
        ClipboardItem.looksLikePassword(text)
    }

    // MARK: - Character-class heuristic

    func testFourCharacterClassesIsPassword() {
        XCTAssertTrue(isPassword("Xk9#mP2$vLq7"))
    }

    func testThreeClassesWithHighDigitOrSymbolRatioIsPassword() {
        // Upper + lower + digit, 8 of 10 characters are digits.
        XCTAssertTrue(isPassword("Ab12345678"))
    }

    func testThreeClassesThatReadLikeAWordIsNotPassword() {
        // Upper + lower + digit, but only 1 of 9 characters is a digit.
        XCTAssertFalse(isPassword("Password1"))
    }

    func testTwoClassesIsNotPassword() {
        XCTAssertFalse(isPassword("abcdefgh1234"))
        XCTAssertFalse(isPassword("qwertyuiop"))
    }

    // MARK: - Length and shape

    func testShorterThanEightCharactersIsNotPassword() {
        XCTAssertFalse(isPassword("Xk9#mP2"))
    }

    func testLengthBoundsAreInclusiveAt128() {
        let unit = "Xk9#"
        let exactly128 = String(repeating: unit, count: 32)
        let over = exactly128 + "a"
        XCTAssertEqual(exactly128.count, 128)
        XCTAssertTrue(isPassword(exactly128))
        XCTAssertFalse(isPassword(over))
    }

    func testMultiLineTextIsNotPassword() {
        XCTAssertFalse(isPassword("Xk9#mP2$\nvLq7abcD"))
    }

    func testTextContainingSpacesIsNotPassword() {
        XCTAssertFalse(isPassword("Xk9#mP2$ vLq7"))
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertTrue(isPassword("  Xk9#mP2$vLq7\n"))
    }

    func testEmptyOrWhitespaceOnlyIsNotPassword() {
        XCTAssertFalse(isPassword(""))
        XCTAssertFalse(isPassword("   \n\t "))
    }

    // MARK: - Known secret prefixes

    func testKnownSecretPrefixesAreAlwaysPasswords() {
        // These are deliberately lowercase+digit-only bodies (2 character classes), so
        // only the prefix rule can be what flags them.
        let tokens = [
            "sk-abcdefghijklmnop",            // OpenAI / Anthropic
            "ghp_abcdefghijklmnop",           // GitHub classic
            "github_pat_abcdefghijklmnop",    // GitHub fine-grained
            "glpat-abcdefghijklmnop",         // GitLab
            "xoxb-1234-abcdefghijklmnop",     // Slack bot
            "xapp-1-abcdefghijklmnop",        // Slack app
            "sk_live_abcdefghijklmnop",       // Stripe secret
            "hf_abcdefghijklmnop",            // Hugging Face
            "npm_abcdefghijklmnop",           // npm
            "eyJhbGciOiJIUzI1NiJ9",           // JWT header
            "AKIAIOSFODNN7EXAMPLE",           // AWS access key id
            "AIzaSyabcdefghijklmnop",         // Google API key
        ]
        for token in tokens {
            XCTAssertTrue(isPassword(token), "\(token) should be detected by its prefix")
        }
    }

    // MARK: - PEM private keys

    func testPEMPrivateKeyBlocksArePasswords() {
        let rsa = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF8PbnGy0AHB4pP1mkQqJ2xGkzHhG
        -----END RSA PRIVATE KEY-----
        """
        let openssh = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        -----END OPENSSH PRIVATE KEY-----
        """
        let pgp = """
        -----BEGIN PGP PRIVATE KEY BLOCK-----

        lQdGBGF0h5UBEADIcE8m7f3ZlKb1z0G6W8b7Cq6mY9m2F7bFq2yRJ1Tc9X8JzgG
        -----END PGP PRIVATE KEY BLOCK-----
        """
        XCTAssertTrue(isPassword(rsa))
        XCTAssertTrue(isPassword(openssh))
        XCTAssertTrue(isPassword(pgp))
    }

    func testPEMCertificateIsNotPassword() {
        // Public material shares the armour but not the secrecy.
        let cert = """
        -----BEGIN CERTIFICATE-----
        MIIDdzCCAl+gAwIBAgIEAgAAuTANBgkqhkiG9w0BAQUFADBaMQswCQYDVQQGEwJJ
        -----END CERTIFICATE-----
        """
        XCTAssertFalse(isPassword(cert))
    }

    // MARK: - Exclusions

    func testURLsAreNotPasswords() {
        XCTAssertFalse(isPassword("https://Example.com/Ab1?x=9#frag"))
        XCTAssertFalse(isPassword("http://Example.com/Ab1?x=9"))
        XCTAssertFalse(isPassword("ftp://User1:Pa$$word@host.example"))
        XCTAssertFalse(isPassword("ssh://Root1@10.0.0.1:2222"))
        XCTAssertFalse(isPassword("file:///Users/Ab1/Notes.txt"))
        XCTAssertFalse(isPassword("mailto:Ab1@example.com"))
    }

    func testEmailAddressIsNotPassword() {
        XCTAssertFalse(isPassword("John.Doe1+Tag@example.com"))
    }

    func testFilePathsAreNotPasswords() {
        XCTAssertFalse(isPassword("/Users/Dung/Secret1!"))
        XCTAssertFalse(isPassword("~/.config/App1!"))
    }

    func testDomainsAreNotPasswords() {
        XCTAssertFalse(isPassword("Api-Server1.example.com"))
        XCTAssertFalse(isPassword("My-App1.io"))
        XCTAssertFalse(isPassword("My-App1.dev"))
        XCTAssertFalse(isPassword("Localhost:8080/Ab1!"))
    }

    // MARK: - Instance property

    @MainActor
    func testItemWithoutPlainTextIsNotSensitive() {
        let storage = StorageManager(inMemory: true)
        let item = ClipboardItem(title: "Image", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.png.identifier, value: Data([0x89, 0x50, 0x4E, 0x47]))
        ]
        storage.context.insert(item)

        XCTAssertFalse(item.looksLikePassword)
    }

    @MainActor
    func testItemUsesItsPlainTextRepresentation() {
        let storage = StorageManager(inMemory: true)
        let item = ClipboardItem(title: "Xk9#mP2$vLq7", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.rtf.identifier, value: Data("{\\rtf1 hidden}".utf8)),
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data("Xk9#mP2$vLq7".utf8)),
        ]
        storage.context.insert(item)

        XCTAssertTrue(item.looksLikePassword)
    }

    @MainActor
    func testProseItemIsNotSensitive() {
        let storage = StorageManager(inMemory: true)
        let item = ClipboardItem(title: "hello world", contentHash: "hash")
        item.contents = [
            ClipboardItemContent(type: UTType.utf8PlainText.identifier, value: Data("hello world".utf8))
        ]
        storage.context.insert(item)

        XCTAssertFalse(item.looksLikePassword)
    }
}
