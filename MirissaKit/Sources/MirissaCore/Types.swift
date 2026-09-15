import Foundation

public typealias Id = String

// MARK: - Kalem referansı

public enum ItemKind: String, Codable, Sendable {
    case material, product
}

public struct ItemRef: Codable, Hashable, Sendable, Identifiable {
    public var kind: ItemKind
    public var id: Id

    public init(kind: ItemKind, id: Id) {
        self.kind = kind
        self.id = id
    }

    public static func material(_ id: Id) -> ItemRef { .init(kind: .material, id: id) }
    public static func product(_ id: Id) -> ItemRef { .init(kind: .product, id: id) }
}

// MARK: - Malzeme (ambalaj & sarf)

public enum MaterialCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case ambalaj, sarf, diger

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .ambalaj: return "Ambalaj"
        case .sarf: return "Sarf"
        case .diger: return "Diğer"
        }
    }
}

public struct StockMaterial: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var name: String
    public var category: MaterialCategory
    /// Temel birim: adet / gram / ml / cm
    public var baseUnit: UnitCode
    /// Kap birimi karşılıkları: ["paket": 100] -> 1 paket = 100 temel birim
    public var packSizesRaw: [String: Double]
    public var minQty: BaseQty?
    public var criticalQty: BaseQty?
    /// Açılış stoğu (uygulamaya geçerken eldeki mevcut)
    public var openingQty: BaseQty?
    public var openingUnitCost: Kurus?
    public var openingDate: DateKey?
    public var archived: Bool
    public var note: String?

    public var packSizes: [UnitCode: Double] {
        get {
            var out: [UnitCode: Double] = [:]
            for (k, v) in packSizesRaw { if let u = UnitCode(rawValue: k) { out[u] = v } }
            return out
        }
        set {
            packSizesRaw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
        }
    }

    public init(
        id: Id = Ids.make(.material),
        name: String,
        category: MaterialCategory = .ambalaj,
        baseUnit: UnitCode = .adet,
        packSizesRaw: [String: Double] = [:],
        minQty: BaseQty? = nil,
        criticalQty: BaseQty? = nil,
        openingQty: BaseQty? = nil,
        openingUnitCost: Kurus? = nil,
        openingDate: DateKey? = nil,
        archived: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.baseUnit = baseUnit
        self.packSizesRaw = packSizesRaw
        self.minQty = minQty
        self.criticalQty = criticalQty
        self.openingQty = openingQty
        self.openingUnitCost = openingUnitCost
        self.openingDate = openingDate
        self.archived = archived
        self.note = note
    }
}

// MARK: - Ürün

public struct CostLine: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var label: String
    public var amount: Kurus

    public init(id: Id = Ids.make(.costLine), label: String, amount: Kurus) {
        self.id = id
        self.label = label
        self.amount = amount
    }
}

public struct RecipeLine: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var materialId: Id
    public var qty: Double
    public var unit: UnitCode
    /// Fiziksel stok tüketimi. Kapalıysa malzeme stoktan düşmez.
    public var consumesStock: Bool?
    /// Maliyete dahil et. Kapalıysa malzeme stoktan düşer ama
    /// maliyeti ürün maliyetine ikinci kez eklenmez.
    public var addsCost: Bool?

    public init(
        id: Id = Ids.make(.recipeLine),
        materialId: Id,
        qty: Double,
        unit: UnitCode,
        consumesStock: Bool? = nil,
        addsCost: Bool? = nil
    ) {
        self.id = id
        self.materialId = materialId
        self.qty = qty
        self.unit = unit
        self.consumesStock = consumesStock
        self.addsCost = addsCost
    }

    /// Varsayılan: hem stoktan düşer hem maliyete girer
    public var resolvedConsumesStock: Bool { consumesStock ?? true }
    public var resolvedAddsCost: Bool { addsCost ?? true }

    public var isDefault: Bool { resolvedConsumesStock && resolvedAddsCost }

    /// Maliyeti ürünün üretim fiyatında zaten var mı.
    /// Kullanıcıya sorulan soru bu; `addsCost` bunun tersidir.
    public var costAlreadyInProductionPrice: Bool { !resolvedAddsCost }

    /// Satırın özel durumunu anlatan kısa etiket (kullanıcı dilinde)
    public var noteLabel: String? {
        switch (resolvedConsumesStock, resolvedAddsCost) {
        case (true, true): return nil
        case (true, false): return "fiyata dahil"
        case (false, true): return "stok tutulmuyor"
        case (false, false): return "üretici sağlıyor"
        }
    }
}

