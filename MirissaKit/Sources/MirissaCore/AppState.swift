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

/// Satışların yaklaşık dağılımı — geçmiş ay verisi yokken hedef hesaplamak için.
/// Kullanıcı onaylamadan kullanılmaz; eşit dağılım yalnızca öneridir.
public struct SalesMix: Codable, Hashable, Sendable {
    /// kanal id → yüzde (toplamı 100 olmalı)
    public var channelShares: [Id: Double]
    /// ürün id → yüzde (toplamı 100 olmalı)
    public var productShares: [Id: Double]
    /// Kullanıcı bu dağılımı onayladı mı
    public var confirmed: Bool
    /// Ne zaman onaylandı
    public var confirmedAt: DateKey?

    public init(channelShares: [Id: Double] = [:], productShares: [Id: Double] = [:],
                confirmed: Bool = false, confirmedAt: DateKey? = nil) {
        self.channelShares = channelShares
        self.productShares = productShares
        self.confirmed = confirmed
        self.confirmedAt = confirmedAt
    }

    /// Kanal ve ürün yüzdelerinin çarpımından (kanal, ürün, pay) listesi
    public func agirliklar(state: AppState) -> [(channelId: Id, productId: Id, pay: Double)] {
        let kanallar = channelShares.filter { $0.value > 0 && state.channel($0.key) != nil }
        let urunler = productShares.filter { $0.value > 0 && state.product($0.key) != nil }
        let kanalToplam = kanallar.values.reduce(0, +)
        let urunToplam = urunler.values.reduce(0, +)
        guard kanalToplam > 0, urunToplam > 0 else { return [] }
        var out: [(Id, Id, Double)] = []
        for (k, kp) in kanallar.sorted(by: { $0.key < $1.key }) {
            for (u, up) in urunler.sorted(by: { $0.key < $1.key }) {
                out.append((k, u, (kp / kanalToplam) * (up / urunToplam)))
            }
        }
        return out
    }

    /// Eşit dağılım önerisi — kullanıcı onaylayana kadar kullanılmaz
    public static func esitOneri(state: AppState) -> SalesMix {
        let kanallar = state.activeChannels
        let urunler = state.activeProducts
        guard !kanallar.isEmpty, !urunler.isEmpty else { return SalesMix() }
        let kp = 100.0 / Double(kanallar.count)
        let up = 100.0 / Double(urunler.count)
        return SalesMix(
            channelShares: Dictionary(uniqueKeysWithValues: kanallar.map { ($0.id, kp) }),
            productShares: Dictionary(uniqueKeysWithValues: urunler.map { ($0.id, up) }),
            confirmed: false
        )
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
    /// Hiç geçmiş ay yokken hedef hesaplamak için kullanılan varsayım (eski)
    public var expectedMix: ExpectedMix?
    /// Satışların yaklaşık kanal + ürün dağılımı
    public var salesMix: SalesMix?
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

    /// Yıllık kâr hedefi (yıl → kuruş)
    public var yearlyProfitGoals: [String: Kurus] = [:]
    /// Reklamlı bir siparişte, reklamdan sonra en az kalması istenen tutar.
    /// nil = kullanıcı henüz seçmedi; sessizce varsayılan kullanılmaz.
    public var adKeepPerOrder: Kurus?
    /// Sonradan eklenen ayarlar (yedek, vergi, nakit, kilit, hatırlatma).
    /// Hepsi isteğe bağlıdır: eski dosyalar okunur, hesaplar değişmez.
    public var ek: EkAyarlar = EkAyarlar()

    public func yearlyProfitGoal(for year: Int) -> Kurus? {
        yearlyProfitGoals["\(year)"].flatMap { $0 > 0 ? $0 : nil }
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
        salesMix: SalesMix? = nil,
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
        self.salesMix = salesMix
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
        case progressAsOf, expectedMix, salesMix
        case defaultVatRate, defaultVatIncluded, vatEnabled, setupCompleted
        case priceCheckInterval, lastPriceCheck, yearlyProfitGoals, adKeepPerOrder, ek
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        // Bozuk bir yedekte sıfır gelirse sıfıra bölme olmasın
        consumptionWindowMonths = max(
            try c.decodeIfPresent(Int.self, forKey: .consumptionWindowMonths)
                ?? d.consumptionWindowMonths, 1)
        capitalizePurchases = try c.decodeIfPresent(Bool.self, forKey: .capitalizePurchases)
            ?? d.capitalizePurchases
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName) ?? d.companyName
        profitGoals = try c.decodeIfPresent([MonthKey: Kurus].self, forKey: .profitGoals) ?? [:]
        progressAsOf = try c.decodeIfPresent([MonthKey: DateKey].self, forKey: .progressAsOf) ?? [:]
        expectedMix = try c.decodeIfPresent(ExpectedMix.self, forKey: .expectedMix)
        salesMix = try c.decodeIfPresent(SalesMix.self, forKey: .salesMix)
        defaultVatRate = try c.decodeIfPresent(VatRate.self, forKey: .defaultVatRate) ?? .yirmi
        defaultVatIncluded = try c.decodeIfPresent(Bool.self, forKey: .defaultVatIncluded) ?? true
        vatEnabled = try c.decodeIfPresent(Bool.self, forKey: .vatEnabled) ?? true
        // Kayıtlı dosyası olan kullanıcı sihirbazı görmez; yalnızca ilk kurulumda çıkar.
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? true
        priceCheckInterval = try c.decodeIfPresent(PriceCheckInterval.self,
                                                   forKey: .priceCheckInterval) ?? .aylik
        lastPriceCheck = try c.decodeIfPresent(DateKey.self, forKey: .lastPriceCheck)
        yearlyProfitGoals = try c.decodeIfPresent([String: Kurus].self,
                                                  forKey: .yearlyProfitGoals) ?? [:]
        adKeepPerOrder = try c.decodeIfPresent(Kurus.self, forKey: .adKeepPerOrder)
        ek = (try? c.decodeIfPresent(EkAyarlar.self, forKey: .ek)) ?? EkAyarlar()
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
    /// Yarım kalmış soru-cevap akışları. Diskte saklanır; uygulama
    /// kapansa bile cevaplar kaybolmaz.
    public var drafts: [WizardDraft]
    public var settings: AppSettings
    /// Kayıtlarda yapılan değişikliklerin günlüğü (en yeni sonda, en fazla 1.000)
    public var changeLog: [ChangeLogEntry] = []

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
        drafts: [WizardDraft] = [],
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
        self.drafts = drafts
        self.settings = settings
    }

