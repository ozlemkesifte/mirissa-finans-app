import Foundation

/// Başa baş noktasını oluşturan sabit giderler, tek tek.
/// Bir ayın başa baş hedefi yüksek görünüyorsa sebebi buradan görülür:
/// yılda bir ödenen bir gider "her ay" girilmiş olabilir ya da tek seferlik büyük bir
/// harcamanın tamamı o aya yazılmıştır.
public struct SabitGiderSatiri: Identifiable, Hashable, Sendable {
    public enum Tur: String, Sendable {
        case herAy, yillikPay, tekSeferlik, yayilmis, kanalUcreti, stokKaybi, elleReklam, reklamSiniri
    }
    public var id: String
    public var ad: String
    public var tutar: Kurus
    public var tur: Tur
    /// Düzenlemek için giderin kendisi
    public var expenseId: Id?

    /// Ekranda tutarın altına yazılan açıklama
    public var aciklama: String {
        switch tur {
        case .herAy: return "Her ay"
        case .yillikPay: return "Yılda bir ödenen tutarın 1/12'si"
        case .tekSeferlik: return "Tek seferlik — tamamı bu ayda"
        case .yayilmis: return "Tek seferlik — aylara bölündü"
        case .kanalUcreti: return "Kanal aylık ücreti"
        case .stokKaybi: return "Stoktan çıkan (fire, kayıp, numune)"
        case .elleReklam: return "Ay sonunda elle girilen reklam tutarının gider kayıtlarından farkı"
        case .reklamSiniri: return "Satışa bağlı reklam eksiye düştü (iade); sabit reklamdan düşüldü"
        }
    }
}

public struct SabitGiderDokumu: Hashable, Sendable {
    public var month: MonthKey
    public var satirlar: [SabitGiderSatiri]
    public var toplam: Kurus { satirlar.reduce(0) { $0 + $1.tutar } }
    /// Satırların açıklayamadığı fark (0 olmalı). 0 değilse hesap tutarsızdır: rakamlara güvenilmez,
    /// fark sahte bir kalemle kapatılmaz.
    public var tutarsizlik: Kurus = 0
    /// Tamamı bu aya yazılmış tek seferlik giderler
    public var tekSeferlikToplam: Kurus {
        satirlar.filter { $0.tur == .tekSeferlik }.reduce(0) { $0 + $1.tutar }
    }
}

public extension Engine {

    /// Ayın sabit giderleri kalem kalem. `planli` doğruysa toplam `plannedFixedCosts(month:)` ile,
    /// değilse (ayın gerçekleşen sonucu) `toplamSabitGider` ile birebir aynıdır.
    func sabitGiderDokumu(month: MonthKey, planli: Bool = true) -> SabitGiderDokumu {
        let r = companyMonth(month)
        let giderler = Dictionary(state.expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var satirlar: [SabitGiderSatiri] = []

        for i in expenseInstances(from: month, to: month)
        where !i.capitalized && i.behavior == .sabit && i.expenseAmount != 0 {
            let e = i.templateId.flatMap { giderler[$0] }
            let tur: SabitGiderSatiri.Tur
            switch i.sourceKind {
            case .duzenli: tur = e?.recurrence == .yillik ? .yillikPay : .herAy
            case .tekSeferlik: tur = (e?.yayilanAy ?? 1) > 1 ? .yayilmis : .tekSeferlik
            case .stokAlimi, .taksit, .ayriOdeme, .ayriKdv: tur = .tekSeferlik
            }
            let kanal = i.scope.channelId.flatMap { state.channel($0)?.name }
            satirlar.append(SabitGiderSatiri(
                id: i.id, ad: kanal.map { "\(i.name) (\($0))" } ?? i.name,
                tutar: i.expenseAmount, tur: tur, expenseId: e?.id))
        }
        for kat in [ExpenseCategory.stokKaybi, .influencer, .ambalaj, .urunUretimi] {
            let t = stoktanGider(from: month, to: month, category: kat)
            if t != 0 {
                let ad = kat == .ambalaj || kat == .urunUretimi
                    ? "Alım fiyat farkı (\(kat.displayName.lowercased(with: Locale(identifier: "tr_TR"))))" : kat.displayName
                satirlar.append(SabitGiderSatiri(id: "stok-\(kat.rawValue)", ad: ad, tutar: t, tur: .stokKaybi))
            }
        }
        for c in r.channels {
            let ucret = min(c.fixedDeduction, c.otherDeduction.amount)
            if ucret != 0 {
                satirlar.append(SabitGiderSatiri(id: "kanal-\(c.channelId)", ad: "\(c.channelName) aylık ücreti",
                                                 tutar: ucret, tur: .kanalUcreti))
            }
        }
        // Henüz satışı olmayan kanalın aylık ücreti (hedefte sayılır)
        let planlanan = planli ? plannedFixedCosts(month: month) : r.toplamSabitGider
        let kanalEk = planlanan - r.toplamSabitGider
        if kanalEk != 0 {
            satirlar.append(SabitGiderSatiri(id: "kanal-plan", ad: "Kanal aylık ücretleri",
                                             tutar: kanalEk, tur: .kanalUcreti))
        }
        // Ay sonunda elle girilen reklam tutarı gider kayıtlarından farklı olabilir; satışa bağlı reklam
        // iadesi (eksi) sabit reklamı da azaltır. Sabit reklamın kayıtlarla açıklanmayan kısmı kendi adıyla gösterilir
        let kanalReklamKaydi = Dictionary(grouping: expenseInstances(from: month, to: month).filter {
            !$0.capitalized && $0.behavior == .sabit && $0.category == .reklam && $0.scope.channelId != nil
        }, by: { $0.scope.channelId! }).mapValues { $0.reduce(0) { $0 + $1.expenseAmount } }
        for c in r.channels {
            let elle = min(c.adsFixed, c.ads.amount) - (kanalReklamKaydi[c.channelId] ?? 0)
            guard elle != 0 else { continue }
            satirlar.append(c.ads.isManual
                ? SabitGiderSatiri(id: "elle-reklam-\(c.channelId)", ad: "\(c.channelName) elle girilen aylık reklam",
                                   tutar: elle, tur: .elleReklam)
                : SabitGiderSatiri(id: "reklam-siniri-\(c.channelId)", ad: "\(c.channelName) reklam iadesi",
                                   tutar: elle, tur: .reklamSiniri))
        }
        satirlar.sort { $0.tutar > $1.tutar }
        var d = SabitGiderDokumu(month: month, satirlar: satirlar)
        // Açıklanamayan fark varsa kalem uydurulmaz, tutarsızlık olarak bildirilir
        d.tutarsizlik = planlanan - d.toplam
        return d
    }
}