public struct BundleComponent: Codable, Identifiable, Hashable, Sendable {
    public var id: Id { productId }
    public var productId: Id
    public var qty: Double

    public init(productId: Id, qty: Double) {
        self.productId = productId
        self.qty = qty
    }
}

public struct Product: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var name: String
    public var sku: String?
    public var isBundle: Bool
    public var components: [BundleComponent]
    /// Ürünün kendi maliyet kalemleri (üretim, kutu, etiket...)
    public var costLines: [CostLine]
    /// Paketleme reçetesi — 1 adet satıldığında kullanılan malzemeler
    public var recipe: [RecipeLine]
    /// Üretim maliyetine ZATEN dahil olan malzemeler.
    /// Bunlar stoktan düşer ama maliyetleri ikinci kez sayılmaz.
    public var costIncludesMaterials: [Id]
    public var minQty: BaseQty?
    public var criticalQty: BaseQty?
    public var openingQty: BaseQty?
    public var openingUnitCost: Kurus?
    public var openingDate: DateKey?
    public var archived: Bool
    /// Etiket fiyatı — kanal belirtilmemişse geçerli olan satış fiyatı (KDV dahil).
    /// Kâr hesabı gerçek satış tutarından yapılır; bu yalnızca giriş kolaylığı
    /// ve birim kâr göstergesi içindir.
    public var listPrice: Kurus?
    /// Kanala özel satış fiyatları (kanal id → fiyat)
    public var channelPrices: [Id: Kurus]?

    /// Bu kanalda geçerli satış fiyatı; kanala özel yoksa etiket fiyatı.
    public func price(for channelId: Id? = nil) -> Kurus? {
        if let channelId, let p = channelPrices?[channelId], p > 0 { return p }
        return (listPrice ?? 0) > 0 ? listPrice : nil
    }

    /// Setler kendi stoklarını tutmaz; satıldığında bileşenleri düşer.
    public var tracksOwnStock: Bool { !isBundle }

    /// Bu malzemenin maliyeti üretim maliyetine dahil mi
    public func costAlreadyIncludes(_ materialId: Id) -> Bool {
        costIncludesMaterials.contains(materialId)
    }

    public init(
        id: Id = Ids.make(.product),
        name: String,
        sku: String? = nil,
        isBundle: Bool = false,
        components: [BundleComponent] = [],
        costLines: [CostLine] = [],
        recipe: [RecipeLine] = [],
        costIncludesMaterials: [Id] = [],
        minQty: BaseQty? = nil,
        criticalQty: BaseQty? = nil,
        openingQty: BaseQty? = nil,
        openingUnitCost: Kurus? = nil,
        openingDate: DateKey? = nil,
        archived: Bool = false,
        listPrice: Kurus? = nil,
        channelPrices: [Id: Kurus]? = nil
    ) {
        self.id = id
        self.name = name
        self.sku = sku
        self.isBundle = isBundle
        self.components = components
        self.costLines = costLines
        self.recipe = recipe
        self.costIncludesMaterials = costIncludesMaterials
        self.minQty = minQty
        self.criticalQty = criticalQty
        self.openingQty = openingQty
        self.openingUnitCost = openingUnitCost
        self.openingDate = openingDate
        self.archived = archived
        self.listPrice = listPrice
        self.channelPrices = channelPrices
    }
}

// MARK: - Satış kanalları

