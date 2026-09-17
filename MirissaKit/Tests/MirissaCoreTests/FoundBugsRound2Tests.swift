import Testing
import Foundation
@testable import MirissaCore

/// İkinci uçtan uca denetimde bulunan hesap hataları.
/// Her beklenen değer elle hesaplanmıştır; testler eski motorda başarısız olur.
@Suite("Denetim 2: bulunan hesap hataları")
struct FoundBugsRound2Tests {

    // MARK: B1 — KDV hariç girilen satışta kesinti tabanı

    @Test func kdvHaricSatistaKomisyonKdvDahilTutardan() {
        var s = Fx.base()
        s.sales.append(SalesEntry(id: "s1", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(1_000),
                                  vatRate: .yirmi, vatIncluded: false))
        let e = Engine(s)
        let c = e.companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
        // Müşteri 1.200 TL öder; %20 komisyon 240 TL
        #expect(c.netSalesIncVat == tl(1_200))
        #expect(c.netSales == tl(1_000))
        #expect(c.commission.amount == tl(240))
        #expect(c.outputVat == tl(200))
        #expect(e.adPerformance(month: "2026-09").revenue == tl(1_200))
    }

    /// Aynı satış KDV dahil 1.200 olarak girilince sonuç aynı olmalı
    @Test func kdvDahilVeHaricGirisAyniSonucuVerir() {
        func sonuc(_ tutar: Kurus, dahil: Bool) -> ChannelMonthResult {
            var s = Fx.base()
            s.sales.append(SalesEntry(id: "s1", month: "2026-09", channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 1, grossSales: tutar,
                                      vatRate: .yirmi, vatIncluded: dahil))
            return Engine(s).companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
        }
        let a = sonuc(tl(1_000), dahil: false)
        let b = sonuc(tl(1_200), dahil: true)
        #expect(a.commission.amount == b.commission.amount)
        #expect(a.kanaldaKalan == b.kanaldaKalan)
    }

    // MARK: B2 — dağılımda adet ile kuruş toplanmamalı

    private func dagilimDurumu(serumFiyati: Bool) -> AppState {
        var s = Fx.base()
        s.products[0].setPrice(tl(600), channelId: ChannelIds.trendyol, from: "2026-01-01")
        if serumFiyati {
            s.products[1].setPrice(tl(1_200), channelId: ChannelIds.trendyol, from: "2026-01-01")
        }
        // A: 100 adet, 60.000 TL. B: adedi boş eski kayıt, 2.400 TL
        s.sales.append(SalesEntry(id: "a", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 100, grossSales: tl(60_000)))
        s.sales.append(SalesEntry(id: "b", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 0, grossSales: tl(2_400)))
        return s
    }

    @Test func adediBosSatirFiyattanAdetTahminEdilir() {
        let mix = Engine(dagilimDurumu(serumFiyati: true)).targetMix(month: "2026-09").agirliklar
        let a = mix.first { $0.productId == Fx.sampuanId }!.pay
        let b = mix.first { $0.productId == Fx.serumId }!.pay
        // 2.400 ÷ 1.200 = 2 adet → 100 / 102 ve 2 / 102
        #expect(abs(a - 100.0 / 102) < 1e-9)
        #expect(abs(b - 2.0 / 102) < 1e-9)
    }

    @Test func fiyatYoksaTumSatirlarTutaraGoreTartilir() {
        let mix = Engine(dagilimDurumu(serumFiyati: false)).targetMix(month: "2026-09").agirliklar
        let a = mix.first { $0.productId == Fx.sampuanId }!.pay
        // 60.000 / 62.400 — eski motor B'ye %99,9 pay veriyordu
        #expect(abs(a - 60_000.0 / 62_400) < 1e-9)
    }

    // MARK: B3 — reklam hedefi sipariş başına

