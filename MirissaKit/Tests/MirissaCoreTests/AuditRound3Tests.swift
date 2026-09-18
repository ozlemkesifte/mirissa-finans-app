import Testing
import Foundation
@testable import MirissaCore

/// Üçüncü denetimde bulunan hatalar. Beklenen değerler elle hesaplanmıştır.
@Suite("Denetim 3: sayım sırası ve koli bayrakları")
struct AuditRound3Tests {

    /// 100 koli 1.000 TL (10 TL), sayım ve sonraki alım aynı ay içinde
    private func durum() -> AppState {
        var s = Fx.base()
        s.addPurchase("p1", "2026-03-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        return s
    }

    @Test func sayimdanSonrakiAlimSayimiBozmaz() {
        var s = durum()
        s.counts.append(StockCount(id: "c", date: "2026-03-10", item: .material(Fx.koliId),
                                   countedQty: 100, unit: .adet))
        s.addPurchase("p2", "2026-03-20", .material(Fx.koliId), qty: 50, paid: tl(500))
        let e = Engine(s)
        // Sayım günü stok doğru sayıldı; sonradan 50 koli daha geldi → 150 adet, 1.500 TL
        #expect(e.qty(.material(Fx.koliId)) == 150)
        #expect(e.balance(.material(Fx.koliId)).value == tl(1_500))
        // Ortada fire yok
        #expect(e.companyMonth("2026-03").expenseBreakdown[.stokKaybi] == nil)
    }

    @Test func sayimdakiGercekEksikSonrakiAlimlaKarismaz() {
        var s = durum()
        s.counts.append(StockCount(id: "c", date: "2026-03-10", item: .material(Fx.koliId),
                                   countedQty: 95, unit: .adet))
        s.addPurchase("p2", "2026-03-20", .material(Fx.koliId), qty: 50, paid: tl(500))
        let e = Engine(s)
        // 5 koli eksik çıktı (50 TL fire), sonra 50 koli geldi → 145 adet
        #expect(e.qty(.material(Fx.koliId)) == 145)
        #expect(e.companyMonth("2026-03").expenseBreakdown[.stokKaybi] == tl(50))
    }

    @Test func ayniAydaIkiSayimTarihSirasiylaUygulanir() {
        var s = Fx.base()
        s.addPurchase("p1", "2026-03-01", .material(Fx.koliId), qty: 200, paid: tl(2_000))
        s.counts.append(StockCount(id: "c1", date: "2026-03-05", item: .material(Fx.koliId),
                                   countedQty: 100, unit: .adet))
        s.addPurchase("p2", "2026-03-10", .material(Fx.koliId), qty: 50, paid: tl(500))
        s.counts.append(StockCount(id: "c2", date: "2026-03-20", item: .material(Fx.koliId),
                                   countedQty: 120, unit: .adet))
        let e = Engine(s)
        // 5 Mart: 200 yerine 100 sayıldı → 100 eksik (1.000 TL)
        // 20 Mart: 150 beklenirken 120 sayıldı → 30 eksik (300 TL)
        #expect(e.qty(.material(Fx.koliId)) == 120)
        #expect(e.companyMonth("2026-03").expenseBreakdown[.stokKaybi] == tl(1_300))
    }

    /// Sayımın kimliği (id) sıralamayı belirlememeli: aynı veriden aynı sonuç
    @Test func sayimSirasiKayitIdsindenBagimsiz() {
        func sonuc(_ id1: Id, _ id2: Id) -> (Double, Kurus?) {
            var s = Fx.base()
            s.addPurchase("p1", "2026-03-01", .material(Fx.koliId), qty: 200, paid: tl(2_000))
            s.counts.append(StockCount(id: id1, date: "2026-03-05", item: .material(Fx.koliId),
                                       countedQty: 100, unit: .adet))
            s.counts.append(StockCount(id: id2, date: "2026-03-20", item: .material(Fx.koliId),
                                       countedQty: 120, unit: .adet))
            let e = Engine(s)
            return (e.qty(.material(Fx.koliId)),
                    e.companyMonth("2026-03").expenseBreakdown[.stokKaybi])
        }
        let a = sonuc("aaa", "zzz")
        let b = sonuc("zzz", "aaa")
        #expect(a.0 == b.0)
        #expect(a.1 == b.1)
        #expect(a.0 == 120)
    }

    // MARK: Koli: stoktan düşme ve maliyet bayrakları ayrı

    private func koliDurumu(stoktanDus: Bool, maliyeteEkle: Bool) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        let i = s.materials.firstIndex { $0.id == Fx.koliId }!
        s.materials[i].perOrder = true
        s.addPurchase("k", "2026-09-01", .material(Fx.koliId), qty: 1_000, paid: tl(10_000))
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))],
                                recipe: [RecipeLine(id: "r", materialId: Fx.koliId, qty: 1, unit: .adet,
                                                    consumesStock: stoktanDus, addsCost: maliyeteEkle)])
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: tl(6_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 10, bigOrderCount: 0))
        return s
    }

    private func kanal(_ e: Engine) -> ChannelMonthResult {
        e.companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
    }

    @Test func koliMaliyeteGirmiyorsaStoktanDuserAmaGiderYazilmaz() {
        let e = Engine(koliDurumu(stoktanDus: true, maliyeteEkle: false))
        #expect(e.qty(.material(Fx.koliId)) == 1_000 - 10)
        #expect(kanal(e).packagingCost == 0)
    }

    @Test func koliStoktanDusmuyorsaStokAyniKalirGiderYazilir() {
        let e = Engine(koliDurumu(stoktanDus: false, maliyeteEkle: true))
        #expect(e.qty(.material(Fx.koliId)) == 1_000)
        #expect(kanal(e).packagingCost == tl(100))   // 10 koli × 10 TL
    }

    @Test func ikisiDeAcikOlanKoliHemDuserHemGiderOlur() {
        let e = Engine(koliDurumu(stoktanDus: true, maliyeteEkle: true))
        #expect(e.qty(.material(Fx.koliId)) == 990)
        #expect(kanal(e).packagingCost == tl(100))
    }
}

