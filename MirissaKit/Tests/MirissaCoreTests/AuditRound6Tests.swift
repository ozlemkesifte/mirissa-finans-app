import Testing
import Foundation
@testable import MirissaCore

/// 6. denetim turunda bulunan hataların düzeltmeleri. Beklenen rakamlar elle hesaplandı.
@Suite("Denetim 6")
@MainActor
struct AuditRound6Tests {

    private func koliliSerumSampuan(_ s: inout AppState) {
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.materials = s.materials.map { var m = $0; if m.id == Fx.koliId { m.perOrder = false }; return m }
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = [RecipeLine(id: "a", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.products[1] = Fx.serum(cost: 0); s.products[1].recipe = [RecipeLine(id: "b", materialId: Fx.koliId, qty: 1, unit: .adet)]
    }

    // MARK: Stok maliyeti

    @Test func ayniMalzemeyiKullananIkiUrunEksiyeDusunceYalnizEksikMaliyetlenir() {
        var s = Fx.base()
        koliliSerumSampuan(&s)
        s.materials = s.materials.map { var m = $0; if m.id == Fx.koliId { m.openingQty = 100; m.openingDate = "2026-01-01" }; return m }
        s.addSale("a", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 80, gross: tl(800))
        s.addSale("b", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 50, gross: tl(500))
        s.addPurchase("k", "2026-03-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        let e = Engine(s)
        // 100 maliyetsiz + 30 eksik × 10 TL = 300 TL (birim 2,31 TL'ye yuvarlanır: 130 × 2,31 = 300,30)
        let ocak = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost
        #expect(abs(ocak - tl(300)) <= 130)
        #expect(e.balance(.material(Fx.koliId)).value == tl(700))   // 70 × 10
    }

    @Test func eksiStoguKapatanPahaliAliminFarkiAlimAyindaGiderOlur() {
        var s = Fx.base()
        koliliSerumSampuan(&s)
        s.addPurchase("k1", "2026-01-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.addSale("b", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 150, gross: tl(1_500))
        s.addPurchase("k2", "2026-03-01", .material(Fx.koliId), qty: 200, paid: tl(4_000))
        let e = Engine(s)
        // Ocak: 150 × 10 = 1.500; mart: eksik 50 adet × (20 − 10) = 500 fiyat farkı; stok 150 × 20 = 3.000
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost == tl(1_500))
        #expect(e.stoktanGider(from: "2026-03", to: "2026-03", category: .ambalaj) == tl(500))
        #expect(e.balance(.material(Fx.koliId)).value == tl(3_000))
        #expect(e.companyMonth("2026-03").toplamGider == tl(500))
    }

    @Test func alimdanGelenUrunMaliyetiKurusKaybetmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addPurchase("u", "2026-01-01", .product(Fx.sampuanId), qty: 3_000, paid: tl(10_000))
        s.addSale("a", "2026-02", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 3_000, gross: tl(30_000))
        #expect(Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-02").productCost == tl(10_000))
    }

    // MARK: Gider

    @Test func ikiKezBolunenGiderBaginiKorur() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.expenses.append(Expense(id: "e", date: "2026-01-05", name: "Kira", amount: tl(100),
                                  category: .sabit, recurrence: .aylik))
        let st = AppStore.inMemory(s)
        var e = st.state.expenses.first { $0.id == "e" }!; e.amount = tl(200)
        let d1 = st.giderGuncelleAydanItibaren(e, ay: "2026-05")
        e = st.state.expenses.first { $0.id == "e" }!; e.amount = tl(150)
        let d2 = st.giderGuncelleAydanItibaren(e, ay: "2026-03")
        #expect(st.state.expenses.first { $0.id == d2 }?.devamId == d1)
        st.resumeExpense(d2, buAy: "2026-09")   // devamı var: yeniden başlatılmaz
        let eng = st.engine
        #expect(eng.companyMonth("2026-02").ortakGider == tl(100))
        #expect(eng.companyMonth("2026-04").ortakGider == tl(150))
        #expect(eng.companyMonth("2026-10").ortakGider == tl(200))
    }

    @Test func yillikGiderAyniYilIcindeYenidenBaslayincaIkinciOdemeYok() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "y", date: "2026-01-10", name: "Lisans", amount: tl(12_000),
                                  category: .sabit, recurrence: .yillik, endMonth: "2026-03"))
        let st = AppStore.inMemory(s)
        st.resumeExpense("y", buAy: "2026-05")
        let e = st.engine
        #expect(e.companyTotals(from: "2026-01", to: "2026-12").ortakGider == tl(12_000))
        #expect(e.companyMonth("2026-05").nakitCikisi == 0)
        #expect(e.companyMonth("2027-01").nakitCikisi == tl(12_000))
    }

    // MARK: KDV oranı, vergi, nakit

    @Test func ayIcindeBirdenCokSatirdaIlkSatirinKdvOrani() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.sales.append(SalesEntry(id: "1", month: "2026-06", channelId: ChannelIds.trendyol, productId: Fx.sampuanId,
                                  qty: 1, grossSales: tl(110), vatRate: .on, vatIncluded: true))
        s.sales.append(SalesEntry(id: "2", month: "2026-06", channelId: ChannelIds.trendyol, productId: Fx.sampuanId,
                                  qty: 1, grossSales: tl(101), vatRate: .bir, vatIncluded: true))
        #expect(Engine(s).satisKdvOrani(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                        on: "2026-08-15", today: "2026-09-19") == .on)
    }

    @Test func zararliCeyrektenSonraGeciciVergiOdenenleDusulur() throws {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("q1", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 1, gross: tl(100_000))
        s.expenses.append(Expense(id: "z", date: "2026-04-10", name: "Zarar", amount: tl(50_000), category: .diger))
        s.addSale("q3", "2026-07", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 1, gross: tl(100_000))
        s.settings.ek.vergiOrani = 20
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-09", today: "2026-12-01"))
        // Kümülatif 150.000 × %20 = 30.000; 1. çeyrekte 20.000 ödendi (2. çeyrekte iade yok) → 10.000
        #expect(v.ceyrek == 3)
        #expect(v.ceyrekGeciciVergi == tl(10_000))
    }

    @Test func satisiGirilmemisGecenAyTahminEdilir() throws {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        for ay in ["2026-05", "2026-06", "2026-07"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(30_000))
        }
        for i in s.sales.indices { s.sales[i].vatRate = .yirmi; s.sales[i].vatIncluded = true }
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(12_000), category: .sabit,
                                  recurrence: .aylik, vatRate: .yirmi, vatIncluded: true))
        s.settings.ek.kasaBakiye = tl(100_000)
        s.settings.ek.kasaTarih = "2026-09-01"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-09-01"))
        // Ağustos satışı henüz girilmedi: 3 ay ortalaması 5.000 hesaplanan − 2.000 indirilecek = 3.000
        #expect(t.bilinenKalemler.first { $0.id == "kdv:2026-08" }?.tutar == -tl(3_000))
        #expect(t.bilinenKalemler.first { $0.id == "kdv:2026-09" }?.tutar == -tl(3_000))
        #expect(t.aylikTahsilat == tl(30_000))
    }

    @Test func buAyIlkKezSatilanUrununHiziGecenGuneGore() {
        var s = Fx.base()
        s.products[0].openingQty = 500; s.products[0].openingDate = "2026-01-01"
        s.addSale("a", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 100, gross: tl(10_000))
        let r = Engine(s).consumptionRate(.product(Fx.sampuanId), endingAt: "2026-09", bugun: "2026-09-05")
        // 5 günde 100 → ayda 100 ÷ (5/30) = 600
        #expect(abs(r.perMonth - 600) < 1e-6)
    }

    // MARK: Hedefler

    private func fiyatDegisen(elleKomisyon: Bool) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 20
        s.products[0] = Fx.sampuan(cost: tl(200)); s.products[0].recipe = []
        s.products[0].setPrice(tl(600), channelId: ChannelIds.trendyol, from: "1970-01-01")
        s.products[0].setPrice(tl(720), channelId: ChannelIds.trendyol, from: "2026-09-01")
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(6_000))
        s.channelMonths.append(ChannelMonth(month: "2026-08", channelId: ChannelIds.trendyol, orderCount: 10,
                                            commissionActual: elleKomisyon ? tl(1_200) : nil))
        return s
    }

    @Test func fiyatDegisinceElleGirilenKomisyonDaOlceklenir() {
        let elle = Engine(fiyatDegisen(elleKomisyon: true)).plan(month: "2026-09", today: "2026-09-16")
        let oto = Engine(fiyatDegisen(elleKomisyon: false)).plan(month: "2026-09", today: "2026-09-16")
        // 720 − %20 (144) − 200 = 376 sipariş başına, iki durumda da
        #expect(abs(elle.contributionPerOrder - Double(tl(376))) < 0.01)
        #expect(abs(oto.contributionPerOrder - Double(tl(376))) < 0.01)
    }

    @Test func urunBazliVeKarisikReklamHedefiAyni() throws {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: tl(200)); s.products[0].recipe = []
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "1970-01-01")
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        s.expenses.append(Expense(id: "inf", date: "2026-08-05", name: "Influencer", amount: tl(1_000),
                                  category: .influencer, behavior: .satisaBagli))
        let e = Engine(s)
        let tek = try #require(e.adTargets(keepPerOrder: nil, on: "2026-09-16").first)
        let karisik = try #require(e.blendedAdTarget(month: "2026-09", keepPerOrder: nil, today: "2026-09-16"))
        // 1.000 − 200 − 100 (influencer ÷ 10 sipariş) = 700
        #expect(tek.beforeAds == tl(700))
        #expect(karisik.beforeAds == tl(700))
    }

    @Test func siparisHatirlatmasiSonGundekiStogaGore() throws {
        var s = Fx.base()
        s.products[0].tedarikSuresiGun = 10
        s.addPurchase("u", "2026-05-01", .product(Fx.sampuanId), qty: 1_210, paid: tl(12_100))
        for ay in ["2026-06", "2026-07", "2026-08"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 300, gross: tl(30_000))
        }
        let o = try #require(Engine(s).siparisOnerisi(.product(Fx.sampuanId), bugun: "2026-09-01"))
        // Günde 10, elde 310 → 31 gün; son gün 31 − 17 = 14 gün sonra, o gün elde 170 → 10 × 40 − 170 = 230
        #expect(o.kalanGun == 31)
        #expect(o.sonGundeMiktar == 230)
    }

    @Test func gecmisYilinPlaniBugunkuFiyatlaDegismez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: tl(200)); s.products[0].recipe = []
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "1970-01-01")
        s.addSale("a", "2025-12", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        s.expenses.append(Expense(id: "k", date: "2025-01-05", name: "Kira", amount: tl(1_000), category: .sabit, recurrence: .aylik))
        let once = Engine(s).yearlyPlan(year: 2025, today: "2026-09-19").contributionPerOrder
        s.products[0].setPrice(tl(500), channelId: ChannelIds.trendyol, from: "2026-09-19")
        #expect(Engine(s).yearlyPlan(year: 2025, today: "2026-09-19").contributionPerOrder == once)
    }

    @Test func beklenenProfilGecmisAyiBugunkuMaliyetleOynatmaz() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: tl(200)); s.products[0].recipe = []
        s.settings.expectedMix = ExpectedMix(channelId: ChannelIds.trendyol, productId: Fx.sampuanId, averageOrderValue: tl(1_000))
        let once = Engine(s).expectedMixBasis(month: "2026-05", today: "2026-09-19")?.contributionPerOrder
        s.products[0].applyCostLines([CostLine(id: "cst_s", label: "Üretim", amount: tl(500))], today: "2026-09-19")
        #expect(Engine(s).expectedMixBasis(month: "2026-05", today: "2026-09-19")?.contributionPerOrder == once)
    }

    // MARK: Rapor aktarma

    private func kalem(_ no: String, _ urun: String, iptal: Bool = false) -> RaporIceAktarma.Kalem {
        .init(siparisNo: no, tarih: "2026-08-03", urunAnahtari: urun, urunAdi: urun, adet: 1, tutar: tl(100),
              indirim: 0, iptal: iptal)
    }

    private func aktar(_ st: AppStore, _ k: [RaporIceAktarma.Kalem], eslesme: [String: Id]) {
        let r = RaporIceAktarma.donustur(k, kanalId: ChannelIds.trendyol, eslesme: eslesme,
                                         mevcutAylar: RaporIceAktarma.satisiOlanAylar(st.state, kanalId: ChannelIds.trendyol),
                                         urunKdvOrani: { _ in nil })
        st.raporuKaydet(r, kanalId: ChannelIds.trendyol)
    }

    @Test func tekKalemiIptalSiparisTekrarAktarimdaBozulmaz() {
        var s = Fx.base(); s.settings.vatEnabled = false
        let st = AppStore.inMemory(s)
        let rapor = [kalem("TY1", "S"), kalem("TY1", "R", iptal: true), kalem("TY2", "S")]
        let es = ["S": Fx.sampuanId, "R": Fx.serumId]
        for _ in 0..<3 { aktar(st, rapor, eslesme: es) }
        let satis = st.state.sales.filter { $0.month == "2026-08" }
        #expect(satis.filter { $0.productId == Fx.sampuanId }.reduce(0) { $0 + $1.qty } == 2)
        #expect(satis.filter { $0.productId == Fx.serumId }.reduce(0) { $0 + $1.qty } == 0)
        #expect(st.state.channelMonth(month: "2026-08", channelId: ChannelIds.trendyol)?.orderCount == 2)
    }

    @Test func atlananKalemSonradanEslesinceEklenir() {
        var s = Fx.base(); s.settings.vatEnabled = false
        let st = AppStore.inMemory(s)
        let rapor = [kalem("TY1", "S"), kalem("TY1", "R")]
        aktar(st, rapor, eslesme: ["S": Fx.sampuanId])                       // Serum atlandı
        aktar(st, rapor, eslesme: ["S": Fx.sampuanId, "R": Fx.serumId])      // sonra eşleşti
        let satis = st.state.sales.filter { $0.month == "2026-08" }
        #expect(satis.filter { $0.productId == Fx.sampuanId }.reduce(0) { $0 + $1.qty } == 1)
        #expect(satis.filter { $0.productId == Fx.serumId }.reduce(0) { $0 + $1.qty } == 1)
        #expect(st.state.channelMonth(month: "2026-08", channelId: ChannelIds.trendyol)?.orderCount == 1)
    }

    // MARK: Kilit ve günlük

    @Test func kilitliAydaHakedisVeAdDegisebilirTutarDegismez() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 1, gross: tl(1_200))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-08", channelId: ChannelIds.trendyol, orderCount: 1))
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(1_000), category: .sabit,
                                  recurrence: .aylik, vatRate: .yirmi, vatIncluded: true))
        s.settings.ek.kilitliAylar = ["2026-08"]
        let st = AppStore.inMemory(s)
        var cm = st.state.channelMonth(month: "2026-08", channelId: ChannelIds.trendyol)!
        cm.payoutActual = tl(900); cm.note = "yattı"
        st.upsertChannelMonth(cm)
        #expect(st.sonHata == nil)
        var e = st.state.expenses[0]; e.name = "Ofis kirası"
        st.updateExpense(e)
        #expect(st.sonHata == nil)
        e.amount = tl(2_000)
        st.updateExpense(e)
        #expect(st.sonHata != nil)
    }

    @Test func kdvAyariDegisikligiGunlugeYazilir() {
        let st = AppStore.inMemory(Fx.base())
        st.setVatEnabled(!st.state.settings.vatEnabled)
        #expect(st.state.changeLog.contains { $0.alan == "KDV ayarı" })
    }

    // MARK: Doğrulama turunda bulunanlar

    @Test func eksiStokIkiAlimlaKapaninca() {
        var s = Fx.base()
        koliliSerumSampuan(&s)
        s.addPurchase("k1", "2026-01-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.addSale("b", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 150, gross: tl(1_500))
        s.addPurchase("k2", "2026-03-01", .material(Fx.koliId), qty: 30, paid: tl(600))
        s.addPurchase("k3", "2026-04-01", .material(Fx.koliId), qty: 100, paid: tl(3_000))
        let e = Engine(s)
        // 50 eksik 10 TL'den yazıldı: mart 30 × (20 − 10) = 300, nisan 20 × (30 − 10) = 400
        #expect(e.stoktanGider(from: "2026-03", to: "2026-03", category: .ambalaj) == tl(300))
        #expect(e.stoktanGider(from: "2026-04", to: "2026-04", category: .ambalaj) == tl(400))
        // 1.500 + 300 + 400 + stokta 80 × 30 = 2.400 → 4.600 ödendi
        #expect(e.balance(.material(Fx.koliId)).value == tl(2_400))
    }

    @Test func elleMaliyetliUrundeFiyatFarkiYok() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: tl(5)); s.products[0].recipe = []
        s.addPurchase("u1", "2026-01-01", .product(Fx.sampuanId), qty: 100, paid: tl(1_000))
        s.addSale("a", "2026-01", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 150, gross: tl(1_500))
        s.addPurchase("u2", "2026-03-01", .product(Fx.sampuanId), qty: 100, paid: tl(2_000))
        #expect(Engine(s).stoktanGider(from: "2026-03", to: "2026-03", category: .urunUretimi) == 0)
    }

    @Test func satirSilinipYenidenAktarilincaSiparisIkiKezSayilmaz() {
        var s = Fx.base(); s.settings.vatEnabled = false
        let st = AppStore.inMemory(s)
        let rapor = [kalem("TY1", "S"), kalem("TY2", "R")]
        let es = ["S": Fx.sampuanId, "R": Fx.serumId]
        aktar(st, rapor, eslesme: es)
        #expect(st.state.channelMonth(month: "2026-08", channelId: ChannelIds.trendyol)?.orderCount == 2)
        let serumSatiri = st.state.sales.first { $0.productId == Fx.serumId }!.id
        st.deleteSale(serumSatiri)
        aktar(st, rapor, eslesme: es)
        #expect(st.state.channelMonth(month: "2026-08", channelId: ChannelIds.trendyol)?.orderCount == 2)
        #expect(st.state.sales.filter { $0.productId == Fx.serumId }.reduce(0) { $0 + $1.qty } == 1)
    }

    @Test func gercektenSatissizGecenAyAyinOnundanSonraTahminEdilmez() throws {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        for ay in ["2026-05", "2026-06", "2026-07"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(30_000))
        }
        for i in s.sales.indices { s.sales[i].vatRate = .yirmi; s.sales[i].vatIncluded = true }
        s.settings.ek.kasaBakiye = tl(100_000)
        s.settings.ek.kasaTarih = "2026-09-20"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-09-20"))
        // 20 Eylül: Ağustos'ta satış yok sayılır (girilmemiş değil), KDV'si 0
        #expect(!t.bilinenKalemler.contains { $0.id == "kdv:2026-08" })
    }

    @Test func maliyetsizEksikIkiAlimlaKapaninca() {
        var s = Fx.base()
        koliliSerumSampuan(&s)
        s.addSale("b", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 150, gross: tl(1_500))
        s.addPurchase("k2", "2026-02-01", .material(Fx.koliId), qty: 60, paid: tl(600))
        s.addPurchase("k3", "2026-03-01", .material(Fx.koliId), qty: 100, paid: tl(2_000))
        let e = Engine(s)
        // Ocak 150 × 10 (ilk alımın fiyatı) = 1.500; mart: kalan 90 eksik × (20 − 10) = 900; stok 10 × 20 = 200
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost == tl(1_500))
        #expect(e.stoktanGider(from: "2026-03", to: "2026-03", category: .ambalaj) == tl(900))
        #expect(e.balance(.material(Fx.koliId)).value == tl(200))
    }
}
