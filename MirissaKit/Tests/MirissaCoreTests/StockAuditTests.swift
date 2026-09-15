import Testing
import Foundation
@testable import MirissaCore

/// Stok motorunun matematiksel kimliği ve varsayılan değer denetimi.
@Suite("Stok kimliği ve varsayılanlar")
struct StockAuditTests {

    private typealias G = Golden.G

    /// Başlangıç + alım + iade − satış − her türlü düzeltme = mevcut stok
    @Test func stokKimligiTumDuzeltmeTurleriyleTutar() {
        var s = Golden.senaryo()
        // Her düzeltme sebebi ayrı ayrı uygulanır
        let sebepler: [AdjustReason] = [.kirik, .hasarli, .fire, .kayip,
                                        .numune, .influencer, .pr, .icKullanim, .diger]
        for (i, sebep) in sebepler.enumerated() {
            s.adjustments.append(StockAdjustment(
                id: "adj_\(i)", date: "2026-09-\(String(format: "%02d", 10 + i))",
                item: .material(G.koli), qty: 3, unit: .adet,
                isIncrease: false, reason: sebep))
        }
        let e = Engine(s)
        // 1330 − 9 düzeltme × 3
        #expect(e.qty(.material(G.koli)) == 1330 - 27)

        // Bağımsız hesap
        var beklenen = 1000.0                      // açılış
        beklenen += 500                            // alım
        beklenen -= 100 + 50 + 20                  // satış tüketimi
        beklenen -= Double(sebepler.count) * 3     // düzeltmeler
        #expect(e.qty(.material(G.koli)) == beklenen)
    }

    /// Artı yönlü düzeltme de doğru işler
    @Test func artiDuzeltmeStoguArtirir() {
        var s = Golden.senaryo()
        s.adjustments.append(StockAdjustment(id: "adj_p", date: "2026-09-12",
                                             item: .material(G.koli), qty: 40,
                                             unit: .adet, isIncrease: true, reason: .diger))
        #expect(Engine(s).qty(.material(G.koli)) == 1370)
    }

    /// Satılamaz iade: stoğa girer ve hemen fire olur — net etki sıfır, izi görünür
    @Test func hasarliIadeNetEtkiBirakmazAmaIzBirakir() {
        var s = Golden.senaryo()
        let i = s.sales.firstIndex { $0.id == "sal_g1" }!
        s.sales[i].returnsRestock = false
        let e = Engine(s)
        // 10 adet iade stoğa dönmez: 320 − 10
        #expect(e.qty(.product(G.sampuan)) == 310)
        let hareketler = e.history(.product(G.sampuan))
        #expect(hareketler.contains { $0.kind == .iade })
        #expect(hareketler.contains { $0.kind == .duzeltme })
    }

    /// Sayım, ayın son sözüdür: ay ortasında girilse bile ay sonu satışından sonra uygulanır
    @Test func sayimAyinSonSozudur() {
        var s = Golden.senaryo()
        s.counts.append(StockCount(id: "cnt_1", date: "2026-09-10",
                                   item: .material(G.koli), countedQty: 1200, unit: .adet))
        // Ay ortasında sayılmış olsa da sonuç sayılan değerdir
        #expect(Engine(s).qty(.material(G.koli)) == 1200)
    }

    /// Sayım birim maliyeti değiştirmez
    @Test func sayimBirimMaliyetiDegistirmez() {
        var s = Golden.senaryo()
        s.counts.append(StockCount(id: "cnt_1", date: "2026-09-25",
                                   item: .material(G.koli), countedQty: 50, unit: .adet))
        #expect(Engine(s).unitCost(.material(G.koli)) == Double(tl(10)))
    }

    // MARK: Ağırlıklı ortalama ve birim dönüşümü