/// "Aylık gerçek tutarı ben gireceğim" denen kesintiler
@Suite("Denetim 3: aylık girilen kesintiler")
struct MonthlyEnteredFeeTests {

    /// Trendyol komisyonu aylık girilecek; fiyat 1.000 TL, ürün 100 TL, KDV yok
    private func durum(agustosKomisyonu: Kurus?) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))])
        s.products[1].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.channels[0].commissionPct = 0
        s.channels[0].setRates(ChannelRates(
            from: "2026-01-01", commissionPct: 0,
            extras: [ChannelExtraFee(label: "Komisyon", basis: .elleAylik)]))
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: tl(10_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-08", channelId: ChannelIds.trendyol,
                                            orderCount: 10, commissionActual: agustosKomisyonu))
        return s
    }

    @Test func gecmisAyinGercekTutarindanOranTahminEdilir() {
        let e = Engine(durum(agustosKomisyonu: tl(2_000)))
        let u = e.unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                   on: "2026-09-15")!
        // 2.000 ÷ 10.000 = %20 → 1.000 TL siparişte 200 TL komisyon
        #expect(u.channelFees == tl(200))
        #expect(u.contribution == tl(700))
        #expect(u.estimatedFees == ["Komisyon"])
        #expect(u.missingFees.isEmpty)
        let t = e.adTargets(keepPerOrder: nil, on: "2026-09-15").first { $0.productId == Fx.serumId }!
        #expect(t.beforeAds == tl(700))
        #expect(t.missingFees.contains { $0.contains("tahmin") })
    }

    @Test func hicTutarGirilmemisseSifirSayilmazAcikcaSoylenir() {
        let e = Engine(durum(agustosKomisyonu: nil))
        let u = e.unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                   on: "2026-09-15")!
        #expect(u.channelFees == 0)
        #expect(u.missingFees == ["Komisyon"])
        // Hedef listesi ve "yaklaşık" işareti bunu gösterir
        #expect(e.missingForTarget(month: "2026-09", today: "2026-09-15")
            .contains { $0.kind == .kanalKesintisi && $0.title.contains("komisyon tutarı hiç girilmemiş") })
        #expect(e.eksikKanalKesintisiVar(month: "2026-09"))
        #expect(e.adTargets(keepPerOrder: nil, on: "2026-09-15")
            .first { $0.productId == Fx.serumId }!.missingFees.contains { $0.contains("girilmemiş") })
    }

    @Test func aylikTutarGirilmemisAyEksikBilgiIleIsaretlenir() {
        var s = durum(agustosKomisyonu: tl(2_000))
        s.sales.append(SalesEntry(id: "s2", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 5, grossSales: tl(5_000)))
        let e = Engine(s)
        let eylul = e.companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(eylul.commission.amount == 0)
        #expect(eylul.eksikBilgiler.contains { $0.contains("aylık tutar girilmemiş") })
        // Ağustos'ta tutar girilmiş: o ay eksik değil
        let agustos = e.companyMonth("2026-08").channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(agustos.commission.amount == tl(2_000))
        #expect(agustos.eksikBilgiler.isEmpty)
    }

    @Test func kargoAylikGiriliyorsaSiparisBasinaTahminEdilir() {
        var s = durum(agustosKomisyonu: nil)
        s.channels[0].setRates(ChannelRates(
            from: "2026-01-01", commissionPct: 0,
            extras: [ChannelExtraFee(label: "Kargo", basis: .elleAylik)]))
        s.channelMonths[0].shippingActual = tl(600)     // 10 siparişte 600 TL → 60 TL/sipariş
        let u = Engine(s).unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                           on: "2026-09-15")!
        #expect(u.channelFees == tl(60))
        #expect(u.perOrderFees == tl(60))
        #expect(u.contribution == tl(840))
    }
}

