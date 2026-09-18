import Testing
import Foundation
@testable import MirissaCore

@Suite("Hatırlatmalar")
struct ReminderTests {
    @Test func haftaninGunu() {
        #expect(Dates.weekday(of: "2026-09-20") == 1)   // pazar
        #expect(Dates.weekday(of: "2026-09-18") == 6)   // cuma
        #expect(Dates.weekday(of: "1970-01-01") == 5)   // perşembe
    }

    @Test func aylikVeVadeliHatirlatmalar() {
        var s = Fx.base()
        var p = StockPurchase(id: "p", date: "2026-09-10", item: .product(Fx.sampuanId), qty: 10,
                              unit: .adet, totalPaid: tl(1_000))
        p.odeme = OdemePlani(pesinat: 0, taksitler: [Taksit(id: "t1", vade: "2026-10-15", tutar: tl(1_000))])
        s.purchases = [p]
        let l = Engine(s).hatirlatmalar(bugun: "2026-09-18", gunSayisi: 45)
        #expect(l.contains { $0.id == "satis-2026-10" && $0.gun == "2026-10-02" })
        #expect(l.contains { $0.id == "kdv-2026-09" && $0.gun == "2026-09-24" })
        #expect(l.contains { $0.id == "maliyet-2026-10" && $0.gun == "2026-10-05" })
        #expect(l.contains { $0.id == "taksit-p#t1" && $0.gun == "2026-10-13" })
        #expect(l.contains { $0.id == "yedek-2026-09-20" })
        // Hepsi gelecekte ve sıralı
        #expect(l.allSatisfy { $0.gun > "2026-09-18" })
        #expect(l.map(\.gun) == l.map(\.gun).sorted())
    }
}
