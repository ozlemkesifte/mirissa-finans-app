import Foundation

/// Geçmiş veri yokken hedef hesaplamak için kullanıcının verdiği basit varsayım.
public struct ExpectedMix: Codable, Hashable, Sendable {
    public var channelId: Id
    public var productId: Id
    /// Ortalama sipariş tutarı (müşterinin ödediği)
    public var averageOrderValue: Kurus
    /// Sipariş başına ortalama ürün adedi
    public var unitsPerOrder: Double

    public init(channelId: Id, productId: Id, averageOrderValue: Kurus, unitsPerOrder: Double = 1) {
        self.channelId = channelId
        self.productId = productId
        self.averageOrderValue = averageOrderValue
        self.unitsPerOrder = max(unitsPerOrder, 0.01)
    }
}

public struct AppSettings: Hashable, Sendable {
    /// "Yaklaşık kaç siparişlik kaldı" hesabında kullanılacak geçmiş ay sayısı
    public var consumptionWindowMonths: Int
    /// Stok alımları kâr hesabına gider olarak değil, satıldıkça maliyet olarak girer.
    public var capitalizePurchases: Bool
    public var companyName: String
    /// Kullanıcının kendi belirlediği aylık kâr hedefi: ["2026-09": 7_500_000]
    public var profitGoals: [MonthKey: Kurus]
    /// "Bu ayın satışları şu tarihe kadar girildi" — ara durum işareti.
    /// Boşsa girilen satışlar ayın tamamı sayılır.
    public var progressAsOf: [MonthKey: DateKey]
    /// Hiç geçmiş ay yokken hedef hesaplamak için kullanılan varsayım
    public var expectedMix: ExpectedMix?
    /// Yeni kayıtlarda önerilen KDV oranı
    public var defaultVatRate: VatRate
    /// Yeni kayıtlarda "tutar KDV dahil" varsayılanı
    public var defaultVatIncluded: Bool
    /// KDV takibi açık mı — kapalıyken hiçbir ekranda KDV görünmez
    public var vatEnabled: Bool
    /// İlk kurulum sihirbazı tamamlandı mı
    public var setupCompleted: Bool
    /// Fiyat kontrol hatırlatıcısının sıklığı
    public var priceCheckInterval: PriceCheckInterval
    /// Fiyatların en son ne zaman gözden geçirildiği
    public var lastPriceCheck: DateKey?

    /// Hatırlatma zamanı geldi mi. Hiç kontrol edilmediyse ilk gün sayılır.
    public func priceCheckDue(on today: DateKey, since firstUse: DateKey? = nil) -> Bool {
        guard let gun = priceCheckInterval.days else { return false }
        guard let son = lastPriceCheck ?? firstUse else { return true }
        return Dates.daysBetween(son, today) >= gun
    }

    public func profitGoal(for month: MonthKey) -> Kurus? {
        profitGoals[month].flatMap { $0 > 0 ? $0 : nil }
    }

    public init(
        consumptionWindowMonths: Int = 3,
        capitalizePurchases: Bool = true,
        companyName: String = "Mirissa Lab",
        profitGoals: [MonthKey: Kurus] = [:],
        progressAsOf: [MonthKey: DateKey] = [:],
        expectedMix: ExpectedMix? = nil,
        defaultVatRate: VatRate = .yirmi,
        defaultVatIncluded: Bool = true,
        vatEnabled: Bool = true,
        setupCompleted: Bool = false,
        priceCheckInterval: PriceCheckInterval = .aylik,
        lastPriceCheck: DateKey? = nil
    ) {
        self.consumptionWindowMonths = consumptionWindowMonths
        self.capitalizePurchases = capitalizePurchases
        self.companyName = companyName
        self.profitGoals = profitGoals
        self.progressAsOf = progressAsOf
        self.expectedMix = expectedMix
        self.defaultVatRate = defaultVatRate
        self.defaultVatIncluded = defaultVatIncluded
        self.vatEnabled = vatEnabled
        self.setupCompleted = setupCompleted
        self.priceCheckInterval = priceCheckInterval
        self.lastPriceCheck = lastPriceCheck
    }
}