    private func sepetDurumu() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []
        s.products[0].setPrice(tl(600), channelId: ChannelIds.shopify, from: "2026-01-01")
        s.channels[1].paymentPct = 0
        s.channels[1].shippingPerOrder = tl(100)
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 20, grossSales: tl(12_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-08",
                                            channelId: ChannelIds.shopify, orderCount: 10))
        return s
    }

    @Test func siparisteIkiUrunVarsaHedefSiparisBasina() {
        let e = Engine(sepetDurumu())
        let t = e.adTargets(keepPerOrder: tl(100), on: "2026-09-10")
            .first { $0.productId == Fx.sampuanId && $0.channelId == ChannelIds.shopify }!
        // Siparişte 2 ürün: değer 1.200, kalan 2 × (600 − 100) − 100 kargo = 900
        #expect(t.unitsPerOrder == 2)
        #expect(t.unitsPerOrderKnown)
        #expect(t.orderValue == tl(1_200))
        #expect(t.beforeAds == tl(900))
        #expect(t.maxCPA == tl(800))
        #expect(abs(t.breakevenROAS! - 1_200.0 / 900) < 1e-9)
        #expect(abs(t.targetROAS! - 1_200.0 / 800) < 1e-9)
    }

    @Test func karisikHedefBasaBasPlaniylaAyniSiparisKatkisiniVerir() {
        let e = Engine(sepetDurumu())
        let k = e.blendedAdTarget(month: "2026-09", keepPerOrder: nil, today: "2026-09-10")!
        let plan = e.plan(month: "2026-09", today: "2026-09-10")
        // Geçen ay: 12.000 − 1.000 kargo − 2.000 ürün = 9.000 ÷ 10 sipariş = 900
        #expect(k.beforeAds == tl(900))
        #expect(k.orderValue == tl(1_200))
        #expect(abs(plan.contributionPerOrder - Double(k.beforeAds)) < 1)
    }

    @Test func siparisSayisiGirilmemisseBirUrunKabulEdilirVeSoylenir() {
        var s = sepetDurumu()
        s.channelMonths = []
        let t = Engine(s).adTargets(keepPerOrder: nil, on: "2026-09-10").first!
        #expect(t.unitsPerOrder == 1)
        #expect(!t.unitsPerOrderKnown)
        #expect(t.beforeAds == tl(400))   // 600 − 100 ürün − 100 kargo
    }

    // MARK: B4 — planlanan kanal ücreti KDV'siz

    @Test func planlananAylikUcretKdvHaric() {
        var s = Fx.base()
        s.channels[0].platformFeeMonthly = tl(1_200)
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        #expect(Engine(s).plannedFixedCosts(month: "2026-09") == tl(1_000))
    }

    @Test func dahaSonraBaslayanKanalinUcretiOncekiAyaYazilmaz() {
        var s = Fx.base()
        s.channels[0].platformFeeMonthly = tl(1_200)
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.sales.append(SalesEntry(id: "s", month: "2026-11", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(500)))
        let e = Engine(s)
        #expect(e.plannedFixedCosts(month: "2026-09") == 0)
        #expect(e.plannedFixedCosts(month: "2026-11") == tl(1_000))
    }

    // MARK: B5 — kanal başlamadan aylık ücret yok

    @Test func kanalBaslamadanGirilenGiderAylikUcretYazdirmaz() {
        var s = Fx.base()
        s.channels[1].paymentPct = 0
        s.channels[1].platformFeeMonthly = tl(500)
        s.sales.append(SalesEntry(id: "s", month: "2026-03", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(1_000)))
        s.expenses.append(Expense(id: "r", date: "2026-01-15", name: "Tanıtım",
                                  amount: tl(100), category: .reklam,
                                  scope: .channel(ChannelIds.shopify)))
        let e = Engine(s)
        func gider(_ ay: MonthKey) -> Kurus {
            guard let c = e.companyMonth(ay).channels.first(where: { $0.channelId == ChannelIds.shopify })
            else { return 0 }
            return c.otherDeduction.amount + c.ads.amount
        }
        #expect(gider("2026-01") == tl(100))
        #expect(gider("2026-02") == 0)
        #expect(gider("2026-03") == tl(500))
    }

    // MARK: B6 — maliyeti eksik ürün işaretlenir

    @Test func maliyetiGirilmemisUrunHedefteIsaretlenir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].setPrice(tl(600), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[1].setPrice(tl(600), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[2].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        let liste = Engine(s).adTargets(keepPerOrder: nil, on: "2026-09-10")
        let sampuan = liste.first { $0.productId == Fx.sampuanId }
        let serum = liste.first { $0.productId == Fx.serumId }
        let set = liste.first { $0.productId == Fx.setId }
        #expect(sampuan?.missingCostProducts == [])
        #expect(serum?.missingCostProducts == ["Serum"])
        // Set maliyeti bileşenlerden gelir: eksik olan Serum
        #expect(set?.missingCostProducts == ["Serum"])
        #expect(serum?.eksikBilgiVar == true)
    }

    // MARK: B7 — beklenen sepet KDV dahil ve kesinti KDV'si düşülür

    @Test func beklenenSepetKesintiKdvsiDusulur() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.settings.expectedMix = ExpectedMix(channelId: ChannelIds.trendyol,
                                             productId: Fx.sampuanId, averageOrderValue: tl(1_200))
        let b = Engine(s).expectedMixBasis()!
        // 1.200 → 1.000 net; komisyon 240 KDV dahil → 200 net; 1.000 − 200 − 100 = 700
        #expect(abs(b.contributionPerOrder - Double(tl(700))) <= 1)
        #expect(abs(b.revenuePerOrder - Double(tl(1_000))) <= 1)
    }

    // MARK: L1 — dönem toplamında indirilecek gider KDV'si

    @Test func donemToplamiGiderKdvsiniToplar() {
        var s = Fx.base()
        var g = Expense(id: "k", date: "2026-01-01", name: "Kira", amount: tl(1_200),
                        category: .sabit, recurrence: .aylik)
        g.vatRate = .yirmi
        g.vatIncluded = true
        s.expenses.append(g)
        let e = Engine(s)
        #expect(e.companyTotals(from: "2026-01", to: "2026-02").giderKdv == tl(400))
    }

    // MARK: L2 — tarihçesiz kanalda oran değişince geçmiş korunur

    @Test @MainActor func tarihcesizKanaldaOranDegisinceGecmisDegismez() {
        var s = Fx.base()
        s.sales.append(SalesEntry(id: "s", month: "2026-01", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(500)))
        let store = AppStore.inMemory(s)
        let once = store.engine.companyMonth("2026-01").channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(once.commission.amount == tl(100))

        var ch = store.state.channel(ChannelIds.trendyol)!
        ch.commissionPct = 60
        store.updateChannel(ch)

        let sonra = store.engine.companyMonth("2026-01").channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(sonra.commission.amount == tl(100))
        #expect(store.state.channel(ChannelIds.trendyol)!.currentRates.commissionPct == 60)
    }

    // MARK: Eksi hedef

    @Test func eksiBirakilacakTutarHedefiBozmaz() {
        let t = AdTarget(productId: "p", productName: "Ü", channelId: "c", channelName: "K",
                         orderValue: tl(700), beforeAds: tl(300), keepPerOrder: tl(-50))
        #expect(t.maxCPA == tl(300))
    }
}
