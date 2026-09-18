import Testing
import Foundation
@testable import MirissaCore

/// 4. denetim turunda bulunan hataların düzeltmeleri. Beklenen rakamlar elle hesaplandı.
@Suite("Denetim 4: planlama ve vergi")
struct AuditRound4PlanTests {
    private func karliUcAy() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        for ay in ["2026-01", "2026-02", "2026-03"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        }
        s.settings.ek.vergiOrani = 20
        s.settings.ek.kasaBakiye = tl(100_000)
        s.settings.ek.kasaTarih = "2026-03-10"
        return s
    }

    @Test func geciciVergiNakitTahmindeBirKez() throws {
        let t = try #require(Engine(karliUcAy()).nakitTahmini(bugun: "2026-03-10"))
        let v = t.bilinenKalemler.filter { $0.id.hasPrefix("vergi:") }
        // 1. çeyrek: 30.000 kâr × %20 = 6.000, son gün 17 Mayıs — bir kez
        #expect(v.count == 1)
        #expect(v.first?.tutar == -tl(6_000))
        #expect(v.first?.gun == "2026-05-17")
    }

    @Test func geciciVergiHatirlatmasiBirKez() {
        let h = Engine(karliUcAy()).hatirlatmalar(bugun: "2026-03-20").filter { $0.id.hasPrefix("vergi") }
        #expect(h.count == 1)
    }

    /// Kanal seçilmeden girilen reklam, reklam hedefinde iki kez düşülmez
    @Test func ortakReklamReklamHedefindeIkiKezDusulmez() throws {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[0].costLines = [CostLine(id: "c", label: "Üretim", amount: tl(200))]
        s.sales.append(SalesEntry(id: "a", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        s.expenses.append(Expense(id: "meta", date: "2026-08-05", name: "Meta", amount: tl(3_000),
                                  category: .reklam, recurrence: .tek))
        let k = try #require(Engine(s).blendedAdTarget(month: "2026-09", keepPerOrder: nil, today: "2026-09-16"))
        // 1.000 fiyat − 200 maliyet = 800 reklamdan önce kalan; başa baş ROAS 1.000 / 800
        #expect(k.beforeAds == tl(800))
        #expect(abs((k.breakevenROAS ?? 0) - 1.25) < 0.001)
    }
}

@Suite("Denetim 4: geçmiş aylar değişmez")
@MainActor
struct AuditRound4GecmisTests {
    /// Serum: 10 TL'lik patpat reçetede; set kutusu 50 TL
    private func serumlu() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.addPurchase("pp", "2026-01-01", .material(Fx.patpatId), qty: 100, paid: tl(1_000))
        s.addPurchase("sk", "2026-01-01", .material(Fx.setKutuId), qty: 100, paid: tl(5_000))
        s.addSale("ocak", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 10, gross: tl(5_000))
        return s
    }

    @Test func receteDegisinceGecmisAyDegismez() {
        let st = AppStore.inMemory(serumlu())
        let once = st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost
        #expect(once == tl(100))                                   // 10 × 10 TL patpat
        var p = st.state.product(Fx.serumId)!
        p.recipe.append(RecipeLine(id: "yeni", materialId: Fx.setKutuId, qty: 1, unit: .adet))
        st.updateProduct(p)
        // Ocak eski reçeteyle kalır; set kutusu ocakta stoktan düşmez
        #expect(st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost == once)
        #expect(st.engine.qty(.material(Fx.setKutuId)) == 100)
        #expect(st.state.product(Fx.serumId)!.eskiReceteler?.count == 1)
        // Bu ayın satışı yeni reçeteyle: 10 + 50
        st.addSale(SalesEntry(id: "bu", month: Dates.currentMonth(), channelId: ChannelIds.trendyol,
                              productId: Fx.serumId, qty: 1, grossSales: tl(500)))
        #expect(st.engine.channelResult(channelId: ChannelIds.trendyol, month: Dates.currentMonth())
            .packagingCost == tl(60))
    }

    @Test func satisiOlmayanUrununRecetesiBastanDuzelir() {
        let st = AppStore.inMemory(serumlu())
        var p = st.state.product(Fx.sampuanId)!
        p.recipe.removeAll()
        st.updateProduct(p)
        #expect(st.state.product(Fx.sampuanId)!.eskiReceteler == nil)
    }

    @Test func kesintiKdvAyariGecmisiDegistirmez() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].feeVatRate = .yok
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("m", "2026-03", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        let st = AppStore.inMemory(s)
        let once = st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-03")
        var ch = st.state.channel(ChannelIds.trendyol)!
        ch.feeVatRate = .yirmi
        ch.feesIncludeVat = true
        st.updateChannel(ch)
        let sonra = st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-03")
        #expect(sonra.commission.amount == once.commission.amount)
        #expect(sonra.feeVat == once.feeVat)
        #expect(st.state.channel(ChannelIds.trendyol)!.kesintiKdv(on: Dates.today()).oran == .yirmi)
        #expect(st.state.channel(ChannelIds.trendyol)!.kesintiKdv(on: "2026-03-31").oran == .yok)
    }

    @Test func stopajDonemleri() {
        var c = Fx.channels()[0]
        // Kanal kaydı gibi: ekrandaki ayarlar yeni kanala yazılır, dönemler geçmişi koruyarak işlenir
        func kaydet(_ degistir: (inout Channel) -> Void, _ ay: MonthKey) {
            var y = c
            degistir(&y)
            y.stopajDonemleri = StopajDonemi.guncelle(eski: c, yeni: y, buAy: ay)
            c = y
        }
        // Kapalıyken açılır: bu aydan başlar
        kaydet({ $0.stopajPct = 1; $0.stopajBaslangic = "2026-09-01" }, "2026-09")
        #expect(c.stopajDonemleri == [StopajDonemi(bas: "2026-09", oran: 1)])
        #expect(c.stopajOrani(month: "2026-08") == nil)
        // Kullanıcı başlangıcı geriye alır
        kaydet({ $0.stopajBaslangic = "2026-01-01" }, "2026-09")
        #expect(c.stopajOrani(month: "2026-03") == 1)
        // Oran değişir: bu aydan itibaren; geçmiş %1 kalır
        kaydet({ $0.stopajPct = 2 }, "2026-10")
        #expect(c.stopajOrani(month: "2026-09") == 1)
        #expect(c.stopajOrani(month: "2026-10") == 2)
        // Kapatılır: geçen aya kadar kesilmiş sayılır
        kaydet({ $0.stopajBitis = "2026-11" }, "2026-12")
        #expect(c.stopajOrani(month: "2026-11") == 2)
        #expect(c.stopajOrani(month: "2026-12") == nil)
        // Yeniden açılır: aradaki aylar kesilmemiş kalır
        kaydet({ $0.stopajBitis = nil; $0.stopajBaslangic = "2027-03-01" }, "2027-03")
        #expect(c.stopajOrani(month: "2027-01") == nil)
        #expect(c.stopajOrani(month: "2027-03") == 2)
        #expect(c.stopajOrani(month: "2026-05") == 1)
    }

    @Test func yillikGiderYilOrtasindaDurdurulsaDaTamamiKaraYazilir() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "y", date: "2026-01-10", name: "Yazılım", amount: tl(12_000),
                                  category: .sabit, recurrence: .yillik, endMonth: "2026-03"))
        let e = Engine(s)
        // 12.000 ödendi: yılın 12 ayına 1.000'er; 2027'de yeni ödeme yok
        #expect(e.companyTotals(from: "2026-01", to: "2026-12").ortakGider == tl(12_000))
        #expect(e.companyMonth("2026-12").ortakGider == tl(1_000))
        #expect(e.companyTotals(from: "2027-01", to: "2027-12").ortakGider == 0)
        #expect(e.companyTotals(from: "2026-01", to: "2027-12").nakitCikisi == tl(12_000))
    }

    @Test func duzenliGiderBuAydanItibarenDegisir() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik,
                                  overrides: ["2026-03": ExpenseOverride(amount: tl(900)),
                                              "2026-07": ExpenseOverride(amount: tl(800))]))
        let st = AppStore.inMemory(s)
        var yeni = st.state.expenses[0]
        yeni.amount = tl(1_500)
        st.giderGuncelleAydanItibaren(yeni, ay: "2026-06")
        let e = st.engine
        #expect(e.companyMonth("2026-01").ortakGider == tl(1_000))
        #expect(e.companyMonth("2026-03").ortakGider == tl(900))
        #expect(e.companyMonth("2026-05").ortakGider == tl(1_000))
        #expect(e.companyMonth("2026-06").ortakGider == tl(1_500))
        #expect(e.companyMonth("2026-07").ortakGider == tl(800))   // o aya özel tutar korunur
        #expect(e.companyMonth("2026-08").ortakGider == tl(1_500))
        #expect(st.state.expenses.count == 2)
    }

    @Test func ilkGirilenOranlarBastanGecerli() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("m", "2026-01", channel: ChannelIds.other, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        let st = AppStore.inMemory(s)
        var ch = st.state.channel(ChannelIds.other)!
        ch.commissionPct = 20
        st.updateChannel(ch)
        // Kanal hiç kurulmamıştı: ilk girilen %20 ocak satışına da uygulanır
        #expect(st.engine.channelResult(channelId: ChannelIds.other, month: "2026-01").commission.amount == tl(2_000))
        // Sonraki değişiklik bugünden başlar
        ch = st.state.channel(ChannelIds.other)!
        ch.commissionPct = 30
        st.updateChannel(ch)
        #expect(st.engine.channelResult(channelId: ChannelIds.other, month: "2026-01").commission.amount == tl(2_000))
    }
}

