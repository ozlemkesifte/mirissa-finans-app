import Foundation

public enum VatRate: Int, Codable, Sendable, CaseIterable, Identifiable {
    case yok = 0
    case bir = 1
    case on = 10
    case yirmi = 20

    public var id: Int { rawValue }

    public var displayName: String {
        self == .yok ? "KDV yok" : "%\(rawValue)"
    }

    public var multiplier: Double { Double(rawValue) / 100 }
}

/// Bir tutarın KDV hariç kısmı ile KDV kısmı.
public struct VatSplit: Hashable, Sendable {
    public var net: Kurus
    public var vat: Kurus

    public var total: Kurus { net + vat }
    public static let zero = VatSplit(net: 0, vat: 0)

    public static func + (a: VatSplit, b: VatSplit) -> VatSplit {
        VatSplit(net: a.net + b.net, vat: a.vat + b.vat)
    }

    public static func += (a: inout VatSplit, b: VatSplit) { a = a + b }
}

public enum Vat {
    /// Tutarı KDV hariç net ve KDV olarak ayırır.
    /// `included` doğruysa girilen tutar KDV'yi zaten içerir.
    public static func split(_ amount: Kurus, rate: VatRate, included: Bool) -> VatSplit {
        guard rate != .yok, amount != 0 else { return VatSplit(net: amount, vat: 0) }
        if included {
            let net = Money.roundHalfAwayFromZero(Double(amount) / (1 + rate.multiplier))
            return VatSplit(net: net, vat: amount - net)
        }
        return VatSplit(net: amount, vat: Money.roundHalfAwayFromZero(Double(amount) * rate.multiplier))
    }

    /// Sadece KDV hariç tutar
    public static func net(_ amount: Kurus, rate: VatRate, included: Bool) -> Kurus {
        split(amount, rate: rate, included: included).net
    }
}

/// Bir ayın KDV durumu.
public struct VatStatus: Hashable, Sendable {
    public var month: MonthKey
    /// Satışlardan doğan KDV
    public var hesaplanan: Kurus
    /// Gider, alım ve kanal kesintilerinden indirilebilecek KDV
    public var indirilecek: Kurus
    /// Önceki aydan devreden KDV (indirilecek fazlası)
    public var oncekiDevreden: Kurus

    /// Bu ayın sonucu: pozitifse ödenecek, negatifse sonraki aya devreder
    public var fark: Kurus { hesaplanan - indirilecek - oncekiDevreden }

    public var odenecek: Kurus { max(fark, 0) }
    /// Sonraki aya devreden KDV
    public var devreden: Kurus { max(-fark, 0) }

    public var hasData: Bool { hesaplanan != 0 || indirilecek != 0 || oncekiDevreden != 0 }

    public var summary: String {
        if odenecek > 0 { return "Tahmini ödenecek KDV: \(Money.format(odenecek))" }
        if devreden > 0 { return "Sonraki aya devreden KDV: \(Money.format(devreden))" }
        return "Bu ay ödenecek KDV çıkmıyor."
    }
}

// MARK: - Alacak / Ödenecek özeti

public struct BalanceSummary: Hashable, Sendable {
    public var alacaklar: [BalanceItem]
    public var odenecekler: [BalanceItem]
    /// Bu ayın tahmini ödenecek KDV'si (ödenecekler tarafına eklenir)
    public var tahminiKdv: Kurus

    public var toplamAlacak: Kurus { alacaklar.reduce(0) { $0 + $1.amount } }
    public var toplamOdenecek: Kurus { odenecekler.reduce(0) { $0 + $1.amount } + tahminiKdv }
    /// Alacaklar tahsil edilip borçlar ödendiğinde kalan
    public var net: Kurus { toplamAlacak - toplamOdenecek }

    public var isEmpty: Bool { alacaklar.isEmpty && odenecekler.isEmpty && tahminiKdv == 0 }

    public static let empty = BalanceSummary(alacaklar: [], odenecekler: [], tahminiKdv: 0)
}

