import Testing
import Foundation
@testable import MirissaCore

@Suite("Vergi karşılığı")
struct TaxTests {
    private func durum() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        // Ocak +10.000, Şubat −4.000 (gider), Mart +6.000, Nisan +8.000
        for (ay, tutar) in [("2026-01", 10_000.0), ("2026-03", 6_000), ("2026-04", 8_000)] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 1, grossSales: tl(tutar)))
        }
        s.expenses.append(Expense(id: "g", date: "2026-02-10", name: "Gider", amount: tl(4_000), category: .diger))
        s.settings.ek.vergiOrani = 25
        return s
    }

    @Test func oranGirilmemisseTahminYok() {
        var s = durum(); s.settings.ek.vergiOrani = nil
        #expect(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-09-15") == nil)
    }

    @Test func yilBasindanKarVeCeyrekGeciciVergi() {
        let e = Engine(durum())
        let mart = e.vergiKarsiligi(month: "2026-03", today: "2026-09-15")!
        #expect(mart.yilBasindanKar == tl(12_000))
        #expect(mart.yilBasindanKarsilik == tl(3_000))
        #expect(mart.ayinPayi == tl(1_500))            // 3.000 − 1.500 (şubat sonu 6.000 × %25)
        #expect(mart.ceyrek == 1)
        #expect(mart.ceyrekGeciciVergi == tl(3_000))
        #expect(mart.ceyrekSonOdeme == "2026-05-17")
        let nisan = e.vergiKarsiligi(month: "2026-04", today: "2026-09-15")!
        #expect(nisan.ceyrek == 2)
        #expect(nisan.ceyrekGeciciVergi == tl(2_000))  // 20.000 × %25 − 3.000
    }

    @Test func zarardaKarsilikEksiyeDusmez() {
        let e = Engine(durum())
        let subat = e.vergiKarsiligi(month: "2026-02", today: "2026-09-15")!
        #expect(subat.ayinPayi == 0)
        #expect(subat.yilBasindanKarsilik == tl(1_500))
    }
}
