import Testing
import Foundation
@testable import MirissaCore

@Suite("Ürün × kanal kârlılığı")
struct ProductProfitTests {

    @Test func elleHesaplananOrnek() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: tl(30)); s.products[0].recipe = []
        s.products[1] = Fx.serum(cost: tl(100)); s.products[1].recipe = []
        s.channels[0].commissionPct = 10
        s.channels[0].shippingPerOrder = tl(10)
        s.sales.append(SalesEntry(id: "a", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(1_000)))
        s.sales.append(SalesEntry(id: "b", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: tl(3_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                            orderCount: 20))
        s.expenses.append(Expense(id: "r", date: "2026-09-05", name: "Reklam", amount: tl(400),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol)))
        let e = Engine(s)
        let l = e.urunKanalKarliligi(month: "2026-09")
        let a = l.first { $0.productId == Fx.sampuanId }!
        let b = l.first { $0.productId == Fx.serumId }!
        // Şampuan: 1.000 − 100 komisyon − 100 kargo − 300 ürün − 100 reklam = 400
        #expect(a.kesinti == tl(100)); #expect(a.kargo == tl(100)); #expect(a.reklam == tl(100))
        #expect(a.kalan == tl(400))
        // Serum: 3.000 − 300 − 100 − 1.000 − 300 = 1.300
        #expect(b.kalan == tl(1_300))
        #expect(a.kalan + b.kalan == e.companyMonth("2026-09").channels
            .first { $0.channelId == ChannelIds.trendyol }!.kanaldaKalan)
    }

    @Test func urunlerinToplamiKanalinKalaniniKurusuKurusunaTutar() {
        for s in [Golden.senaryo(), SeedData.initialState()] {
            let e = Engine(s)
            for ay in Set(s.sales.map(\.month)) {
                let r = e.companyMonth(ay)
                let l = e.urunKanalKarliligi(month: ay)
                for c in r.channels {
                    let urunler = l.filter { $0.channelId == c.channelId }
                    guard !urunler.isEmpty else { continue }
                    #expect(urunler.reduce(0) { $0 + $1.kalan } == c.kanaldaKalan)
                    #expect(urunler.reduce(0) { $0 + $1.netSatis } == c.netSales)
                }
            }
        }
    }

    @Test func dagitimToplamiBozmaz() {
        for t in [0, 1, 7, 100, 12_345, -99] as [Kurus] {
            for a in [[1.0], [1, 1, 1], [0.3, 0.3, 0.4], [5, 0, 2], [0, 0]] {
                #expect(Engine.dagit(t, a).reduce(0, +) == t)
            }
        }
    }
}

@Suite("Ürün × kanal kârlılığı: rastgele senaryolar")
struct ProductProfitPropertyTests {
    struct R: RandomNumberGenerator {
        var d: UInt64
        init(_ t: UInt64) { d = t &* 0x9E3779B97F4A7C15 &+ 1 }
        mutating func next() -> UInt64 { d ^= d << 13; d ^= d >> 7; d ^= d << 17; return d }
    }

    @Test(arguments: 0..<80)
    func toplamHepTutar(tohum: Int) {
        var g = R(UInt64(tohum + 1))
        var s = Golden.senaryo()
        let oranlar: [VatRate?] = [nil, .yok, .on, .yirmi]
        for i in s.channels.indices {
            s.channels[i].commissionPct = Double(Int.random(in: 0...25, using: &g))
            s.channels[i].shippingPerOrder = Kurus(Int.random(in: 0...9_000, using: &g))
            s.channels[i].serviceFeePerOrder = Kurus(Int.random(in: 0...2_000, using: &g))
            s.channels[i].platformFeeMonthly = Kurus(Int.random(in: 0...50_000, using: &g))
            s.channels[i].otherDeductionPct = Double(Int.random(in: 0...4, using: &g))
            s.channels[i].feeVatRate = Bool.random(using: &g) ? .yirmi : nil
        }
        for i in s.sales.indices {
            let a = Double(Int.random(in: 1...150, using: &g))
            s.sales[i].qty = a
            s.sales[i].returnsQty = Double(Int.random(in: 0...Int(a / 4), using: &g))
            s.sales[i].grossSales = Kurus(Int.random(in: 10_000...5_000_000, using: &g))
            s.sales[i].discount = Kurus(Int.random(in: 0...(s.sales[i].grossSales / 5), using: &g))
            s.sales[i].vatRate = oranlar[Int.random(in: 0..<oranlar.count, using: &g)]
        }
        if Bool.random(using: &g), let k = s.materials.firstIndex(where: { $0.name.lowercased().contains("koli") }) {
            s.materials[k].perOrder = true
        }
        let e = Engine(s)
        for ay in Set(s.sales.map(\.month)) {
            let g = e.giderAyrimi(from: ay, to: ay)
            #expect(g.urunBasinaToplam + g.genelToplam == e.companyMonth(ay).toplamGider)
            let l = e.urunKanalKarliligi(month: ay)
            for c in e.companyMonth(ay).channels {
                let u = l.filter { $0.channelId == c.channelId }
                guard !u.isEmpty else { continue }
                #expect(u.reduce(0) { $0 + $1.kalan } == c.kanaldaKalan)
            }
        }
    }
}