/// Kasadan çıkan para: KDV dahil gerçekten ödenen tutar
@Suite("Denetim 3: nakit çıkışı")
struct CashOutTests {

    @Test func kdvHaricGirilenGiderinKdvsiDeKasadanCikar() {
        var s = Fx.base()
        var g = Expense(id: "e", date: "2026-09-05", name: "Ajans", amount: tl(1_000),
                        category: .sabit)
        g.vatRate = .yirmi
        g.vatIncluded = false
        s.expenses.append(g)
        let r = Engine(s).companyMonth("2026-09")
        // 1.000 + %20 KDV = 1.200 TL ödenir; kâra 1.000 TL gider yazılır
        #expect(r.nakitCikisi == tl(1_200))
        #expect(r.toplamGider == tl(1_000))
        #expect(r.giderKdv == tl(200))
    }

    @Test func platformunKestigiKdvDeNakitCikisidir() {
        var s = Fx.base()
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(1_200),
                                  vatRate: .yirmi, vatIncluded: true))
        let r = Engine(s).companyMonth("2026-09")
        // Komisyon 1.200 × %20 = 240 TL kesilir (200 gider + 40 indirilecek KDV)
        let c = r.channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(c.commission.amount == tl(200))
        #expect(c.feeVat == tl(40))
        #expect(r.nakitCikisi == tl(240))
    }
}

/// Geçmiş ay, çifte kesinti, arşiv, ondalık artık ve uyarılar
@Suite("Denetim 3: karışık")
struct AuditRound3MiscTests {

