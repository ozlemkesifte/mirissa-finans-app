import Testing
import Foundation
@testable import MirissaCore

/// İmkânsız veri sessizce hesaba girmesin: bozuk durumlar açıkça bildirilir.
@Suite("Veri bütünlüğü")
struct IntegrityTests {

    private typealias G = GoldenScenarioTests.G
    private func durum() -> AppState { GoldenScenarioTests.senaryo() }

    @Test func saglikliVeriUyariUretmez() {
        #expect(Integrity.check(durum()).isEmpty)
        #expect(Integrity.blocking(durum()).isEmpty)
        #expect(Integrity.check(SeedData.initialState()).isEmpty)
    }

    // MARK: Kimlik çakışması

    @Test func ayniKimlikIkiKayittaYakalanir() {
        var s = durum()
        s.sales.append(s.sales[0])
        #expect(Integrity.blocking(s).contains { $0.message.contains("Aynı kimlik") })
    }

    // MARK: Ürün ve set

    @Test func kendiniIcerenSetYakalanir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.set }!
        s.products[i].components.append(BundleComponent(productId: G.set, qty: 1))
        #expect(Integrity.blocking(s).contains { $0.message.contains("kendini içeriyor") })
    }

    @Test func olmayanBilesenYakalanir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.set }!
        s.products[i].components = [BundleComponent(productId: "yok_boyle_urun", qty: 1)]
        #expect(Integrity.blocking(s).contains { $0.message.contains("olmayan bir ürün") })
    }

    @Test func setinKendiStoguSupheliSayilir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.set }!
        s.products[i].openingQty = 50
        #expect(Integrity.check(s).contains { $0.message.contains("kendi başlangıç stoğu") })
    }

    @Test func olmayanMalzemeninReceteSatiriYakalanir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].recipe.append(RecipeLine(materialId: "yok_boyle_malzeme",
                                               qty: 1, unit: .adet))
        #expect(Integrity.blocking(s).contains { $0.message.contains("olmayan bir malzeme") })
    }

    @Test func eksiMaliyetYakalanir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].costLines = [CostLine(label: "Üretim", amount: -tl(10))]
        #expect(Integrity.blocking(s).contains { $0.message.contains("maliyet kalemi eksi") })
    }

    /// Aynı anda geçerli iki aynı adlı maliyet kalemi = çift sayım riski
    @Test func ciftGecerliMaliyetKalemiYakalanir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].costLines.append(CostLine(label: "Üretim", amount: tl(100)))
        #expect(Integrity.check(s).contains { $0.message.contains("iki kez sayılıyor") })
    }

    // MARK: Kanal

    @Test func yuzdeYuzuAsanKesintiYakalanir() {
        var s = durum()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].setRates(ChannelRates(from: "2026-01-01", commissionPct: 60,
                                            paymentPct: 30, otherDeductionPct: 20))
        #expect(Integrity.blocking(s).contains { $0.message.contains("%100") })
    }

    @Test func ayniTarihteIkiKesintiAyariYakalanir() {
        var s = durum()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].rateHistory = [
            ChannelRates(id: "a", from: "2026-01-01", commissionPct: 10),
            ChannelRates(id: "b", from: "2026-01-01", commissionPct: 20),
        ]
        #expect(Integrity.blocking(s).contains { $0.message.contains("aynı tarihte iki farklı kesinti") })
    }

    @Test func gecersizTarihYakalanir() {
        var s = durum()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].rateHistory = [ChannelRates(from: "2026-02-30", commissionPct: 10)]
        #expect(Integrity.blocking(s).contains { $0.message.contains("geçersiz tarih") })
    }

    // MARK: Satış

    @Test func olmayanUrunVeKanalYakalanir() {
        var s = durum()
        s.sales.append(SalesEntry(id: "sal_kotu", month: "2026-09",
                                  channelId: "yok_kanal", productId: "yok_urun",
                                  qty: 1, grossSales: tl(100)))
        let sorunlar = Integrity.blocking(s)
        #expect(sorunlar.contains { $0.message.contains("Olmayan bir ürüne") })
        #expect(sorunlar.contains { $0.message.contains("Olmayan bir kanala") })
    }

    @Test func iadeSatistanFazlaYakalanir() {
        var s = durum()
        let i = s.sales.firstIndex { $0.id == "sal_g1" }!
        s.sales[i].returnsQty = 500
        #expect(Integrity.blocking(s).contains { $0.message.contains("İade adedi") })
    }

    @Test func eksiNetSatisYakalanir() {
        var s = durum()
        let i = s.sales.firstIndex { $0.id == "sal_g1" }!
        s.sales[i].discount = tl(900_000)
        #expect(Integrity.blocking(s).contains { $0.message.contains("net satış eksi") })
    }

    @Test func ayniAyAyniUrunIkiSatirSupheli() {
        var s = durum()
        s.sales.append(SalesEntry(id: "sal_tekrar", month: "2026-09", channelId: G.trendyol,
                                  productId: G.sampuan, qty: 10, grossSales: tl(12_000)))
        #expect(Integrity.check(s).contains { $0.message.contains("iki kez girilmiş olabilir") })
    }

    // MARK: Stok

    @Test func eksiStokSessizceGecilmez() {
        var s = durum()
        s.sales.append(SalesEntry(id: "sal_cok", month: "2026-09", channelId: G.trendyol,
                                  productId: G.serum, qty: 5000, grossSales: tl(100_000)))
        #expect(Integrity.check(s).contains { $0.message.contains("eksiye düştü") })
    }

    @Test func eksiDuzeltmeMiktariYakalanir() {
        var s = durum()
        s.adjustments.append(StockAdjustment(id: "adj_kotu", date: "2026-09-10",
                                             item: .material(G.koli), qty: -5,
                                             unit: .adet, reason: .fire))
        #expect(Integrity.blocking(s).contains { $0.message.contains("miktarı eksi") })
    }

    // MARK: Fiyat tarihçesi

    @Test func ayniTarihteIkiFiyatYakalanir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].priceHistory = [
            PricePoint(id: "a", channelId: G.trendyol, amount: tl(699), from: "2026-09-01"),
            PricePoint(id: "b", channelId: G.trendyol, amount: tl(749), from: "2026-09-01"),
        ]
        #expect(Integrity.blocking(s).contains { $0.message.contains("aynı tarihte iki farklı fiyat") })
    }

    @Test func celiskiliFiyatDonemiYakalanir() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].priceHistory = [
            PricePoint(channelId: G.trendyol, amount: tl(699),
                       from: "2026-09-20", to: "2026-09-01"),
        ]
        #expect(Integrity.blocking(s).contains { $0.message.contains("bitişi başlangıcından önce") })
    }

    // MARK: Normal iş akışları temiz kalmalı

    @Test func fiyatVeKomisyonDegisiklikleriUyariUretmez() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].setPrice(tl(699), channelId: G.trendyol, from: "2026-09-01")
        s.products[i].setPrice(tl(749), channelId: G.trendyol, from: "2026-10-01")
        let j = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[j].setRates(ChannelRates(from: "2026-10-01", commissionPct: 25,
                                            shippingPerOrder: tl(110)))
        #expect(Integrity.check(s).isEmpty)
    }

    @Test func maliyetGecmisiUyariUretmez() {
        var s = durum()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].applyCostLines(
            [CostLine(id: "cst_g_s", label: "Üretim", amount: tl(130))], today: "2026-10-01")
        #expect(Integrity.check(s).isEmpty)
    }
}