public struct Channel: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var name: String
    public var kind: ChannelKind
    public var archived: Bool
    /// Oranlar ve sipariş başı sabit tutarlar — otomatik hesap için
    public var commissionPct: Double
    public var paymentPct: Double
    public var shippingPerOrder: Kurus
    public var serviceFeePerOrder: Kurus
    public var platformFeeMonthly: Kurus
    public var otherDeductionPct: Double
    public var otherDeductionMonthly: Kurus
    /// Komisyon, kargo gibi kesintilerin KDV oranı
    public var feeVatRate: VatRate?
    /// Kesinti tutarları KDV'yi içeriyor mu
    public var feesIncludeVat: Bool?

    public init(
        id: Id,
        name: String,
        kind: ChannelKind = .other,
        archived: Bool = false,
        commissionPct: Double = 0,
        paymentPct: Double = 0,
        shippingPerOrder: Kurus = 0,
        serviceFeePerOrder: Kurus = 0,
        platformFeeMonthly: Kurus = 0,
        otherDeductionPct: Double = 0,
        otherDeductionMonthly: Kurus = 0,
        feeVatRate: VatRate? = nil,
        feesIncludeVat: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.archived = archived
        self.commissionPct = commissionPct
        self.paymentPct = paymentPct
        self.shippingPerOrder = shippingPerOrder
        self.serviceFeePerOrder = serviceFeePerOrder
        self.platformFeeMonthly = platformFeeMonthly
        self.otherDeductionPct = otherDeductionPct
        self.otherDeductionMonthly = otherDeductionMonthly
        self.feeVatRate = feeVatRate
        self.feesIncludeVat = feesIncludeVat
    }

    public var resolvedFeeVatRate: VatRate { feeVatRate ?? .yok }
    public var resolvedFeesIncludeVat: Bool { feesIncludeVat ?? true }
}

public enum ChannelKind: String, Codable, Sendable {
    case marketplace   // Trendyol tipi: komisyon + hizmet bedeli
    case ownStore      // Shopify tipi: ödeme komisyonu + platform ücreti
    case other
}

public enum ChannelIds {
    public static let trendyol = "trendyol"
    public static let shopify = "shopify"
    public static let other = "diger"
}

/// Kanal + ay için gerçek rakam girişleri.
/// Bir alan doluysa otomatik hesabın **üzerine yazar**.
public struct ChannelMonth: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var month: MonthKey
    public var channelId: Id
    public var orderCount: Int?
    public var commissionActual: Kurus?
    public var shippingActual: Kurus?
    public var serviceFeeActual: Kurus?
    public var otherDeductionActual: Kurus?
    public var adsActual: Kurus?
    public var note: String?

    public init(
        id: Id = Ids.make(.channelMonth),
        month: MonthKey,
        channelId: Id,
        orderCount: Int? = nil,
        commissionActual: Kurus? = nil,
        shippingActual: Kurus? = nil,
        serviceFeeActual: Kurus? = nil,
        otherDeductionActual: Kurus? = nil,
        adsActual: Kurus? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.month = month
        self.channelId = channelId
        self.orderCount = orderCount
        self.commissionActual = commissionActual
        self.shippingActual = shippingActual
        self.serviceFeeActual = serviceFeeActual
        self.otherDeductionActual = otherDeductionActual
        self.adsActual = adsActual
        self.note = note
    }

    public var isEmpty: Bool {
        orderCount == nil && commissionActual == nil && shippingActual == nil
            && serviceFeeActual == nil && otherDeductionActual == nil && adsActual == nil
            && (note?.isEmpty ?? true)
    }
}

// MARK: - Satış

public struct SalesEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var month: MonthKey
    public var channelId: Id
    public var productId: Id
    public var qty: Double
    public var grossSales: Kurus
    public var discount: Kurus
    public var returnsAmount: Kurus
    public var returnsQty: Double
    /// İade edilen ürün stoğa geri girsin mi (ambalaj asla geri gelmez)
    public var returnsRestock: Bool
    public var note: String?
    /// KDV oranı. `nil` eski kayıtlar için "KDV yok" sayılır.
    public var vatRate: VatRate?
    /// Girilen tutarlar KDV'yi içeriyor mu
    public var vatIncluded: Bool?

    public init(
        id: Id = Ids.make(.sale),
        month: MonthKey,
        channelId: Id,
        productId: Id,
        qty: Double,
        grossSales: Kurus,
        discount: Kurus = 0,
        returnsAmount: Kurus = 0,
        returnsQty: Double = 0,
        returnsRestock: Bool = true,
        note: String? = nil,
        vatRate: VatRate? = nil,
        vatIncluded: Bool? = nil
    ) {
        self.id = id
        self.month = month
        self.channelId = channelId
        self.productId = productId
        self.qty = qty
        self.grossSales = grossSales
        self.discount = discount
        self.returnsAmount = returnsAmount
        self.returnsQty = returnsQty
        self.returnsRestock = returnsRestock
        self.note = note
        self.vatRate = vatRate
        self.vatIncluded = vatIncluded
    }

    public var resolvedVatRate: VatRate { vatRate ?? .yok }
    public var resolvedVatIncluded: Bool { vatIncluded ?? true }

    /// Girildiği haliyle net satış (KDV dahil olabilir)
    public var netSales: Kurus { grossSales - discount - returnsAmount }
    public var netQty: Double { max(qty - returnsQty, 0) }

    /// KDV hariç net satış ve hesaplanan KDV
    public var vatSplit: VatSplit {
        Vat.split(netSales, rate: resolvedVatRate, included: resolvedVatIncluded)
    }
}

