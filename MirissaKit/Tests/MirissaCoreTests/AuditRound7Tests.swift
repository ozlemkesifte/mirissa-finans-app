import Testing
import Foundation
@testable import MirissaCore

/// Formül denetimi (8 konu) regresyon testleri. Rakamlar elle hesaplandı.
@Suite("Denetim 7 — formüller")
struct AuditRound7Tests {

    // MARK: 1 — Yıllık hedef aylardan

    /// KDV'siz, komisyonsuz; Şampuan 1.000 TL, üretim 200 TL, reçetesiz.
    /// Ağustos'ta 10 sipariş (10 ürün), kira ağustostan itibaren ayda 10.000 TL.
    private func yillikDurum() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[0].costLines = [CostLine(id: "c", label: "Üretim", amount: tl(200))]
        s.products[0].recipe = []
        s.sales.append(SalesEntry(id: "a", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        s.channelMonths.append(ChannelMonth(month: "2026-08", channelId: ChannelIds.trendyol, orderCount: 10))
        s.expenses.append(Expense(id: "kira", date: "2026-08-01", name: "Kira", amount: tl(10_000),
                                  category: .sabit, recurrence: .aylik))
        return s
    }

    @Test func yillikHedefHerAyinKendiKatkisiylaToplanir() throws {
        var s = yillikDurum()
        // Kasım'dan itibaren fiyat 1.500 TL
        s.products[0].setPrice(tl(1_500), channelId: ChannelIds.trendyol, from: "2026-11-01")
        let p = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        let be = try #require(p.targets.first { $0.isBreakeven })
        // Ağu–Eki katkı 800 TL: ceil(10.000 / 800) = 13; Kas–Ara katkı 1.300 TL: ceil(10.000 / 1.300) = 8
        #expect(be.aylik == ["2026-08": 13, "2026-09": 13, "2026-10": 13, "2026-11": 8, "2026-12": 8])
        #expect(be.ordersPerYear == 55)
        // Tek katkıyla (800) hesaplansaydı ceil(50.000 / 800) = 63 çıkardı
        #expect(be.ordersPerYear != 63)
        #expect(be.aylikAralik == 8...13)
        // Ciro da ay ay: 39 × 1.000 + 16 × 1.500 = 63.000 TL
        #expect(be.revenue == tl(63_000))
        #expect(p.fixedCosts == tl(50_000))
    }

    @Test func yillikKarHedefiFaaliyettekiAylaraBolunur() throws {
        var s = yillikDurum()
        s.products[0].setPrice(tl(1_500), channelId: ChannelIds.trendyol, from: "2026-11-01")
        s.settings.yearlyProfitGoals = ["2026": tl(120_000)]
        let p = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        let ozel = try #require(p.targets.first { $0.isCustom })
        // 5 faaliyet ayına 24.000 TL: Ağu–Eki ceil(34.000 / 800) = 43; Kas–Ara ceil(34.000 / 1.300) = 27
        #expect(ozel.aylik == ["2026-08": 43, "2026-09": 43, "2026-10": 43, "2026-11": 27, "2026-12": 27])
        #expect(ozel.ordersPerYear == 183)
    }

    @Test func fiyatDegismezseAylarAyni() throws {
        let p = Engine(yillikDurum()).yearlyPlan(year: 2026, today: "2026-09-16")
        let be = try #require(p.targets.first { $0.isBreakeven })
        #expect(be.ordersPerYear == 65)          // 5 × 13
        #expect(be.aylikAralik == 13...13)
    }

    @Test func birAyinKatkisiEksiyseYillikHedefUydurulmaz() {
        var s = yillikDurum()
        // Kasım'dan itibaren fiyat maliyetin altında: sipariş başına −50 TL
        s.products[0].setPrice(tl(150), channelId: ChannelIds.trendyol, from: "2026-11-01")
        let p = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        #expect(p.targets.isEmpty)
        #expect(p.blocking == .katkiNegatif)
    }

    @Test func kullanilmayanKanalinUcretiIsinOlmadigiAylariFaaliyetteGostermez() throws {
        var s = yillikDurum()
        s.channels[1].platformFeeMonthly = tl(500)
        s.channels[1].feeVatRate = .yok
        s.settings.yearlyProfitGoals = ["2026": tl(120_000)]
        let p = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        let ozel = try #require(p.targets.first { $0.isCustom })
        // Ocak–Temmuz'da ne satış ne gider var: hedefe girmez, kâr hedefi 5 aya bölünür
        #expect(ozel.aylik.keys.sorted() == ["2026-08", "2026-09", "2026-10", "2026-11", "2026-12"])
        // Ağustos: ceil((10.000 + 24.000) / 800) = 43
        #expect(ozel.aylik["2026-08"] == 43)
    }

    @Test func bitmemisAyinYarimVerisiYillikHedefiBozmaz() throws {
        var s = yillikDurum()
        // 3 Eylül: 2 sipariş girildi, ayın başında 5.000 TL satışa bağlı reklam
        s.sales.append(SalesEntry(id: "e", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 2, grossSales: tl(2_000)))
        s.expenses.append(Expense(id: "rk", date: "2026-09-01", name: "Reklam", amount: tl(5_000),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol), recurrence: .tek,
                                  behavior: .satisaBagli))
        let p = Engine(s).yearlyPlan(year: 2026, today: "2026-09-03")
        let be = try #require(p.targets.first { $0.isBreakeven })
        // Eylül, Ağustos karışımıyla (800 TL) hesaplanır: ceil(10.000 / 800) = 13
        #expect(be.aylik["2026-09"] == 13)
    }

