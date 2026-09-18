import Foundation

/// Başa baş noktasını oluşturan sabit giderler, tek tek.
/// Bir ayın başa baş hedefi yüksek görünüyorsa sebebi buradan görülür:
/// yılda bir ödenen bir gider "her ay" girilmiş olabilir ya da tek seferlik büyük bir
/// harcamanın tamamı o aya yazılmıştır.
public struct SabitGiderSatiri: Identifiable, Hashable, Sendable {
    public enum Tur: String, Sendable {
        case herAy, yillikPay, tekSeferlik, yayilmis, kanalUcreti, stokKaybi, fark
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
        case .fark: return "Elle girilen aylık tutarlardan gelen fark"
        }
    }
}

public struct SabitGiderDokumu: Hashable, Sendable {
    public var month: MonthKey
    public var satirlar: [SabitGiderSatiri]
    public var toplam: Kurus { satirlar.reduce(0) { $0 + $1.tutar } }
    /// Tamamı bu aya yazılmış tek seferlik giderler
    public var tekSeferlikToplam: Kurus {
        satirlar.filter { $0.tur == .tekSeferlik }.reduce(0) { $0 + $1.tutar }
    }
}

public extension Engine {

    /// Ayın sabit giderleri kalem kalem. Toplam her zaman `plannedFixedCosts(month:)` ile aynıdır.
    func sabitGiderDokumu(month: MonthKey) -> SabitGiderDokumu {
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
            case .stokAlimi, .taksit: tur = .tekSeferlik
            }
            let kanal = i.scope.channelId.flatMap { state.channel($0)?.name }
            satirlar.append(SabitGiderSatiri(
                id: i.id, ad: kanal.map { "\(i.name) (\($0))" } ?? i.name,
                tutar: i.expenseAmount, tur: tur, expenseId: e?.id))
        }
        for kat in [ExpenseCategory.stokKaybi, .influencer] {
            let t = stoktanGider(from: month, to: month, category: kat)
            if t != 0 {
                satirlar.append(SabitGiderSatiri(id: "stok-\(kat.rawValue)", ad: kat.displayName,
                                                 tutar: t, tur: .stokKaybi))
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
        let planlanan = plannedFixedCosts(month: month)
        let kanalEk = planlanan - r.toplamSabitGider
        if kanalEk != 0 {
            satirlar.append(SabitGiderSatiri(id: "kanal-plan", ad: "Kanal aylık ücretleri",
                                             tutar: kanalEk, tur: .kanalUcreti))
        }
        // Toplam, başa baş hesabındaki sabit giderle kuruşu kuruşuna aynı olsun
        let fark = planlanan - satirlar.reduce(0) { $0 + $1.tutar }
        if fark != 0 {
            satirlar.append(SabitGiderSatiri(id: "fark", ad: "Diğer / düzeltme", tutar: fark, tur: .fark))
        }
        satirlar.sort { $0.tutar > $1.tutar }
        return SabitGiderDokumu(month: month, satirlar: satirlar)
    }
}
