import XCTest
import TelegramCore
@testable import ComposeUI

final class CreateBotUsernameSubmoduleCompatibilityTests: XCTestCase {
    private let endings = CreateBotUsernameEndings(configuredValue: ["bot", "ai", "agent", "app", "game"] as [Any])
    private let noConfiguredEndings = CreateBotUsernameEndings(configuredValue: nil)

    override func setUp() {
        super.setUp()
        applyMacEnglishStrings()
    }

    override func tearDown() {
        applyMacEnglishStrings([:])
        super.tearDown()
    }

    func testConfiguredEndingsOtherThanBotNeedPremium() {
        XCTAssertEqual(self.endings.premium, ["ai", "agent", "app", "game"])
        XCTAssertEqual(self.endings.all, ["bot", "ai", "agent", "app", "game"])
    }

    func testEndingsAreReadThroughTheAppConfigurationsJSON() {
        let data: JSON = ["bot_allowed_suffixes": ["bot", "ai", "app"]]
        let endings = CreateBotUsernameEndings(configuredValue: data[CreateBotUsernameEndings.appConfigurationKey])
        XCTAssertEqual(endings.premium, ["ai", "app"])
    }

    func testConfiguredEndingsAreNormalized() {
        let endings = CreateBotUsernameEndings(configuredValue: ["AI", "ai", "", "Bot", "app"] as [Any])
        XCTAssertEqual(endings.premium, ["ai", "app"])
    }

    func testWithoutTheKeyOnlyBotIsOffered() {
        XCTAssertEqual(self.noConfiguredEndings.all, ["bot"])
        XCTAssertEqual(CreateBotUsernameEndings(configuredValue: "ai,app").all, ["bot"])
        XCTAssertEqual(CreateBotUsernameEndings(configuredValue: [1.0, 2.0] as [Any]).all, ["bot"])
    }

    func testPlainTextGetsTheGreyBotSuffix() {
        let value = CreateBotUsername(typedText: "durgerking", endings: self.endings)

        XCTAssertEqual(value.ending, "bot")
        XCTAssertEqual(value.appendedSuffix, "bot")
        XCTAssertEqual(value.username, "durgerkingbot")
        XCTAssertFalse(value.requiresPremium)
    }

    func testATypedEndingIsUsedExactlyAsTyped() {
        for ending in self.endings.all {
            let value = CreateBotUsername(typedText: "durgerking" + ending, endings: self.endings)

            XCTAssertEqual(value.ending, ending)
            XCTAssertNil(value.appendedSuffix, "\(ending) was typed, so nothing is appended")
            XCTAssertEqual(value.username, "durgerking" + ending)
            XCTAssertEqual(value.requiresPremium, ending != "bot")
        }
    }

    func testAnEndingTheServerDoesNotListIsOrdinaryText() {
        let value = CreateBotUsername(typedText: "durgerkingapp", endings: self.noConfiguredEndings)
        XCTAssertEqual(value.username, "durgerkingappbot")
        XCTAssertFalse(value.requiresPremium)
    }

    func testTheLongestConfiguredEndingWins() {
        let endings = CreateBotUsernameEndings(configuredValue: ["gpt", "chatgpt"] as [Any])
        XCTAssertEqual(CreateBotUsername(typedText: "mychatgpt", endings: endings).ending, "chatgpt")
        XCTAssertEqual(CreateBotUsername(typedText: "mygpt", endings: endings).ending, "gpt")
    }

    func testEndingsAreCaseInsensitiveAndKeepTheTypedCase() {
        XCTAssertEqual(CreateBotUsername(typedText: "DurgerKingApp", endings: self.endings).ending, "app")
        XCTAssertEqual(CreateBotUsername(typedText: "DurgerKingApp", endings: self.endings).username, "DurgerKingApp")
        XCTAssertEqual(CreateBotUsername(typedText: "FooBot", endings: self.endings).ending, "bot")
        XCTAssertEqual(CreateBotUsername(typedText: "FooBot", endings: self.endings).username, "FooBot")
    }

