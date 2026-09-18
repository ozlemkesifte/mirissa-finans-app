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
    /// Sipariş verildikten kaç gün sonra elde olur (tedarik süresi)
    public var tedarikSuresiGun: Int?
    /// Tedarikçinin kabul ettiği en az sipariş (temel birim)
    public var minSiparis: BaseQty?
    /// Açılış stoğu (uygulamaya geçerken eldeki mevcut)
    public var openingQty: BaseQty?
    public var openingUnitCost: Kurus?
    public var openingDate: DateKey?
    public var archived: Bool
    public var note: String?
    /// Sipariş başına kullanılır (koli gibi): ürün adedine göre değil, gönderilen
    /// koli sayısına göre düşer. 1–2 ürünlük sipariş 1, 3 ve üzeri 2 adet.
    public var perOrder: Bool?

    public var usedPerOrder: Bool { perOrder ?? false }

    /// Adında "koli" geçen malzeme, kullanıcı aksini seçmedikçe sipariş başına kullanılır
    public static func koliMi(_ ad: String) -> Bool {
        ad.lowercased(with: Locale(identifier: "tr_TR")).contains("koli")
    }

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
        note: String? = nil,
        perOrder: Bool? = nil
    ) {
        self.perOrder = perOrder
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
    /// Bu maliyetin geçerli olmaya başladığı gün. Boşsa baştan beri geçerli.
    public var validFrom: DateKey?
    /// Son geçerli gün. Boşsa hâlâ geçerli. Maliyet değişince eski satır
    /// silinmez, burası doldurulur — geçmiş raporlar bozulmaz.
    public var validTo: DateKey?

    public init(id: Id = Ids.make(.costLine), label: String, amount: Kurus,
                validFrom: DateKey? = nil, validTo: DateKey? = nil) {
        self.id = id
        self.label = label
        self.amount = amount
        self.validFrom = validFrom
        self.validTo = validTo
    }

    /// Verilen günde geçerli mi. Tarih verilmezse BUGÜN geçerli olanlar sayılır.
    /// İleri tarihli bir kalem bugünün maliyeti değildir — aksi halde ekranda
    /// görünen maliyet ile motorun kullandığı maliyet ayrışırdı.
    public func isValid(on date: DateKey?) -> Bool {
        let gun = date ?? Dates.today()
        if let f = validFrom, gun < f { return false }
        if let t = validTo, gun > t { return false }
        return true
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

/// Bir SKU'nun belirli bir kanalda, belirli bir tarihten itibaren geçerli fiyatı.
/// Fiyat değişince eski kayıt yerinde kalır — geçmiş raporlar bozulmaz.
public struct PricePoint: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    /// nil = etiket fiyatı (kanal belirtilmemiş)
    public var channelId: Id?
    public var amount: Kurus
    /// Bu fiyatın geçerli olmaya başladığı gün
    public var from: DateKey
    /// Varsa son geçerli gün. Boşsa sonraki fiyat başlayana kadar geçerlidir.
    public var to: DateKey?

    public init(id: Id = Ids.make(.price), channelId: Id? = nil,
                amount: Kurus, from: DateKey, to: DateKey? = nil) {
        self.id = id
        self.channelId = channelId
        self.amount = amount
        self.from = from
        self.to = to
    }
}

public struct Product: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var name: String
    public var sku: String?
    /// Ürünün satış KDV oranı (kozmetik %20, bazı ürünler %10/%1). nil = ayarlardaki varsayılan
    public var kdvOrani: VatRate? = nil
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
    /// Sipariş verildikten (üretime verildikten) kaç gün sonra elde olur
    public var tedarikSuresiGun: Int?
    /// En az sipariş / üretim adedi
    public var minSiparis: BaseQty?
    public var openingQty: BaseQty?
    public var openingUnitCost: Kurus?
    public var openingDate: DateKey?
    public var archived: Bool
    /// Fiyat geçmişi. Fiyat değiştiğinde eski kayıt SİLİNMEZ, yeni bir
    /// kayıt eklenir; geçmiş aylar kendi tarihindeki fiyatla kalır.
    public var priceHistory: [PricePoint]?
    /// Eski sürümlerden gelen tek fiyat alanları. Yükleme sırasında
    /// `priceHistory` içine taşınır; yeni kayıtlarda kullanılmaz.
    public var listPrice: Kurus?
    public var channelPrices: [Id: Kurus]?

    /// Verilen tarihte bu kanalda geçerli satış fiyatı.
    /// Kanala özel fiyat yoksa etiket fiyatına düşer.
    public func price(for channelId: Id? = nil, on date: DateKey) -> Kurus? {
        if let channelId, let p = gecerliFiyat(channelId, date) { return p }
        if let p = gecerliFiyat(nil, date) { return p }
        // Eski veri: tarihçesiz tek fiyat
        if let channelId, let p = channelPrices?[channelId], p > 0 { return p }
        return (listPrice ?? 0) > 0 ? listPrice : nil
    }

    /// Bir kanalın fiyat geçmişi, eskiden yeniye.
    public func priceTimeline(for channelId: Id?) -> [PricePoint] {
        (priceHistory ?? [])
            .filter { $0.channelId == channelId }
            .sorted { $0.from < $1.from }
    }

    /// Fiyatı değiştirmek eskisini silmez: yeni bir geçerlilik kaydı ekler.
    /// Aynı gün için ikinci bir kayıt girilirse o günün kaydı güncellenir.
    public mutating func setPrice(_ amount: Kurus, channelId: Id?, from: DateKey) {
        var liste = priceHistory ?? []
        if let i = liste.firstIndex(where: { $0.channelId == channelId && $0.from == from }) {
            liste[i].amount = amount
        } else {
            liste.append(PricePoint(channelId: channelId, amount: amount, from: from))
        }
        priceHistory = liste.sorted {
            $0.from == $1.from ? ($0.channelId ?? "") < ($1.channelId ?? "") : $0.from < $1.from
        }
    }

    /// Formlardan gelen "şu anki fiyat" girişini geçmişi bozmadan yazar.
    /// Hiç fiyat yoksa baştan beri geçerli sayılır; varsa ve değiştiyse
    /// bugünden başlayan yeni bir kayıt eklenir.
    public mutating func applyCurrentPrice(_ amount: Kurus, channelId: Id?, today: DateKey) {
        let mevcut = price(for: channelId, on: today)
        let kanalKaydiVar = (priceHistory ?? []).contains { $0.channelId == channelId }
        guard amount > 0 else {
            // Sıfır girildi: yalnızca hiç kayıt yoksa bir şey yapma.
            return
        }
        if mevcut == amount { return }
        if !kanalKaydiVar && mevcut == nil {
            setPrice(amount, channelId: channelId, from: "1970-01-01")
        } else {
            setPrice(amount, channelId: channelId, from: today)
        }
    }

    private func gecerliFiyat(_ channelId: Id?, _ date: DateKey) -> Kurus? {
        let uygun = (priceHistory ?? []).filter {
            $0.channelId == channelId && $0.from <= date
                && ($0.to.map { date <= $0 } ?? true)
        }
        guard let son = uygun.max(by: { $0.from < $1.from }), son.amount > 0 else { return nil }
        return son.amount
    }

    /// Setler kendi stoklarını tutmaz; satıldığında bileşenleri düşer.
    public var tracksOwnStock: Bool { !isBundle }

    /// Verilen günde geçerli maliyet kalemleri
    public func costLines(on date: DateKey?) -> [CostLine] {
        costLines.filter { $0.isValid(on: date) }
    }

    /// Form veya kurulumdan gelen güncel maliyet kalemlerini geçmişi
    /// bozmadan uygular: değişen kalem kapatılır, yerine yenisi açılır.
    public mutating func applyCostLines(_ yeni: [CostLine], today: DateKey) {
        let aktif = costLines.filter { $0.validTo == nil }
        // "İlk kez" yalnızca hiç maliyet kaydı yoksa: kalemler silinip yeniden
        // girildiyse eski dönemlerin maliyeti vardır, yeni rakam bugünden başlar.
        let ilkKez = costLines.isEmpty
        var sonuc = costLines.filter { $0.validTo != nil }   // geçmiş olduğu gibi kalır
        let dun = Dates.addDays(today, -1)

        for eski in aktif {
            guard let g = yeni.first(where: { $0.id == eski.id }) else {
                // Kaldırılan kalem silinmez, bugünden itibaren geçersiz olur
                var kapali = eski
                kapali.validTo = dun
                sonuc.append(kapali)
                continue
            }
            if g.amount == eski.amount && g.label == eski.label {
                sonuc.append(eski)
            } else if eski.validFrom == today {
                // Bugün girilen kalem: yeni sürüm açmaya gerek yok
                var guncel = eski
                guncel.amount = g.amount
                guncel.label = g.label
                sonuc.append(guncel)
            } else {
                var kapali = eski
                kapali.validTo = dun
                sonuc.append(kapali)
                sonuc.append(CostLine(label: g.label, amount: g.amount, validFrom: today))
            }
        }
        for g in yeni where !aktif.contains(where: { $0.id == g.id }) {
            // İlk kez maliyet giriliyorsa geçmişe de uygulanır
            sonuc.append(CostLine(id: g.id, label: g.label, amount: g.amount,
                                  validFrom: ilkKez ? nil : today))
        }
        costLines = sonuc
    }

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
        priceHistory: [PricePoint]? = nil,
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
        self.priceHistory = priceHistory
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
    /// Komisyon KDV hariç satış fiyatı üzerinden mi hesaplanıyor (Trendyol böyle yapar,
    /// üstüne KDV ekler). nil/false = KDV dahil fiyatın yüzdesi. %20 KDV'li üründe ikisi aynı sonucu verir.
    public var komisyonKdvHaric: Bool? = nil
    /// E-ticaret stopajı oranı (%). Pazaryeri KDV hariç satış tutarından keser; gider değil,
    /// gelir/kurumlar vergisinden mahsup edilen peşin vergidir. nil = kesilmiyor.
    public var stopajPct: Double? = nil
    /// Stopajın kesilmeye başladığı gün (yasal başlangıç 2025-01-01)
    public var stopajBaslangic: DateKey? = nil
    /// Stopaj kapatıldıysa son ay (dahil). Kapatmak geçmiş ayları değiştirmez.
    public var stopajBitis: MonthKey? = nil

    /// O ay kesilen stopaj oranı (%); kesilmiyorsa nil
    public func stopajOrani(month: MonthKey) -> Double? {
        guard let oran = stopajPct, oran > 0,
              month >= Dates.month(of: stopajBaslangic ?? "2025-01-01") else { return nil }
        if let son = stopajBitis, month > son { return nil }
        return oran
    }
    /// Stopaj bugün açık mı
    public var stopajAcik: Bool { (stopajPct ?? 0) > 0 && stopajBitis == nil }
    /// Tarihli kesinti ayarları. Boşsa yukarıdaki düz alanlar kullanılır.
    /// Komisyon değişince eski kayıt silinmez; geçmiş dönemler bozulmaz.
    public var rateHistory: [ChannelRates]?
    /// Kurulum soru-cevabı tamamlandı mı
    public var setupCompleted: Bool?
    /// Bu kanalda satılan SKU'lar. Boşsa bilinmiyor demektir —
    /// sistem her ürünü her kanalda satılıyor varsaymaz.
    public var soldProductIds: [Id]?

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
        feesIncludeVat: Bool? = nil,
        rateHistory: [ChannelRates]? = nil,
        setupCompleted: Bool? = nil,
        soldProductIds: [Id]? = nil
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
        self.rateHistory = rateHistory
        self.setupCompleted = setupCompleted
        self.soldProductIds = soldProductIds
    }

    public var resolvedFeeVatRate: VatRate { feeVatRate ?? .yok }
    public var resolvedFeesIncludeVat: Bool { feesIncludeVat ?? true }
    public var resolvedSetupCompleted: Bool { setupCompleted ?? true }

    /// Bu kanalda hangi SKU'lar satılıyor. Liste girilmemişse fiyatı
    /// tanımlı olanlar kullanılır; o da yoksa boş döner ve sistem
    /// "bilmiyorum" der — her ürünü her kanala yaymaz.
    public func soldProducts(in state: AppState, on date: DateKey) -> [Id] {
        if let liste = soldProductIds, !liste.isEmpty {
            return liste.filter { id in state.activeProducts.contains { $0.id == id } }
        }
        return state.activeProducts
            .filter { $0.price(for: id, on: date) != nil }
            .map(\.id)
    }

    /// Verilen tarihte geçerli kesinti ayarları.
    /// Tarihçe yoksa kanalın düz alanları kullanılır — eski veriler aynen çalışır.
    public func rates(on date: DateKey) -> ChannelRates {
        let uygun = (rateHistory ?? []).filter { $0.from <= date }
        if let son = uygun.max(by: { $0.from < $1.from }) { return son }
        if let ilk = (rateHistory ?? []).min(by: { $0.from < $1.from }), ilk.from > date {
            // İlk kayıttan öncesi: o günlerde kanal henüz kurulmamış sayılır,
            // yine de düz alanlara düşülür ki geçmiş rapor boş kalmasın.
            _ = ilk
        }
        return duzAlanlardanRates()
    }

    /// Bugün geçerli ayarlar
    public var currentRates: ChannelRates { rates(on: Dates.today()) }

    /// Yeni oran seti ekler; eskisi silinmez.
    public mutating func setRates(_ yeni: ChannelRates) {
        var liste = (rateHistory ?? []).filter { $0.from != yeni.from }
        // İlk kez tarihçe açılıyorsa, o güne kadarki oranlar kayda geçirilir.
        // Aksi halde geçmiş aylar yeni oranla hesaplanır ve raporlar değişirdi.
        if liste.isEmpty, yeni.from > "1970-01-01" {
            var eski = duzAlanlardanRates()
            eski.id = "\(id)_baslangic"
            liste.append(eski)
        }
        liste.append(yeni)
        rateHistory = liste.sorted { $0.from < $1.from }
        // Düz alanlar "bugünkü değer" olarak güncel tutulur: eski ekranlar bozulmaz.
        let bugunku = rates(on: Dates.today())
        commissionPct = bugunku.commissionPct
        paymentPct = bugunku.paymentPct
        shippingPerOrder = bugunku.shippingPerOrder
        serviceFeePerOrder = bugunku.serviceFeePerOrder
        platformFeeMonthly = bugunku.platformFeeMonthly
        otherDeductionPct = bugunku.otherDeductionPct
        otherDeductionMonthly = bugunku.otherDeductionMonthly
    }

    private func duzAlanlardanRates() -> ChannelRates {
        ChannelRates(
            id: "\(id)_duz", from: "1970-01-01",
            commissionPct: commissionPct,
            paymentPct: paymentPct,
            shippingPerOrder: shippingPerOrder,
            serviceFeePerOrder: serviceFeePerOrder,
            platformFeeMonthly: platformFeeMonthly,
            otherDeductionPct: otherDeductionPct,
            otherDeductionMonthly: otherDeductionMonthly
        )
    }

    /// O gün komisyonun KDV hariç fiyattan alınıp alınmadığı (tarihli)
    public func komisyonKdvHaric(on date: DateKey) -> Bool {
        rates(on: date).komisyonKdvHaric ?? komisyonKdvHaric ?? false
    }
}