    @Test func gecmisAyinHedefiOAyinFiyatiylaHesaplanir() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))])
        s.products[1].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[1].setPrice(tl(2_000), channelId: ChannelIds.trendyol, from: "2026-09-01")
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: tl(10_000)))
        let e = Engine(s)
        // Ağustos hedefi ağustosun fiyatıyla: zam sonradan yapıldı
        let agustos = e.blendedAdTarget(month: "2026-08", keepPerOrder: nil, today: "2026-09-15")!
        #expect(agustos.orderValue == tl(1_000))
        // Eylül hedefi yeni fiyatla
        let eylul = e.blendedAdTarget(month: "2026-09", keepPerOrder: nil, today: "2026-09-15")!
        #expect(eylul.orderValue == tl(2_000))
    }

    @Test func elleGirilenKomisyonAyniAdliEkKesintiyiDeDegistirir() {
        var s = Fx.base()
        s.channels[0].commissionPct = 0
        s.channels[0].setRates(ChannelRates(
            from: "2026-01-01", commissionPct: 0,
            extras: [ChannelExtraFee(label: "Komisyon", basis: .siparisBasi, value: Double(tl(50)))]))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                            orderCount: 10, commissionActual: tl(300)))
        let c = Engine(s).companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
        // Gerçek komisyon 300 TL girildi: sipariş başı 50 TL'lik komisyon ikinci kez eklenmez
        #expect(c.commission.amount == tl(300))
        #expect(c.otherDeduction.amount == 0)
    }

    @Test func arsivlenenKanalGecmisiDegistirmezGelecegeUcretYazmaz() {
        var s = Fx.base()
        s.channels[0].platformFeeMonthly = tl(500)
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(1_000)))
        func ucret(_ ay: MonthKey, _ durum: AppState) -> Kurus {
            Engine(durum).companyMonth(ay).channels
                .first { $0.channelId == ChannelIds.trendyol }?.otherDeduction.amount ?? 0
        }
        #expect(ucret("2026-08", s) == tl(500))
        #expect(ucret("2026-10", s) == tl(500))
        s.channels[0].archived = true
        #expect(ucret("2026-08", s) == tl(500))   // geçmiş değişmedi
        #expect(ucret("2026-10", s) == 0)         // kapandıktan sonra ücret yok
    }

    @Test func donemToplamiEksikBilgiUyarisiniTasir() {
        var s = Fx.base()
        s.channels[0].setRates(ChannelRates(from: "2026-01-01", commissionPct: 0,
                                            unknownFields: ["komisyon"]))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(1_000)))
        let toplam = Engine(s).companyTotals(from: "2026-08", to: "2026-09")
        #expect(toplam.channels.first { $0.channelId == ChannelIds.trendyol }?
            .eksikBilgiler.contains("komisyon") == true)
    }

    @Test func ondalikArtikStoguEksiyeDusurmez() {
        var s = Fx.base()
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                recipe: [RecipeLine(id: "r", materialId: Fx.dolguId,
                                                    qty: 0.7, unit: .gram)])
        s.addPurchase("d", "2026-09-01", .material(Fx.dolguId), qty: 63, unit: .gram, paid: tl(630))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 90, grossSales: tl(9_000)))
        let e = Engine(s)
        // 0,7 × 90 = 63: tam biter, eksiye düşmez
        #expect(e.qty(.material(Fx.dolguId)) == 0)
        #expect(!e.balance(.material(Fx.dolguId)).wentNegative)
        #expect(!Integrity.check(s).contains {
            $0.message.contains("Dolgu") && $0.message.contains("eksiye düştü")
        })
    }

    @Test func gecmisteEksiyeDusupDuzelenStokUyariVerir() {
        var s = Fx.base()
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        s.addPurchase("u", "2026-09-01", .product(Fx.sampuanId), qty: 50, paid: tl(5_000))
        let e = Engine(s)
        #expect(e.qty(.product(Fx.sampuanId)) == 40)
        #expect(Integrity.check(s).contains { $0.message.contains("bir dönem eksiye düştü") })
    }

    @Test func maliyetsizAcilisStoguVeBozukBirimUyarilir() {
        var s = Fx.base()
        s.materials[0].openingQty = 100          // koli, maliyet girilmemiş
        s.materials[0].openingDate = "2026-08-01"
        s.addPurchase("p", "2026-09-01", .material(Fx.etiketId), qty: 2, unit: .paket, paid: tl(100))
        s.materials[2].packSizesRaw = [:]        // "paket" karşılığı silindi
        let sorunlar = Integrity.check(s)
        #expect(sorunlar.contains { $0.message.contains("açılış stoğu birim maliyeti girilmeden") })
        #expect(sorunlar.contains { $0.severity == .bozuk && $0.message.contains("bu birimin karşılığı yok") })
    }
}

/// Reklam hedefi: gerçekleşen fiyat ve reklam dışı satışa bağlı giderler
@Suite("Denetim 3: reklam hedefi gerçeğe yakın")
struct AdTargetRealismTests {

    /// Liste 1.000 TL; ağustosta %20 indirimle 800 TL'ye satılmış. KDV yok.
    private func durum(indirim: Kurus, influencer: Kurus = 0) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))])
        s.products[1].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.channels[0].commissionPct = 10
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: tl(10_000),
                                  discount: indirim))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-08",
                                            channelId: ChannelIds.trendyol, orderCount: 10))
        if influencer > 0 {
            var g = Expense(id: "inf", date: "2026-08-10", name: "İş birliği", amount: influencer,
                            category: .influencer)
            g.behavior = .satisaBagli
            s.expenses.append(g)
        }
        return s
    }

    @Test func indirimsizHedefListeFiyatiyla() {
        let k = Engine(durum(indirim: 0)).blendedAdTarget(month: "2026-09", keepPerOrder: nil,
                                                          today: "2026-09-15")!
        // 1.000 − %10 komisyon (100) − 100 ürün = 800
        #expect(k.orderValue == tl(1_000))
        #expect(k.beforeAds == tl(800))
    }

    @Test func gecmisAydakiIndirimHedefeYansir() {
        let k = Engine(durum(indirim: tl(2_000))).blendedAdTarget(month: "2026-09", keepPerOrder: nil,
                                                                  today: "2026-09-15")!
        // Gerçekte 800 TL'ye satılmış: 800 − 80 komisyon − 100 ürün = 620
        #expect(k.orderValue == tl(800))
        #expect(k.beforeAds == tl(620))
        #expect(abs(k.breakevenROAS! - 800.0 / 620) < 1e-9)
    }

    @Test func reklamDisiSatisaBagliGiderSiparisBasinaDuser() {
        let e = Engine(durum(indirim: 0, influencer: tl(500)))
        let k = e.blendedAdTarget(month: "2026-09", keepPerOrder: nil, today: "2026-09-15")!
        // 500 TL influencer ÷ 10 sipariş = 50 TL/sipariş → 800 − 50 = 750
        #expect(k.beforeAds == tl(750))
        // Başa baş hesabı da aynı rakamı kullanır: geçmiş ayın gerçek katkısı
        // (10.000 − 1.000 komisyon − 1.000 ürün − 500 influencer) ÷ 10 sipariş = 750
        let plan = e.plan(month: "2026-09", today: "2026-09-15")
        #expect(abs(plan.contributionPerOrder - Double(tl(750))) < 1)
        #expect(plan.contributionPerOrder == Double(k.beforeAds))
    }
}

