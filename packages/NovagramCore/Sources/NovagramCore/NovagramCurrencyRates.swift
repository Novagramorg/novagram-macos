//
//  NovagramCurrencyRates.swift
//  NovagramCore
//
//  Settings → Currency rates, like iOS (submodules/Novagram/CurrencyRates): the row is shown while the
//  Developer switch "Show currency rates" is on. The page hosts the NovagramServices SDK's SwiftUI
//  converter: CurrencyCalculatorView, and a bar button that opens MultiCurrencyView. Rates come from
//  the SDK core (currencyRates.latest(), kept by the SDK for the day); every text is ours.
//

import Cocoa
import SwiftUI
import TGUIKit
import SwiftSignalKit
import TelegramTheme
import Localization
import NovagramServices
import NovagramServicesUI

public enum NovagramCurrencyRatesEntry {
    public static var rowTitle: String {
        return NovagramCurrencyRatesStrings.title(langCode: appCurrentLanguage.languageCode)
    }

    public static func makeController() -> ViewController {
        return NovagramCurrencyRatesController(screen: .calculator, rates: nil)
    }

    public static func isCalculator(_ controller: ViewController) -> Bool {
        guard let controller = controller as? NovagramCurrencyRatesController, case .calculator = controller.screen else {
            return false
        }
        return true
    }
}

// What the user leaves on the two screens, so the next opening starts there (the iOS keys; the SDK
// views report their state, they never store anything themselves).
private enum NovagramCurrencyRatesStore {
    private static let udSuite = "pro_messager"
    private static let stateKey = "novagram_currency_converter_state"
    private static let favoritesKey = "novagram_currency_favorites"

    // One client for both screens: the SDK keeps the bank's answer for the day.
    static let client = ServicesClient()

    static var state: CurrencyConverterState {
        get {
            guard let data = UserDefaults(suiteName: udSuite)?.data(forKey: stateKey),
                  let state = try? JSONDecoder().decode(CurrencyConverterState.self, from: data) else {
                return .default
            }
            return state
        }
        set {
            UserDefaults(suiteName: udSuite)?.set(try? JSONEncoder().encode(newValue), forKey: stateKey)
        }
    }

    static var favorites: [String] {
        get {
            return UserDefaults(suiteName: udSuite)?.stringArray(forKey: favoritesKey) ?? MultiCurrencyView.defaultFavorites
        }
        set {
            UserDefaults(suiteName: udSuite)?.set(newValue, forKey: favoritesKey)
        }
    }
}

final class NovagramCurrencyRatesView: NovagramKitView {
    let host = NSHostingController(rootView: AnyView(EmptyView()))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.host.view.autoresizingMask = []
        self.addSubview(self.host.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.host.view.frame = self.bounds
    }
}

/// One of the SDK's two converter screens: the calculator (with a bar button that opens the list) or
/// the list of favorite currencies.
final class NovagramCurrencyRatesController: GenericViewController<NovagramCurrencyRatesView> {
    enum Screen {
        case calculator
        case list(base: String, amount: Decimal)
    }

    let screen: Screen
    private var rates: [CurrencyRate]?
    private var ratesTask: Task<Void, Never>?
    private let appearanceDisposable = MetaDisposable()

    init(screen: Screen, rates: [CurrencyRate]?) {
        self.screen = screen
        self.rates = rates
        super.init()
    }

    private var langCode: String {
        return appCurrentLanguage.languageCode
    }

    override var enableBack: Bool {
        return true
    }

    override var defaultBarTitle: String {
        switch self.screen {
        case .calculator:
            return NovagramCurrencyRatesStrings.title(langCode: self.langCode)
        case .list:
            return NovagramCurrencyRatesStrings.listTitle(langCode: self.langCode)
        }
    }

    override func getRightBarViewOnce() -> BarView {
        guard case .calculator = self.screen, let icon = self.listIcon() else {
            return super.getRightBarViewOnce()
        }
        let bar = ImageBarView(controller: self, icon)
        bar.button.set(handler: { [weak self] _ in
            self?.openList()
        }, for: .Click)
        return bar
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.appearanceDisposable.set(appearanceSignal.start(next: { [weak self] _ in
            self?.updateContent()
        }))
        self.readyOnce()
        self.loadRates()
    }