    func testAnEndingAloneIsOrdinaryText() {
        XCTAssertEqual(CreateBotUsername(typedText: "agent", endings: self.endings).username, "agentbot")
        XCTAssertEqual(CreateBotUsername(typedText: "bot", endings: self.endings).username, "botbot")
        XCTAssertEqual(CreateBotUsername(typedText: "", endings: self.endings).username, "bot")
    }

    func testAWordThatHappensToEndInAnEndingTakesIt() {
        XCTAssertEqual(CreateBotUsername(typedText: "shanghai", endings: self.endings).ending, "ai")
        XCTAssertEqual(CreateBotUsername(typedText: "shanghai", endings: self.endings).username, "shanghai")
        XCTAssertEqual(CreateBotUsername(typedText: "shanghaibot", endings: self.endings).ending, "bot")
    }

    func testAPartlyTypedEndingKeepsTheGreySuffix() {
        XCTAssertEqual(CreateBotUsername(typedText: "durgerkingap", endings: self.endings).username, "durgerkingapbot")
        XCTAssertEqual(CreateBotUsername(typedText: "durgerkingbo", endings: self.endings).username, "durgerkingbobot")
    }

    func testMinimumLengthCountsTheAppendedSuffix() {
        XCTAssertNil(CreateBotUsername(typedText: "ab", endings: self.endings).validationError)
        XCTAssertEqual(CreateBotUsername(typedText: "a", endings: self.endings).validationError, .tooShort)
    }

    func testMaximumLengthCountsTheAppendedSuffix() {
        let stem29 = String(repeating: "a", count: 29)
        XCTAssertNil(CreateBotUsername(typedText: stem29, endings: self.endings).validationError)
        XCTAssertEqual(CreateBotUsername(typedText: stem29 + "a", endings: self.endings).validationError, .tooLong)
        XCTAssertNil(CreateBotUsername(typedText: stem29 + "app", endings: self.endings).validationError)
    }

    func testCharacterRules() {
        XCTAssertEqual(CreateBotUsername(typedText: "1durger", endings: self.endings).validationError, .startsWithNumber)
        XCTAssertEqual(CreateBotUsername(typedText: "durger-king", endings: self.endings).validationError, .unsupportedCharacters)
        XCTAssertNil(CreateBotUsername(typedText: "durger_king", endings: self.endings).validationError)
    }

    func testLimitsMatchTheSubmodule() {
        XCTAssertEqual(CreateBotUsername.minLength, 5)
        XCTAssertEqual(CreateBotUsername.maxLength, 32)
        XCTAssertEqual(CreateBotUsername.defaultSuffixLimit, 2)
    }

    func testKnownServerErrors() {
        XCTAssertEqual(BotUsernameServerError(errorDescription: "USERNAME_OCCUPIED"), .occupied)
        XCTAssertEqual(BotUsernameServerError(errorDescription: "USERNAME_PURCHASE_AVAILABLE"), .purchaseAvailable)
        XCTAssertEqual(BotUsernameServerError(errorDescription: "USERNAME_SUFFIX_MISSING"), .suffixNotAllowed)
    }

    func testPremiumErrorsMatchByKeyword() {
        for error in ["USERNAME_PREMIUM_REQUIRED", "PREMIUM_ACCOUNT_REQUIRED", "BOT_USERNAME_SUFFIX_PREMIUM"] {
            XCTAssertEqual(BotUsernameServerError(errorDescription: error), .premiumRequired, error)
        }
    }

    func testTheEndingCapMatchesByKeywordAndReadsATrailingNumber() {
        XCTAssertEqual(BotUsernameServerError(errorDescription: "BOT_USERNAME_SUFFIX_LIMIT_EXCEEDED"), .suffixLimitExceeded(limit: nil))
        XCTAssertEqual(BotUsernameServerError(errorDescription: "USERNAME_SUFFIX_LIMIT_2"), .suffixLimitExceeded(limit: 2))
        XCTAssertEqual(BotUsernameServerError(errorDescription: "BOT_USERNAMES_TOO_MANY"), .suffixLimitExceeded(limit: nil))
        XCTAssertEqual(BotUsernameServerError(errorDescription: "USERNAME_PREMIUM_LIMIT_EXCEEDED"), .suffixLimitExceeded(limit: nil))
    }