    public static let empty = AppState()
}

// Eksik alanlar boş kabul edilir. Yeni bir liste eklemek, eski yedekleri
// okunamaz hale getirmesin — aksi halde güncelleme veri kaybına yol açar.
extension AppState: Codable {
    enum CodingKeys: String, CodingKey {
        case materials, products, channels, channelMonths, sales
        case expenses, purchases, adjustments, counts, balances, drafts, settings, changeLog
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
        drafts = try c.decodeIfPresent([WizardDraft].self, forKey: .drafts) ?? []
        // Kayıtlı dosyası olan kullanıcı kurulumu zaten yapmıştır
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings)
            ?? AppSettings(setupCompleted: true)
        changeLog = (try? c.decodeIfPresent([ChangeLogEntry].self, forKey: .changeLog)) ?? []
    }
}

// MARK: - Arama yardımcıları

public extension AppState {
    func material(_ id: Id) -> StockMaterial? { materials.first { $0.id == id } }
    func product(_ id: Id) -> Product? { products.first { $0.id == id } }
    /// Ürünün satış KDV oranı: ürüne özel oran, yoksa ayarlardaki varsayılan. KDV kapalıysa nil.
    /// Yeni satış girişinde önerilen KDV: ürüne özel oran, yoksa ayarlardaki varsayılan (KDV kapalıysa nil).
    /// Motorun geçmiş satışlara da bakan `satisKdvOrani(productId:channelId:on:)` kuralından ayrıdır.
    func varsayilanSatisKdvOrani(_ productId: Id) -> VatRate? {
        guard settings.vatEnabled else { return nil }
        return product(productId)?.kdvOrani ?? settings.defaultVatRate
    }
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

    /// Paket boyutları; tarih verilirse o gün geçerli olanlar (geçmiş paketli alım değişmesin)
    func itemPackSizes(_ ref: ItemRef, on date: DateKey? = nil) -> [UnitCode: Double] {
        switch ref.kind {
        case .material: return material(ref.id)?.tarihli(date).packSizes ?? [:]
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