public enum ChannelKind: String, Codable, Sendable {
    case marketplace   // Pazaryeri: komisyon + hizmet bedeli
    case ownStore      // Kendi sitesi: ödeme komisyonu + platform ücreti
    case manual        // Elden, fuar, WhatsApp
    case other
}

public enum ChannelIds {
    public static let trendyol = "trendyol"
    public static let shopify = "shopify"
    public static let other = "diger"
}

/// Kurulumda seçilebilecek hazır kanallar. Liste sabit değil:
/// "Diğer" ile istenen isimde kanal eklenebilir ve hepsi aynı
/// soru-cevap motorundan geçer.
public struct ChannelPreset: Identifiable, Hashable, Sendable {
    public var id: Id
    public var name: String
    public var kind: ChannelKind

    public init(id: Id, name: String, kind: ChannelKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public static let hazir: [ChannelPreset] = [
        ChannelPreset(id: ChannelIds.trendyol, name: "Trendyol", kind: .marketplace),
        ChannelPreset(id: ChannelIds.shopify, name: "Shopify / Kendi web sitem", kind: .ownStore),
        ChannelPreset(id: "hepsiburada", name: "Hepsiburada", kind: .marketplace),
        ChannelPreset(id: "amazon", name: "Amazon", kind: .marketplace),
        ChannelPreset(id: "ciceksepeti", name: "ÇiçekSepeti", kind: .marketplace),
        ChannelPreset(id: "n11", name: "N11", kind: .marketplace),
        ChannelPreset(id: "pazarama", name: "Pazarama", kind: .marketplace),
        ChannelPreset(id: "manuel", name: "Manuel / fiziksel satış", kind: .manual),
    ]
}

/// Bir kesintinin nasıl hesaplandığı.
public enum FeeBasis: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    /// Satış tutarının yüzdesi
    case yuzde
    /// Her sipariş için sabit tutar
    case siparisBasi
    /// Ay başına sabit tutar (sipariş sayısından bağımsız)
    case aylikSabit
    /// Otomatik hesaplanmaz; kullanıcı her ay gerçek tutarı girer
    case elleAylik

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yuzde: return "Satışın yüzdesi"
        case .siparisBasi: return "Sipariş başına sabit tutar"
        case .aylikSabit: return "Ayda bir sabit tutar"
        case .elleAylik: return "Aylık gerçek tutarı ben gireceğim"
        }
    }
}