// MARK: - Gider

public enum ExpenseCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case reklam, kargo, urunUretimi, influencer, sabit, ambalaj, komisyon, diger

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .reklam: return "Reklam"
        case .kargo: return "Kargo"
        case .urunUretimi: return "Ürün üretimi"
        case .influencer: return "Influencer"
        case .sabit: return "Sabit giderler"
        case .ambalaj: return "Ambalaj / sarf"
        case .komisyon: return "Komisyon"
        case .diger: return "Diğer"
        }
    }

    public var symbolName: String {
        switch self {
        case .reklam: return "megaphone"
        case .kargo: return "shippingbox"
        case .urunUretimi: return "wrench.and.screwdriver"
        case .influencer: return "person.2"
        case .sabit: return "repeat"
        case .ambalaj: return "cube.box"
        case .komisyon: return "percent"
        case .diger: return "ellipsis.circle"
        }
    }

    /// Kullanıcının gider ekleme formunda seçebileceği kategoriler
    /// (komisyon kanal hesabından otomatik gelir, elle girilmez)
    public static var userSelectable: [ExpenseCategory] {
        [.reklam, .kargo, .urunUretimi, .influencer, .sabit, .ambalaj, .diger]
    }
}

/// Bir giderin satış arttıkça artıp artmadığı.
/// Başa baş hesabı buna göre yapılır: sabit giderleri katkı karşılar,
/// satışa bağlı giderler sipariş başına kazancı düşürür.
public enum CostBehavior: String, Codable, Sendable, CaseIterable, Identifiable {
    case sabit
    case satisaBagli

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sabit: return "Sabit gider"
        case .satisaBagli: return "Satışa bağlı"
        }
    }

    public var explanation: String {
        switch self {
        case .sabit:
            return "Kaç sipariş çıkarsa çıksın aynı kalır. Başa baş noktasını yukarı iter."
        case .satisaBagli:
            return "Satış arttıkça artar. Sipariş başına kazancı düşürür."
        }
    }
}

public extension ExpenseCategory {
    /// Kategorinin makul varsayılanı — kullanıcı her gider için değiştirebilir.
    /// Reklam varsayılan olarak satışa bağlı sayılır; sabit bütçeyle
    /// çalışılıyorsa gider formundan "Sabit gider" seçilebilir.
    var defaultBehavior: CostBehavior {
        switch self {
        case .reklam, .kargo, .ambalaj, .urunUretimi, .komisyon: return .satisaBagli
        case .influencer, .sabit, .diger: return .sabit
        }
    }
}

public enum ExpenseScope: Codable, Hashable, Sendable {
    case ortak
    case channel(Id)

    public var channelId: Id? {
        if case let .channel(id) = self { return id }
        return nil
    }
}

public enum Recurrence: String, Codable, Sendable, CaseIterable, Identifiable {
    case tek, aylik, yillik

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .tek: return "Tek seferlik"
        case .aylik: return "Her ay"
        case .yillik: return "Her yıl"
        }
    }
}

public struct ExpenseOverride: Codable, Hashable, Sendable {
    public var amount: Kurus?
    public var name: String?
    public var skipped: Bool
    /// O aya ait fatura — düzenli giderlerde her ayın kendi faturası olabilir
    public var attachment: String?

    public init(amount: Kurus? = nil, name: String? = nil, skipped: Bool = false, attachment: String? = nil) {
        self.amount = amount
        self.name = name
        self.skipped = skipped
        self.attachment = attachment
    }

    public var isEmpty: Bool {
        amount == nil && name == nil && !skipped && attachment == nil
    }
}