/// Denetimde bulunan küçük ama gerçek hatalar
@Suite("Denetim 3: küçük hatalar")
struct AuditRound3SmallTests {

    @Test func bugunkuMaliyetIleriTarihliAlimiIcermez() {
        var s = Fx.base()
        s.addPurchase("p1", "2026-09-01", .product(Fx.sampuanId), qty: 100, paid: tl(10_000))
        s.addPurchase("p2", "2026-12-01", .product(Fx.sampuanId), qty: 100, paid: tl(30_000))
        // Bugün (2026-09) maliyeti 100 TL; aralıktaki alım bugünü etkilemez
        #expect(Engine(s).cost(of: Fx.sampuanId).intrinsic == tl(100))
        #expect(Engine(s).cost(of: Fx.sampuanId, asOf: "2026-12-31").intrinsic == tl(200))
    }

    @Test func fireDegerlemesiEksiStoktaSismez() {
        var s = Fx.base()
        s.addPurchase("p", "2026-09-01", .material(Fx.koliId), qty: 10, paid: tl(100))
        // Elde 10 koli varken 12 koli fire: 10 adedi değerlenir, olmayan 2 adet şişirmez
        s.adjustments.append(StockAdjustment(id: "a", date: "2026-09-10",
                                             item: .material(Fx.koliId), qty: 12, unit: .adet,
                                             isIncrease: false, reason: .kirik))
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.expenseBreakdown[.stokKaybi] == tl(120))   // 12 × 10 TL
    }

    @Test func urununKendiKdvOraniKullanilir() {
        var s = Fx.base()
        s.settings.defaultVatRate = .yirmi
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))])
        s.products[1].setPrice(tl(1_100), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.channels[0].commissionPct = 0
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 1, grossSales: tl(1_100),
                                  vatRate: .on, vatIncluded: true))
        let u = Engine(s).unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                           on: "2026-09-15")!
        // Ürün %10 KDV'li satılıyor: 1.100 ÷ 1,10 = 1.000 net (varsayılan %20 değil)
        #expect(u.netRevenue == tl(1_000))
    }

    @Test func netSatisArtiKdvKdvDahilTutariVerir() {
        var s = Fx.base()
        for (i, tutar) in [tl(333.33), tl(777.77), tl(1_234.56)].enumerated() {
            s.sales.append(SalesEntry(id: "s\(i)", month: "2026-09", channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 1, grossSales: tutar,
                                      discount: tl(11.11), returnsAmount: tl(7.77),
                                      vatRate: .yirmi, vatIncluded: true))
        }
        let c = Engine(s).companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(c.netSales + c.outputVat == c.netSalesIncVat)
        #expect(c.grossSales - c.discount - c.returnsAmount == c.netSales)
    }

    @Test func elleGirilenAylikReklamTutariKasadanCikar() {
        var s = Fx.base()
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(1_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                            adsActual: tl(5_000)))
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.expenseBreakdown[.reklam] == tl(5_000))
        // 5.000 reklam + %20 komisyon (200 TL) kasadan çıkar
        #expect(r.nakitCikisi == tl(5_200))
    }
}

/// Veri dosyası okunamazsa hiçbir şey kaybolmamalı
@Suite("Denetim 3: bozuk veri dosyası", .serialized)
@MainActor
struct CorruptFileTests {