public extension Engine {
    /// Bir ayın KDV durumu. Önceki aydan devreden KDV zincirlenerek hesaplanır.
    func vatStatus(_ month: MonthKey) -> VatStatus {
        if let v = vatCacheGet(month) { return v }

        // Veri başlangıcından bu aya kadar zincirle: devreden KDV aylar boyunca taşınır
        // Zincir, KDV doğuran en eski aydan başlar: satış, gider, alım ya da kanal kaydı
        let adaylar = [state.dataMonthBounds.first]
            + state.channelMonths.map(\.month)
            + state.expenses.map { Dates.month(of: $0.date) }
            + state.purchases.map { Dates.month(of: $0.date) }
        let baslangic = min(adaylar.min() ?? month, month)
        var devreden: Kurus = 0
        var sonuc = VatStatus(month: month, hesaplanan: 0, indirilecek: 0, oncekiDevreden: 0)

        for m in Dates.monthRange(from: baslangic, to: month) {
            let r = companyMonth(m)
            let adim = VatStatus(
                month: m,
                hesaplanan: r.hesaplananKdv,
                indirilecek: r.indirilecekKdv,
                oncekiDevreden: devreden
            )
            vatCacheSet(m, adim)
            devreden = adim.devreden
            sonuc = adim
        }
        return sonuc
    }

    /// Kesintisi olduğu halde kesinti KDV oranı girilmemiş kanallar.
    /// Bunlar varken indirilecek KDV olduğundan az çıkar.
    func channelsMissingFeeVat(month: MonthKey) -> [String] {
        companyMonth(month).channels.compactMap { c in
            guard c.channelFees > 0,
                  let ch = state.channel(c.channelId),
                  ch.feeVatRate == nil else { return nil }   // "KDV yok" seçilmişse uyarı verilmez
            return ch.name
        }
    }

    /// Alacak ve ödenecekler + bu ayın tahmini KDV'si
    func balanceSummary(month: MonthKey) -> BalanceSummary {
        let acik = state.balances.filter { !$0.settled }
        return BalanceSummary(
            alacaklar: acik.filter { $0.kind == .alacak }.sorted { $0.amount > $1.amount },
            odenecekler: acik.filter { $0.kind == .odenecek }.sorted { $0.amount > $1.amount },
            tahminiKdv: state.settings.vatEnabled ? vatStatus(month).odenecek : 0
        )
    }
}

// MARK: - KDV kayıtları (neden indirildi / indirilmedi)

/// Bir ayın KDV'sini oluşturan kayıtlar. Toplamlar `vatStatus` ile birebir aynıdır:
/// hesaplananlar = hesaplanan KDV, indirilecekler = indirilecek KDV.
public struct KdvKaydi: Identifiable, Hashable, Sendable {
    public enum Tur: String, Sendable { case hesaplanan, indirilecek, indirilemeyen }
    public var id: String
    public var tur: Tur
    public var ad: String
    public var tarih: DateKey?
    public var tutar: Kurus
    /// Neden bu gruba girdiği
    public var neden: String
}

public extension Engine {
    func kdvKayitlari(_ month: MonthKey) -> [KdvKaydi] {
        let r = companyMonth(month)
        var out: [KdvKaydi] = []
        for c in r.channels where c.outputVat != 0 {
            out.append(KdvKaydi(id: "satis-\(c.channelId)", tur: .hesaplanan, ad: "\(c.channelName) satışları",
                                tarih: nil, tutar: c.outputVat,
                                neden: "Satışın KDV'si, satışın yapıldığı ayda hesaplanır (iade ve indirim düşülmüş)."))
        }
        for c in r.channels where c.feeVat != 0 {
            out.append(KdvKaydi(id: "kesinti-\(c.channelId)", tur: .indirilecek, ad: "\(c.channelName) kesinti faturaları",
                                tarih: nil, tutar: c.feeVat,
                                neden: "Komisyon, kargo ve hizmet faturalarının KDV'si; kanal ayarındaki kesinti KDV oranıyla."))
        }
        for i in expenseInstances(month: month) {
            if i.inputVat != 0 {
                out.append(KdvKaydi(id: "gider-\(i.id)", tur: .indirilecek, ad: i.name, tarih: i.date, tutar: i.inputVat,
                                    neden: i.capitalized ? "Stok alımı faturası: KDV alım ayında indirilir."
                                        : "Gider faturası: KDV ödeme (fatura) ayında indirilir."))
            }
            if i.indirilemeyenKdv != 0 {
                out.append(KdvKaydi(id: "indirilemez-\(i.id)", tur: .indirilemeyen, ad: i.name, tarih: i.date,
                                    tutar: i.indirilemeyenKdv,
                                    neden: "\"KDV indirilemez\" işaretli: KDV gidere eklendi, indirilecek KDV'ye girmedi"
                                        + (i.kkeg ? " (KKEG gider)." : ".")))
            }
        }
        return out
    }
}
