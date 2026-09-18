import Testing
import Foundation
@testable import MirissaCore

@Suite("Giderler: ürün başına ve genel ayrımı")
struct ExpenseSplitTests {

    @Test func elleHesaplananOrnek() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: tl(30)); s.products[0].recipe = []
        s.products[1] = Fx.serum(cost: tl(100)); s.products[1].recipe = []
        s.channels[0].commissionPct = 10
        s.channels[0].shippingPerOrder = tl(10)
        s.channels[0].platformFeeMonthly = tl(500)
        s.sales.append(SalesEntry(id: "a", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(1_000)))
        s.sales.append(SalesEntry(id: "b", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: tl(3_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol, orderCount: 20))
        s.expenses.append(Expense(id: "r", date: "2026-09-05", name: "Reklam", amount: tl(400),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol)))
        s.expenses.append(Expense(id: "k", date: "2026-09-01", name: "Kira", amount: tl(8_000),
                                  category: .sabit, recurrence: .aylik))
        let e = Engine(s)
        let g = e.giderAyrimi(from: "2026-09", to: "2026-09")
        func ub(_ ad: String) -> Kurus? { g.urunBasina.first { $0.ad == ad }?.tutar }
        func gn(_ ad: String) -> Kurus? { g.genel.first { $0.ad == ad }?.tutar }
        #expect(ub("Ürün maliyeti") == tl(1_300))
        #expect(ub("Komisyon ve kesintiler") == tl(400))
        #expect(ub("Kargo ve hizmet bedeli") == tl(200))
        #expect(ub("Satışa bağlı reklam") == tl(400))
        #expect(gn("Sabit giderler") == tl(8_000))
        #expect(gn("Kanal aylık ücretleri") == tl(500))
        #expect(g.urunBasinaToplam + g.genelToplam == e.companyMonth("2026-09").toplamGider)
        // Ürün bazında: Şampuan 300 ürün + 100 komisyon + 100 kargo = 500 → adet başı 50 TL
        let a = g.urunler.first { $0.productId == Fx.sampuanId }!
        #expect(a.toplam == tl(500))
        #expect(abs(a.adetBasi! - Double(tl(50))) < 1e-9)
        // Aylık ücret ürüne yazılmaz (genelde)
        #expect(g.urunler.reduce(0) { $0 + $1.kesinti } == tl(400))
    }

    @Test func ikiGrupHerZamanToplamiTutar() {
        for s in [Golden.senaryo(), SeedData.initialState()] {
            let e = Engine(s)
            for (a, b) in [("2026-08", "2026-08"), ("2026-09", "2026-09"), ("2026-01", "2026-09")] {
                let g = e.giderAyrimi(from: a, to: b)
                #expect(g.urunBasinaToplam + g.genelToplam == e.companyTotals(from: a, to: b).toplamGider)
            }
        }
    }
}
