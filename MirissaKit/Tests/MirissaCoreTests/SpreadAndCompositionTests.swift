import Testing
import Foundation
@testable import MirissaCore

/// Tek seferlik giderin aylara bölünmesi, "her ay" girilmiş yıllık giderin düzeltilmesi
/// ve başa baş hedefini oluşturan sabit giderlerin dökümü. Rakamlar elle hesaplandı.
@Suite("Aylara bölme ve başa baş dökümü")
@MainActor
struct SpreadAndCompositionTests {
    private func durum() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = true
        // 12.000 TL KDV dahil web sitesi (10.000 net + 2.000 KDV), mart ayında ödendi
        s.expenses.append(Expense(id: "web", date: "2026-03-10", name: "Web sitesi", amount: tl(12_000),
                                  category: .diger, vatRate: .yirmi, vatIncluded: true))
        // Muhasebe her ay 1.000 TL (KDV'siz)
        s.expenses.append(Expense(id: "muh", date: "2026-01-05", name: "Muhasebe", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik))
        return s
    }

    @Test func bolunmezseTamamiOdemeAyinda() {
        let e = Engine(durum())
        #expect(e.companyMonth("2026-03").ortakGider == tl(11_000))
        #expect(e.companyMonth("2026-04").ortakGider == tl(1_000))
    }

    @Test func altiAyaBolununceHerAyaPayYazilirParaOdemeAyinda() {
        var s = durum()
        s.expenses[0].yayilanAy = 6
        let e = Engine(s)
        // 10.000 net / 6 = 1.666,67 (ilk 4 ay) ve 1.666,66 (son 2 ay)
        let paylar = (0..<6).map { e.companyMonth(Dates.addMonths("2026-03", $0)).ortakGider - tl(1_000) }
        #expect(paylar == [166_667, 166_667, 166_667, 166_667, 166_666, 166_666])
        #expect(paylar.reduce(0, +) == tl(10_000))
        #expect(e.companyMonth("2026-09").ortakGider == tl(1_000))
        #expect(e.companyMonth("2026-02").ortakGider == tl(1_000))
        // Para ve KDV mart ayında
        #expect(e.companyMonth("2026-03").nakitCikisi == tl(13_000))
        #expect(e.companyMonth("2026-04").nakitCikisi == tl(1_000))
        #expect(e.companyMonth("2026-03").giderKdv == tl(2_000))
        #expect(e.companyMonth("2026-04").giderKdv == 0)
        // Yıl toplamı bölünse de bölünmese de aynı
        #expect(e.companyTotals(from: "2026-01", to: "2026-12").ortakGider
                == Engine(durum()).companyTotals(from: "2026-01", to: "2026-12").ortakGider)
    }

    @Test func herAyGirilenYillikGiderDuzeltilir() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "ka", date: "2026-01-15", name: "Kolektif ağız", amount: tl(6_000),
                                  category: .sabit, recurrence: .aylik,
                                  overrides: ["2026-02": ExpenseOverride(amount: tl(5_000)),
                                              "2027-01": ExpenseOverride(amount: tl(7_200))]))
        let st = AppStore.inMemory(s)
        #expect(st.engine.companyMonth("2026-05").ortakGider == tl(6_000))
        st.giderYillikYap("ka")
        // Yılda 6.000 → ayda 500; şubat için "her ay" döneminden kalan aya özel tutar atılır
        #expect(st.engine.companyMonth("2026-02").ortakGider == tl(500))
        #expect(st.engine.companyMonth("2026-05").ortakGider == tl(500))
        #expect(st.engine.companyTotals(from: "2026-01", to: "2026-12").ortakGider == tl(6_000))
        // Yıldönümündeki aya özel tutar korunur: 2027'de 7.200 → ayda 600
        #expect(st.engine.companyMonth("2027-03").ortakGider == tl(600))
        #expect(st.state.expenses[0].overrides.keys.sorted() == ["2027-01"])
    }

    @Test func basaBasDokumuToplamiPlanlaAyni() {
        var s = durum()
        s.channels[0].platformFeeMonthly = tl(500)
        s.channels[0].feeVatRate = .yok
        let e = Engine(s)
        let d = e.sabitGiderDokumu(month: "2026-03")
        #expect(d.toplam == e.plannedFixedCosts(month: "2026-03"))
        #expect(d.tekSeferlikToplam == tl(10_000))
        let web = d.satirlar.first { $0.expenseId == "web" }
        #expect(web?.tur == .tekSeferlik)
        #expect(d.satirlar.first { $0.expenseId == "muh" }?.tur == .herAy)
        // Bölünce döküm de bölünmüş payı gösterir
        var s2 = s; s2.expenses[0].yayilanAy = 12
        let d2 = Engine(s2).sabitGiderDokumu(month: "2026-03")
        #expect(d2.satirlar.first { $0.expenseId == "web" }?.tur == .yayilmis)
        #expect(d2.satirlar.first { $0.expenseId == "web" }?.tutar == 83_334)
        #expect(d2.toplam == Engine(s2).plannedFixedCosts(month: "2026-03"))
    }

    @Test func yillikGiderDokumdeOnIkideBir() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "y", date: "2026-01-15", name: "Yazılım", amount: tl(1_200),
                                  category: .sabit, recurrence: .yillik))
        let d = Engine(s).sabitGiderDokumu(month: "2026-06")
        #expect(d.satirlar.count == 1)
        #expect(d.satirlar[0].tur == .yillikPay)
        #expect(d.satirlar[0].tutar == tl(100))
    }

    @Test func kilitliAyaYayilmaEngellenir() {
        var s = durum()
        s.settings.ek.kilitliAylar = ["2026-04"]
        let st = AppStore.inMemory(s)
        st.giderAylaraBol("web", ay: 6)
        // Nisan kilitli: değişiklik uygulanmaz
        #expect(st.state.expenses.first { $0.id == "web" }?.yayilanAy == nil)
    }
}