@Suite("Denetim 4: hedef, kampanya, stok hızı")
struct AuditRound4HedefTests {
    private func agustos(kira: Bool = true, reklam: Kurus = 0) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[0].costLines = [CostLine(id: "c", label: "Üretim", amount: tl(200))]
        s.products[0].recipe = []
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        s.channelMonths.append(ChannelMonth(month: "2026-08", channelId: ChannelIds.trendyol, orderCount: 10))
        if kira {
            s.expenses.append(Expense(id: "kira", date: "2026-01-01", name: "Kira", amount: tl(10_000),
                                      category: .sabit, recurrence: .aylik))
        }
        if reklam > 0 {
            s.expenses.append(Expense(id: "meta", date: "2026-08-05", name: "Meta", amount: reklam,
                                      category: .reklam, scope: .channel(ChannelIds.trendyol), recurrence: .tek))
        }
        return s
    }

    @Test func basaBasHedefiYeniAyinKomisyonunuGorur() {
        var s = agustos()
        s.channels[0].setRates(ChannelRates(from: "2026-09-01", commissionPct: 30))
        let plan = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        // 1.000 − 200 maliyet − 300 komisyon = 500; 10.000 / 500 = 20 sipariş
        #expect(abs(plan.contributionPerOrder - Double(tl(500))) < 0.01)
        #expect(plan.targets.first { $0.isBreakeven }?.orders == 20)
    }

    @Test func kampanyaBasaBasiAnaKartlaAyni() throws {
        let e = Engine(agustos(reklam: tl(4_000)))
        let plan = e.plan(month: "2026-09", today: "2026-09-16")
        let k = try #require(e.kampanyaHesabi(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                                indirimPct: 0, on: "2026-09-16"))
        // (10.000 − 2.000 maliyet − 4.000 reklam) / 10 = 400; 10.000 / 400 = 25
        #expect(plan.targets.first { $0.isBreakeven }?.orders == 25)
        #expect(k.basaBasOnce == 25)
    }

    @Test func ayBasindaTuketimHiziDusmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.addPurchase("p1", "2026-05-01", .product(Fx.sampuanId), qty: 500, paid: tl(5_000))
        for ay in ["2026-06", "2026-07", "2026-08"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 90, gross: tl(9_000))
        }
        let e = Engine(s)
        #expect(e.consumptionRate(.product(Fx.sampuanId), endingAt: "2026-09", bugun: "2026-09-01").perMonth == 90)
        #expect(e.consumptionRate(.product(Fx.sampuanId), endingAt: "2026-08", bugun: "2026-09-01").perMonth == 90)
    }
}

