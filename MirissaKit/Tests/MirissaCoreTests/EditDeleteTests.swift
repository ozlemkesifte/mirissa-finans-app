import Testing
import Foundation
@testable import MirissaCore

/// Düzenleme ve silme: eski etki tamamen kalkmalı, kirli hareket kalmamalı.
@Suite("Düzenleme ve silme", .serialized)
@MainActor
struct EditDeleteTests {

    private typealias G = GoldenScenarioTests.G

    private func store() -> AppStore { AppStore.inMemory(GoldenScenarioTests.senaryo()) }

    // MARK: Alım

    /// 500 → 300 düzeltilince sonuç 300 olmalı; "+500 sonra −200" izi kalmamalı
    @Test func alimDuzenlemesiSonDurumuVerir() {
        let st = store()
        let once = st.engine.qty(.material(G.koli))          // 1330
        var p = st.state.purchases.first { $0.id == "pur_g1" }!
        p.qty = 300
        st.updatePurchase(p)
        // 1330 − 200 = 1130
        #expect(st.engine.qty(.material(G.koli)) == once - 200)
        // Tek bir alım hareketi olmalı
        let hareketler = st.engine.history(.material(G.koli)).filter { $0.kind == .purchase }
        #expect(hareketler.count == 1)
        #expect(hareketler.first?.delta == 300)
    }

    @Test func alimSilinincaTumEtkisiKalkar() {
        let st = store()
        let onceKar = st.engine.companyMonth("2026-09").gercekKar
        let onceKdv = st.engine.vatStatus("2026-09").indirilecek
        let onceNakit = st.engine.companyMonth("2026-09").nakitCikisi

        st.deletePurchase("pur_g1")

        #expect(st.engine.qty(.material(G.koli)) == 830)      // 1330 − 500
        // Alımın KDV'si ve nakdi kalkar
        #expect(st.engine.vatStatus("2026-09").indirilecek == onceKdv - tl(1_000))
        #expect(st.engine.companyMonth("2026-09").nakitCikisi == onceNakit - tl(6_000))
        // Kâr değişmez: stok alımı zaten bu ayın gideri değildi
        #expect(st.engine.companyMonth("2026-09").gercekKar == onceKar)
        #expect(st.engine.companyMonth("2026-09").stokAlimi == 0)
    }

    // MARK: Satış