    @Test func bozukDosyaninUstuneOrnekVeriYazilmaz() throws {
        let kok = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirissa-bozuk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: kok) }
        let dosya = kok.appendingPathComponent("veri.json")
        let bozuk = Data("{ yarım kalmış".utf8)
        try bozuk.write(to: dosya)

        let st = AppStore(file: FileStore(url: dosya), saveDelay: .zero)
        #expect(st.loadError?.contains("okunamadı") == true)
        st.flush()
        // Asıl dosya olduğu gibi duruyor, bir kopyası da kenara alındı
        #expect(try Data(contentsOf: dosya) == bozuk)
        let kopyalar = try FileManager.default.contentsOfDirectory(atPath: kok.path)
            .filter { $0.hasPrefix("bozuk-") }
        #expect(kopyalar.count == 1)
    }

    @Test func dosyaYoksaBaslangicVerisiYazilir() throws {
        let kok = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirissa-yeni-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: kok) }
        let dosya = kok.appendingPathComponent("veri.json")
        let st = AppStore(file: FileStore(url: dosya), saveDelay: .zero)
        #expect(st.loadError == nil)
        st.flush()
        #expect(FileManager.default.fileExists(atPath: dosya.path))
    }
}

/// Yıllık toplam: henüz gelmemiş aylar sayılmaz
@Suite("Denetim 3: yıllık toplam")
struct YearToDateTests {

    @Test func gelecekAylarinDuzenliGideriYillikToplamaGirmez() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "k", date: "2026-01-01", name: "Kira", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik))
        let e = Engine(s)
        // Bugün 17 Eylül: Ocak–Eylül = 9 ay × 1.000 TL
        #expect(e.year(2026, today: "2026-09-17").toplamGider == tl(9_000))
        #expect(e.periodTotals(from: "2026-01", to: "2026-12", today: "2026-09-17").toplamGider == tl(9_000))
        // Geçmiş yıl tam 12 ay
        #expect(e.year(2025, today: "2026-09-17").toplamGider == 0)
        #expect(e.periodTotals(from: "2026-01", to: "2026-12", today: "2027-02-01").toplamGider == tl(12_000))
    }
}

/// Aylık girilen kesintiler: her etiket kendi alanına, tahmin ayarın yerine geçer
@Suite("Denetim 3 tur 2: aylık kesinti eşleştirmesi")
struct MonthlyFeeMappingTests {

    private func durum(_ extras: [ChannelExtraFee], komisyonYuzde: Double = 0,
                       ay: ChannelMonth) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))])
        s.products[1].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.channels[0].commissionPct = komisyonYuzde
        s.channels[0].setRates(ChannelRates(from: "2026-01-01", commissionPct: komisyonYuzde,
                                            extras: extras))
        s.sales.append(SalesEntry(id: "s", month: ay.month, channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: tl(10_000)))
        s.channelMonths.append(ay)
        return s
    }

    @Test func girilenKomisyonHizmetBedeliniSilmez() {
        let s = durum([ChannelExtraFee(label: "Hizmet bedeli", basis: .siparisBasi, value: Double(tl(5)))],
                      ay: ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                       orderCount: 10, commissionActual: tl(1_000)))
        let c = Engine(s).companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(c.commission.amount == tl(1_000))
        #expect(c.otherDeduction.amount == tl(50))     // 10 sipariş × 5 TL hizmet kalır
    }

    @Test func tahminAyardakiOraninYerineGecerUstuneEklenmez() {
        // Ayarda %5 komisyon da var; ama komisyon aylık giriliyor ve ağustosta %20 çıkmış
        let s = durum([ChannelExtraFee(label: "Komisyon", basis: .elleAylik)], komisyonYuzde: 5,
                      ay: ChannelMonth(id: "cm", month: "2026-08", channelId: ChannelIds.trendyol,
                                       orderCount: 10, commissionActual: tl(2_000)))
        let u = Engine(s).unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                           on: "2026-09-15")!
        #expect(u.channelFees == tl(200))    // %25 değil, %20
    }

    @Test func sifirGirilenTutarGirilmisSayilir() {
        let s = durum([ChannelExtraFee(label: "Kargo", basis: .elleAylik)],
                      ay: ChannelMonth(id: "cm", month: "2026-08", channelId: ChannelIds.trendyol,
                                       orderCount: 10, shippingActual: 0))
        let u = Engine(s).unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                           on: "2026-09-15")!
        #expect(u.missingFees.isEmpty)
        #expect(u.estimatedFees == ["Kargo"])
        #expect(u.channelFees == 0)
    }

    @Test func siparisSayisiSifirsaAdettenHesaplanir() {
        let s = durum([ChannelExtraFee(label: "Kargo", basis: .elleAylik)],
                      ay: ChannelMonth(id: "cm", month: "2026-08", channelId: ChannelIds.trendyol,
                                       orderCount: 0, shippingActual: tl(500)))
        let u = Engine(s).unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                           on: "2026-09-15")!
        // 500 TL ÷ 10 ürün (sipariş) = 50 TL, yüzdeye dönüşmez
        #expect(u.perOrderFees == tl(50))
    }

    @Test func buyukHarfliEtiketDeEslesir() {
        let s = durum([ChannelExtraFee(label: "KOMISYON", basis: .elleAylik)],
                      ay: ChannelMonth(id: "cm", month: "2026-08", channelId: ChannelIds.trendyol,
                                       orderCount: 10, commissionActual: tl(1_500)))
        let u = Engine(s).unitContribution(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                           on: "2026-09-15")!
        #expect(u.channelFees == tl(150))
    }

    @Test func aylikReklamKanalKesintisiEksigiSayilmaz() {
        let s = durum([ChannelExtraFee(label: "Kanal reklam gideri", basis: .elleAylik)],
                      ay: ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                       orderCount: 10))
        let c = Engine(s).companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(!c.eksikBilgiler.contains { $0.contains("reklam") })
    }
}