    private func listIcon() -> CGImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        return NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)?.precomposed(theme.colors.accentIcon)
    }

    private func openList() {
        let state = NovagramCurrencyRatesStore.state
        self.navigationController?.push(NovagramCurrencyRatesController(screen: .list(base: state.from, amount: state.amount), rates: self.rates))
    }

    // nil rates (loading or failed) make the views show their placeholders.
    private func loadRates() {
        self.ratesTask = Task { [weak self] in
            let rates = try? await NovagramCurrencyRatesStore.client.currencyRates.latest()
            await MainActor.run {
                guard let self, let rates else {
                    return
                }
                self.rates = rates
                self.updateContent()
            }
        }
    }

    private func updateContent() {
        guard self.isLoaded() else {
            return
        }
        self.genericView.backgroundColor = theme.colors.listBackground
        if let bar = self.rightBarView as? ImageBarView, let icon = self.listIcon() {
            bar.set(image: icon)
        }
        // The same view type stays at the root, so SwiftUI keeps what the user typed.
        self.genericView.host.rootView = self.makeContent()
    }

    private func makeContent() -> AnyView {
        let colors = theme.colors
        let uiTheme = NovagramServicesCardColors(
            cardBackground: colors.background,
            separator: colors.border,
            primaryText: colors.text,
            secondaryText: colors.grayText,
            accent: colors.accent,
            positive: colors.greenUI,
            negative: colors.redUI,
            isDark: colors.isDark
        ).theme
        let locale = Locale(identifier: self.langCode)
        let strings = NovagramCurrencyRatesStrings.converter(langCode: self.langCode, ratesDate: self.rates?.first?.date)
        switch self.screen {
        case .calculator:
            return AnyView(CurrencyCalculatorView(
                rates: self.rates,
                state: NovagramCurrencyRatesStore.state,
                strings: strings,
                theme: uiTheme,
                locale: locale,
                onStateChange: { state in
                    NovagramCurrencyRatesStore.state = state
                }
            )
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        case let .list(base, amount):
            return AnyView(MultiCurrencyView(
                rates: self.rates,
                base: base,
                amount: amount,
                favorites: NovagramCurrencyRatesStore.favorites,
                strings: strings,
                theme: uiTheme,
                locale: locale,
                onFavoritesChange: { favorites in
                    NovagramCurrencyRatesStore.favorites = favorites
                }
            ))
        }
    }

    deinit {
        self.appearanceDisposable.dispose()
        self.ratesTask?.cancel()
    }
}

// The SDK ships no translations: every text of its converter screens comes from here (iOS texts).
enum NovagramCurrencyRatesStrings {
    static func title(langCode: String) -> String {
        switch langCode {
        case "uz": return "Valyuta kurslari"
        case "ru": return "Курсы валют"
        default:   return "Currency rates"
        }
    }

    static func listTitle(langCode: String) -> String {
        switch langCode {
        case "uz": return "Bir nechta valyuta"
        case "ru": return "Несколько валют"
        default:   return "Many currencies"
        }
    }

    static func converter(langCode: String, ratesDate: Date?) -> CurrencyConverterStrings {
        let footer = ratesDate.map { self.footer(date: $0, langCode: langCode) }
        switch langCode {
        case "uz":
            return CurrencyConverterStrings(
                sumName: "O'zbek so'mi", sumSymbol: "so'm", footer: footer,
                swap: "Almashtirish", delete: "O'chirish", copy: "Nusxalash",
                amountLabel: "Miqdor", resultLabel: "Natija", quickAmounts: "Tez miqdor",
                yourAmount: "Sizdagi summa", favorites: "Sevimli valyutalar", tapHint: "Bosing — asosiy bo'ladi",
                addCurrency: "Valyuta qo'shish", makeBase: "Asosiy qilish", remove: "Ro'yxatdan olib tashlash",
                pickerTitle: "Valyuta tanlang", search: "Kod yoki nom", frequent: "Tez-tez",
                allCurrencies: "Barcha valyutalar", noResults: "Topilmadi", close: "Yopish",
                chooseCurrency: "Valyutani tanlash"
            )
        case "ru":
            return CurrencyConverterStrings(
                sumName: "Узбекский сум", sumSymbol: "сум", footer: footer,
                swap: "Поменять местами", delete: "Удалить", copy: "Копировать",
                amountLabel: "Сумма", resultLabel: "Результат", quickAmounts: "Быстрые суммы",
                yourAmount: "Ваша сумма", favorites: "Избранные валюты", tapHint: "Нажмите — станет основной",
                addCurrency: "Добавить валюту", makeBase: "Сделать основной", remove: "Убрать из списка",
                pickerTitle: "Выберите валюту", search: "Код или название", frequent: "Часто",
                allCurrencies: "Все валюты", noResults: "Ничего не найдено", close: "Закрыть",
                chooseCurrency: "Выбрать валюту"
            )
        default:
            return CurrencyConverterStrings(
                sumName: "Uzbek sum", sumSymbol: "sum", footer: footer,
                swap: "Swap", delete: "Delete", copy: "Copy",
                amountLabel: "Amount", resultLabel: "Result", quickAmounts: "Quick amounts",
                yourAmount: "Your amount", favorites: "Favorite currencies", tapHint: "Click to make it the base",
                addCurrency: "Add currency", makeBase: "Make base", remove: "Remove from list",
                pickerTitle: "Choose a currency", search: "Code or name", frequent: "Frequent",
                allCurrencies: "All currencies", noResults: "Nothing found", close: "Close",
                chooseCurrency: "Choose currency"
            )
        }
    }

    // "Central Bank rate, October 27". The bank sets its rates per Tashkent day.
    private static func footer(date: Date, langCode: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Tashkent")
        switch langCode {
        case "uz":
            formatter.locale = Locale(identifier: "uz_Latn_UZ")
            formatter.dateFormat = "d-MMMM"
            return "Markaziy bank kursi, \(formatter.string(from: date))"
        case "ru":
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMMM"
            return "Курс ЦБ Узбекистана, \(formatter.string(from: date))"
        default:
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMMM d"
            return "Central Bank rate, \(formatter.string(from: date))"
        }
    }
}