    @Test func satisDuzenlemesiStokVeCiroyuYenidenHesaplar() {
        let st = store()
        var e = st.state.sales.first { $0.id == "sal_g1" }!
        e.qty = 40
        e.grossSales = tl(48_000)
        e.returnsQty = 0
        e.returnsAmount = 0
        st.updateSale(e)
        // Şampuan: 500 − 40 − 50 (set) − 40 (2'li)
        #expect(st.engine.qty(.product(G.sampuan)) == 370)
        // Trendyol net satış: 40.000 + 75.000
        #expect(st.engine.channelResult(channelId: G.trendyol, month: "2026-09")
            .netSales == tl(115_000))
    }

    @Test func satisSilinincaStokGeriGelir() {
        let st = store()
        st.deleteSale("sal_g2")                               // Set satışı
        #expect(st.engine.qty(.product(G.sampuan)) == 370)    // 320 + 50
        #expect(st.engine.qty(.product(G.serum)) == 300)      // 250 + 50
        #expect(st.engine.qty(.material(G.setKutu)) == 500)   // ambalaj da geri gelir
        #expect(st.engine.channelResult(channelId: G.trendyol, month: "2026-09")
            .netSales == tl(90_000))                          // 165.000 − 75.000
    }

    /// Silinen satışın izi hiçbir hesapta kalmaz
    @Test func silinenSatisHicbirYerdeKalmaz() {
        let st = store()
        st.deleteSale("sal_g1")
        st.deleteSale("sal_g2")
        st.deleteSale("sal_g3")
        let r = st.engine.companyMonth("2026-09")
        #expect(r.gercekCiro == 0)
        #expect(r.units == 0)
        #expect(r.orders == 0)
        #expect(st.engine.vatStatus("2026-09").hesaplanan == 0)
        // Stoklar başlangıç + alım seviyesine döner
        #expect(st.engine.qty(.product(G.sampuan)) == 500)
        #expect(st.engine.qty(.material(G.koli)) == 1500)
    }

    // MARK: Gider

    @Test func giderDuzenlemesiKariYenidenHesaplar() {
        let st = store()
        var e = st.state.expenses.first { $0.id == "exp_g1" }!
        e.amount = tl(24_000)                                 // net 20.000
        st.updateExpense(e)
        #expect(st.engine.companyMonth("2026-09").ortakGider == tl(20_000))
        #expect(st.engine.companyMonth("2026-09").gercekKar == tl(66_150))
    }

    @Test func giderSilinincaKarVeKdvDuzelir() {
        let st = store()
        st.deleteExpense("exp_g2")                            // Trendyol reklamı
        let r = st.engine.companyMonth("2026-09")
        #expect(r.channels.first { $0.channelId == G.trendyol }?.ads.amount == 0)
        #expect(r.gercekKar == tl(96_150))                    // 76.150 + 20.000
        #expect(st.engine.vatStatus("2026-09").indirilecek == tl(3_000))
    }

    // MARK: Ürün ve kanal silme

    @Test func urunSilinincaSatislariDaTemizlenir() {
        let st = store()
        st.deleteProduct(G.serum)
        // Serum'u içeren set satışı da geçersizleşir; kalıntı satır kalmamalı
        #expect(Integrity.blocking(st.state).isEmpty)
        #expect(st.state.products.contains { $0.id == G.serum } == false)
    }

    @Test func kanalSilinincaSatislariDaTemizlenir() {
        let st = store()
        st.deleteChannel(G.shopify)
        #expect(Integrity.blocking(st.state).isEmpty)
        #expect(st.state.sales.contains { $0.channelId == G.shopify } == false)
    }

    // MARK: Stok sayımı ve düzeltme

    @Test func sayimSilinincaEskiBakiyeGeriGelir() {
        let st = store()
        let once = st.engine.qty(.material(G.kutu))
        st.addCount(StockCount(id: "cnt_x", date: "2026-09-20",
                               item: .material(G.kutu), countedQty: 100, unit: .adet))
        #expect(st.engine.qty(.material(G.kutu)) == 100)
        st.deleteCount("cnt_x")
        #expect(st.engine.qty(.material(G.kutu)) == once)
    }

    @Test func duzeltmeSilinincaStokGeriGelir() {
        let st = store()
        let once = st.engine.qty(.material(G.koli))
        st.addAdjustment(StockAdjustment(id: "adj_x", date: "2026-09-15",
                                         item: .material(G.koli), qty: 30,
                                         unit: .adet, isIncrease: false, reason: .fire))
        #expect(st.engine.qty(.material(G.koli)) == once - 30)
        st.deleteAdjustment("adj_x")
        #expect(st.engine.qty(.material(G.koli)) == once)
    }

    // MARK: Aynı kaydın tekrar girilmesi

    @Test func ayniSatisIkiKezGirilirseUyarilir() {
        let st = store()
        let taslak = SalesEntry(month: "2026-09", channelId: G.trendyol,
                                productId: G.sampuan, qty: 100, grossSales: tl(120_000))
        let sorunlar = Validation.sale(taslak, state: st.state)
        #expect(sorunlar.contains { $0.code == .mukerrerFatura })
    }

    @Test func ayniFaturaAyniTedarikciEngellenir() {
        let st = store()
        var p = StockPurchase(date: "2026-09-05", item: .material(G.koli),
                              qty: 100, unit: .adet, totalPaid: tl(1_200))
        p.invoiceNo = "A-123"
        p.vendor = "ABC Ambalaj"
        st.addPurchase(p)
        var ayni = p
        ayni.id = Ids.make(.purchase)
        let sorunlar = Validation.purchase(ayni, state: st.state)
        #expect(sorunlar.hardBlocking.contains { $0.code == .mukerrerFatura })
    }

    // MARK: Düzenleme sonrası bütünlük

    @Test func birDiziDuzenlemeSonrasiVeriTutarli() {
        let st = store()
        var p = st.state.purchases[0]; p.qty = 250; st.updatePurchase(p)
        var e = st.state.sales[0]; e.qty = 60; e.grossSales = tl(72_000); st.updateSale(e)
        var g = st.state.expenses[0]; g.amount = tl(6_000); st.updateExpense(g)
        st.deleteSale("sal_g3")

        #expect(Integrity.blocking(st.state).isEmpty)
        let r = st.engine.companyMonth("2026-09")
        #expect(r.gercekCiro - r.toplamGider == r.gercekKar)
        #expect(r.gercekCiro == r.channels.reduce(0) { $0 + $1.netSales })
    }
}
