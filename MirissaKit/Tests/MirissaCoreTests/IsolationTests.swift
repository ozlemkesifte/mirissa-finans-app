import Testing
import Foundation
@testable import MirissaCore

/// "Bir kayıt başka kaydı değiştirmesin" — her temel varlık için yalıtım testi.
/// A kaydı değişince B kaydının model ve hesap sonucu aynı kalmalı.
@Suite("Kayıt yalıtımı")
struct IsolationTests {

    private typealias G = GoldenScenarioTests.G

    private func durum() -> AppState { GoldenScenarioTests.senaryo() }

    /// Bir değişiklikten sonra "dokunulmaması gereken" ölçüleri karşılaştırır
    private func olcum(_ s: AppState, hedefUrun: Id, hedefKanal: Id) -> [String: Int] {
        let e = Engine(s)
        let ay = Dates.monthEnd("2026-09")
        let k = e.channelResult(channelId: hedefKanal, month: "2026-09")
        return [
            "stok": Int(e.qty(.product(hedefUrun))),
            "maliyet": e.cost(of: hedefUrun, asOf: ay).total,
            "ambalaj": e.cost(of: hedefUrun, asOf: ay).packaging,
            "kanalNetSatis": k.netSales,
            "kanalKomisyon": k.commission.amount,
            "kanalKargo": k.shipping.amount,
            "kanaldaKalan": k.kanaldaKalan,
        ]
    }

    // MARK: Ürün