/// Kanalın bilinen alanlarına sığmayan kesintiler: kampanya katkısı,
/// kupon katkısı, işlem bedeli, POS komisyonu, kanal reklamı…
/// Liste açık uçludur; kullanıcı istediği adla ekleyebilir.
public struct ChannelExtraFee: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var label: String
    public var basis: FeeBasis
    /// `yuzde` ise oran (4 = %4), diğerlerinde kuruş
    public var value: Double
    /// "Şimdilik bilmiyorum" — hesaba katılmaz, sonuç yaklaşık işaretlenir
    public var unknown: Bool

    public init(id: Id = Ids.make(.channelFee), label: String, basis: FeeBasis,
                value: Double = 0, unknown: Bool = false) {
        self.id = id
        self.label = label
        self.basis = basis
        self.value = value
        self.unknown = unknown
    }
}

/// Bir kanalın belirli tarihten itibaren geçerli kesinti ayarları.
/// Komisyon %4'ten %6'ya çıkınca eski dönemler %4 kalır.
public struct ChannelRates: Codable, Identifiable, Hashable, Sendable {
    public var id: Id
    public var from: DateKey
    public var commissionPct: Double
    public var paymentPct: Double
    public var shippingPerOrder: Kurus
    public var serviceFeePerOrder: Kurus
    public var platformFeeMonthly: Kurus
    public var otherDeductionPct: Double
    public var otherDeductionMonthly: Kurus
    public var extras: [ChannelExtraFee]
    /// Kurulumda "bilmiyorum" denen alanların adları
    public var unknownFields: [String]
    /// Bu tarihten itibaren komisyon KDV hariç fiyattan mı. nil = kanalın ayarı
    public var komisyonKdvHaric: Bool? = nil