/// Eksik veri gerçek rakammış gibi gösterilmesin
@Suite("Eksik veri açıkça söylenir")
struct MissingDataTests {

    private typealias G = Golden.G

    @Test func bilinmeyenKesintiHedefteYaklasikIsaretler() {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].setRates(ChannelRates(
            from: "2026-01-01", commissionPct: 20,
            unknownFields: ["kargo gideri"]
        ))
        let e = Engine(s)
        let plan = e.plan(month: "2026-10", today: "2026-10-01")
        #expect(plan.issues.contains(BreakevenIssue.eksikKanalBilgisi))
        #expect(e.yearlyPlan(year: 2026, today: "2026-10-01")
            .issues.contains(BreakevenIssue.eksikKanalBilgisi))
        // Mesaj kullanıcıya "sıfırmış gibi hesaplandı" diyor
        #expect(BreakevenIssue.eksikKanalBilgisi.message.contains("sıfırmış gibi"))
    }

    @Test func eksikBilgiSatisOlmayanAydaDaGorunur() {
        var s = Golden.senaryo()
        let i = s.channels.firstIndex { $0.id == G.shopify }!
        s.channels[i].setRates(ChannelRates(from: "2026-01-01", paymentPct: 3,
                                            unknownFields: ["hizmet bedeli"]))
        let uyari = Engine(s).companyMonth("2026-12").yaklasikUyarisi
        #expect(uyari?.contains("hizmet bedeli") == true)
    }

    @Test func butunBilgilerGirilmisseYaklasikDenmez() {
        let e = Engine(Golden.senaryo())
        #expect(e.companyMonth("2026-09").yaklasikUyarisi == nil)
        #expect(!e.plan(month: "2026-10", today: "2026-10-01")
            .issues.contains(BreakevenIssue.eksikKanalBilgisi))
    }

    /// Referans ay yoksa hedef üretilmez — uydurma rakam gösterilmez
    @Test func referansYoksaHedefUretilmez() {
        var s = Golden.senaryo()
        s.sales = []
        let plan = Engine(s).plan(month: "2026-10", today: "2026-10-01")
        #expect(plan.targets.isEmpty)
        #expect(plan.blocking == .referansYok)
        #expect(!plan.canCompute)
    }

    /// Satış girilmemiş ayda gerçek kâr varmış gibi davranılmaz
    @Test func satisGirilmemisAydaGercekKarIddiasiYok() {
        let plan = Engine(Golden.senaryo()).plan(month: "2026-11", today: "2026-11-10")
        #expect(plan.mode == .hedef)
        #expect(plan.actual == nil)
        #expect(plan.progressOrders == nil)
        #expect(plan.targets.allSatisfy { $0.remainingOrders == nil })
        #expect(!plan.hasProgress)
    }
}