    @Test func agirlikliOrtalamaFarkliFiyatlardaDogru() {
        var s = Golden.senaryo()
        // 500 koli × 12 TL eklenirse: (1000×10 + 500×10 + 500×12) / 2000
        s.purchases.append(StockPurchase(id: "pur_2", date: "2026-09-06",
                                         item: .material(G.koli), qty: 500, unit: .adet,
                                         totalPaid: tl(6_000)))
        let e = Engine(s)
        // Alımlar satıştan önce (ay sonu) işlenir: 20.000 / 2000 = 10,5
        #expect(abs(e.unitCost(.material(G.koli)) - Double(tl(10.5))) < 1)
    }

    @Test func kiloGramCevrimiFinansiBozmaz() {
        var s = Golden.senaryo()
        s.materials.append(StockMaterial(id: "mat_dolgu", name: "Dolgu", baseUnit: .gram))
        s.purchases.append(StockPurchase(id: "pur_kg", date: "2026-09-02",
                                         item: .material("mat_dolgu"), qty: 10, unit: .kg,
                                         totalPaid: tl(2_000)))
        let e = Engine(s)
        #expect(e.qty(.material("mat_dolgu")) == 10_000)          // 10 kg = 10.000 gram
        #expect(e.unitCost(.material("mat_dolgu")) == Double(tl(0.2)))  // 2.000 / 10.000
    }

    // MARK: Varsayılan değer denetimi

    /// Yeni kayıt, önceki kaydın kullanıcı değerini miras almaz
    @Test func yeniKayitOncekindenDegerAlmaz() {
        let m1 = StockMaterial(name: "Koli")
        #expect(m1.openingQty == nil)
        #expect(m1.openingUnitCost == nil)
        let m2 = StockMaterial(name: "Patpat")
        #expect(m2.openingUnitCost == nil)

        let p1 = Product(name: "Şampuan")
        #expect(p1.costLines.isEmpty)
        #expect(p1.openingQty == nil)
        #expect(p1.priceHistory == nil)
        #expect(p1.price(on: "2026-09-15") == nil)

        let c = Channel(id: "x", name: "Yeni kanal")
        #expect(c.commissionPct == 0)
        #expect(c.shippingPerOrder == 0)
        #expect(c.rateHistory == nil)
    }

    /// Sistem varsayılanları açıkça tanımlıdır ve gerçek veri gibi gösterilmez
    @Test func sistemVarsayilanlariAcik() {
        let a = AppSettings()
        #expect(a.defaultVatRate == .yirmi)        // yalnızca öneri
        #expect(a.priceCheckInterval == .aylik)
        #expect(a.consumptionWindowMonths == 3)
        // Fiyatı olmayan ürün "0 TL" değil "fiyat yok" döner
        #expect(Product(name: "X").price(on: "2026-09-15") == nil)
        // Kesinti oranı girilmemiş kanal sıfır kesinti demektir, tahmin değil
        #expect(Channel(id: "x", name: "X").rates(on: "2026-09-01").commissionPct == 0)
    }

    /// Sipariş sayısı girilmemişse tahmin olduğu işaretlenir
    @Test func tahminEdilenSiparisSayisiIsaretlenir() {
        let r = Engine(Golden.senaryo())
            .channelResult(channelId: G.trendyol, month: "2026-09")
        #expect(r.ordersIsEstimate)
        var s = Golden.senaryo()
        s.channelMonths.append(ChannelMonth(id: "chm", month: "2026-09",
                                            channelId: G.trendyol, orderCount: 130))
        let r2 = Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
        #expect(r2.ordersIsEstimate == false)
        #expect(r2.orders == 130)
    }

    /// Elle girilen kesinti "elle girildi" olarak işaretlenir
    @Test func elleGirilenKesintiIsaretlenir() {
        var s = Golden.senaryo()
        s.channelMonths.append(ChannelMonth(id: "chm", month: "2026-09",
                                            channelId: G.trendyol,
                                            commissionActual: tl(30_000)))
        let r = Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
        #expect(r.commission.isManual)
        #expect(r.shipping.isManual == false)
    }
}