    @Test func gunlukHedefEnYogunAyinGunSayisiyla() throws {
        var s = yillikDurum()
        s.expenses[0].date = "2026-10-01"
        s.expenses[0].amount = tl(80_000)
        let p = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        let be = try #require(p.targets.first { $0.isBreakeven })
        // Eki–Ara ceil(80.000 / 800) = 100; Ağustos satışlı ama sabit gidersiz: 0 (aralığa girmez)
        #expect(be.aylik["2026-08"] == 0)
        #expect(be.aylikAralik == 100...100)
        #expect(be.ordersPerMonth == 100)
        #expect(be.ordersPerDay == 4)          // Kasım: ceil(100 / 30)
        #expect(be.ordersPerYear == 300)
    }

    // MARK: 2 — Olağandışı gerçekleşme oranı

    private func oranDurumu(brut: Kurus) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[0].costLines = [CostLine(id: "c", label: "Üretim", amount: tl(200))]
        s.products[0].recipe = []
        s.sales.append(SalesEntry(id: "a", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: brut))
        return s
    }

    @Test func olagandisiOrandaBirVarsayilmaz() throws {
        // 10 × 1.000 TL liste fiyatı, gerçekleşen 1.000 TL: oran 0,1 — veri hatası
        let e = Engine(oranDurumu(brut: tl(1_000)))
        #expect(e.gerceklesmeOrani(channelId: ChannelIds.trendyol, productId: Fx.sampuanId, month: "2026-08") == nil)
        #expect(e.blendedAdTarget(month: "2026-09", keepPerOrder: nil, today: "2026-09-16") == nil)
        #expect(e.olagandisiGerceklesmeler(month: "2026-09") == ["Şampuan (Trendyol)"])
        let t = try #require(e.adTargets(keepPerOrder: tl(50), on: "2026-09-16").first { $0.productId == Fx.sampuanId })
        #expect(t.gerceklesmeOlagandisi)
        #expect(t.breakevenROAS == nil)
        #expect(t.targetROAS == nil)
        #expect(t.gecerliMaxCPA == nil)
    }

    @Test func normalOrandaHedefHesaplanir() throws {
        // Gerçekleşen 9.000 TL: oran 0,9
        let e = Engine(oranDurumu(brut: tl(9_000)))
        #expect(e.gerceklesmeOrani(channelId: ChannelIds.trendyol, productId: Fx.sampuanId, month: "2026-08") == 0.9)
        #expect(e.olagandisiGerceklesmeler(month: "2026-09").isEmpty)
        let k = try #require(e.blendedAdTarget(month: "2026-09", keepPerOrder: nil, today: "2026-09-16"))
        #expect(!k.gerceklesmeOlagandisi)
        #expect(k.orderValue == tl(900))
        #expect(k.breakevenROAS != nil)
    }

    @Test func olagandisiOrandaBeklenenDagilimaSessizceGecilmez() {
        // İşin ilk ayı, ara durum işaretli; 10 ürün 1.000 TL'ye (liste 1.000 TL) — oran 0,1
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[0].costLines = [CostLine(id: "c", label: "Üretim", amount: tl(200))]
        s.products[0].recipe = []
        s.sales.append(SalesEntry(id: "a", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(1_000)))
        s.settings.progressAsOf["2026-09"] = "2026-09-10"
        s.settings.expectedMix = ExpectedMix(channelId: ChannelIds.trendyol, productId: Fx.sampuanId,
                                             averageOrderValue: tl(1_000))
        s.expenses.append(Expense(id: "kira", date: "2026-09-01", name: "Kira", amount: tl(10_000),
                                  category: .sabit, recurrence: .aylik))
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        #expect(p.targets.isEmpty)
        #expect(p.blocking == .gerceklesmeOlagandisi)
    }

    // MARK: 3 — Açıklanamayan fark "Diğer / düzeltme" olmaz

    @Test func elleGirilenReklamFarkiKendiAdiylaGosterilir() {
        var s = yillikDurum()
        s.expenses.append(Expense(id: "rk", date: "2026-08-05", name: "Reklam", amount: tl(1_000),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol), recurrence: .tek,
                                  behavior: .sabit))
        s.channelMonths[0].adsActual = tl(1_500)
        let e = Engine(s)
        let d = e.sabitGiderDokumu(month: "2026-08", planli: false)
        #expect(d.tutarsizlik == 0)
        #expect(d.toplam == e.companyMonth("2026-08").toplamSabitGider)
        #expect(d.satirlar.first { $0.tur == .elleReklam }?.tutar == tl(500))
        #expect(!d.satirlar.contains { $0.ad == "Diğer / düzeltme" })
        let g = e.giderAyrimi(from: "2026-08", to: "2026-08")
        #expect(g.tutarsizlik == 0)
        #expect(!g.genel.contains { $0.ad == "Diğer / düzeltme" })
        #expect(g.urunBasinaToplam + g.genelToplam == e.companyMonth("2026-08").toplamGider)
    }

    @Test func dokumToplamiVeTutarsizlikPlanlaHepAyni() {
        var s = yillikDurum()
        s.channels[0].platformFeeMonthly = tl(500)
        s.channels[0].feeVatRate = .yok
        s.expenses.append(Expense(id: "iade", date: "2026-08-20", name: "İade edilen gider", amount: -tl(300),
                                  category: .diger, recurrence: .tek))
        let e = Engine(s)
        for ay in ["2026-08", "2026-09", "2026-10"] {
            let d = e.sabitGiderDokumu(month: ay)
            #expect(d.toplam + d.tutarsizlik == e.plannedFixedCosts(month: ay))
            #expect(d.tutarsizlik == 0, "\(ay)")
        }
        let g = e.giderAyrimi(from: "2026-08", to: "2026-08")
        #expect(g.urunBasinaToplam + g.genelToplam + g.tutarsizlik == e.companyMonth("2026-08").toplamGider)
        #expect(!g.genel.contains { $0.ad == "Diğer / düzeltme" })
    }

    @Test func satisaBagliReklamIadesiTutarsizlikUretmez() {
        var s = yillikDurum()
        s.expenses.append(Expense(id: "rs", date: "2026-08-05", name: "Sabit reklam", amount: tl(1_000),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol), recurrence: .tek,
                                  behavior: .sabit))
        s.expenses.append(Expense(id: "ri", date: "2026-08-20", name: "Reklam iadesi", amount: -tl(200),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol), recurrence: .tek,
                                  behavior: .satisaBagli))
        let e = Engine(s)
        let d = e.sabitGiderDokumu(month: "2026-08", planli: false)
        #expect(d.tutarsizlik == 0)
        #expect(d.toplam == e.companyMonth("2026-08").toplamSabitGider)
        #expect(d.satirlar.first { $0.tur == .reklamSiniri }?.tutar == -tl(200))
    }

    // MARK: 4 — "0 satış" ile "girilmedi" ayrı

    @Test func satisDurumuUcAyriHal() {
        var s = yillikDurum()
        s.expenses.append(Expense(id: "k2", date: "2026-07-01", name: "Muhasebe", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik))
        #expect(Engine(s).satisDurumu("2026-08") == .girildi)
        #expect(Engine(s).satisDurumu("2026-07") == .girilmedi)
        #expect(Engine(s).satisGirilmedi(month: "2026-07", today: "2026-09-16"))
        s.settings.ek.aySonuIsaretleri = ["2026-07": ["satis"]]
        let e = Engine(s)
        #expect(e.satisDurumu("2026-07") == .sifirSatis)
        #expect(!e.satisGirilmedi(month: "2026-07", today: "2026-09-16"))
        // Tamamlandı: 0 satış gerçek sıfırdır
        #expect(e.companyMonth("2026-07").gercekCiro == 0)
    }

    @Test func girilmemisAyTuketimHiziniDusurmezSifirSatisDusurur() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0].recipe = []
        s.addPurchase("p", "2026-05-01", .product(Fx.sampuanId), qty: 1_000, paid: tl(10_000))
        s.addSale("h", "2026-06", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 90, gross: tl(9_000))
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 90, gross: tl(9_000))
        // Temmuz girilmedi: pencere Haz + Ağu → ayda 90
        let r1 = Engine(s).consumptionRate(.product(Fx.sampuanId), endingAt: "2026-08", bugun: "2026-09-19")
        #expect(abs(r1.perMonth - 90) < 0.001)
        // Temmuz "0 satış": pencere Haz + Tem + Ağu → ayda 60
        s.settings.ek.aySonuIsaretleri = ["2026-07": ["satis"]]
        let r2 = Engine(s).consumptionRate(.product(Fx.sampuanId), endingAt: "2026-08", bugun: "2026-09-19")
        #expect(abs(r2.perMonth - 60) < 0.001)
    }

    // MARK: 5 — Koli iki kez maliyetlenmez

    /// Koli sipariş başına (perOrder), 10 TL; şampuan kutusu 2 TL; set kutusu 5 TL.
    private func koliDurumu(siparisBasi: Bool) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.materials = s.materials.map { var m = $0; if m.id == Fx.koliId { m.perOrder = siparisBasi }; return m }
        s.products[0].recipe = [RecipeLine(id: "s1", materialId: Fx.sampuanKutuId, qty: 1, unit: .adet),
                                RecipeLine(id: "s2", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.products[1].recipe = [RecipeLine(id: "r1", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.products[2].recipe = [RecipeLine(id: "t1", materialId: Fx.setKutuId, qty: 1, unit: .adet),
                                RecipeLine(id: "t2", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.products[0].setPrice(tl(100), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.addPurchase("k", "2026-01-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.addPurchase("u", "2026-01-01", .material(Fx.sampuanKutuId), qty: 100, paid: tl(200))
        s.addPurchase("t", "2026-01-01", .material(Fx.setKutuId), qty: 100, paid: tl(500))
        return s
    }

    @Test func siparisBasiKoliKanalMaliyetindeBirKez() {
        var s = koliDurumu(siparisBasi: true)
        // 10 şampuan, 5 sipariş (siparişte 2 ürün → 1 koli)
        s.addSale("a", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(1_000))
        s.channelMonths.append(ChannelMonth(month: "2026-01", channelId: ChannelIds.trendyol, orderCount: 5))
        let e = Engine(s)
        let c = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01")
        // 10 kutu × 2 + 5 koli × 10 = 70 TL (koli reçeteden ürün başına ayrıca sayılsaydı 170 olurdu)
        #expect(c.koliSayisi == 5)
        #expect(c.packagingCost == tl(70))
        #expect(e.qty(.material(Fx.koliId)) == 95)
        #expect(e.qty(.material(Fx.sampuanKutuId)) == 90)
    }

    @Test func siparisBasiKoliBirimKatkidaBirKez() throws {
        let e = Engine(koliDurumu(siparisBasi: true))
        let u = try #require(e.unitContribution(productId: Fx.sampuanId, channelId: ChannelIds.trendyol, on: "2026-01-31"))
        #expect(u.packagingCost == tl(2))           // yalnız kutu
        #expect(u.orderPackagingCost == tl(10))     // koli siparişte bir kez
        #expect(e.cost(of: Fx.sampuanId, asOf: "2026-01-31").total == tl(12))
    }

    @Test func setSatisindaBilesenKolileriSayilmaz() {
        var s = koliDurumu(siparisBasi: true)
        s.addSale("a", "2026-01", channel: ChannelIds.trendyol, product: Fx.setId, qty: 4, gross: tl(800))
        s.channelMonths.append(ChannelMonth(month: "2026-01", channelId: ChannelIds.trendyol, orderCount: 4))
        let e = Engine(s)
        let c = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01")
        // 4 set kutusu × 5 + 4 koli × 10 = 60 TL; bileşenlerin kolisi (8 adet daha) sayılmaz
        #expect(c.packagingCost == tl(60))
        #expect(e.qty(.material(Fx.koliId)) == 96)
        #expect(e.cost(of: Fx.setId, asOf: "2026-01-31").orderPackaging == tl(10))
    }

    @Test func siparisBasiDegilseKoliUrunBasinaVeSiparisteSifir() throws {
        var s = koliDurumu(siparisBasi: false)
        s.addSale("a", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(1_000))
        s.channelMonths.append(ChannelMonth(month: "2026-01", channelId: ChannelIds.trendyol, orderCount: 5))
        let e = Engine(s)
        let c = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01")
        #expect(c.packagingCost == tl(120))        // 10 × (2 + 10)
        #expect(c.koliSayisi == 0)
        #expect(e.qty(.material(Fx.koliId)) == 90)
        let u = try #require(e.unitContribution(productId: Fx.sampuanId, channelId: ChannelIds.trendyol, on: "2026-01-31"))
        #expect(u.packagingCost == tl(12))
        #expect(u.orderPackagingCost == 0)
    }

    // MARK: 6 — Ay içinde maliyet değişimi

    @Test func ayIcindeMaliyetDegisinceYaklasikDenir() {
        var s = yillikDurum()
        s.products[0].costLines = [
            CostLine(id: "c1", label: "Üretim", amount: tl(200), validTo: "2026-08-14"),
            CostLine(id: "c2", label: "Üretim", amount: tl(300), validFrom: "2026-08-15"),
        ]
        let e = Engine(s)
        let r = e.companyMonth("2026-08")
        #expect(r.maliyetiDegisenUrunler == ["Şampuan"])
        #expect(r.maliyetDegisimUyarisi?.contains("kârlılık yaklaşık hesaplanmıştır") == true)
    }

    @Test func maliyetAyBasindaDegistiyseYaklasikDenmez() {
        var s = yillikDurum()
        s.products[0].costLines = [
            CostLine(id: "c1", label: "Üretim", amount: tl(200), validTo: "2026-07-31"),
            CostLine(id: "c2", label: "Üretim", amount: tl(300), validFrom: "2026-08-01"),
        ]
        let r = Engine(s).companyMonth("2026-08")
        #expect(r.maliyetiDegisenUrunler.isEmpty)
        #expect(r.maliyetDegisimUyarisi == nil)
    }

    @Test func ayIcindePahaliAlimYaklasikDenir() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0].recipe = []
        s.addPurchase("p1", "2026-07-01", .product(Fx.sampuanId), qty: 100, paid: tl(1_000))
        s.addPurchase("p2", "2026-08-20", .product(Fx.sampuanId), qty: 100, paid: tl(3_000))
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(1_000))
        #expect(Engine(s).companyMonth("2026-08").maliyetiDegisenUrunler == ["Şampuan"])
    }

    @Test func kucukOrtalamaMaliyetOynamasiUyariUretmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0].recipe = []
        s.addPurchase("p1", "2026-07-01", .product(Fx.sampuanId), qty: 100, paid: tl(1_000))
        s.addPurchase("p2", "2026-08-20", .product(Fx.sampuanId), qty: 100, paid: tl(1_010))
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(1_000))
        // 10,00 → 10,05 TL (%0,5): yaklaşık denmez
        #expect(Engine(s).companyMonth("2026-08").maliyetiDegisenUrunler.isEmpty)
    }

    // MARK: 7 — Reklam hedefinde imkânsız hedef

    private func hedef(deger: Kurus, kalan: Kurus, birak: Kurus?) -> AdTarget {
        AdTarget(productId: "p", productName: "Ürün", channelId: "c", channelName: "Kanal",
                 orderValue: deger, beforeAds: kalan, keepPerOrder: birak)
    }

    @Test func maxCPASifirVeyaEksiyseROASUretilmez() {
        let esit = hedef(deger: tl(1_000), kalan: tl(300), birak: tl(300))
        #expect(esit.maxCPA == 0)
        #expect(esit.targetROAS == nil)
        #expect(esit.gecerliMaxCPA == nil)
        #expect(esit.hedefiKaldirmiyor)
        let asan = hedef(deger: tl(1_000), kalan: tl(300), birak: tl(400))
        #expect(asan.targetROAS == nil)
        #expect(asan.gecerliMaxCPA == nil)
        #expect(asan.hedefiKaldirmiyor)
        #expect(Engine(Fx.base()).ordersForBudget(tl(1_000), target: asan) == nil)
        #expect(Engine(Fx.base()).budgetForOrders(10, target: asan) == nil)
        #expect(AdTarget.hedefMumkunDegil == "Bu fiyat ve maliyetlerle bu kâr hedefi mümkün değil.")
        // Mümkün hedef: 1.000 / (300 − 100) = 5
        let olur = hedef(deger: tl(1_000), kalan: tl(300), birak: tl(100))
        #expect(olur.targetROAS == 5)
        #expect(olur.gecerliMaxCPA == tl(200))
    }

    @Test func siparisDegeriSifirsaROASUretilmez() {
        let t = hedef(deger: 0, kalan: tl(300), birak: tl(100))
        #expect(t.breakevenROAS == nil)
        #expect(t.targetROAS == nil)
        #expect(t.gecerliMaxCPA == nil)
        let zarar = hedef(deger: tl(1_000), kalan: -tl(50), birak: nil)
        #expect(zarar.breakevenROAS == nil)
        #expect(zarar.reklamsizZarar)
    }

    // MARK: 8 — Geçici vergi eksi olamaz

    @Test func zararEdenCeyrekteGeciciVergiEksiOlmaz() throws {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0].recipe = []
        for ay in ["2026-01", "2026-02", "2026-03"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        }
        // 2. çeyrekte büyük zarar
        s.expenses.append(Expense(id: "z", date: "2026-05-10", name: "Büyük gider", amount: tl(50_000),
                                  category: .diger, recurrence: .tek))
        s.settings.ek.vergiOrani = 20
        let e = Engine(s)
        let q1 = try #require(e.vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(q1.ceyrekGeciciVergi == tl(6_000))      // 30.000 × %20
        let q2 = try #require(e.vergiKarsiligi(month: "2026-06", today: "2026-07-01"))
        #expect(q2.ceyrekGeciciVergi == 0)               // max(0 − 6.000, 0)
        #expect(q2.yilBasindanKarsilik == 0)
        for ay in 1...12 {
            let v = try #require(e.vergiKarsiligi(month: Dates.monthKey(2026, ay), today: "2026-12-31"))
            #expect(v.ceyrekGeciciVergi >= 0)
            #expect(v.yilBasindanKarsilik >= 0)
            #expect(v.ayinPayi >= 0)
        }
    }
}