    func testUnrelatedErrorsAreNotClaimed() {
        for error in ["BOT_CREATE_LIMIT_EXCEEDED", "USERNAME_INVALID", "FLOOD_WAIT_30", "INTERNAL"] {
            XCTAssertNil(BotUsernameServerError(errorDescription: error), error)
        }
    }

    func testServerAvailabilityMapsToTheSheetStatus() {
        XCTAssertEqual(CreateBotUsernameStatus(.available), .valid)
        XCTAssertEqual(CreateBotUsernameStatus(.invalid), .invalid)
        XCTAssertEqual(CreateBotUsernameStatus(.purchaseAvailable), .invalid)
        XCTAssertEqual(CreateBotUsernameStatus(.taken), .taken)
        XCTAssertEqual(CreateBotUsernameStatus(.suffixNotAllowed), .suffixNotAllowed)
        XCTAssertEqual(CreateBotUsernameStatus(.premiumRequired), .premiumRequired)
        XCTAssertEqual(CreateBotUsernameStatus(.suffixLimitExceeded(limit: 3)), .suffixLimitExceeded(limit: 3))
        XCTAssertEqual(CreateBotUsernameStatus(.suffixLimitExceeded(limit: nil)), .suffixLimitExceeded(limit: nil))
    }

    func testInvalidAndPremiumEndingsAreDecidedWithoutTheServer() {
        let tooShort = CreateBotUsername(typedText: "a", endings: self.endings)
        XCTAssertEqual(CreateBotUsernameStatus.decidedLocally(for: tooShort, isPremium: true), .invalid)

        let premiumEnding = CreateBotUsername(typedText: "durgerkingapp", endings: self.endings)
        XCTAssertEqual(CreateBotUsernameStatus.decidedLocally(for: premiumEnding, isPremium: false), .premiumRequired)
        XCTAssertNil(CreateBotUsernameStatus.decidedLocally(for: premiumEnding, isPremium: true))

        let freeEnding = CreateBotUsername(typedText: "durgerking", endings: self.endings)
        XCTAssertNil(CreateBotUsernameStatus.decidedLocally(for: freeEnding, isPremium: false))
        XCTAssertNil(CreateBotUsernameStatus.decidedLocally(for: freeEnding, isPremium: true))
    }

    func testFooterShowsTheValidationErrorFirstEvenForAnEmptyField() {
        let empty = CreateBotUsername(typedText: "", endings: self.endings)
        XCTAssertEqual(CreateBotUsernameFooter(username: empty, status: nil), .validationError(.tooShort))
        XCTAssertEqual(CreateBotUsernameFooter(username: empty, status: .valid), .validationError(.tooShort))

        let dashed = CreateBotUsername(typedText: "durger-king", endings: self.endings)
        XCTAssertEqual(CreateBotUsernameFooter(username: dashed, status: .taken), .validationError(.unsupportedCharacters))
    }

    func testFooterFollowsTheCheckedStatus() {
        let plain = CreateBotUsername(typedText: "durgerking", endings: self.endings)
        XCTAssertEqual(CreateBotUsernameFooter(username: plain, status: nil), .hint)
        XCTAssertEqual(CreateBotUsernameFooter(username: plain, status: .checking), .hint)
        XCTAssertEqual(CreateBotUsernameFooter(username: plain, status: .valid), .hint)
        XCTAssertEqual(CreateBotUsernameFooter(username: plain, status: .invalid), .invalid)
        XCTAssertEqual(CreateBotUsernameFooter(username: plain, status: .taken), .taken)
        XCTAssertEqual(CreateBotUsernameFooter(username: plain, status: .suffixNotAllowed), .hintError)
        XCTAssertEqual(CreateBotUsernameFooter(username: plain, status: .suffixLimitExceeded(limit: 2)), .suffixLimitExceeded(limit: 2))

        let app = CreateBotUsername(typedText: "durgerkingapp", endings: self.endings)
        XCTAssertEqual(CreateBotUsernameFooter(username: app, status: .premiumRequired), .premiumRequired(ending: "app"))
    }

