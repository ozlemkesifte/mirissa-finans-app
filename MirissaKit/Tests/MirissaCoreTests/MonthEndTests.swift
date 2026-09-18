import Testing
import Foundation
@testable import MirissaCore

@Suite("Ay sonu kontrol listesi")
struct MonthEndTests {
    private func durum() -> AppState {
        var s = Fx.base()
        for ay in ["2026-07", "2026-08"] {
            s.sales.append(SalesEntry(id: "t\(ay)", month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 5, grossSales: tl(500)))
        }
        s.sales.append(SalesEntry(id: "s07", month: "2026-07", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 5, grossSales: tl(500)))
        s.expenses.append(Expense(id: "k", date: "2026-01-01", name: "Kira", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik))
        return s
    }

    private func madde(_ l: [AySonuMaddesi], _ e: AySonuMaddesi.Eylem) -> AySonuMaddesi? {
        l.first { $0.eylem == e }
    }

    @Test func eksiklerKendiligindenGorunur() {
        let l = Engine(durum()).aySonuListesi(month: "2026-08", today: "2026-09-05")
        // Temmuzda Shopify satışı vardı, ağustosta yok
        #expect(madde(l, .satis)?.tamam == false)
        #expect(madde(l, .satis)?.aciklama.contains("Shopify") == true)
        #expect(madde(l, .siparis)?.tamam == false)
        #expect(madde(l, .hakedis)?.tamam == false)      // Trendyol pazaryeri
        #expect(madde(l, .sayim)?.tamam == false)
        #expect(madde(l, .gider)?.tamam == false)
        #expect(madde(l, .yedek)?.tamam == false)
    }

    @Test func girilenVeriyleTamamlanir() {
        var s = durum()
        s.sales.append(SalesEntry(id: "s08", month: "2026-08", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 5, grossSales: tl(500)))
        s.channelMonths = [
            ChannelMonth(id: "a", month: "2026-08", channelId: ChannelIds.trendyol, orderCount: 5, payoutActual: tl(400)),
            ChannelMonth(id: "b", month: "2026-08", channelId: ChannelIds.shopify, orderCount: 5),
        ]
        s.counts.append(StockCount(id: "c", date: "2026-08-31", item: .material(Fx.koliId), countedQty: 0, unit: .adet))
        s.settings.ek.aySonuIsaretleri = ["2026-08": ["gider"]]
        s.settings.ek.kilitliAylar = ["2026-08"]
        s.settings.ek.sonYedekPaylasim = "2026-09-02"
        let l = Engine(s).aySonuListesi(month: "2026-08", today: "2026-09-05")
        #expect(l.allSatisfy { $0.tamam })
    }

    @Test func satisGirilmeyenAyIsaretlenir() {
        let e = Engine(durum())
        #expect(e.satisGirilmedi(month: "2026-06", today: "2026-09-05"))     // kira var, satış yok
        #expect(!e.satisGirilmedi(month: "2026-08", today: "2026-09-05"))
        #expect(!e.satisGirilmedi(month: "2026-11", today: "2026-09-05"))    // gelecek ay
    }
}
