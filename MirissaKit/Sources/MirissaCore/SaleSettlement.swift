import Foundation

/// Tek ürünlük bir siparişin baştan sona dökümü:
/// satış fiyatı → KDV → pazaryeri kesintileri (her biri ayrı) → stopaj → hesabına yatan
/// → ürün ve ambalaj maliyeti → sana kalan.
/// Bütün rakamlar kullanıcının girdiği fiyat, oran ve maliyetlerden gelir; tahmin yoktur.
public struct HakedisKalemi: Identifiable, Hashable, Sendable {
    public var id: String
    public var ad: String
    /// Nasıl hesaplandı: "%21 × 1.000,00 TL" gibi
    public var detay: String
    /// Pazaryerinin faturasındaki tutar (KDV dahil)
    public var brut: Kurus
    /// KDV hariç tutar — kâra etki eden
    public var net: Kurus
    public var kdv: Kurus { brut - net }
    /// Aylık gerçek tutarlardan türetildi
    public var tahmini: Bool = false
}

public struct SatisHakedisDokumu: Hashable, Sendable {
    public var productId: Id
    public var channelId: Id
    public var kanalAdi: String
    /// Müşterinin ödediği fiyat (KDV dahil)
    public var fiyat: Kurus
    public var satisKdvOrani: VatRate
    /// Satıştan devlete ödenecek KDV (hesaplanan)
    public var satisKdv: Kurus
    public var kdvHaricSatis: Kurus { fiyat - satisKdv }
    public var kesintiler: [HakedisKalemi]
    /// E-ticaret stopajı: gider değil, gelir/kurumlar vergisinden düşülür
    public var stopaj: Kurus
    public var stopajOrani: Double?
    /// Siparişe bölünmeyen aylık sabit kesintiler (bilgi için)
    public var aylikSabitler: [AylikSabitKesinti]
    public var urunMaliyeti: Kurus
    public var ambalajMaliyeti: Kurus
    public var koliMaliyeti: Kurus
    /// Maliyeti bilinmeyen / aylık tutarı girilmemiş kalemler
    public var eksikler: [String]

    public var kesintiBrut: Kurus { kesintiler.reduce(0) { $0 + $1.brut } }
    public var kesintiNet: Kurus { kesintiler.reduce(0) { $0 + $1.net } }
    /// Kesinti faturalarındaki KDV: satış KDV'sinden indirilir
    public var kesintiKdv: Kurus { kesintiler.reduce(0) { $0 + $1.kdv } }
    /// Pazaryerinin hesabına yatırdığı para
    public var hesabinaYatan: Kurus { fiyat - kesintiBrut - stopaj }
    /// Bu satış yüzünden ödenecek KDV (satış KDV'si − kesinti KDV'si)
    public var odenecekKdv: Kurus { satisKdv - kesintiKdv }
    /// Ürün + ambalaj + koli
    public var maliyet: Kurus { urunMaliyeti + ambalajMaliyeti + koliMaliyeti }
    /// Sana kalan (vergi öncesi kâr): KDV hariç satış − KDV hariç kesintiler − maliyet.
    /// Aynı sonuç: hesabına yatan − ödenecek KDV + stopaj (vergiden düşülecek) − maliyet.
    public var netKalan: Kurus { kdvHaricSatis - kesintiNet - maliyet }
}

public struct AylikSabitKesinti: Hashable, Sendable {
    public var ad: String
    public var tutar: Kurus
}

public extension Engine {