@Suite("Denetim 4: kayıt ve içe aktarma")
struct AuditRound4KayitTests {
    @Test func iadeAdetleriToplamiKorunur() {
        #expect(SaleSplit.iadeAdetleri(1, adetler: [1, 1]).reduce(0, +) == 1)
        #expect(SaleSplit.iadeAdetleri(1, adetler: [1, 1, 1]).reduce(0, +) == 1)
        #expect(SaleSplit.iadeAdetleri(3, adetler: [1, 10]).reduce(0, +) == 3)
        #expect(SaleSplit.iadeAdetleri(3, adetler: [1, 10])[0] <= 1)
        #expect(Engine.dagit(2, [1, 1, 1, 1]).reduce(0, +) == 2)
    }

    @Test func shopifyIadeSiparisininSonrakiSatirlariAlinmaz() {
        let csv = """
        Name,Financial Status,Created at,Lineitem quantity,Lineitem name,Lineitem price,Lineitem sku
        #1001,refunded,2026-09-02 10:00:00 +0300,1,Şampuan,100.00,S1
        #1001,,,1,Serum,150.00,S2
        #1002,paid,2026-09-03 10:00:00 +0300,1,Serum,150.00,S2
        """
        let t = RaporIceAktarma.oku(csv)
        let k = RaporIceAktarma.kalemler(t, sutun: RaporIceAktarma.sutunlariBul(t.basliklar)).kalemler
        let iptaller = k.filter { $0.siparisNo == "#1001" }.map(\.iptal)
        #expect(iptaller == [true, true])
        #expect(k.first { $0.siparisNo == "#1002" }?.iptal == false)
    }

