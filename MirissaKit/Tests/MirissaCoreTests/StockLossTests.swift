import Testing
import Foundation
@testable import MirissaCore

/// Satış dışında stoktan çıkan malın maliyeti kâra düşmeli.
/// Alım gider yazılmaz (stoğa girer); kırılan, kaybolan, numune verilen mal
/// başka hiçbir yerde gider olarak görünmez.
@Suite("Fire, kayıp, numune ve sayım farkı")
struct StockLossTests {

    /// 100 koli 1.000 TL (10 TL), 100 şampuan 10.000 TL (100 TL). KDV yok.
    private func durum() -> AppState {
        var s = Fx.base()
        s.addPurchase("k", "2026-09-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.addPurchase("u", "2026-09-01", .product(Fx.sampuanId), qty: 100, paid: tl(10_000))
        return s
    }

    private func duzelt(_ s: inout AppState, _ id: Id, _ item: ItemRef, _ adet: Double,
                        _ neden: AdjustReason, artis: Bool = false, tarih: DateKey = "2026-09-10") {
        s.adjustments.append(StockAdjustment(id: id, date: tarih, item: item, qty: adet,
                                             unit: .adet, isIncrease: artis, reason: neden))
    }

    @Test func kirikKoliKaraFireOlarakDuser() {
        var s = durum()
        duzelt(&s, "a", .material(Fx.koliId), 5, .kirik)
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.expenseBreakdown[.stokKaybi] == tl(50))
        #expect(r.gercekKar == -tl(50))
        // Nakit çıkışı değildir: parası alımda ödendi
        #expect(r.nakitCikisi == Engine(durum()).companyMonth("2026-09").nakitCikisi)
    }

    @Test func numuneVeInfluencerPazarlamaGideri() {
        var s = durum()
        duzelt(&s, "n", .product(Fx.sampuanId), 1, .numune)
        duzelt(&s, "i", .product(Fx.sampuanId), 2, .influencer)
        duzelt(&s, "p", .material(Fx.koliId), 3, .pr)
        let r = Engine(s).companyMonth("2026-09")
        // 3 şampuan × 100 + 3 koli × 10
        #expect(r.expenseBreakdown[.influencer] == tl(330))
        #expect(r.expenseBreakdown[.stokKaybi] == nil)
    }

    @Test func sayimEksigiGiderFazlasiGiderAzaltir() {
        var s = durum()
        s.counts.append(StockCount(id: "c1", date: "2026-09-15", item: .material(Fx.koliId),
                                   countedQty: 97, unit: .adet))
        #expect(Engine(s).companyMonth("2026-09").expenseBreakdown[.stokKaybi] == tl(30))

        s.counts.append(StockCount(id: "c2", date: "2026-09-20", item: .material(Fx.koliId),
                                   countedQty: 99, unit: .adet))
        // 3 eksik − 2 fazla = 1 koli
        #expect(Engine(s).companyMonth("2026-09").expenseBreakdown[.stokKaybi] == tl(10))
    }

