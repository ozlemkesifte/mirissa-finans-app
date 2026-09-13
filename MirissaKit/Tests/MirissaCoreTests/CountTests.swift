import Testing
import Foundation
@testable import MirissaCore

@Suite("Stok sayımı")
struct CountTests {

    /// Sisteme göre 500, gerçek sayım 480 -> fark -20, birim maliyet değişmez
    @Test func sayimFarkiHesaplanir() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.counts.append(StockCount(
            id: "cnt_1", date: "2026-01-25", item: .material(Fx.koliId),
            countedQty: 480, unit: .adet, reason: .kayip
        ))
        let e = Fx.engine(s)
        let b = e.balance(.material(Fx.koliId))
        #expect(b.qty == 480)
        #expect(approx(b.unitCost, Double(tl(10))))   // sayım fiyatı değiştirmez
        #expect(b.value == tl(4800))

        let row = e.ledger.rows(for: .material(Fx.koliId)).first { $0.kind == .sayim }
        #expect(row?.delta == -20)
    }

    /// Sayımdan ÖNCEKİ bir alım düzeltilirse sayım sonrası bakiye DEĞİŞMEZ.
    /// Sayım bir kontrol noktasıdır; farkı değişir ama sonucu değişmez.
    @Test func sayimKontrolNoktasiGibiDavranir() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.counts.append(StockCount(
            id: "cnt_1", date: "2026-01-25", item: .material(Fx.koliId),
            countedQty: 480, unit: .adet
        ))
        #expect(Fx.engine(s).qty(.material(Fx.koliId)) == 480)

        // alım 500 -> 450 olarak düzeltiliyor
        s.purchases[0].qty = 450
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 480)  // sayım sonrası bakiye aynı
        let row = e.ledger.rows(for: .material(Fx.koliId)).first { $0.kind == .sayim }
        #expect(row?.delta == 30)                     // fark ise yeniden hesaplandı
    }

    /// Hiç hareketi olmayan kaleme sayım girilebilir
    @Test func hareketsizKalemeSayim() {
        var s = Fx.base()
        s.counts.append(StockCount(
            id: "cnt_1", date: "2026-05-01", item: .material(Fx.patpatId),
            countedQty: 120, unit: .adet
        ))
        #expect(Fx.engine(s).qty(.material(Fx.patpatId)) == 120)
    }

    /// Sayımdan sonraki satış, sayımın belirlediği miktardan düşer
    @Test func sayimSonrasiSatis() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.counts.append(StockCount(
            id: "cnt_1", date: "2026-01-25", item: .material(Fx.koliId), countedQty: 400, unit: .adet
        ))
        s.addSale("sal_1", "2026-02", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(20000))
        #expect(Fx.engine(s).qty(.material(Fx.koliId)) == 300)
    }

    /// Sayım aynı gün alımdan SONRA uygulanır (gün sonunda gözlenen gerçektir)
    @Test func ayniGunSayimAlimdanSonra() {
        var s = Fx.base()
        s.counts.append(StockCount(
            id: "cnt_1", date: "2026-01-10", item: .material(Fx.koliId), countedQty: 90, unit: .adet
        ))
        s.addPurchase("pur_1", "2026-01-10", .material(Fx.koliId), qty: 500, paid: tl(5000))
        #expect(Fx.engine(s).qty(.material(Fx.koliId)) == 90)
    }
}