/// Tek seferlik gider VEYA düzenli gider şablonu.
public struct Expense: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    /// Düzenli giderlerde ilk görüneceği tarih
    public var date: DateKey
    public var name: String
    public var amount: Kurus
    public var category: ExpenseCategory
    public var scope: ExpenseScope
    public var recurrence: Recurrence
    /// Dahil son ay. `nil` = devam ediyor. "Durdur" bunu ayarlar; geçmiş aylar korunur.
    public var endMonth: MonthKey?
    public var overrides: [MonthKey: ExpenseOverride]
    public var note: String?
    /// Mükerrer kayıt kontrolü için fatura/fiş numarası
    public var invoiceNo: String?
    /// Faturayı kesen taraf — fatura numarası tek başına ayırt edici değil
    public var vendor: String?
    /// Satış arttıkça artar mı. `nil` ise kategorinin varsayılanı kullanılır.
    public var behavior: CostBehavior?
    /// Fatura/fiş dosyasının adı (uygulamanın ekler klasöründe durur)
    public var attachment: String?
    /// KDV oranı. `nil` eski kayıtlar için "KDV yok" sayılır.
    public var vatRate: VatRate?
    public var vatIncluded: Bool?

    public init(
        id: Id = Ids.make(.expense),
        date: DateKey,
        name: String,
        amount: Kurus,
        category: ExpenseCategory,
        scope: ExpenseScope = .ortak,
        recurrence: Recurrence = .tek,
        endMonth: MonthKey? = nil,
        overrides: [MonthKey: ExpenseOverride] = [:],
        note: String? = nil,
        invoiceNo: String? = nil,
        vendor: String? = nil,
        behavior: CostBehavior? = nil,
        attachment: String? = nil,
        vatRate: VatRate? = nil,
        vatIncluded: Bool? = nil
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.amount = amount
        self.category = category
        self.scope = scope
        self.recurrence = recurrence
        self.endMonth = endMonth
        self.overrides = overrides
        self.note = note
        self.invoiceNo = invoiceNo
        self.vendor = vendor
        self.behavior = behavior
        self.attachment = attachment
        self.vatRate = vatRate
        self.vatIncluded = vatIncluded
    }

    public var resolvedBehavior: CostBehavior { behavior ?? category.defaultBehavior }
    public var resolvedVatRate: VatRate { vatRate ?? .yok }
    public var resolvedVatIncluded: Bool { vatIncluded ?? true }

    public var startMonth: MonthKey { Dates.month(of: date) }
    public var isRecurring: Bool { recurrence != .tek }
    public var isStopped: Bool { endMonth != nil }
}

// MARK: - Stok hareketleri (saklanan kaynaklar)

public struct StockPurchase: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var date: DateKey
    public var item: ItemRef
    public var qty: Double
    public var unit: UnitCode
    /// Ödenen toplam. Birim maliyet buradan hesaplanır.
    public var totalPaid: Kurus
    /// Alıma ait kargo/nakliye — birim maliyete dahil edilir
    public var shippingCost: Kurus
    public var vendor: String?
    public var expenseCategory: ExpenseCategory?
    public var expenseScope: ExpenseScope
    /// Giderler listesinde hiç görünmesin (ör. başka bir kasadan ödendi)
    public var excludeFromExpenses: Bool
    public var note: String?
    /// Mükerrer kayıt kontrolü için fatura/fiş numarası
    public var invoiceNo: String?
    /// Fatura/fiş dosyasının adı
    public var attachment: String?
    /// KDV oranı. `nil` eski kayıtlar için "KDV yok" sayılır.
    public var vatRate: VatRate?
    public var vatIncluded: Bool?

    public init(
        id: Id = Ids.make(.purchase),
        date: DateKey,
        item: ItemRef,
        qty: Double,
        unit: UnitCode,
        totalPaid: Kurus,
        shippingCost: Kurus = 0,
        vendor: String? = nil,
        expenseCategory: ExpenseCategory? = nil,
        expenseScope: ExpenseScope = .ortak,
        excludeFromExpenses: Bool = false,
        note: String? = nil,
        invoiceNo: String? = nil,
        attachment: String? = nil,
        vatRate: VatRate? = nil,
        vatIncluded: Bool? = nil
    ) {
        self.id = id
        self.date = date
        self.item = item
        self.qty = qty
        self.unit = unit
        self.totalPaid = totalPaid
        self.shippingCost = shippingCost
        self.vendor = vendor
        self.expenseCategory = expenseCategory
        self.expenseScope = expenseScope
        self.excludeFromExpenses = excludeFromExpenses
        self.note = note
        self.invoiceNo = invoiceNo
        self.attachment = attachment
        self.vatRate = vatRate
        self.vatIncluded = vatIncluded
    }

    public var resolvedVatRate: VatRate { vatRate ?? .yok }
    public var resolvedVatIncluded: Bool { vatIncluded ?? true }

    /// Ödenen toplam (KDV dahil olabilir)
    public var landedTotal: Kurus { totalPaid + shippingCost }

    /// Stok maliyeti KDV HARİÇ tutulur: indirilecek KDV, ödenecek KDV'den
    /// mahsup edilir; ürün maliyetine yazılırsa kârlılık yanlış çıkar.
    public var landedSplit: VatSplit {
        Vat.split(landedTotal, rate: resolvedVatRate, included: resolvedVatIncluded)
    }

    public var resolvedCategory: ExpenseCategory {
        expenseCategory ?? (item.kind == .material ? .ambalaj : .urunUretimi)
    }
}