    public init(
        id: Id = Ids.make(.channelRate),
        from: DateKey,
        commissionPct: Double = 0,
        paymentPct: Double = 0,
        shippingPerOrder: Kurus = 0,
        serviceFeePerOrder: Kurus = 0,
        platformFeeMonthly: Kurus = 0,
        otherDeductionPct: Double = 0,
        otherDeductionMonthly: Kurus = 0,
        extras: [ChannelExtraFee] = [],
        unknownFields: [String] = []
    ) {
        self.id = id
        self.from = from
        self.commissionPct = commissionPct
        self.paymentPct = paymentPct
        self.shippingPerOrder = shippingPerOrder
        self.serviceFeePerOrder = serviceFeePerOrder
        self.platformFeeMonthly = platformFeeMonthly
        self.otherDeductionPct = otherDeductionPct
        self.otherDeductionMonthly = otherDeductionMonthly
        self.extras = extras
        self.unknownFields = unknownFields
    }

    /// Otomatik hesaba girmeyen, yalnızca elle girilecek kesintiler
    public var elleGirilecekler: [ChannelExtraFee] {
        extras.filter { $0.basis == .elleAylik }
    }

    /// Hesaba katılamayan bilinmeyen alanlar
    public var eksikler: [String] {
        unknownFields + extras.filter(\.unknown).map(\.label)
    }
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
    /// 3 ve daha fazla ürünlü (2 koli giden) sipariş sayısı. Girilmemişse tahmin edilir.
    public var bigOrderCount: Int?
    /// Bu ayın satışları için pazaryerinin hesaba yatırdığı gerçek tutar (hakediş).
    /// Hesabı değiştirmez; beklenenle karşılaştırılır.
    public var payoutActual: Kurus?

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
        note: String? = nil,
        bigOrderCount: Int? = nil,
        payoutActual: Kurus? = nil
    ) {
        self.bigOrderCount = bigOrderCount
        self.payoutActual = payoutActual
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
            && bigOrderCount == nil && payoutActual == nil && (note?.isEmpty ?? true)
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
    /// Kırık, fire, kayıp, sayım eksiği: stoktan çıkan malın maliyeti. Elle girilmez.
    case stokKaybi

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
        case .stokKaybi: return "Fire, kayıp ve sayım farkı"
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
        case .stokKaybi: return "exclamationmark.triangle"
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
        case .influencer, .sabit, .diger, .stokKaybi: return .sabit
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
    /// O ayın tutarı farklı KDV ile girilmişse (ör. bir ay KDV'siz fatura)
    public var vatRate: VatRate?
    public var vatIncluded: Bool?

    public init(amount: Kurus? = nil, name: String? = nil, skipped: Bool = false,
                attachment: String? = nil, vatRate: VatRate? = nil, vatIncluded: Bool? = nil) {
        self.amount = amount
        self.name = name
        self.skipped = skipped
        self.attachment = attachment
        self.vatRate = vatRate
        self.vatIncluded = vatIncluded
    }

    public var isEmpty: Bool {
        amount == nil && name == nil && !skipped && attachment == nil
            && vatRate == nil && vatIncluded == nil
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
    /// Tek seferlik büyük bir gider kaç aya bölünerek kâra yazılsın (ör. 12 = bir yıla).
    /// Para ve KDV ödeme ayında çıkar. nil / 1 = tamamı ödendiği ayda.
    public var yayilanAy: Int? = nil

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
        vatIncluded: Bool? = nil,
        yayilanAy: Int? = nil
    ) {
        self.yayilanAy = yayilanAy
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
    /// Vadeli ya da taksitli ödeme. `nil` = peşin (tamamı alım günü ödendi).
    public var odeme: OdemePlani?

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