    @Test func ayniRaporIkiKezAktarilincaIkiKezSayilmaz() {
        func kalem(_ no: String, _ gun: DateKey) -> RaporIceAktarma.Kalem {
            .init(siparisNo: no, tarih: gun, urunAnahtari: "s", urunAdi: "Ş", adet: 1, tutar: tl(100),
                  indirim: 0, iptal: false)
        }
        let ilkYari = [kalem("1", "2026-09-02"), kalem("2", "2026-09-10")]
        let r1 = RaporIceAktarma.donustur(ilkYari, kanalId: "ty", eslesme: ["s": "p"], mevcutAylar: [],
                                          urunKdvOrani: { _ in nil })
        #expect(r1.eklenenAylar.isEmpty)
        // Aynı rapor tekrar: hiçbir şey eklenmez
        let r2 = RaporIceAktarma.donustur(ilkYari, kanalId: "ty", eslesme: ["s": "p"], mevcutAylar: r1.aylar,
                                          urunKdvOrani: { _ in nil })
        #expect(r2.satislar.isEmpty)
        #expect(r2.tekrarAtlanan == 2)
        // Ayın ikinci yarısı: yalnız yeni sipariş eklenir, sipariş sayısı toplanır
        let r3 = RaporIceAktarma.donustur(ilkYari + [kalem("3", "2026-09-20")], kanalId: "ty",
                                          eslesme: ["s": "p"], mevcutAylar: r1.aylar, urunKdvOrani: { _ in nil })
        #expect(r3.eklenenAylar == ["2026-09"])
        #expect(r3.satislar.reduce(0) { $0 + $1.qty } == 1)
        #expect(r3.aylar.first?.orderCount == 3)
    }

