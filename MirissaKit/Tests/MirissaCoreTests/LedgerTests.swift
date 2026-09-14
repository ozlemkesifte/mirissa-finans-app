import Testing
import Foundation
@testable import MirissaCore

func approx(_ a: Double, _ b: Double, _ eps: Double = 0.01) -> Bool { abs(a - b) < eps }

@Suite("Stok ve ortalama maliyet")
struct LedgerTests {

    /// 500 koli 10 TL'den, sonra 500 koli 12 TL'den -> ortalama 11 TL
    @Test func agirlikliOrtalamaMaliyet() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.addPurchase("pur_2", "2026-02-10", .material(Fx.koliId), qty: 500, paid: tl(6000))
        let b = Fx.engine(s).balance(.material(Fx.koliId))
        #expect(b.qty == 1000)
        #expect(approx(b.unitCost, Double(tl(11))))
        #expect(b.value == tl(11000))
    }

    /// Ortalamayı değiştiren alımı SİL -> bütün sonraki değerler kendiliğinden düzelir
    @Test func alimSilinincebutunDegerlerDuzelir() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.addPurchase("pur_2", "2026-02-10", .material(Fx.koliId), qty: 500, paid: tl(6000))
        #expect(approx(Fx.engine(s).unitCost(.material(Fx.koliId)), Double(tl(11))))

        s.purchases.removeAll { $0.id == "pur_2" }
        let after = Fx.engine(s)
        #expect(approx(after.unitCost(.material(Fx.koliId)), Double(tl(10))))
        #expect(after.qty(.material(Fx.koliId)) == 500)
    }

    /// Tüketim miktarı düşürür, birim maliyeti değiştirmez
    @Test func tuketimBirimMaliyetiDegistirmez() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.addPurchase("pur_2", "2026-01-11", .material(Fx.koliId), qty: 500, paid: tl(6000))
        s.adjustments.append(StockAdjustment(
            id: "adj_1", date: "2026-01-20", item: .material(Fx.koliId),
            qty: 200, unit: .adet, reason: .fire
        ))
        let b = Fx.engine(s).balance(.material(Fx.koliId))
        #expect(b.qty == 800)
        #expect(approx(b.unitCost, Double(tl(11))))
        #expect(b.value == tl(8800))
    }

    /// Geçmişe tarihli alım, daha sonraki bir satışın ambalaj maliyetini değiştirir
    @Test func gecmiseTarihliAlimEskiMaliyetiDegistirir() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-05", .material(Fx.koliId), qty: 100, paid: tl(1000))
        s.addSale("sal_1", "2026-02", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 10, gross: tl(5000))
        let before = Fx.engine(s).cost(of: Fx.sampuanId, asOf: "2026-02-28").packaging

        s.addPurchase("pur_0", "2026-01-20", .material(Fx.koliId), qty: 100, paid: tl(3000))
        let after = Fx.engine(s).cost(of: Fx.sampuanId, asOf: "2026-02-28").packaging
        #expect(after > before)
        #expect(after - before == tl(10)) // koli 10 TL -> 20 TL
    }

    /// Alıma ait nakliye maliyeti birim maliyete girer
    @Test func nakliyeBirimMaliyeteGirer() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 100, paid: tl(1000), shipping: tl(200))
        #expect(approx(Fx.engine(s).unitCost(.material(Fx.koliId)), Double(tl(12))))
    }

    /// Stok sıfırlanıp satış devam ederse NaN/sonsuz üretmez
    @Test func sifirStoktaSatisGuvenli() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 10, paid: tl(100))
        s.addSale("sal_1", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 20, gross: tl(2000))
        let b = Fx.engine(s).balance(.material(Fx.koliId))
        #expect(b.qty == -10)
        #expect(b.unitCost.isFinite)
        #expect(!b.unitCost.isNaN)
        #expect(b.value == 0)
        #expect(b.wentNegative)
    }

    /// Eksi stok kırpılmaz: geçmişe alım eklenince kendiliğinden düzelir
    @Test func eksiStokGecmiseAlimlaDuzelir() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-03", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 50, gross: tl(10000))
        #expect(Fx.engine(s).qty(.material(Fx.koliId)) == -50)

        s.addPurchase("pur_1", "2026-03-01", .material(Fx.koliId), qty: 200, paid: tl(2000))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 150)
        #expect(!e.balance(.material(Fx.koliId)).wentNegative)
    }

    /// Sonuç, kayıtların dizideki sırasından bağımsız
    @Test func siralamaBelirli() {
        var a = Fx.base()
        a.addPurchase("pur_a", "2026-01-10", .material(Fx.koliId), qty: 100, paid: tl(1000))
        a.addPurchase("pur_b", "2026-01-10", .material(Fx.koliId), qty: 100, paid: tl(3000))
        var b = Fx.base()
        b.addPurchase("pur_b", "2026-01-10", .material(Fx.koliId), qty: 100, paid: tl(3000))
        b.addPurchase("pur_a", "2026-01-10", .material(Fx.koliId), qty: 100, paid: tl(1000))

        #expect(Fx.engine(a).ledger.rows.map(\.id) == Fx.engine(b).ledger.rows.map(\.id))
        #expect(Fx.engine(a).unitCost(.material(Fx.koliId)) == Fx.engine(b).unitCost(.material(Fx.koliId)))
    }

    /// 10 kg dolgu alındı, sipariş başına 20 gram kullanıldı
    @Test func agirlikBazliStok() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.dolguId), qty: 10, unit: .kg, paid: tl(2000))
        let e0 = Fx.engine(s)
        #expect(e0.qty(.material(Fx.dolguId)) == 10000)              // 10 kg = 10.000 gram
        #expect(approx(e0.unitCost(.material(Fx.dolguId)), 20))      // 0,20 TL/gram = 20 kuruş

        s.addSale("sal_1", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 80, gross: tl(50000))
        #expect(Fx.engine(s).qty(.material(Fx.dolguId)) == 10000 - 1600) // 80 × 20 gram
    }

    /// Kap birimi: 1 paket = 50 adet etiket
    @Test func paketBirimiCevrimi() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.etiketId), qty: 4, unit: .paket, paid: tl(400))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.etiketId)) == 200)
        #expect(approx(e.unitCost(.material(Fx.etiketId)), Double(tl(2))))
    }

    /// Tanımsız kap birimi sessizce 1 sayılmaz
    @Test func tanimsizPaketBirimiSessizceYanlisOlmaz() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 5, unit: .paket, paid: tl(500))
        #expect(Fx.engine(s).qty(.material(Fx.koliId)) == 0)
    }

    /// Eksiye düşmüş stoğa alım yapılınca birim maliyet şişmez
    @Test func eksiStoktanSonraAlimMaliyetiSismez() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-05", .material(Fx.koliId), qty: 100, paid: tl(1000))
        // 150 sipariş -> stok -50'ye düşer
        s.addSale("sal_1", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 150, gross: tl(75_000))
        s.addPurchase("pur_2", "2026-02-05", .material(Fx.koliId), qty: 200, paid: tl(2000))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 150)
        #expect(approx(e.unitCost(.material(Fx.koliId)), Double(tl(10))))
        #expect(e.balance(.material(Fx.koliId)).value == tl(1500))
    }

    /// Silinmiş malzemeye ait hareket uygulamayı çökertmez
    @Test func silinmisMalzemeCokertmez() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material("mat_yok"), qty: 10, paid: tl(100))
        let e = Fx.engine(s)
        #expect(e.ledger.rows.isEmpty)
        #expect(e.totalStockValue == 0)
    }
}