@Suite("Denetim 3 tur 2: maliyet kalemi yeniden girilince")
struct CostLineReentryTests {
    @Test func hepsiSilinipYenidenGirilenMaliyetGecmisiDegistirmez() {
        var p = Fx.sampuan()
        p.applyCostLines([CostLine(id: "a", label: "Üretim", amount: tl(100))], today: "2026-01-10")
        p.applyCostLines([], today: "2026-05-01")                       // hepsi kaldırıldı
        p.applyCostLines([CostLine(id: "b", label: "Üretim", amount: tl(160))], today: "2026-09-01")
        let toplam: (DateKey) -> Kurus = { d in p.costLines(on: d).reduce(0) { $0 + $1.amount } }
        #expect(toplam("2026-03-15") == tl(100))   // eski dönem eski maliyetle
        #expect(toplam("2026-06-15") == 0)         // kaldırıldığı dönem
        #expect(toplam("2026-09-15") == tl(160))   // yeni maliyet bugünden
    }
}

/// Stok tahminleri ve dışa aktarma
@Suite("Denetim 3 tur 2: stok tahmini ve CSV")
struct ProjectionAndCSVTests {

    @Test func stogaDonenIadeTuketimOraniniSisirmez() {
        var s = Fx.base()
        s.addPurchase("u", "2026-07-01", .product(Fx.sampuanId), qty: 1_000, paid: tl(100_000))
        // Eylül: 100 satış, 20 iade stoğa döndü → net 80 ürün, 80 sipariş
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 100, grossSales: tl(100_000),
                                  returnsAmount: tl(20_000), returnsQty: 20, returnsRestock: true))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 80))
        let r = Engine(s).consumptionRate(.product(Fx.sampuanId), endingAt: "2026-09")
        #expect(abs(r.perOrder - 1.0) < 1e-9)       // 80 ürün ÷ 80 sipariş
    }

    @Test func yeniUrununAylikHiziOncekiAylarlaSulanmaz() {
        var s = Fx.base()
        s.addPurchase("u", "2026-09-01", .product(Fx.sampuanId), qty: 1_000, paid: tl(100_000))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 90, grossSales: tl(90_000)))
        let r = Engine(s).consumptionRate(.product(Fx.sampuanId), endingAt: "2026-09")
        // Ürün eylülde başladı: ayda 90, üç aya bölünüp 30 değil
        #expect(abs(r.perMonth - 90) < 1e-9)
    }

    @Test func kayanNoktaArtigiBirSiparisEksikSaymaz() {
        var s = Fx.base()
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                recipe: [RecipeLine(id: "r", materialId: Fx.dolguId, qty: 7, unit: .gram)])
        s.addPurchase("d", "2026-09-01", .material(Fx.dolguId), qty: 800, unit: .gram, paid: tl(80))
        // 100 ürün × 7 g = 700 g, 600 siparişte → sipariş başı 7/6 g; kalan 100 g → 100 ÷ (7/6) = 85,7 → 85
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 100, grossSales: tl(10_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 600))
        let e = Engine(s)
        #expect(e.ordersLeft(.material(Fx.dolguId), endingAt: "2026-09") == 85)
        // Tam bölünen durum: kalan 35 ve sipariş başı 7/6 → 30 (29 değil)
        var s2 = s
        s2.purchases[0].qty = 735
        #expect(Engine(s2).ordersLeft(.material(Fx.dolguId), endingAt: "2026-09") == 30)
    }

    @Test func bosIcSetYapilabilirSayisiniSifirlamaz() {
        var s = Fx.base()
        s.addPurchase("u", "2026-09-01", .product(Fx.sampuanId), qty: 10, paid: tl(1_000))
        s.addPurchase("r", "2026-09-01", .product(Fx.serumId), qty: 10, paid: tl(1_000))
        s.products.append(Product(id: "bos", name: "Boş set", isBundle: true))
        if let i = s.products.firstIndex(where: { $0.id == Fx.setId }) {
            s.products[i].components.append(BundleComponent(productId: "bos", qty: 1))
        }
        #expect(Engine(s).buildable(Fx.setId) == 10)
    }

    @Test func csvGelecekAylariYazmazOdenenTutarKdvDahil() {
        var s = Fx.base()
        var g = Expense(id: "k", date: "2026-01-01", name: "Kira", amount: tl(1_000),
                        category: .sabit, recurrence: .aylik)
        g.vatRate = .yirmi
        g.vatIncluded = false
        s.expenses.append(g)
        let dosyalar = CSVExport.all(Engine(s), from: "2026-01", to: "2026-12", today: "2026-09-17")
        let ozet = dosyalar.first { $0.name == "aylik-ozet.csv" }!.contents
        #expect(ozet.contains("2026-09"))
        #expect(!ozet.contains("2026-10"))
        let giderler = dosyalar.first { $0.name == "giderler.csv" }!.contents
        #expect(giderler.contains("1200,00"))        // 1.000 + %20 KDV ödendi
    }

    @Test func csvBicimleri() {
        #expect(CSVExport.num(-0.001, digits: 1) == "0,0")
        #expect(CSVExport.adet(0.5) == "0,500")
        #expect(CSVExport.adet(12) == "12")
        #expect(CSVExport.esc("a\r\nb").hasPrefix("\""))
        #expect(CSVExport.birimMaliyet(0.3) == "0,0030")
    }
}

