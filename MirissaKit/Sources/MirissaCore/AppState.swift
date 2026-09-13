import Foundation

public struct AppSettings: Codable, Hashable, Sendable {
    /// "Yaklaşık kaç siparişlik kaldı" hesabında kullanılacak geçmiş ay sayısı
    public var consumptionWindowMonths: Int
    /// Stok alımları kâr hesabına gider olarak değil, satıldıkça maliyet olarak girer.
    public var capitalizePurchases: Bool
    public var companyName: String

    public init(
        consumptionWindowMonths: Int = 3,
        capitalizePurchases: Bool = true,
        companyName: String = "Mirissa Lab"
    ) {
        self.consumptionWindowMonths = consumptionWindowMonths
        self.capitalizePurchases = capitalizePurchases
        self.companyName = companyName
    }
}

public struct AppState: Codable, Hashable, Sendable {
    public var materials: [StockMaterial]
    public var products: [Product]
    public var channels: [Channel]
    public var channelMonths: [ChannelMonth]
    public var sales: [SalesEntry]
    public var expenses: [Expense]
    public var purchases: [StockPurchase]
    public var adjustments: [StockAdjustment]
    public var counts: [StockCount]
    public var settings: AppSettings

    public init(
        materials: [StockMaterial] = [],
        products: [Product] = [],
        channels: [Channel] = [],
        channelMonths: [ChannelMonth] = [],
        sales: [SalesEntry] = [],
        expenses: [Expense] = [],
        purchases: [StockPurchase] = [],
        adjustments: [StockAdjustment] = [],
        counts: [StockCount] = [],
        settings: AppSettings = AppSettings()
    ) {
        self.materials = materials
        self.products = products
        self.channels = channels
        self.channelMonths = channelMonths
        self.sales = sales
        self.expenses = expenses
        self.purchases = purchases
        self.adjustments = adjustments
        self.counts = counts
        self.settings = settings
    }

    public static let empty = AppState()
}

// MARK: - Arama yardımcıları

public extension AppState {
    func material(_ id: Id) -> StockMaterial? { materials.first { $0.id == id } }
    func product(_ id: Id) -> Product? { products.first { $0.id == id } }
    func channel(_ id: Id) -> Channel? { channels.first { $0.id == id } }

    var activeMaterials: [StockMaterial] { materials.filter { !$0.archived } }
    var activeProducts: [Product] { products.filter { !$0.archived } }
    var activeChannels: [Channel] { channels.filter { !$0.archived } }

    func itemName(_ ref: ItemRef) -> String {
        switch ref.kind {
        case .material: return material(ref.id)?.name ?? "Silinmiş malzeme"
        case .product: return product(ref.id)?.name ?? "Silinmiş ürün"
        }
    }

    func itemBaseUnit(_ ref: ItemRef) -> UnitCode {
        switch ref.kind {
        case .material: return material(ref.id)?.baseUnit ?? .adet
        case .product: return .adet
        }
    }

    func itemPackSizes(_ ref: ItemRef) -> [UnitCode: Double] {
        switch ref.kind {
        case .material: return material(ref.id)?.packSizes ?? [:]
        case .product: return [:]
        }
    }

    func itemExists(_ ref: ItemRef) -> Bool {
        switch ref.kind {
        case .material: return material(ref.id) != nil
        case .product: return product(ref.id) != nil
        }
    }

    func channelMonth(month: MonthKey, channelId: Id) -> ChannelMonth? {
        channelMonths.first { $0.month == month && $0.channelId == channelId }
    }

    /// Verideki en erken ve en geç ay — rapor aralıkları için
    var dataMonthBounds: (first: MonthKey, last: MonthKey) {
        var months: [MonthKey] = sales.map(\.month)
        months += expenses.map(\.startMonth)
        months += purchases.map { Dates.month(of: $0.date) }
        months += adjustments.map { Dates.month(of: $0.date) }
        months += counts.map { Dates.month(of: $0.date) }
        let now = Dates.currentMonth()
        guard let mn = months.min(), let mx = months.max() else { return (now, now) }
        return (min(mn, now), max(mx, now))
    }
}
