import Testing
import Foundation
@testable import MirissaCore

@Suite("Vadeli ve taksitli alımlar")
struct PayablesTests {
    private func durum(plan: OdemePlani?) -> AppState {
        var s = Fx.base()
        var p = StockPurchase(id: "p", date: "2026-09-10", item: .product(Fx.sampuanId), qty: 100,
                              unit: .adet, totalPaid: tl(12_000), vendor: "Fason A",
                              vatRate: .yirmi, vatIncluded: true)
        p.odeme = plan
        s.purchases = [p]
        return s
    }

    @Test func pesinAlimDegismez() {
        let r = Engine(durum(plan: nil)).companyMonth("2026-09")
        #expect(r.nakitCikisi == tl(12_000))
        #expect(r.giderKdv == tl(2_000))
    }

    @Test func taksitlerOdendigiAyinNakdineYazilir() {
        let plan = OdemePlani.esit(toplam: tl(12_000), pesinat: tl(3_000), taksitSayisi: 3,
                                   ilkVade: "2026-10-31")
        #expect(plan.taksitler.map(\.vade) == ["2026-10-31", "2026-11-30", "2026-12-31"])
        #expect(plan.toplam == tl(12_000))
        let e = Engine(durum(plan: plan))
        // Maliyet, stok ve KDV alım ayında; yalnızca para zamanla çıkar
        #expect(e.companyMonth("2026-09").nakitCikisi == tl(3_000))
        #expect(e.companyMonth("2026-09").giderKdv == tl(2_000))
        #expect(e.companyMonth("2026-09").toplamGider == 0)
        #expect(e.companyMonth("2026-10").nakitCikisi == tl(3_000))
        #expect(e.companyMonth("2026-12").nakitCikisi == tl(3_000))
        #expect(e.qty(.product(Fx.sampuanId)) == 100)
        #expect(e.acikBorclar(today: "2026-11-15").count == 3)
        #expect(e.acikBorclar(today: "2026-11-15").first?.gecikti == true)
        #expect(e.acikBorcToplami == tl(9_000))
    }

    @Test @MainActor func taksitOdenenceBorctanDuserGercekGunundeCikar() {
        let plan = OdemePlani.esit(toplam: tl(12_000), pesinat: tl(3_000), taksitSayisi: 3,
                                   ilkVade: "2026-10-31")
        let st = AppStore.inMemory(durum(plan: plan))
        let ilk = plan.taksitler[0]
        st.taksitOdendi(purchaseId: "p", taksitId: ilk.id, tarih: "2026-11-05")
        #expect(st.engine.acikBorclar().count == 2)
        #expect(st.engine.companyMonth("2026-10").nakitCikisi == 0)
        #expect(st.engine.companyMonth("2026-11").nakitCikisi == tl(6_000))
    }

    @Test func planToplamiTutmazsaUyarilir() {
        let s = durum(plan: OdemePlani(pesinat: tl(1_000), taksitler: [Taksit(vade: "2026-10-01", tutar: tl(1_000))]))
        #expect(Integrity.check(s).contains { $0.message.contains("ödeme planı") })
    }

    @Test func ayEkleAySonunaYaslanir() {
        #expect(Dates.addMonthsToDate("2026-01-31", 1) == "2026-02-28")
        #expect(Dates.addMonthsToDate("2028-01-31", 1) == "2028-02-29")
        #expect(Dates.addMonthsToDate("2026-11-15", 2) == "2027-01-15")
    }
}
