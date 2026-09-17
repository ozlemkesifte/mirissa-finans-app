import Testing
import Foundation
@testable import MirissaCore

/// PARA KORUNUMU
///
/// Stoğa giren her kuruş ya satıldıkça (ürün + ambalaj maliyeti), ya fire / numune /
/// sayım farkı olarak kâra düşmeli, ya da dönem sonunda stokta değer olarak durmalı.
///   alımlar (KDV hariç) = kâra düşen stok maliyetleri + dönem sonu stok değeri
/// Hangi hesap katmanında olursa olsun kaybolan ya da iki kez sayılan para bu eşitliği bozar.
@Suite("Para korunumu: alınan mal ya gider olur ya stokta durur")
struct MoneyConservationTests {

    struct Rastgele: RandomNumberGenerator {
        var d: UInt64
        init(_ t: UInt64) { d = t &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }
        mutating func next() -> UInt64 { d ^= d << 13; d ^= d >> 7; d ^= d << 17; return d }
    }

    private func senaryo(_ g: inout Rastgele) -> AppState {
        var s = Fx.base()           // maliyet kalemi yok: ürün maliyeti alımlardan gelir
        let aylar = ["2026-07", "2026-08", "2026-09"]
        // Bol stok: eksiye düşmesin (eksi stok ayrı bir kuraldır)
        for (i, ay) in aylar.enumerated() {
            let gun = "\(ay)-0\(1 + i)"
            s.addPurchase("pk\(i)", gun, .material(Fx.koliId), qty: 2_000,
                          paid: Kurus(Int.random(in: 500_000...3_000_000, using: &g)))
            s.addPurchase("pp\(i)", gun, .material(Fx.patpatId), qty: 3_000,
                          paid: Kurus(Int.random(in: 100_000...900_000, using: &g)))
            s.addPurchase("pe\(i)", gun, .material(Fx.etiketId), qty: 5_000,
                          paid: Kurus(Int.random(in: 50_000...400_000, using: &g)))
            s.addPurchase("pd\(i)", gun, .material(Fx.dolguId), qty: 40, unit: .kg,
                          paid: Kurus(Int.random(in: 200_000...900_000, using: &g)))
            s.addPurchase("pb\(i)", gun, .material(Fx.sampuanKutuId), qty: 2_000,
                          paid: Kurus(Int.random(in: 300_000...1_500_000, using: &g)))
            s.addPurchase("pt\(i)", gun, .material(Fx.setKutuId), qty: 1_000,
                          paid: Kurus(Int.random(in: 300_000...1_500_000, using: &g)))
            s.addPurchase("ps\(i)", gun, .product(Fx.sampuanId), qty: 1_500,
                          paid: Kurus(Int.random(in: 9_000_000...30_000_000, using: &g)))
            s.addPurchase("pr\(i)", gun, .product(Fx.serumId), qty: 1_500,
                          paid: Kurus(Int.random(in: 9_000_000...30_000_000, using: &g)))
            for (j, urun) in [Fx.sampuanId, Fx.serumId, Fx.setId].enumerated() {
                let adet = Double(Int.random(in: 0...200, using: &g))
                let iade = Double(Int.random(in: 0...Int(adet / 5), using: &g))
                s.sales.append(SalesEntry(
                    id: "s\(i)\(j)", month: ay,
                    channelId: j == 2 ? ChannelIds.shopify : ChannelIds.trendyol,
                    productId: urun, qty: adet, grossSales: tl(adet * 500),
                    returnsAmount: tl(iade * 500), returnsQty: iade,
                    returnsRestock: Bool.random(using: &g)))
            }
            let nedenler = AdjustReason.userSelectable
            for k in 0..<4 {
                let item: ItemRef = Bool.random(using: &g) ? .product(Fx.sampuanId) : .material(Fx.koliId)
                s.adjustments.append(StockAdjustment(
                    id: "a\(i)\(k)", date: "\(ay)-2\(k)", item: item,
                    qty: Double(Int.random(in: 1...30, using: &g)), unit: .adet,
                    isIncrease: Int.random(in: 0..<5, using: &g) == 0,
                    reason: nedenler[Int.random(in: 0..<nedenler.count, using: &g)]))
            }
            if Bool.random(using: &g) {
                let e = Engine(s)
                let sistem = e.qty(.material(Fx.koliId))
                s.counts.append(StockCount(id: "c\(i)", date: "\(ay)-28", item: .material(Fx.koliId),
                                           countedQty: max(sistem + Double(Int.random(in: -40...20, using: &g)), 0),
                                           unit: .adet))
            }
        }
        return s
    }

    @Test(arguments: 0..<60)
    func alinanParaKaybolmaz(tohum: Int) {
        var g = Rastgele(UInt64(tohum + 1))
        let s = senaryo(&g)
        let e = Engine(s)
        let aylar = ["2026-07", "2026-08", "2026-09"]

        let alimlar = aylar.reduce(0) { $0 + e.companyMonth($1).stokAlimi }
        var kariDusen = 0
        for ay in aylar {
            let r = e.companyMonth(ay)
            kariDusen += r.channels.reduce(0) { $0 + $1.productCost + $1.packagingCost }
            kariDusen += e.stoktanGider(from: ay, to: ay, category: .stokKaybi)
            kariDusen += e.stoktanGider(from: ay, to: ay, category: .influencer)
        }
        let stokDegeri = e.totalStockValue
        #expect(!s.materials.contains { e.qty(.material($0.id)) < 0 })
        #expect(!s.products.filter(\.tracksOwnStock).contains { e.qty(.product($0.id)) < 0 })

        // Yuvarlama payı: birim maliyet kuruşa yuvarlanır (ürün ve ambalaj ayrı ayrı),
        // satılan her adette en fazla yarımşar kuruş. Mantık hatası bundan çok büyük çıkar:
        // tek bir kolinin maliyeti bile ~250+ kuruştur.
        let adet = s.sales.reduce(0.0) { $0 + $1.qty }
        let pay = 50 + Int(adet.rounded(.up))
        #expect(abs(alimlar - (kariDusen + stokDegeri)) <= pay,
                "alım \(alimlar) ≠ gider \(kariDusen) + stok \(stokDegeri), fark \(alimlar - kariDusen - stokDegeri)")
    }
}