/// Tek tek geçerli görünen ama birlikte yanlış sonuç veren girişler
@Suite("Denetim 3 tur 2: giriş tutarlılığı")
struct InputConsistencyTests {

    private func mesajlar(_ s: AppState) -> [String] { Integrity.check(s).map(\.message) }

    @Test func kendiniIcerenSetteHedefHesabiCokmez() {
        var s = Fx.base()
        let i = s.products.firstIndex { $0.id == Fx.setId }!
        s.products[i].components.append(BundleComponent(productId: Fx.setId, qty: 1))
        s.products[i].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.sales.append(SalesEntry(id: "s", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.setId, qty: 1, grossSales: tl(1_000)))
        let e = Engine(s)
        _ = e.missingForTarget(month: "2026-09", today: "2026-09-15")
        _ = Integrity.check(s)
    }

    @Test func adetsizSatisVeTutarsizSatisUyarilir() {
        var s = Fx.base()
        s.sales.append(SalesEntry(id: "a", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 0, grossSales: tl(5_000)))
        s.sales.append(SalesEntry(id: "b", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 10, grossSales: 0))
        let m = mesajlar(s)
        #expect(m.contains { $0.contains("adet girilmemiş") })
        #expect(m.contains { $0.contains("tutar 0") })
    }

    @Test func siparisSayisiUrundenFazlaysaVeEksiTutarUyarilir() {
        var s = Fx.base()
        s.sales.append(SalesEntry(id: "a", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 100, grossSales: tl(10_000)))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                            orderCount: 150, commissionActual: -tl(500),
                                            bigOrderCount: 200))
        let m = mesajlar(s)
        #expect(m.contains { $0.contains("satılan üründen") })
        #expect(m.contains { $0.contains("3+ ürünlü sipariş") })
        #expect(m.contains { $0.contains("eksi tutar") })
    }

    @Test func miktariSifirReceteReceteSayilmaz() {
        var s = Fx.base()
        s.products[1].recipe = [RecipeLine(id: "r", materialId: Fx.koliId, qty: 0, unit: .adet)]
        s.sales.append(SalesEntry(id: "a", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: 5, grossSales: tl(500)))
        #expect(mesajlar(s).contains { $0.contains("Serum satılıyor ama ambalaj reçetesi yok") })
    }

    @Test func seteYapilanAlimUyarilir() {
        var s = Fx.base()
        s.addPurchase("p", "2026-09-01", .product(Fx.setId), qty: 10, paid: tl(1_000))
        #expect(mesajlar(s).contains { $0.contains("bir set ama alım") })
    }
}