    @Test func hasarliIadeninMaliyetiFireOlur() {
        var s = durum()
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 3, grossSales: tl(3_000),
                                  returnsAmount: tl(1_000), returnsQty: 1, returnsRestock: false))
        let r = Engine(s).companyMonth("2026-09")
        // Satılan 2 şampuanın maliyeti ürün maliyetinde, bozuk dönen 1 şampuan fire
        #expect(r.expenseBreakdown[.urunUretimi] == tl(200))
        #expect(r.expenseBreakdown[.stokKaybi] == tl(100))
    }

    @Test func eksiStoktaYapilanSayimKazancYazmaz() {
        var s = Fx.base()
        // Açılış stoğu girilmemiş: satış stoğu eksiye düşürür, sonra alım ve sayım
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        s.counts.append(StockCount(id: "c", date: "2026-09-05", item: .product(Fx.sampuanId),
                                   countedQty: 40, unit: .adet))
        s.addPurchase("u", "2026-08-01", .product(Fx.sampuanId), qty: 0.0001, paid: tl(0.01))
        let e = Engine(s)
        #expect(e.companyMonth("2026-09").expenseBreakdown[.stokKaybi] == nil)
    }

    @Test func gecmisAyinFiresiSonrakiAlimlaDegismez() {
        var s = durum()
        duzelt(&s, "a", .material(Fx.koliId), 5, .kirik)
        let once = Engine(s).companyMonth("2026-09").expenseBreakdown[.stokKaybi]
        s.addPurchase("k2", "2026-10-01", .material(Fx.koliId), qty: 100, paid: tl(3_000))
        #expect(Engine(s).companyMonth("2026-09").expenseBreakdown[.stokKaybi] == once)
    }

    @Test func toplamGiderDagilimiTutar() {
        var s = durum()
        duzelt(&s, "a", .material(Fx.koliId), 5, .kirik)
        duzelt(&s, "n", .product(Fx.sampuanId), 1, .numune)
        duzelt(&s, "b", .material(Fx.koliId), 2, .diger, artis: true)
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.expenseBreakdown.values.reduce(0, +) == r.toplamGider)
        #expect(r.gercekKar == r.gercekCiro - r.toplamGider)
        #expect(r.expenseBreakdown[.stokKaybi] == tl(30))   // 5 kırık − 2 bulunan
    }

    // MARK: Ambalaj uyarıları

    @Test func ambalajReceteYoksaUyarilir() {
        var s = Fx.base()
        s.products[1].recipe = []
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 1, grossSales: tl(500)))
        let sorunlar = Integrity.check(s)
        #expect(sorunlar.contains { $0.message.contains("Serum satılıyor ama ambalaj reçetesi yok") })
    }

    @Test func maliyetiBilinmeyenAmbalajMalzemesiUyarilir() {
        var s = Fx.base()
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 1, grossSales: tl(500)))
        let sorunlar = Integrity.check(s)
        #expect(sorunlar.contains { $0.message.contains("Kargo kolisi Serum paketlemesinde kullanılıyor ama maliyeti bilinmiyor") })
    }
}

/// Ürün maliyeti: girilen kalemler mi, gerçek alım ortalaması mı
@Suite("Ürün maliyetinin kaynağı")
struct ProductCostSourceTests {

    @Test func maliyetGirilmemisseAlimOrtalamasiKullanilir() {
        var s = Fx.base()   // Şampuan maliyeti girilmemiş
        s.addPurchase("u1", "2026-09-01", .product(Fx.sampuanId), qty: 100, paid: tl(10_000))
        s.addPurchase("u2", "2026-09-05", .product(Fx.sampuanId), qty: 100, paid: tl(14_000))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(5_000)))
        let e = Engine(s)
        let b = e.cost(of: Fx.sampuanId, asOf: "2026-09-30")
        // (10.000 + 14.000) ÷ 200 = 120 TL
        #expect(b.intrinsic == tl(120))
        #expect(b.ownFromPurchases)
        #expect(e.companyMonth("2026-09").expenseBreakdown[.urunUretimi] == tl(1_200))
        // Maliyet biliniyor: "maliyeti girilmemiş" diye sorulmaz
        #expect(!e.missingForTarget(month: "2026-10", today: "2026-10-01")
            .contains { $0.kind == .urunMaliyeti && $0.productId == Fx.sampuanId })
    }

    @Test func girilenMaliyetOnceliklidirFarkliysaUyarilir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.addPurchase("u1", "2026-09-01", .product(Fx.sampuanId), qty: 100, paid: tl(15_000))
        let e = Engine(s)
        #expect(e.cost(of: Fx.sampuanId, asOf: "2026-09-30").intrinsic == tl(100))
        #expect(!e.cost(of: Fx.sampuanId, asOf: "2026-09-30").ownFromPurchases)
        #expect(Integrity.check(s).contains {
            $0.message.contains("Şampuan maliyeti 100 TL girilmiş ama alımlardan ortalama 150 TL çıkıyor")
        })
    }

    @Test func girilenMaliyetAlimlaUyusuyorsaUyariYok() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.addPurchase("u1", "2026-09-01", .product(Fx.sampuanId), qty: 100, paid: tl(10_100))
        #expect(!Integrity.check(s).contains { $0.area == "Maliyet" })
    }
}