    @Test func stokAlimiNakdiGercektenOdenen() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.settings.capitalizePurchases = true
        s.purchases.append(StockPurchase(id: "a", date: "2026-09-02", item: .material(Fx.koliId), qty: 100,
                                         unit: .adet, totalPaid: tl(10_000), vatRate: .yirmi, vatIncluded: false))
        var vadeli = StockPurchase(id: "b", date: "2026-09-03", item: .material(Fx.patpatId), qty: 100,
                                   unit: .adet, totalPaid: tl(12_000), vatRate: .yok)
        vadeli.odeme = OdemePlani.esit(toplam: tl(12_000), pesinat: tl(2_000), taksitSayisi: 2, ilkVade: "2026-10-03")
        s.purchases.append(vadeli)
        let r = Engine(s).companyMonth("2026-09")
        // 12.000 (KDV eklenmiş) + 2.000 peşinat
        #expect(r.stokAlimiNakit == tl(14_000))
        #expect(r.stokAlimi == tl(24_000))
    }

    @Test func girilenSiparisSayilariylaDonemTahminiSayilmaz() {
        var s = Fx.base()
        for ay in ["2026-03", "2026-04"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 5, gross: tl(500))
            s.channelMonths.append(ChannelMonth(month: ay, channelId: ChannelIds.trendyol, orderCount: 5))
        }
        let c = Engine(s).companyTotals(from: "2026-03", to: "2026-04").channels.first { $0.channelId == ChannelIds.trendyol }
        #expect(c?.ordersIsEstimate == false)
    }

    @Test func kanalFiyatiSilinceEtiketFiyatinaDoner() {
        var p = Fx.sampuan()
        p.setPrice(tl(100), channelId: nil, from: "1970-01-01")
        p.setPrice(tl(120), channelId: ChannelIds.trendyol, from: "1970-01-01")
        p.applyCurrentPrice(0, channelId: ChannelIds.trendyol, today: "2026-09-18")
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-18") == tl(100))
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-08-01") == tl(120))
    }

    @Test func odenmisVadeliAlimDuzeltilinceNakitTutar() {
        var plan = OdemePlani.esit(toplam: tl(1_200), pesinat: 0, taksitSayisi: 2, ilkVade: "2026-08-01")
        for i in plan.taksitler.indices { plan.taksitler[i].odemeTarihi = "2026-08-01" }
        let artan = plan.tutariDuzelt(tl(1_500), bugun: "2026-09-18")
        #expect(artan.toplam == tl(1_500))
        #expect(artan.taksitler.last?.tutar == tl(300))
        #expect(artan.taksitler.last?.odendi == false)
        var kismen = OdemePlani.esit(toplam: tl(1_200), pesinat: 0, taksitSayisi: 2, ilkVade: "2026-08-01")
        kismen.taksitler[0].odemeTarihi = "2026-08-01"
        let azalan = kismen.tutariDuzelt(tl(300), bugun: "2026-09-18")
        // 600 ödenmiş taksit + 0 kalan taksit − 300 alacak = 300
        #expect(azalan.toplam == tl(300))
        #expect(azalan.taksitler[1].tutar == 0)
        #expect(azalan.taksitler.last?.tutar == -tl(300))
    }
}

@Suite("Denetim 4: doğrulama turunda bulunanlar")
@MainActor
struct AuditRound4DogrulamaTests {
    @Test func ilkKurulumdaOranVeKomisyonTabaniBirlikte() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("m", "2026-01", channel: ChannelIds.other, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        let st = AppStore.inMemory(s)
        var ch = st.state.channel(ChannelIds.other)!
        ch.commissionPct = 20
        ch.komisyonKdvHaric = true
        st.updateChannel(ch)
        let c = st.state.channel(ChannelIds.other)!
        #expect(c.rates(on: Dates.today()).commissionPct == 20)
        #expect(c.rates(on: "2026-01-31").commissionPct == 20)
        #expect(st.engine.channelResult(channelId: ChannelIds.other, month: "2026-01").commission.amount == tl(2_000))
    }