public enum AdjustReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case kirik, hasarli, fire, kayip, numune, influencer, pr, icKullanim, sayimFarki, diger

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kirik: return "Kırık"
        case .hasarli: return "Hasarlı"
        case .fire: return "Fire"
        case .kayip: return "Kayıp"
        case .numune: return "Numune"
        case .influencer: return "Influencer"
        case .pr: return "PR gönderimi"
        case .icKullanim: return "İç kullanım"
        case .sayimFarki: return "Sayım farkı"
        case .diger: return "Diğer"
        }
    }

    /// Stok düzeltme ekranında seçilebilenler (sayım farkı sadece sayımdan gelir)
    public static var userSelectable: [AdjustReason] {
        [.kirik, .hasarli, .fire, .kayip, .numune, .influencer, .pr, .icKullanim, .diger]
    }
}

public struct StockAdjustment: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var date: DateKey
    public var item: ItemRef
    /// Girilen miktar (pozitif). `isIncrease` yönü belirler.
    public var qty: Double
    public var unit: UnitCode
    public var isIncrease: Bool
    public var reason: AdjustReason
    public var note: String?

    public init(
        id: Id = Ids.make(.adjustment),
        date: DateKey,
        item: ItemRef,
        qty: Double,
        unit: UnitCode,
        isIncrease: Bool = false,
        reason: AdjustReason,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.item = item
        self.qty = qty
        self.unit = unit
        self.isIncrease = isIncrease
        self.reason = reason
        self.note = note
    }
}

public struct StockCount: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var date: DateKey
    public var item: ItemRef
    public var countedQty: Double
    public var unit: UnitCode
    public var reason: AdjustReason?
    public var note: String?

    public init(
        id: Id = Ids.make(.count),
        date: DateKey,
        item: ItemRef,
        countedQty: Double,
        unit: UnitCode,
        reason: AdjustReason? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.item = item
        self.countedQty = countedQty
        self.unit = unit
        self.reason = reason
        self.note = note
    }
}


// MARK: - Alacak / Ödenecek

public enum BalanceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Bize gelecek para
    case alacak
    /// Bizim ödeyeceğimiz
    case odenecek

    public var id: String { rawValue }
    public var displayName: String { self == .alacak ? "Alacak" : "Ödenecek" }
}

public enum BalanceSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case kanal
    case tedarikci
    case diger

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .kanal: return "Satış kanalı ödemesi"
        case .tedarikci: return "Tedarikçi faturası"
        case .diger: return "Diğer"
        }
    }
}

/// Basit bir alacak/ödenecek satırı. Muhasebe cari hesabı değil —
/// "kim bana borçlu, ben kime borçluyum" listesi.
public struct BalanceItem: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var kind: BalanceKind
    public var source: BalanceSource
    public var name: String
    public var amount: Kurus
    public var dueDate: DateKey?
    public var settled: Bool
    public var note: String?

    public init(
        id: Id = Ids.make(.balance),
        kind: BalanceKind,
        source: BalanceSource = .diger,
        name: String,
        amount: Kurus,
        dueDate: DateKey? = nil,
        settled: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.settled = settled
        self.note = note
    }
}
