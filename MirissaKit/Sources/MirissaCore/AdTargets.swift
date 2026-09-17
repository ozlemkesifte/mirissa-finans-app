import Foundation

/// Reklam hedefi: bir SKU'nun bir kanalda reklamla satılması ne zaman kârlı.
///
/// Tanımlar (hepsi sipariş başına):
///  - Sipariş değeri: müşterinin ödediği, KDV dahil fiyat. Meta'nın "satın alma
///    değeri" olarak raporladığı tutar budur.
///  - Reklamdan önce kalan: KDV hariç gelir − kanal kesintileri − ürün − ambalaj.
///  - Başa baş ROAS = sipariş değeri ÷ reklamdan önce kalan.
///    Bunun altında her reklamlı satış zarar ettirir.
///  - En fazla CPA = reklamdan önce kalan − siparişte bırakmak istenen tutar.
///  - Hedef ROAS = sipariş değeri ÷ en fazla CPA.
///
/// Reklam harcaması KDV hariç kabul edilir (Meta harcamayı KDV hariç gösterir,
/// KDV'si indirilecek KDV'ye gider).
public struct AdTarget: Identifiable, Hashable, Sendable {
    public var productId: Id
    public var productName: String
    public var channelId: Id
    public var channelName: String
    /// Sipariş değeri (KDV dahil)
    public var orderValue: Kurus
    /// Reklamdan önce siparişte kalan
    public var beforeAds: Kurus
    /// Kullanıcının siparişte bırakmak istediği tutar (nil = henüz seçilmedi)
    public var keepPerOrder: Kurus?

    public var id: String { "\(channelId)#\(productId)" }

    /// Reklamsız bile zarar ediyor mu
    public var reklamsizZarar: Bool { beforeAds <= 0 }

    public var breakevenROAS: Double? {
        beforeAds > 0 ? Double(orderValue) / Double(beforeAds) : nil
    }

    /// Sipariş başına en fazla reklam harcaması. Hedef seçilmemişse başa baş sınırı.
    public var maxCPA: Kurus { beforeAds - (keepPerOrder ?? 0) }

    public var targetROAS: Double? {
        guard keepPerOrder != nil, maxCPA > 0 else { return nil }
        return Double(orderValue) / Double(maxCPA)
    }

    /// Hedef seçilmiş ama bu ürün o kadarını bırakamıyor
    public var hedefiKaldirmiyor: Bool { keepPerOrder != nil && maxCPA <= 0 && beforeAds > 0 }
}

/// Bir ayın gerçekleşen reklam performansı (uygulamaya girilen verilerden)
public struct AdPerformance: Hashable, Sendable {
    /// KDV dahil net satış (indirim ve iade düşülmüş)
    public var revenue: Kurus
    /// Reklam harcaması (KDV hariç) — kanala ait ve ortak reklam giderleri
    public var adSpend: Kurus
    public var orders: Int

    /// Toplam ciro ÷ toplam reklam. Meta'nın kendi ROAS'ından daha gerçekçidir.
    /// Satış girilmemişse hesaplanmaz: "0" demek, eksik veriyi kötü sonuç gibi gösterir.
    public var mer: Double? { adSpend > 0 && revenue > 0 ? Double(revenue) / Double(adSpend) : nil }
    /// Sipariş başına ortalama reklam harcaması
    public var cpa: Kurus? {
        orders > 0 && adSpend > 0 ? Money.roundHalfAwayFromZero(Double(adSpend) / Double(orders)) : nil
    }
}

/// Gerçekleşenin hedefe göre durumu
public enum AdVerdict: String, Sendable, Hashable {
    case veriYok
    case zarar          // başa başın altında
    case basaBasUstu    // başa başın üstünde ama hedefin altında
    case hedefUstu      // hedefin üstünde
}

public extension Engine {

    /// Satılan her SKU + kanal için reklam hedefi. Fiyatı olmayanlar listede yok.
    func adTargets(keepPerOrder: Kurus?, on date: DateKey = Dates.today()) -> [AdTarget] {
        unitContributions(on: date).map {
            AdTarget(productId: $0.productId, productName: $0.productName,
                     channelId: $0.channelId, channelName: $0.channelName,
                     orderValue: $0.price, beforeAds: $0.contribution,
                     keepPerOrder: keepPerOrder)
        }
        .sorted { ($0.breakevenROAS ?? .infinity) < ($1.breakevenROAS ?? .infinity) }
    }

    /// Satış karışımına göre ağırlıklı ortak hedef.
    /// Tek bir kampanyada birden çok ürün satılıyorsa bakılacak rakam budur.
    func blendedAdTarget(month: MonthKey, keepPerOrder: Kurus?,
                         today: DateKey = Dates.today()) -> AdTarget? {
        let gun = max(today, Dates.monthStart(month))
        let (agirliklar, _) = targetMix(month: month)
        guard !agirliklar.isEmpty else { return nil }
        var deger = 0.0, kalan = 0.0, pay = 0.0
        for a in agirliklar {
            guard let u = unitContribution(productId: a.productId,
                                           channelId: a.channelId, on: gun) else { continue }
            deger += Double(u.price) * a.pay
            kalan += Double(u.contribution) * a.pay
            pay += a.pay
        }
        guard pay > 0 else { return nil }
        return AdTarget(productId: "", productName: "Satış karışımı",
                        channelId: "", channelName: "Tüm kanallar",
                        orderValue: Money.roundHalfAwayFromZero(deger / pay),
                        beforeAds: Money.roundHalfAwayFromZero(kalan / pay),
                        keepPerOrder: keepPerOrder)
    }

    /// Ayın gerçekleşen reklam performansı
    func adPerformance(month: MonthKey) -> AdPerformance {
        let r = companyMonth(month)
        return AdPerformance(
            revenue: r.channels.reduce(0) { $0 + $1.netSalesIncVat },
            adSpend: r.expenseBreakdown[.reklam] ?? 0,
            orders: r.orders
        )
    }

    /// Gerçekleşeni hedefe göre değerlendirir
    func adVerdict(_ p: AdPerformance, target t: AdTarget?) -> AdVerdict {
        guard let mer = p.mer, let t, let basaBas = t.breakevenROAS else { return .veriYok }
        if mer < basaBas { return .zarar }
        if let hedef = t.targetROAS, mer < hedef { return .basaBasUstu }
        return t.targetROAS == nil ? .basaBasUstu : .hedefUstu
    }

    /// Bütçe hesabı: bu bütçeyle hedef CPA'da kaç sipariş gelmeli
    func ordersForBudget(_ budget: Kurus, target t: AdTarget) -> Int? {
        guard t.maxCPA > 0 else { return nil }
        return Int(ceil(Double(budget) / Double(t.maxCPA)))
    }

    /// Ters hesap: bu kadar reklam siparişi için en fazla ne kadar harcanabilir
    func budgetForOrders(_ orders: Int, target t: AdTarget) -> Kurus? {
        guard t.maxCPA > 0 else { return nil }
        return t.maxCPA * orders
    }
}

public enum RoasFormat {
    /// 1,81 — Meta'daki gibi iki basamak
    public static func format(_ v: Double) -> String {
        guard v.isFinite else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "-"
    }
}