/// Aynı sayının iki ayrı yerde saklanıp birbirinden kopmaması
@Suite("Tek kaynak", .serialized)
@MainActor
struct SingleSourceTests {

    private typealias G = Golden.G

    /// Kanal formundan değiştirilen oran motorda da geçerli olmalı
    @Test func kanalFormundanDegisenOranMotoraYansir() {
        let st = AppStore.inMemory(Golden.senaryo())
        // Kanalın tarihçesi açılır (soru-cevap kurulumu gibi)
        st.applyChannelRates(G.trendyol, ChannelRates(from: "2026-01-01", commissionPct: 20,
                                                      shippingPerOrder: tl(100)))
        #expect(st.engine.channelResult(channelId: G.trendyol, month: "2026-09")
            .commission.amount == tl(39_600))

        // Eski form üzerinden düz alan değiştiriliyor
        var c = st.state.channel(G.trendyol)!
        c.commissionPct = 30
        st.updateChannel(c)

        // Ekranda görünen değer motorda da geçerli: bugünden itibaren %30
        let bugun = Dates.today()
        #expect(st.state.channel(G.trendyol)?.rates(on: bugun).commissionPct == 30)
        #expect(st.state.channel(G.trendyol)?.commissionPct == 30)
        // Geçmiş tarihçe korunur: değişiklikten önceki günler eski oranda
        let dun = Dates.addDays(bugun, -1)
        #expect(st.state.channel(G.trendyol)?.rates(on: dun).commissionPct == 20)
        #expect(Integrity.blocking(st.state).isEmpty)
    }

    @Test func oranDegismediyseYeniTarihceAcilmaz() {
        let st = AppStore.inMemory(Golden.senaryo())
        st.applyChannelRates(G.trendyol, ChannelRates(from: "2026-01-01", commissionPct: 20))
        let adet = st.state.channel(G.trendyol)?.rateHistory?.count ?? 0
        var c = st.state.channel(G.trendyol)!
        c.name = "Trendyol Mağaza"
        st.updateChannel(c)
        #expect(st.state.channel(G.trendyol)?.rateHistory?.count == adet)
        #expect(st.state.channel(G.trendyol)?.name == "Trendyol Mağaza")
    }

    /// Ürün fiyatının tek kaynağı tarihçedir
    @Test func fiyatinTekKaynagiVar() {
        var s = Golden.senaryo()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        s.products[i].listPrice = tl(500)                 // eski alan
        s.products[i].setPrice(tl(699), channelId: nil, from: "2026-09-01")
        // Tarihçe varsa eski alan yok sayılır; ikisi çelişmez
        #expect(s.products[i].price(on: "2026-09-15") == tl(699))
    }

    /// Stok yalnızca hareketlerden türetilir, ayrıca saklanmaz
    @Test func stokSaklanmazTuretilir() {
        let s = Golden.senaryo()
        let e1 = Engine(s)
        let e2 = Engine(s)
        #expect(e1.qty(.material(G.koli)) == e2.qty(.material(G.koli)))
        // Aynı veriden kurulan iki motor aynı sonucu verir: saklanan bakiye yok
        var s2 = s
        s2.purchases.removeAll()
        #expect(Engine(s2).qty(.material(G.koli)) == 830)
    }
}

