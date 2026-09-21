import Foundation

/// The single Material → SF Symbol mapping for stored category icons.
///
/// The React Native app stores **Material icon names** in `categories.app_icon`
/// (free text typed by the user — `CategoryAddModal.tsx` labels the field
/// "Material Icon Name (Optional)" with the placeholder "e.g. fastfood, flight")
/// and hands the string straight to `MaterialIcons`. macOS has no Material font,
/// so the name has to be translated. Every renderer of a category icon —
/// `TransactionRow` (`category_app_icon`), `ReportItemRow`, the living-cost tiles
/// and the category list/picker — goes through here. Do not fork a second table.
///
/// Two source behaviours are reproduced:
/// * `formatIconName` (`transactionService.ts`): a name starting with `Md` has
///   that prefix stripped and the remainder converted from camelCase to
///   kebab-case (`MdLocalGasStation` → `local-gas-station`).
/// * the fallbacks the source uses when `app_icon` is empty: `category` for a
///   category, `receipt` for a transaction/report row.
///
/// Because the stored value is unconstrained free text, this is a **curated**
/// mapping, not an exhaustive Material catalogue: a name with no entry falls back
/// to a neutral SF Symbol rather than showing nothing. See the feature matrix.
enum CategoryIcon {
    /// The glyph shown when the stored name is empty or unrecognised.
    static let fallbackSymbolName = "tag"

    /// The source's fallbacks, kept as the names that actually reach this table.
    static let defaultCategoryName = "category"
    static let defaultTransactionName = "receipt"

    // MARK: - Normalisation