    @Test func urunMaliyetiDegisinceDigerUrunEtkilenmez() {
        var s = durum()
        let once = olcum(s, hedefUrun: G.serum, hedefKanal: G.shopify)
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].costLines = [CostLine(id: "cst_g_s", label: "Üretim", amount: tl(999))]
        // Serum'un maliyeti ve Shopify'ın kargosu değişmemeli
        let sonra = olcum(s, hedefUrun: G.serum, hedefKanal: G.shopify)
        #expect(once["maliyet"] == sonra["maliyet"])
        #expect(once["stok"] == sonra["stok"])
        #expect(once["kanalKargo"] == sonra["kanalKargo"])
    }

    @Test func urunStoguDegisinceDigerUrunEtkilenmez() {
        var s = durum()
        let onceSerum = Engine(s).qty(.product(G.serum))
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].openingQty = 5000
        #expect(Engine(s).qty(.product(G.serum)) == onceSerum)
        #expect(Engine(s).qty(.product(G.sampuan)) == 4820)   // 5000 − 180
    }

    @Test func urunReceteDegisinceDigerUrununAmbalajiDegismez() {
        var s = durum()
        let onceSerum = Engine(s).cost(of: G.serum).packaging
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].recipe.append(RecipeLine(materialId: G.setKutu, qty: 3, unit: .adet))
        #expect(Engine(s).cost(of: G.serum).packaging == onceSerum)
        // Şampuan'ın ambalajı arttı: 15 + 3×15
        #expect(Engine(s).cost(of: G.sampuan).packaging == tl(60))
    }

    // MARK: Bundle

    @Test func setBilesenleriDigerSeteSizmaz() {
        var s = durum()
        let onceIkili = Engine(s).cost(of: G.ikili).intrinsic
        let i = s.products.firstIndex { $0.id == G.set }!
        s.products[i].components = [BundleComponent(productId: G.serum, qty: 5)]
        #expect(Engine(s).cost(of: G.ikili).intrinsic == onceIkili)
        #expect(Engine(s).cost(of: G.set).intrinsic == tl(700))    // 5 × 140
    }

    @Test func setReceteleriBirbirineSizmaz() {
        var s = durum()
        let onceSet = Engine(s).cost(of: G.set).packaging
        let i = s.products.firstIndex { $0.id == G.ikili }!
        s.products[i].recipe = [RecipeLine(materialId: G.koli, qty: 9, unit: .adet)]
        #expect(Engine(s).cost(of: G.set).packaging == onceSet)
        #expect(Engine(s).cost(of: G.ikili).packaging == tl(90))
    }

    // MARK: Malzeme

    @Test func malzemeMiktariDigerMalzemeyeSizmaz() {
        var s = durum()
        let onceKoli = Engine(s).qty(.material(G.koli))
        let i = s.materials.firstIndex { $0.id == G.kutu }!
        s.materials[i].openingQty = 4000
        #expect(Engine(s).qty(.material(G.koli)) == onceKoli)
        #expect(Engine(s).qty(.material(G.kutu)) == 3860)
    }

    @Test func malzemeMaliyetiDigerMalzemeyeSizmaz() {
        var s = durum()
        let onceKoli = Engine(s).unitCost(.material(G.koli))
        let i = s.materials.firstIndex { $0.id == G.kutu }!
        s.materials[i].openingUnitCost = tl(50)
        #expect(Engine(s).unitCost(.material(G.koli)) == onceKoli)
        #expect(Engine(s).unitCost(.material(G.kutu)) == Double(tl(50)))
    }

    // MARK: Kanal

    @Test func kanalKomisyonuDigerKanalaSizmaz() {
        var s = durum()
        let onceShopify = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].commissionPct = 45
        let sonra = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
        #expect(sonra.commission.amount == onceShopify.commission.amount)
        #expect(sonra.kanaldaKalan == onceShopify.kanaldaKalan)
        // Trendyol değişti: 198.000 × %45
        #expect(Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
            .commission.amount == tl(89_100))
    }

    @Test func kanalKargosuDigerKanalaSizmaz() {
        var s = durum()
        let onceTrendyol = Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
        let i = s.channels.firstIndex { $0.id == G.shopify }!
        s.channels[i].shippingPerOrder = tl(250)
        let sonra = Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
        #expect(sonra.shipping.amount == onceTrendyol.shipping.amount)
        #expect(Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
            .shipping.amount == tl(5_000))              // 20 × 250
    }

    @Test func kanalEkKesintisiDigerKanalaSizmaz() {
        var s = durum()
        let onceShopify = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].setRates(ChannelRates(
            from: "2026-01-01", commissionPct: 20, shippingPerOrder: tl(100),
            extras: [ChannelExtraFee(label: "Kampanya", basis: .yuzde, value: 10)]
        ))
        let sonra = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
        #expect(sonra.otherDeduction.amount == onceShopify.otherDeduction.amount)
        #expect(Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
            .otherDeduction.amount == tl(19_800))       // 198.000 × %10
    }

    // MARK: Fiyat

    @Test func birKanalinFiyatiDigerKanalaSizmaz() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].setPrice(tl(749), channelId: G.trendyol, from: "2026-09-01")
        s.products[i].setPrice(tl(699), channelId: G.shopify, from: "2026-09-01")
        let p = Engine(s).state.product(G.sampuan)!
        #expect(p.price(for: G.trendyol, on: "2026-09-15") == tl(749))
        #expect(p.price(for: G.shopify, on: "2026-09-15") == tl(699))
        // Üçüncü bir kanal ikisinden de etkilenmez
        #expect(p.price(for: "baska_kanal", on: "2026-09-15") == nil)
    }

    @Test func birUrununFiyatiDigerUruneSizmaz() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].setPrice(tl(749), channelId: G.trendyol, from: "2026-09-01")
        let serum = Engine(s).state.product(G.serum)!
        #expect(serum.price(for: G.trendyol, on: "2026-09-15") == nil)
    }

    // MARK: Gider

    @Test func kanalGideriDigerKanalaSizmaz() {
        var s = durum()
        let onceShopify = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
        s.expenses.append(Expense(id: "exp_x", date: "2026-09-12", name: "Trendyol influencer",
                                  amount: tl(5_000), category: .influencer,
                                  scope: .channel(G.trendyol), recurrence: .tek))
        let sonra = Engine(s).channelResult(channelId: G.shopify, month: "2026-09")
        #expect(sonra.otherChannelExpensesTotal == onceShopify.otherChannelExpensesTotal)
        #expect(Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
            .otherChannelExpensesTotal == tl(5_000))
    }

    @Test func ortakGiderKanalKarlligininIcineGirmez() {
        var s = durum()
        let once = Engine(s).channelResult(channelId: G.trendyol, month: "2026-09").kanaldaKalan
        s.expenses.append(Expense(id: "exp_y", date: "2026-09-12", name: "Kira",
                                  amount: tl(30_000), category: .sabit, recurrence: .tek))
        #expect(Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
            .kanaldaKalan == once)
        // Ama şirket kârını düşürür
        #expect(Engine(s).companyMonth("2026-09").gercekKar == tl(46_150))
    }

    // MARK: Satış

    @Test func birSatisDigerAyiEtkilemez() {
        var s = durum()
        let onceEylul = Engine(s).companyMonth("2026-09").gercekCiro
        s.sales.append(SalesEntry(id: "sal_x", month: "2026-10", channelId: G.trendyol,
                                  productId: G.sampuan, qty: 10, grossSales: tl(12_000),
                                  vatRate: .yirmi, vatIncluded: true))
        #expect(Engine(s).companyMonth("2026-09").gercekCiro == onceEylul)
        #expect(Engine(s).companyMonth("2026-10").gercekCiro == tl(10_000))
    }

    @Test func birSatisinIadesiDigerSatisiEtkilemez() {
        var s = durum()
        let onceSet = Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
        let i = s.sales.firstIndex { $0.id == "sal_g1" }!
        s.sales[i].returnsQty = 40
        s.sales[i].returnsAmount = tl(48_000)
        let sonra = Engine(s).channelResult(channelId: G.trendyol, month: "2026-09")
        // Set satırının adedi değişmedi
        #expect(sonra.units == onceSet.units)
        // Ama iade adedi ve stok değişti
        #expect(sonra.returnedUnits == 40)
        #expect(Engine(s).qty(.product(G.sampuan)) == 350)
    }

    // MARK: Stok sayımı ve düzeltme

    @Test func birKalemSayimiDigerKalemiEtkilemez() {
        var s = durum()
        let onceKoli = Engine(s).qty(.material(G.koli))
        s.counts.append(StockCount(id: "cnt_x", date: "2026-09-20",
                                   item: .material(G.kutu), countedQty: 700, unit: .adet))
        #expect(Engine(s).qty(.material(G.koli)) == onceKoli)
        #expect(Engine(s).qty(.material(G.kutu)) == 700)
    }

    @Test func fireDigerKalemiEtkilemez() {
        var s = durum()
        let onceKutu = Engine(s).qty(.material(G.kutu))
        s.adjustments.append(StockAdjustment(id: "adj_x", date: "2026-09-18",
                                             item: .material(G.koli), qty: 25,
                                             unit: .adet, isIncrease: false, reason: .fire))
        #expect(Engine(s).qty(.material(G.kutu)) == onceKutu)
        #expect(Engine(s).qty(.material(G.koli)) == 1305)
    }

    // MARK: KDV

    @Test func birKaydinKdvOraniDigerineSizmaz() {
        var s = durum()
        let i = s.expenses.firstIndex { $0.id == "exp_g1" }!
        s.expenses[i].vatRate = .on
        let e = Engine(s)
        // Muhasebeci: 12.000 KDV %10 dahil -> net 10.909,09 / KDV 1.090,91
        #expect(e.companyMonth("2026-09").ortakGider == tl(10_909.09))
        // Reklamın KDV'si hâlâ %20: 4.000
        let v = e.vatStatus("2026-09")
        #expect(v.indirilecek == tl(10_909.09 * 0 + 1_090.91) + tl(4_000) + tl(1_000))
    }

    // MARK: Taslaklar

    @Test func birAkisinTaslagiDigeriniEzmez() throws {
        var s = durum()
        s.drafts = [
            try #require(WizardDraft.make(kind: .kanalKurulumu, subjectId: G.trendyol,
                                          title: "Trendyol", step: 4, totalSteps: 12,
                                          state: ["a": 1])),
            try #require(WizardDraft.make(kind: .kanalKurulumu, subjectId: G.shopify,
                                          title: "Shopify", step: 9, totalSteps: 12,
                                          state: ["a": 2])),
        ]
        #expect(s.drafts.count == 2)
        #expect(s.drafts.first { $0.subjectId == G.trendyol }?.step == 4)
        #expect(s.drafts.first { $0.subjectId == G.shopify }?.step == 9)
    }
}