// Eski yedeklerde olmayan alanlar varsayılanla doldurulur —
// yeni bir ayar eklemek eski kayıtları okunamaz hale getirmesin.
extension AppSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case consumptionWindowMonths, capitalizePurchases, companyName, profitGoals
        case progressAsOf, expectedMix
        case defaultVatRate, defaultVatIncluded, vatEnabled, setupCompleted
        case priceCheckInterval, lastPriceCheck
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        consumptionWindowMonths = try c.decodeIfPresent(Int.self, forKey: .consumptionWindowMonths)
            ?? d.consumptionWindowMonths
        capitalizePurchases = try c.decodeIfPresent(Bool.self, forKey: .capitalizePurchases)
            ?? d.capitalizePurchases
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName) ?? d.companyName
        profitGoals = try c.decodeIfPresent([MonthKey: Kurus].self, forKey: .profitGoals) ?? [:]
        progressAsOf = try c.decodeIfPresent([MonthKey: DateKey].self, forKey: .progressAsOf) ?? [:]
        expectedMix = try c.decodeIfPresent(ExpectedMix.self, forKey: .expectedMix)
        defaultVatRate = try c.decodeIfPresent(VatRate.self, forKey: .defaultVatRate) ?? .yirmi
        defaultVatIncluded = try c.decodeIfPresent(Bool.self, forKey: .defaultVatIncluded) ?? true
        vatEnabled = try c.decodeIfPresent(Bool.self, forKey: .vatEnabled) ?? true
        // Kayıtlı dosyası olan kullanıcı sihirbazı görmez; yalnızca ilk kurulumda çıkar.
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? true
        priceCheckInterval = try c.decodeIfPresent(PriceCheckInterval.self,
                                                   forKey: .priceCheckInterval) ?? .aylik
        lastPriceCheck = try c.decodeIfPresent(DateKey.self, forKey: .lastPriceCheck)
    }
}

/// Fiyatları ne sıklıkla gözden geçirmek istediğin.
public enum PriceCheckInterval: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case haftalik, ikiHaftalik, aylik, kapali

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .haftalik: return "Her hafta"
        case .ikiHaftalik: return "2 haftada bir"
        case .aylik: return "Ayda bir"
        case .kapali: return "Hatırlatma"
        }
    }

    public var days: Int? {
        switch self {
        case .haftalik: return 7
        case .ikiHaftalik: return 14
        case .aylik: return 30
        case .kapali: return nil
        }
    }
}

public struct AppState: Hashable, Sendable {
    public var materials: [StockMaterial]
    public var products: [Product]
    public var channels: [Channel]
    public var channelMonths: [ChannelMonth]
    public var sales: [SalesEntry]
    public var expenses: [Expense]
    public var purchases: [StockPurchase]
    public var adjustments: [StockAdjustment]
    public var counts: [StockCount]
    public var balances: [BalanceItem]
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
        balances: [BalanceItem] = [],
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
        self.balances = balances
        self.settings = settings
    }

    public static let empty = AppState()
}

// Eksik alanlar boş kabul edilir. Yeni bir liste eklemek, eski yedekleri
// okunamaz hale getirmesin — aksi halde güncelleme veri kaybına yol açar.
extension AppState: Codable {
    enum CodingKeys: String, CodingKey {
        case materials, products, channels, channelMonths, sales
        case expenses, purchases, adjustments, counts, balances, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        materials = try c.decodeIfPresent([StockMaterial].self, forKey: .materials) ?? []
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        channels = try c.decodeIfPresent([Channel].self, forKey: .channels) ?? []
        channelMonths = try c.decodeIfPresent([ChannelMonth].self, forKey: .channelMonths) ?? []
        sales = try c.decodeIfPresent([SalesEntry].self, forKey: .sales) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        purchases = try c.decodeIfPresent([StockPurchase].self, forKey: .purchases) ?? []
        adjustments = try c.decodeIfPresent([StockAdjustment].self, forKey: .adjustments) ?? []
        counts = try c.decodeIfPresent([StockCount].self, forKey: .counts) ?? []
        balances = try c.decodeIfPresent([BalanceItem].self, forKey: .balances) ?? []
        // Kayıtlı dosyası olan kullanıcı kurulumu zaten yapmıştır
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings)
            ?? AppSettings(setupCompleted: true)
    }
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