    /// `formatIconName`: trims, strips a leading `Md`, and kebab-cases camelCase.
    ///
    /// `nil` and empty both yield `nil`, so callers can tell "no icon stored"
    /// from "a name that simply has no mapping".
    static func normalizedMaterialName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var formatted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formatted.isEmpty else { return nil }
        if formatted.hasPrefix("Md") {
            formatted = String(formatted.dropFirst(2))
            formatted = kebabCased(formatted)
        }
        return formatted
    }

    /// `formatted.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()`.
    private static func kebabCased(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        let characters = Array(value)
        for (index, character) in characters.enumerated() {
            if character.isUppercase, index > 0 {
                let previous = characters[index - 1]
                if previous.isLowercase || previous.isNumber {
                    result.append("-")
                }
            }
            result.append(Character(character.lowercased()))
        }
        return result
    }

    // MARK: - Mapping

    /// The SF Symbol for a stored Material icon name.
    ///
    /// `fallback` is returned for an empty name; an unrecognised *non-empty* name
    /// also falls back, since the alternative (drawing nothing) reads as a bug.
    static func symbolName(for raw: String?, fallback: String = fallbackSymbolName) -> String {
        guard let name = normalizedMaterialName(raw) else { return fallback }
        return table[name] ?? fallback
    }

    /// Whether the name has an explicit entry (the picker marks these).
    static func isMapped(_ raw: String?) -> Bool {
        guard let name = normalizedMaterialName(raw) else { return false }
        return table[name] != nil
    }

    // MARK: - The source's per-context fallbacks

    /// `transaction.category_app_icon || 'receipt'` — a transaction row and the
    /// report rows built from transactions.
    static func transactionSymbol(_ raw: String?) -> String {
        symbolName(for: isBlank(raw) ? defaultTransactionName : raw)
    }

    /// `ReportListItem`'s chain: `category_app_icon || app_icon || 'receipt'`.
    static func reportSymbol(categoryAppIcon: String?, appIcon: String?) -> String {
        if !isBlank(categoryAppIcon) { return symbolName(for: categoryAppIcon) }
        if !isBlank(appIcon) { return symbolName(for: appIcon) }
        return symbolName(for: defaultTransactionName)
    }

    /// A category's own icon: `app_icon` with the source's `'category'` default.
    static func categorySymbol(_ raw: String?) -> String {
        symbolName(for: isBlank(raw) ? defaultCategoryName : raw)
    }

    /// The living-cost / report-config tiles: `app_icon || 'receipt'`.
    static func configTileSymbol(_ raw: String?) -> String {
        symbolName(for: isBlank(raw) ? defaultTransactionName : raw)
    }

    private static func isBlank(_ raw: String?) -> Bool {
        guard let raw else { return true }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - The table

    /// Material name → SF Symbol. Keys are already normalised (lowercase,
    /// kebab-case), so `MdHome` and `home` resolve identically.
    static let table: [String: String] = [
        // Money & accounts
        "attach-money": "dollarsign.circle",
        "currency-rupee": "indianrupeesign.circle",
        "payments": "banknote",
        "savings": "banknote",
        "account-balance": "building.columns",
        "account-balance-wallet": "wallet.bifold",
        "credit-card": "creditcard",
        "redeem": "gift",
        "card-giftcard": "gift",
        "receipt": "doc.text",
        "receipt-long": "doc.text.magnifyingglass",
        "request-quote": "doc.text",
        "description": "doc.text",
        "work": "briefcase",
        "business-center": "briefcase",
        "subscriptions": "arrow.triangle.2.circlepath",
        "autorenew": "arrow.triangle.2.circlepath",
        "insights": "chart.bar",
        "bar-chart": "chart.bar",
        "pie-chart": "chart.pie",
        "trending-up": "chart.line.uptrend.xyaxis",
        "trending-down": "chart.line.downtrend.xyaxis",

        // Food & drink
        "restaurant": "fork.knife",
        "fastfood": "fork.knife",
        "local-dining": "fork.knife",
        "local-pizza": "fork.knife",
        "lunch-dining": "fork.knife",
        "dinner-dining": "fork.knife",
        "local-cafe": "cup.and.saucer",
        "coffee": "cup.and.saucer",
        "liquor": "wineglass",
        "sports-bar": "mug",
        "local-bar": "mug",
        "cake": "birthday.cake",
        "icecream": "snowflake",

        // Shopping
        "shopping-cart": "cart",
        "shopping-basket": "basket",
        "local-grocery-store": "cart",
        "shopping-bag": "bag",
        "store": "storefront",
        "storefront": "storefront",
        "local-mall": "building.2",
        "kitchen": "refrigerator",
        "checkroom": "tshirt",
        "local-florist": "leaf",

        // Home & utilities
        "home": "house",
        "house": "house",
        "apartment": "building.2",
        "villa": "house",
        "hotel": "bed.double",
        "lightbulb": "lightbulb",
        "electric-bolt": "bolt",
        "bolt": "bolt",
        "energy": "bolt",
        "solar-power": "sun.max",
        "water-drop": "drop",
        "wifi": "wifi",
        "router": "wifi.router",
        "cleaning-services": "sparkles",
        "local-laundry-service": "washer",
        "recycling": "arrow.3.trianglepath",
        "build": "wrench.and.screwdriver",
        "handyman": "hammer",
        "security": "shield",
        "lock": "lock",
        "key": "key",
        "pets": "pawprint",
        "child-care": "figure.child",
        "family-restroom": "figure.2.and.child.holdinghands",

        // Transport
        "directions-car": "car",
        "local-taxi": "car",
        "directions-bus": "bus",
        "train": "tram",
        "flight": "airplane",
        "directions-bike": "bicycle",
        "directions-walk": "figure.walk",
        "local-shipping": "shippingbox",
        "local-gas-station": "fuelpump",
        "commute": "car",
        "ev-station": "bolt.car",

        // Health, sport & leisure
        "local-hospital": "cross.case",
        "medical-services": "cross.case",
        "local-pharmacy": "pills",
        "fitness-center": "figure.run",
        "sports-soccer": "soccerball",
        "sports-esports": "gamecontroller",
        "movie": "film",
        "local-movies": "film",
        "music-note": "music.note",
        "celebration": "party.popper",
        "beach-access": "beach.umbrella",
        "park": "tree",
        "forest": "tree",

        // Education, tech & travel
        "school": "graduationcap",
        "menu-book": "book",
        "book": "book",
        "laptop": "laptopcomputer",
        "phone-android": "iphone",
        "devices": "iphone",
        "gadgets": "cpu",
        "travel-explore": "globe",
        "public": "globe",
        "emoji-events": "trophy",

        // Generic labels
        "category": "square.grid.2x2",
        "category-outlined": "square.grid.2x2",
        "grid-view": "square.grid.2x2",
        "label": "tag",
        "local-offer": "tag",
        "sell": "tag",
        "star": "star",
        "favorite": "heart",
        "person": "person",
        "group": "person.2",
        "people": "person.2",
        "more-horiz": "ellipsis",
        "bug-report": "ladybug",
    ]

    /// The offerable names, alphabetically — the picker grid's contents.
    static let offerableMaterialNames: [String] = table.keys.sorted()
}