    /// Bir ürünün bir kanaldaki TEK satışının (tek ürünlük sipariş, 1 koli) dökümü.
    /// Fiyat girilmemişse `nil`.
    func satisHakedisDokumu(productId: Id, channelId: Id,
                            on date: DateKey = Dates.today()) -> SatisHakedisDokumu? {
        guard let u = unitContribution(productId: productId, channelId: channelId, on: date),
              let ch = state.channel(channelId) else { return nil }
        let r = ch.rates(on: date)
        let ek = elleAylikTahmin(ch, on: date)
        let fiyat = Double(u.price)
        let satisOrani = satisKdvOrani(productId: productId, channelId: channelId, on: date)
        let feeRate = ch.resolvedFeeVatRate, dahil = ch.resolvedFeesIncludeVat

        func yuzde(_ v: Double) -> String { "%" + RoasFormat.format(v).replacingOccurrences(of: ",00", with: "") }
        var kalemler: [HakedisKalemi] = []
        func ekle(_ id: String, _ ad: String, _ detay: String, _ ham: Double, tahmini: Bool = false) {
            let tutar = Money.roundHalfAwayFromZero(ham)
            guard tutar != 0 else { return }
            let s = Vat.split(tutar, rate: feeRate, included: dahil)
            kalemler.append(HakedisKalemi(id: id, ad: ad, detay: detay, brut: s.net + s.vat,
                                          net: s.net, tahmini: tahmini))
        }
        let fiyatYazi = Money.format(u.price)

        // Komisyon (ve ödeme komisyonu)
        if let t = ek.komisyonYuzde {
            ekle("komisyon", "Komisyon", "\(yuzde(t)) × \(fiyatYazi) · aylık gerçek tutarından",
                 fiyat * t / 100, tahmini: true)
        } else {
            let carpan = komisyonTabanCarpani(ch, on: date, satisKdv: satisOrani)
            let taban = ch.komisyonKdvHaric(on: date) ? "KDV hariç fiyatın" : fiyatYazi
            ekle("komisyon", "Pazaryeri komisyonu", "\(yuzde(r.commissionPct)) × \(taban)",
                 fiyat * r.commissionPct * carpan / 100)
            ekle("odeme", "Ödeme / işlem komisyonu", "\(yuzde(r.paymentPct)) × \(fiyatYazi)",
                 fiyat * r.paymentPct / 100)
        }
        let diger = ek.digerYuzde ?? r.otherDeductionPct
        ekle("diger", "Diğer kesinti", "\(yuzde(diger)) × \(fiyatYazi)"
             + (ek.digerYuzde != nil ? " · aylık gerçek tutarından" : ""),
             fiyat * diger / 100, tahmini: ek.digerYuzde != nil)
        ekle("kargo", "Kargo", "sipariş başına" + (ek.kargoSiparisBasi != nil ? " · aylık gerçek tutarından" : ""),
             ek.kargoSiparisBasi ?? Double(r.shippingPerOrder), tahmini: ek.kargoSiparisBasi != nil)
        ekle("hizmet", "Platform hizmet bedeli",
             "sipariş başına" + (ek.hizmetSiparisBasi != nil ? " · aylık gerçek tutarından" : ""),
             ek.hizmetSiparisBasi ?? Double(r.serviceFeePerOrder), tahmini: ek.hizmetSiparisBasi != nil)

        var aylik: [AylikSabitKesinti] = []
        if r.platformFeeMonthly != 0 { aylik.append(.init(ad: "Aylık platform ücreti", tutar: r.platformFeeMonthly)) }
        if r.otherDeductionMonthly != 0 { aylik.append(.init(ad: "Aylık diğer kesinti", tutar: r.otherDeductionMonthly)) }
        for f in r.extras where !f.unknown && !ek.degistirir(AylikKesinti.alan(f)) {
            let ad = f.label.isEmpty ? "Ek kesinti" : f.label
            switch f.basis {
            case .yuzde: ekle("ek-\(f.id)", ad, "\(yuzde(f.value)) × \(fiyatYazi)", fiyat * f.value / 100)
            case .siparisBasi: ekle("ek-\(f.id)", ad, "sipariş başına", f.value)
            case .aylikSabit: aylik.append(.init(ad: ad, tutar: Money.roundHalfAwayFromZero(f.value)))
            case .elleAylik: break   // tahmini ayın gerçeğinden yukarıda ilgili alana yansır
            }
        }

        // Kalemler tek tek yuvarlandı; toplam, kâr hesabındaki kesintiyle kuruşu kuruşuna aynı olsun
        let fark = u.channelFees - kalemler.reduce(0) { $0 + $1.net }
        if fark != 0, let i = kalemler.indices.max(by: { abs(kalemler[$0].net) < abs(kalemler[$1].net) }) {
            kalemler[i].net += fark
            kalemler[i].brut += fark
        }

        var stopaj: Kurus = 0
        var stopajOrani: Double?
        if let oran = ch.stopajPct, oran > 0,
           Dates.month(of: date) >= Dates.month(of: ch.stopajBaslangic ?? "2025-01-01") {
            stopajOrani = oran
            stopaj = Money.roundHalfAwayFromZero(Double(u.netRevenue) * oran / 100)
        }

        var eksik = u.missingFees
        if let d = birimMaliyetDokumu(productId: productId, on: date) {
            eksik += d.kalemler.filter(\.bilinmiyor).map(\.ad)
        }
        return SatisHakedisDokumu(
            productId: productId, channelId: channelId, kanalAdi: ch.name,
            fiyat: u.price, satisKdvOrani: satisOrani, satisKdv: u.price - u.netRevenue,
            kesintiler: kalemler, stopaj: stopaj, stopajOrani: stopajOrani,
            aylikSabitler: aylik,
            urunMaliyeti: u.productCost, ambalajMaliyeti: u.packagingCost,
            koliMaliyeti: u.orderPackagingCost, eksikler: eksik)
    }
}
