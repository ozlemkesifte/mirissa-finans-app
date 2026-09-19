import Foundation

/// Giderlerin iki gruba ayrılması:
///  - Ürün başına (her satışta oluşan): ürün maliyeti, ambalaj ve koli, komisyon, kargo,
///    satışa bağlı reklam ve diğer satışa bağlı giderler. Satış olmasa bunlar da olmaz.
///  - Genel (satış olmasa da ödenen): kira, maaş, muhasebe gibi sabit giderler, kanal aylık
///    ücretleri, sabit reklam bütçesi, fire ve kayıp.
/// İki grubun toplamı her zaman dönemin toplam giderine eşittir.
public struct GiderKalemi: Identifiable, Hashable, Sendable {
    public var ad: String
    public var tutar: Kurus
    public var aciklama: String?
    public var id: String { ad }
}

public struct UrunGideri: Identifiable, Hashable, Sendable {
    public var productId: Id
    public var ad: String
    /// Satılan (iade düşülmüş) adet
    public var adet: Double
    public var urunMaliyeti: Kurus
    public var ambalaj: Kurus
    /// Komisyon ve yüzde kesintiler (aylık sabit ücret payı hariç)
    public var kesinti: Kurus
    public var kargo: Kurus
    public var id: Id { productId }
    public var toplam: Kurus { urunMaliyeti + ambalaj + kesinti + kargo }
    public var adetBasi: Double? { adet > 0 ? Double(toplam) / adet : nil }
}

public struct GiderAyrimi: Hashable, Sendable {
    public var urunBasina: [GiderKalemi]
    public var genel: [GiderKalemi]
    /// İki grubun açıklayamadığı fark (0 olmalı); 0 değilse hesap tutarsızdır
    public var tutarsizlik: Kurus
    public var urunler: [UrunGideri]
    public var urunBasinaToplam: Kurus { urunBasina.reduce(0) { $0 + $1.tutar } }
    public var genelToplam: Kurus { genel.reduce(0) { $0 + $1.tutar } }
}

public extension Engine {

    func giderAyrimi(from: MonthKey, to: MonthKey) -> GiderAyrimi {
        let r = companyTotals(from: from, to: to)
        let c = r.channels
        func top(_ f: (ChannelMonthResult) -> Kurus) -> Kurus { c.reduce(0) { $0 + f($1) } }

        // Ürün başına
        var ub: [GiderKalemi] = [
            GiderKalemi(ad: "Ürün maliyeti", tutar: top(\.productCost),
                        aciklama: "Satılan ürünlerin üretim / alış maliyeti"),
            GiderKalemi(ad: "Ambalaj ve koli", tutar: top(\.packagingCost),
                        aciklama: "Kutu, patpat, dolgu, etiket; koli sipariş başına"),
            GiderKalemi(ad: "Komisyon ve kesintiler",
                        tutar: top { $0.commission.amount + max($0.otherDeduction.amount - $0.fixedDeduction, 0) },
                        aciklama: "Pazaryeri komisyonu, ödeme ve yüzdelik kesintiler"),
            GiderKalemi(ad: "Kargo ve hizmet bedeli", tutar: top { $0.shipping.amount + $0.serviceFee.amount },
                        aciklama: "Sipariş başına kesilenler"),
            GiderKalemi(ad: "Satışa bağlı reklam", tutar: top(\.adsVariable),
                        aciklama: "Satışa bağlı işaretlediğin reklam giderleri"),
            GiderKalemi(ad: "Diğer satışa bağlı giderler",
                        tutar: top(\.otherChannelExpensesVariable) + r.ortakGiderDegisken,
                        aciklama: "Satışa bağlı işaretlediğin diğer giderler"),
        ]
        ub = ub.filter { $0.tutar != 0 }

        // Genel: ortak sabit giderler kategoriye göre
        var ortakSabit: [ExpenseCategory: Kurus] = [:]
        for i in expenseInstances(from: from, to: to)
        where !i.capitalized && i.scope.channelId == nil && i.behavior == .sabit {
            ortakSabit[i.category, default: 0] += i.expenseAmount
        }
        // Stoktan çıkan (fire, numune) ve eksi stoğu kapatan alımın fiyat farkı
        for kat in [ExpenseCategory.stokKaybi, .influencer, .ambalaj, .urunUretimi] {
            let t = stoktanGider(from: from, to: to, category: kat)
            if t != 0 { ortakSabit[kat, default: 0] += t }
        }
        var genel: [GiderKalemi] = ortakSabit
            .filter { $0.value != 0 }
            .sorted { $0.value > $1.value }
            .map { GiderKalemi(ad: $0.key.displayName, tutar: $0.value, aciklama: nil) }
        let kanalUcreti = top { min($0.fixedDeduction, $0.otherDeduction.amount) }
        if kanalUcreti != 0 {
            genel.append(GiderKalemi(ad: "Kanal aylık ücretleri", tutar: kanalUcreti,
                                     aciklama: "Mağaza aboneliği, platform ücreti"))
        }
        let sabitReklam = top { min($0.adsFixed, $0.ads.amount) }
        if sabitReklam != 0 {
            genel.append(GiderKalemi(ad: "Sabit reklam bütçesi", tutar: sabitReklam,
                                     aciklama: "Satıştan bağımsız işaretlediğin reklam"))
        }
        let kanalSabit = top { min($0.otherChannelExpensesFixed, $0.otherChannelExpensesTotal) }
        if kanalSabit != 0 {
            genel.append(GiderKalemi(ad: "Kanala ait sabit giderler", tutar: kanalSabit, aciklama: nil))
        }
        // İki grubun toplamı toplam gideri tutmalı. Tutmuyorsa fark sahte bir kalemle kapatılmaz:
        // tutarsızlık olarak bildirilir (bu rakamlara güvenilmez)
        let fark = r.toplamGider - ub.reduce(0) { $0 + $1.tutar } - genel.reduce(0) { $0 + $1.tutar }

        // Ürün bazında doğrudan maliyetler
        var urunler: [Id: UrunGideri] = [:]
        var sira: [Id] = []
        for s in urunKanalKarliligi(from: from, to: to) {
            if urunler[s.productId] == nil {
                sira.append(s.productId)
                urunler[s.productId] = UrunGideri(productId: s.productId, ad: s.productName, adet: 0,
                                                  urunMaliyeti: 0, ambalaj: 0, kesinti: 0, kargo: 0)
            }
            urunler[s.productId]!.adet += s.adet - s.iadeAdet
            urunler[s.productId]!.urunMaliyeti += s.urunMaliyeti
            urunler[s.productId]!.ambalaj += s.ambalaj
            urunler[s.productId]!.kesinti += s.kesinti - s.sabitKesinti
            urunler[s.productId]!.kargo += s.kargo
        }
        return GiderAyrimi(urunBasina: ub, genel: genel, tutarsizlik: fark,
                           urunler: sira.compactMap { urunler[$0] }.sorted { $0.toplam > $1.toplam })
    }
}