    @Test func yillikGiderSonrakiOdemedenItibarenDegisir() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "y", date: "2025-03-10", name: "Lisans", amount: tl(12_000),
                                  category: .sabit, recurrence: .yillik))
        let st = AppStore.inMemory(s)
        var yeni = st.state.expenses[0]
        yeni.amount = tl(24_000)
        st.giderGuncelleAydanItibaren(yeni, ay: "2027-03")
        let e = st.engine
        #expect(e.companyMonth("2026-03").nakitCikisi == tl(12_000))
        #expect(e.companyMonth("2026-06").ortakGider == tl(1_000))
        #expect(e.companyMonth("2027-02").ortakGider == tl(1_000))
        #expect(e.companyMonth("2027-03").nakitCikisi == tl(24_000))
        #expect(e.companyMonth("2027-04").ortakGider == tl(2_000))
    }

    @Test func durdurulmusGiderinGecmisiDegismez() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(5_000),
                                  category: .sabit, recurrence: .aylik, endMonth: "2026-05"))
        let st = AppStore.inMemory(s)
        var yeni = st.state.expenses[0]
        yeni.amount = tl(9_000)
        st.giderGuncelleAydanItibaren(yeni, ay: "2026-09")
        #expect(st.engine.companyMonth("2026-03").ortakGider == tl(5_000))
    }

    @Test func sonradanIptalEdilenSiparisSatistanDusulur() {
        func kalem(_ no: String, _ gun: DateKey, iptal: Bool = false) -> RaporIceAktarma.Kalem {
            .init(siparisNo: no, tarih: gun, urunAnahtari: "s", urunAdi: "Ş", adet: 1, tutar: tl(100),
                  indirim: 0, iptal: iptal)
        }
        var s = Fx.base()
        s.settings.vatEnabled = false
        let st = AppStore.inMemory(s)
        func aktar(_ k: [RaporIceAktarma.Kalem]) {
            let r = RaporIceAktarma.donustur(k, kanalId: ChannelIds.trendyol, eslesme: ["s": Fx.sampuanId],
                                             mevcutAylar: RaporIceAktarma.satisiOlanAylar(st.state, kanalId: ChannelIds.trendyol),
                                             urunKdvOrani: { _ in nil })
            st.raporuKaydet(r, kanalId: ChannelIds.trendyol)
        }
        aktar([kalem("1", "2026-08-02"), kalem("2", "2026-08-05")])
        // Ay sonu raporu: 2 numaralı sipariş iade edildi, 3 yeni
        aktar([kalem("1", "2026-08-02"), kalem("2", "2026-08-05", iptal: true), kalem("3", "2026-08-20")])
        let satis = st.state.sales.filter { $0.month == "2026-08" }
        #expect(satis.reduce(0) { $0 + $1.qty } == 2)
        #expect(satis.reduce(0) { $0 + $1.grossSales } == tl(200))
        #expect(st.state.channelMonth(month: "2026-08", channelId: ChannelIds.trendyol)?.orderCount == 2)
        // Ay kaydı elle düzenlense de liste korunur (üçüncü aktarım bir şey eklemez)
        aktar([kalem("1", "2026-08-02"), kalem("3", "2026-08-20")])
        #expect(st.state.sales.filter { $0.month == "2026-08" }.reduce(0) { $0 + $1.qty } == 2)
    }

    @Test func setiUruneCevirmekGecmisStoguDegistirmez() {
        var s = Fx.base()
        s.addSale("o", "2026-01", channel: ChannelIds.trendyol, product: Fx.setId, qty: 5, gross: tl(2_500))
        let st = AppStore.inMemory(s)
        let once = st.engine.qty(.product(Fx.sampuanId))
        var p = st.state.product(Fx.setId)!
        p.isBundle = false
        p.components = []
        st.updateProduct(p)
        #expect(st.engine.qty(.product(Fx.sampuanId)) == once)
        #expect(st.engine.qty(.product(Fx.setId)) == 0)
    }
}