/// Sayısal sınır durumlarında sessiz saçmalık üretilmemeli
@Suite("Sayısal güvenlik")
struct NumericSafetyTests {

    @Test func sonsuzVeNaNSifiraDoner() {
        #expect(Money.roundHalfAwayFromZero(.infinity) == 0)
        #expect(Money.roundHalfAwayFromZero(.nan) == 0)
        #expect(Money.roundHalfAwayFromZero(-.infinity) == 0)
    }

    @Test func asiriBuyukTutarCokertmez() {
        // Çökmek yerine sınırda tutulur
        let v = Money.roundHalfAwayFromZero(1e300)
        #expect(v > 0)
        #expect(Money.roundHalfAwayFromZero(-1e300) < 0)
    }

    @Test func sifirBolenSonucUretmez() {
        let s = Golden.senaryo()
        let e = Engine(s)
        // Satışı olmayan ayda marj sıfır, NaN değil
        let bos = e.companyMonth("2026-01")
        #expect(bos.karMarjiPct == 0)
        #expect(bos.karMarjiPct.isFinite)
        for c in bos.channels { #expect(c.marginPct.isFinite) }
    }

    @Test func bozukTuketimPenceresiSifiraBolunmez() throws {
        let json = """
        {"consumptionWindowMonths":0,"companyName":"X"}
        """
        let a = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(a.consumptionWindowMonths >= 1)
        var s = Golden.senaryo()
        s.settings = a
        let oran = Engine(s).ordersLeft(.material(Golden.G.koli))
        #expect(oran == nil || oran! >= 0)
    }
}

/// Maliyetsiz stok sessizce sıfır değer olarak geçmemeli
@Suite("Maliyeti girilmemiş stok")
struct MissingCostTests {

    private typealias G = Golden.G

    @Test func maliyetsizStokUyariUretir() {
        var s = Golden.senaryo()
        // Set kutusunun alımı yok: maliyeti silinince birim maliyet sıfır kalır
        let i = s.materials.firstIndex { $0.id == G.setKutu }!
        s.materials[i].openingUnitCost = nil
        let sorunlar = Integrity.check(s)
        #expect(sorunlar.contains { $0.message.contains("birim maliyeti girilmemiş") })
        // Hesap yine de yapılır ama eksik olduğu söylenir
        #expect(Engine(s).unitCost(.material(G.setKutu)) == 0)
    }

    @Test func maliyetiGirilmisStokUyariUretmez() {
        #expect(!Integrity.check(Golden.senaryo())
            .contains { $0.message.contains("birim maliyeti girilmemiş") })
    }

    @Test func bosKurulumUyariUretmez() {
        #expect(Integrity.check(SeedData.initialState()).isEmpty)
    }
}