    func testCreateNeedsANameAndAUsernameTheServerAccepted() {
        let plain = CreateBotUsername(typedText: "durgerking", endings: self.endings)
        XCTAssertTrue(createBotCanCreate(name: "Durger King", username: plain, status: .valid))
        XCTAssertFalse(createBotCanCreate(name: "", username: plain, status: .valid))
        XCTAssertFalse(createBotCanCreate(name: "Durger King", username: plain, status: nil))
        XCTAssertFalse(createBotCanCreate(name: "Durger King", username: plain, status: .checking))
        XCTAssertFalse(createBotCanCreate(name: "Durger King", username: plain, status: .taken))
        XCTAssertFalse(createBotCanCreate(name: "Durger King", username: plain, status: .premiumRequired))

        let tooShort = CreateBotUsername(typedText: "a", endings: self.endings)
        XCTAssertFalse(createBotCanCreate(name: "Durger King", username: tooShort, status: .valid))
    }

    func testEndingListsAreJoinedLikeTheSubmoduleStrings() throws {
        let strings = try submoduleStrings()
        let endingFormat = try XCTUnwrap(strings["CreateBot.UsernameEnding"])
        let delimiter = try XCTUnwrap(strings["CreateBot.UsernameEndingDelimiter"])
        let finalDelimiter = try XCTUnwrap(strings["CreateBot.UsernameEndingFinalDelimiter"])
        func expected(_ endings: [String]) -> String {
            let items = endings.map { String(format: endingFormat, $0) }
            guard let last = items.last else {
                return ""
            }
            if items.count == 1 {
                return last
            }
            return items.dropLast().joined(separator: delimiter) + finalDelimiter + last
        }
        for endings in [["bot"], ["ai", "app"], ["ai", "agent", "app", "game"]] {
            XCTAssertEqual(createBotUsernameEndingsList(endings), expected(endings))
        }
    }

    func testFooterTextsMatchTheSubmoduleStrings() throws {
        let strings = try submoduleStrings()
        let list: ([String]) -> String = createBotUsernameEndingsList

        let hintFormat = try XCTUnwrap(strings["CreateBot.UsernameHint"])
        XCTAssertEqual(createBotUsernamePremiumHint(endings: self.endings, premiumLink: true), String(format: hintFormat, list(["bot"]), list(self.endings.premium)))
        XCTAssertNil(createBotUsernamePremiumHint(endings: self.noConfiguredEndings, premiumLink: true))

        let premiumRequiredFormat = try XCTUnwrap(strings["CreateBot.UsernameStatus.PremiumRequired"])
        XCTAssertEqual(createBotUsernamePremiumRequiredText(ending: "app"), String(format: premiumRequiredFormat, list(["app"])))

        let limitFormat = try XCTUnwrap(strings["CreateBot.UsernameStatus.SuffixLimit"])
        let countOne = String(format: try XCTUnwrap(strings["CreateBot.UsernameStatus.SuffixLimitCount_1"]), Int32(1))
        let countAny = String(format: try XCTUnwrap(strings["CreateBot.UsernameStatus.SuffixLimitCount_any"]), Int32(2))
        XCTAssertEqual(createBotUsernameSuffixLimitText(limit: 1, endings: self.endings), String(format: limitFormat, countOne, list(self.endings.premium)))
        XCTAssertEqual(createBotUsernameSuffixLimitText(limit: 2, endings: self.endings), String(format: limitFormat, countAny, list(self.endings.premium)))
        XCTAssertEqual(createBotUsernameSuffixLimitText(limit: nil, endings: self.endings), String(format: limitFormat, countAny, list(self.endings.premium)))
    }

    private func submoduleStrings() throws -> [String: String] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], url.path)
    }
}
