import Testing
import Foundation
@testable import MirissaCore

/// "Tek seferlik mi, düzenli mi?" ayrımının aylık ve yıllık raporlara
/// doğru yansıdığını ay ay gösterir.
@Suite("Gider tekrarı ve raporlama")
struct GiderRaporTests {

    private func kurulum() -> AppState {
        var s = SeedData.initialState()
        s.expenses = [
            // Her ay — Ocak'tan itibaren, durdurulmamış
            Expense(id: "e_muh", date: "2026-01-05", name: "Muhasebeci",
                    amount: tl(5000), category: .sabit, recurrence: .aylik),

            // Her ay — ama Haziran sonunda durduruldu
            Expense(id: "e_ajans", date: "2026-01-05", name: "Ajans",
                    amount: tl(20_000), category: .sabit, recurrence: .aylik,
                    endMonth: "2026-06"),

            // Her ay — Mart'ta başladı, Mayıs'ta tutarı farklı, Temmuz atlandı
            {
                var e = Expense(id: "e_klaviyo", date: "2026-03-10", name: "Klaviyo",
                                amount: tl(2000), category: .sabit, recurrence: .aylik)
                e.overrides["2026-05"] = ExpenseOverride(amount: tl(3500))
                e.overrides["2026-07"] = ExpenseOverride(skipped: true)
                return e
            }(),

            // Her yıl — Nisan'da
            Expense(id: "e_alanadi", date: "2026-04-20", name: "Alan adı",
                    amount: tl(1200), category: .diger, recurrence: .yillik),

            // Tek seferlik — sadece Eylül
            Expense(id: "e_inf", date: "2026-09-15", name: "Influencer iş birliği",
                    amount: tl(8000), category: .influencer, recurrence: .tek),

            // Tek seferlik — sadece Kasım
            Expense(id: "e_fuar", date: "2026-11-03", name: "Fuar standı",
                    amount: tl(15_000), category: .diger, recurrence: .tek),
        ]
        return s
    }

    /// Tek seferlik gider SADECE girildiği ayda görünür
    @Test func tekSeferlikSadeceKendiAyinda() {
        let e = Engine(kurulum())
        for ay in 1...12 {
            let m = Dates.monthKey(2026, ay)
            let varMi = e.expenseInstances(month: m).contains { $0.name == "Influencer iş birliği" }
            #expect(varMi == (ay == 9))
        }
    }

    /// Her ay gideri her ayda görünür ve tutarı aynıdır
    @Test func aylikGiderHerAyda() {
        let e = Engine(kurulum())
        for ay in 1...12 {
            let m = Dates.monthKey(2026, ay)
            let satir = e.expenseInstances(month: m).first { $0.name == "Muhasebeci" }
            #expect(satir != nil)
            #expect(satir?.amount == tl(5000))
            #expect(satir?.sourceKind == .duzenli)
        }
    }

    /// Durdurulan düzenli gider bitiş ayına kadar sayılır, sonrasında hiç
    @Test func durdurulanGiderBitisAyinaKadar() {
        let e = Engine(kurulum())
        for ay in 1...12 {
            let m = Dates.monthKey(2026, ay)
            let varMi = e.expenseInstances(month: m).contains { $0.name == "Ajans" }
            #expect(varMi == (ay <= 6))
        }
    }

    /// Aya özel tutar sadece o ayı, atlama sadece o ayı etkiler
    @Test func ayaOzelTutarVeAtlama() {
        let e = Engine(kurulum())
        func klaviyo(_ ay: Int) -> Kurus? {
            e.expenseInstances(month: Dates.monthKey(2026, ay)).first { $0.name == "Klaviyo" }?.amount
        }
        #expect(klaviyo(2) == nil)          // henüz başlamadı
        #expect(klaviyo(3) == tl(2000))
        #expect(klaviyo(4) == tl(2000))
        #expect(klaviyo(5) == tl(3500))     // aya özel
        #expect(klaviyo(6) == tl(2000))     // diğer aylar etkilenmedi
        #expect(klaviyo(7) == nil)          // atlandı
        #expect(klaviyo(8) == tl(2000))     // devam ediyor
    }

    /// Yıllık gider sadece yıl dönümü ayında
    @Test func yillikGiderSadeceDonumAyinda() {
        let e = Engine(kurulum())
        for ay in 1...12 {
            let m = Dates.monthKey(2026, ay)
            let varMi = e.expenseInstances(month: m).contains { $0.name == "Alan adı" }
            #expect(varMi == (ay == 4))
        }
        // Ertesi yıl yine Nisan'da
        #expect(e.expenseInstances(month: "2027-04").contains { $0.name == "Alan adı" })
        #expect(!e.expenseInstances(month: "2027-05").contains { $0.name == "Alan adı" })
    }

    /// Yıllık rapor = 12 ayın toplamı, elle hesapla da tutuyor
    @Test func yillikToplamElleHesaplaTutuyor() {
        let e = Engine(kurulum())
        let yil = e.year(2026)

        // Elle: Muhasebeci 12×5.000 = 60.000
        //       Ajans 6×20.000 = 120.000  (Haziran'da durduruldu)
        //       Klaviyo: Mart,Nis,Haz,Ağu,Eyl,Eki,Kas,Ara = 8×2.000 + Mayıs 3.500 = 19.500
        //       Alan adı 1.200 · Influencer 8.000 · Fuar 15.000
        let elle = tl(60_000) + tl(120_000) + tl(19_500) + tl(1200) + tl(8000) + tl(15_000)
        #expect(yil.toplamGider == elle)
        #expect(yil.toplamGider == yil.months.reduce(0) { $0 + $1.toplamGider })
    }

    /// Ay ay döküm — gözle görülebilsin
    @Test func ayAyDokum() {
        let e = Engine(kurulum())
        print("\n=========== 2026 GİDER DÖKÜMÜ ===========")
        print("  Ay        Toplam        Kalemler")
        var yilToplam: Kurus = 0
        for ay in 1...12 {
            let m = Dates.monthKey(2026, ay)
            let liste = e.expenseInstances(month: m).filter { !$0.capitalized }
            let toplam = liste.reduce(0) { $0 + $1.amount }
            yilToplam += toplam
            let adlar = liste.map { i -> String in
                let tur = i.sourceKind == .duzenli ? "↻" : "•"
                return "\(tur)\(i.name)"
            }.sorted().joined(separator: "  ")
            let ayAdi = Dates.monthNamesShortTR[ay - 1].padding(toLength: 5, withPad: " ", startingAt: 0)
            let tutar = Money.format(toplam).padding(toLength: 13, withPad: " ", startingAt: 0)
            print("  \(ayAdi)  \(tutar) \(adlar)")
        }
        print("  ----------------------------------------")
        print("  YIL   \(Money.format(yilToplam))")
        print("  (↻ düzenli · • tek seferlik)")
        print("=========================================\n")
        #expect(yilToplam == e.year(2026).toplamGider)
    }
}
