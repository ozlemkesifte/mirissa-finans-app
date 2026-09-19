import Testing
import Foundation
@testable import MirissaCore

/// 5. denetim turunda bulunan hataların düzeltmeleri. Beklenen rakamlar elle hesaplandı.
@Suite("Denetim 5: hesap")
@MainActor
struct AuditRound5HesapTests {

    @Test func raporTutarlariDogruOkunur() {
        #expect(RaporIceAktarma.tutar("12,500") == 1_250)        // 12,5 TL
        #expect(RaporIceAktarma.tutar("1,250") == 125)           // 1,25 TL
        #expect(RaporIceAktarma.tutar("-0,50") == -50)
        #expect(RaporIceAktarma.tutar("1,234,567") == 123_456_700)
        #expect(RaporIceAktarma.tutar("12.500") == 1_250_000)    // binlik nokta
        #expect(RaporIceAktarma.tutar("0.125") == 13)            // 0,125 TL
    }

    @Test func stoktanOnceGirilenSatisinMaliyetiKaybolmaz() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(1_000))
        s.addPurchase("p", "2026-09-05", .product(Fx.sampuanId), qty: 100, paid: tl(1_000))
        let e = Engine(s)
        // Ağustos satışı eylül alımının fiyatıyla (10 TL) maliyetlenir; stokta 90 adet × 10 TL kalır
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-08").productCost == tl(100))
        #expect(e.balance(.product(Fx.sampuanId)).qty == 90)
        #expect(e.balance(.product(Fx.sampuanId)).value == tl(900))
    }

    @Test func kilitliAyinKdvsiOncekiAyDegisinceKorunur() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.addSale("t", "2026-07", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(12_000))
        s.sales[0].vatRate = .yirmi; s.sales[0].vatIncluded = true
        s.settings.ek.kilitliAylar = ["2026-07"]
        let st = AppStore.inMemory(s)
        let once = st.engine.vatStatus("2026-07")
        st.addExpense(Expense(id: "haz", date: "2026-06-10", name: "Kira", amount: tl(12_000),
                              category: .sabit, recurrence: .tek, vatRate: .yirmi, vatIncluded: true))
        #expect(st.sonHata != nil)
        #expect(st.engine.vatStatus("2026-07") == once)
        #expect(st.state.expenses.isEmpty)
    }

    @Test func kilitliAydakiAliminTaksitiOdenebilir() {
        var s = Fx.base()
        var p = StockPurchase(id: "v", date: "2026-07-10", item: .material(Fx.koliId), qty: 100, unit: .adet,
                              totalPaid: tl(3_000))
        p.odeme = OdemePlani.esit(toplam: tl(3_000), pesinat: tl(1_000), taksitSayisi: 2, ilkVade: "2026-08-10")
        s.purchases = [p]
        s.settings.ek.kilitliAylar = ["2026-07"]
        let st = AppStore.inMemory(s)
        let t = st.state.purchases[0].odeme!.taksitler[0]
        st.taksitOdendi(purchaseId: "v", taksitId: t.id, tarih: "2026-08-10")
        #expect(st.sonHata == nil)
        #expect(st.state.purchases[0].odeme!.taksitler[0].odendi)
    }

    @Test func kanalArsiviGecmisUcretiSilmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.channels[0].setRates(ChannelRates(from: "2026-01-01", platformFeeMonthly: tl(1_200)))
        s.addSale("mar", "2026-03", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 1, gross: tl(100))
        let st = AppStore.inMemory(s)
        let haziran = st.engine.companyMonth("2026-06").gercekKar
        st.setChannelArchived(ChannelIds.trendyol, true)
        #expect(st.engine.companyMonth("2026-06").gercekKar == haziran)
        #expect(haziran == -tl(1_200))
        // Arşivlendiği ay hâlâ ücretli, sonraki ay değil
        let buAy = Dates.currentMonth()
        #expect(st.engine.companyMonth(buAy).gercekKar == -tl(1_200))
        #expect(st.engine.companyMonth(Dates.addMonths(buAy, 1)).gercekKar == 0)
    }

    @Test func bolunenGiderIkiKezSayilmazDegismedenBolunmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik))
        let st = AppStore.inMemory(s)
        // Hiçbir şey değişmeden kaydet: bölünmez
        st.giderGuncelleAydanItibaren(st.state.expenses[0], ay: "2026-09")
        #expect(st.state.expenses.count == 1)
        // Tutar değişir: bölünür; eski parça yeniden başlatılamaz
        var e = st.state.expenses[0]; e.amount = tl(1_200)
        st.giderGuncelleAydanItibaren(e, ay: "2026-09")
        st.resumeExpense("k")
        #expect(st.engine.companyMonth("2026-09").ortakGider == tl(1_200))
        #expect(st.engine.companyMonth("2026-08").ortakGider == tl(1_000))
    }

    @Test func durdurulanGiderYenidenBaslayincaAradakiAylarEklenmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik, endMonth: "2026-03"))
        let st = AppStore.inMemory(s)
        st.resumeExpense("k", buAy: "2026-09")
        #expect(st.engine.companyMonth("2026-03").ortakGider == tl(1_000))
        #expect(st.engine.companyMonth("2026-06").ortakGider == 0)
        #expect(st.engine.companyMonth("2026-09").ortakGider == tl(1_000))
    }

    @Test func tekAyinAdiDegisebilir() {
        var s = Fx.base()
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik))
        let st = AppStore.inMemory(s)
        st.overrideExpense("k", month: "2026-05", amount: tl(900), name: "Kira (indirimli)")
        #expect(st.engine.expenseInstances(month: "2026-05").first?.name == "Kira (indirimli)")
        #expect(st.engine.expenseInstances(month: "2026-06").first?.name == "Kira")
    }

    @Test func kanalaOzelFiyatEtiketeDusmez() {
        var p = Fx.sampuan()
        p.setPrice(tl(100), channelId: nil, from: "1970-01-01")
        #expect(p.kanalaOzelFiyat(ChannelIds.trendyol, on: "2026-09-19") == nil)
        p.setPrice(tl(120), channelId: ChannelIds.trendyol, from: "1970-01-01")
        #expect(p.kanalaOzelFiyat(ChannelIds.trendyol, on: "2026-09-19") == tl(120))
    }

    @Test func kismiIadeSiparisiSilmezTamIadeIadeOlur() {
        let csv = """
        Name,Created at,Lineitem name,Lineitem quantity,Lineitem price,Financial Status,Lineitem sku
        #1,2026-08-03 10:00:00 +0300,Sampuan,2,500.00,partially_refunded,S
        #2,2026-08-04 10:00:00 +0300,Sampuan,1,500.00,refunded,S
        #3,2026-08-05 10:00:00 +0300,Sampuan,1,500.00,paid,S
        #4,2026-08-06 10:00:00 +0300,Sampuan,1,500.00,voided,S
        """
        let t = RaporIceAktarma.oku(csv)
        let k = RaporIceAktarma.kalemler(t, sutun: RaporIceAktarma.sutunlariBul(t.basliklar)).kalemler
        let r = RaporIceAktarma.donustur(k, kanalId: "ty", eslesme: ["S": "p"], mevcutAylar: [],
                                         urunKdvOrani: { _ in nil })
        // 2 + 1 + 1 gönderildi (iptal edilen #4 hariç); #2 tamamen iade
        #expect(r.satislar.first?.qty == 4)
        #expect(r.satislar.first?.grossSales == tl(2_000))
        #expect(r.satislar.first?.returnsQty == 1)
        #expect(r.satislar.first?.returnsAmount == tl(500))
        #expect(r.aylar.first?.orderCount == 3)
    }

    @Test func sonradanIadeEdilenSiparisIadeOlarakEklenir() {
        func kalem(_ no: String, iade: Bool = false) -> RaporIceAktarma.Kalem {
            .init(siparisNo: no, tarih: "2026-08-03", urunAnahtari: "s", urunAdi: "Ş", adet: 1, tutar: tl(100),
                  indirim: 0, iptal: false, iade: iade)
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
        aktar([kalem("1"), kalem("2")])
        aktar([kalem("1", iade: true), kalem("2")])
        aktar([kalem("1", iade: true), kalem("2")])   // tekrar: iade ikinci kez eklenmez
        let satis = st.state.sales.filter { $0.month == "2026-08" }
        #expect(satis.count == 1)
        #expect(satis.reduce(0) { $0 + $1.qty } == 2)
        #expect(satis.reduce(0) { $0 + $1.returnsQty } == 1)
        #expect(satis.reduce(0) { $0 + $1.returnsAmount } == tl(100))
    }

    @Test func malzemeAyariGecmisiDegistirmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.materials = s.materials.map { var m = $0; if m.id == Fx.koliId { m.perOrder = false; m.packSizesRaw = ["paket": 50] }; return m }
        s.addPurchase("k", "2026-01-02", .material(Fx.koliId), qty: 2, unit: .paket, paid: tl(1_000))
        s.products[1] = Fx.serum(cost: 0)
        s.products[1].recipe = [RecipeLine(id: "r", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.addSale("o", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 20, gross: tl(2_000))
        s.channelMonths.append(ChannelMonth(month: "2026-01", channelId: ChannelIds.trendyol, orderCount: 10))
        let st = AppStore.inMemory(s)
        let ambalaj = st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost
        #expect(ambalaj == tl(200))                         // 20 × 1 koli × 10 TL
        #expect(st.engine.qty(.material(Fx.koliId)) == 80)  // 2 paket × 50 − 20
        var m = st.state.material(Fx.koliId)!
        m.perOrder = true
        m.packSizesRaw = ["paket": 100]
        st.updateMaterial(m)
        #expect(st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost == ambalaj)
        #expect(st.engine.qty(.material(Fx.koliId)) == 80)
    }

    @Test func eldenMaliyetliUrundeHasarliIadeGiderOlur() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: tl(100)); s.products[0].recipe = []
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(2_000),
                  returnsAmount: tl(400), returnsQty: 2, restock: false)
        let e = Engine(s)
        // 8 net adet × 100 = 800 ürün maliyeti; 2 hasarlı × 100 = 200 fire
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-08").productCost == tl(800))
        #expect(e.stoktanGider(from: "2026-08", to: "2026-08", category: .stokKaybi) == tl(200))
    }

    @Test func nakitTahmininde_KdvTahminiGecikmisTaksitVeCiftSayim() throws {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        for ay in ["2026-06", "2026-07", "2026-08"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(12_000))
            s.addPurchase("al\(ay)", "\(ay)-10", .material(Fx.koliId), qty: 100, paid: tl(3_000))
        }
        for i in s.sales.indices { s.sales[i].vatRate = .yirmi; s.sales[i].vatIncluded = true }
        for i in s.purchases.indices { s.purchases[i].vatRate = .yok }
        s.settings.capitalizePurchases = true
        // 25 Eylül'e girilmiş alım (ayın ortalamasıyla aynı)
        s.purchases.append(StockPurchase(id: "ileri", date: "2026-09-25", item: .material(Fx.koliId), qty: 100,
                                         unit: .adet, totalPaid: tl(3_000), vatRate: .yok))
        // Vadesi 5 Eylül'de geçmiş, ödenmemiş taksit
        var v = StockPurchase(id: "v", date: "2026-08-01", item: .material(Fx.patpatId), qty: 10, unit: .adet,
                              totalPaid: tl(4_000), vatRate: .yok)
        v.odeme = OdemePlani(pesinat: 0, taksitler: [Taksit(id: "t1", vade: "2026-09-05", tutar: tl(4_000))])
        s.purchases.append(v)
        s.settings.ek.kasaBakiye = tl(100_000)
        s.settings.ek.kasaTarih = "2026-09-19"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-09-19"))
        // Gecikmiş taksit ilk güne yazılır
        #expect(t.bilinenKalemler.contains { $0.id == "gecikmis:v:t1" && $0.gun == "2026-09-20" && $0.tutar == -tl(4_000) })
        // Eylül KDV'si (henüz satış yok) 3 ay ortalamasıyla: 12.000'in KDV'si 2.000
        #expect(t.bilinenKalemler.first { $0.id == "kdv:2026-09" }?.tutar == -tl(2_000))
        // Eylül'ün alım tahmini, bilinen 3.000'lik alım kadar azalır: 1. haftada yalnız bilinen kalemler
        // (4.000 gecikmiş taksit + 3.000 alım) çıkar, tahmin eklenmez
        #expect(t.haftalar[0].cikis == tl(7_000))
    }

    @Test func hakedisFarkiKdvHaricKesintideKapanir() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = false
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(12_000))
        s.sales[0].vatRate = .yirmi; s.sales[0].vatIncluded = true
        s.channelMonths.append(ChannelMonth(month: "2026-08", channelId: ChannelIds.trendyol, orderCount: 10,
                                            payoutActual: tl(9_000)))
        let st = AppStore.inMemory(s)
        // 12.000 − (2.400 + %20 KDV = 2.880) = 9.120 beklenen; 9.000 yattı → 120 fark
        #expect(st.engine.hakedis(month: "2026-08", channelId: ChannelIds.trendyol)?.fark == tl(120))
        st.hakedisFarkiniKesintiyeYaz(month: "2026-08", channelId: ChannelIds.trendyol)
        #expect(st.engine.hakedis(month: "2026-08", channelId: ChannelIds.trendyol)?.fark == 0)
    }

    @Test func iadeAnaliziKoliyiSiparisBasinaSayar() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.materials = s.materials.map { var m = $0; if m.id == Fx.koliId { m.perOrder = true }; return m }
        s.addPurchase("k", "2026-01-02", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.products[1] = Fx.serum(cost: 0)
        s.products[1].recipe = [RecipeLine(id: "r", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.addSale("o", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 20, gross: tl(2_000),
                  returnsAmount: tl(400), returnsQty: 4)
        s.channelMonths.append(ChannelMonth(month: "2026-01", channelId: ChannelIds.trendyol, orderCount: 10))
        let satir = Engine(s).iadeAnalizi(from: "2026-01", to: "2026-01").first
        // 20 ürün 10 koliyle gitti: iade edilen 4 ürün 2 koli × 10 TL
        #expect(satir?.bosaGidenAmbalaj == tl(20))
    }

    @Test func gerceklesenAyDokumuBaslikla() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.channels[1].setRates(ChannelRates(from: "1970-01-01", platformFeeMonthly: tl(1_000)))
        s.channels[1].feeVatRate = .yok
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(5_000),
                                  category: .sabit, recurrence: .aylik))
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        let e = Engine(s)
        let p = e.plan(month: "2026-08", today: "2026-09-19")
        #expect(e.sabitGiderDokumu(month: "2026-08", planli: false).toplam == p.fixedCosts)
    }

    @Test func sayimFazlasindaKatkiEksiSabitKaraEsit() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        s.expenses.append(Expense(id: "kargo", date: "2026-08-05", name: "Kargo", amount: tl(1_000),
                                  category: .kargo, recurrence: .tek))
        s.addPurchase("k", "2026-08-01", .material(Fx.koliId), qty: 100, paid: tl(10_000))
        s.counts.append(StockCount(date: "2026-08-20", item: .material(Fx.koliId), countedQty: 150, unit: .adet))
        let r = Engine(s).companyMonth("2026-08")
        #expect(r.toplamKatki - r.toplamSabitGider == r.gercekKar)
    }

    @Test func tekSatisDokumuKarHesabiylaKurusuKurusunaAyni() throws {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].commissionPct = 20
        s.channels[0].paymentPct = 1
        s.channels[0].otherDeductionPct = 2
        s.channels[0].shippingPerOrder = tl(60)
        s.channels[0].serviceFeePerOrder = tl(10)
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.products[0].kdvOrani = .yirmi
        s.products[0].priceHistory = [PricePoint(channelId: ChannelIds.trendyol, amount: tl(1_100), from: "1970-01-01")]
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 1, gross: tl(1_100))
        s.sales[0].vatRate = .yirmi; s.sales[0].vatIncluded = true
        s.channelMonths.append(ChannelMonth(month: "2026-08", channelId: ChannelIds.trendyol, orderCount: 1))
        let e = Engine(s)
        let d = try #require(e.satisHakedisDokumu(productId: Fx.sampuanId, channelId: ChannelIds.trendyol, on: "2026-08-31"))
        #expect(d.netKalan == e.channelResult(channelId: ChannelIds.trendyol, month: "2026-08").kanaldaKalan)
        #expect(d.hesabinaYatan == e.beklenenHakedis(month: "2026-08", channelId: ChannelIds.trendyol))
    }

    @Test func giderOzetiNakitVeAylikPay() {
        let s = Fx.base()
        let e = Expense(date: "2026-09-01", name: "Yazılım", amount: tl(1_200), category: .sabit,
                        recurrence: .yillik, vatRate: .yirmi, vatIncluded: false)
        let ozet = Validation.expenseSummary(e, state: s).lines
        // 1.200 KDV hariç → 1.440 ödenir; kâra ayda 100
        #expect(ozet.first?.hasPrefix(Money.format(tl(1_440))) == true)
        #expect(ozet.contains { $0.contains(Money.format(tl(100))) && $0.contains("her ay") })
    }

    // MARK: Doğrulama turunda bulunanlar

    @Test func kilitliAydakiSatisaSonradanAlimGirilebilir() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addSale("a", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(1_000))
        s.settings.ek.kilitliAylar = ["2026-08"]
        let st = AppStore.inMemory(s)
        st.addPurchase(StockPurchase(id: "p", date: "2026-09-05", item: .product(Fx.sampuanId), qty: 100,
                                     unit: .adet, totalPaid: tl(1_000)))
        #expect(st.sonHata == nil)
        #expect(st.state.purchases.count == 1)
    }

    @Test func maliyetsizGirilenStokIkiKezGiderOlmaz() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.materials = s.materials.map { var m = $0; if m.id == Fx.koliId { m.perOrder = false; m.openingQty = 100; m.openingDate = "2026-01-01" }; return m }
        s.products[1] = Fx.serum(cost: 0)
        s.products[1].recipe = [RecipeLine(id: "r", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.addSale("o", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 50, gross: tl(500))
        s.addPurchase("k", "2026-03-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.addSale("n", "2026-04", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 150, gross: tl(1_500))
        let e = Engine(s)
        let ocak = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost
        let nisan = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-04").packagingCost
        // Maliyetsiz açılış stoğu 0 TL; ödenen 1.000 TL bir kez gider olur. (Birim ambalaj maliyeti
        // kuruşa yuvarlanıp adetle çarpılır: 150 × 6,67 = 1.000,50; iki kez sayılsaydı ~1.334 TL olurdu.)
        #expect(ocak == 0)
        #expect(nisan == 100_050)
    }

    @Test func nakitTahminindeDevredenKdvDusulur() throws {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        for ay in ["2026-06", "2026-07", "2026-08"] {
            s.addSale(ay, ay, channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(12_000))
        }
        for i in s.sales.indices { s.sales[i].vatRate = .yirmi; s.sales[i].vatIncluded = true }
        // Ağustos'ta 120.000 + %20 KDV'li büyük alım: 24.000 indirilecek − 2.000 hesaplanan = 22.000 devreder
        s.purchases.append(StockPurchase(id: "b", date: "2026-08-10", item: .material(Fx.koliId), qty: 1000,
                                         unit: .adet, totalPaid: tl(120_000), vatRate: .yirmi, vatIncluded: false))
        s.settings.ek.kasaBakiye = tl(500_000)
        s.settings.ek.kasaTarih = "2026-09-19"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-09-19"))
        // Devreden KDV birkaç ay yeter: Eylül ve Ekim için KDV ödemesi çıkmaz
        #expect(!t.bilinenKalemler.contains { $0.id == "kdv:2026-09" })
        #expect(!t.bilinenKalemler.contains { $0.id == "kdv:2026-10" })
    }

    @Test func vadesiKilitliAydakiTaksitOdenebilir() {
        var s = Fx.base()
        var p = StockPurchase(id: "v", date: "2026-06-10", item: .material(Fx.koliId), qty: 100, unit: .adet,
                              totalPaid: tl(3_000))
        p.odeme = OdemePlani(pesinat: tl(1_000), taksitler: [Taksit(id: "t", vade: "2026-08-10", tutar: tl(2_000))])
        s.purchases = [p]
        s.settings.ek.kilitliAylar = ["2026-08"]
        let st = AppStore.inMemory(s)
        st.taksitOdendi(purchaseId: "v", taksitId: "t", tarih: "2026-09-19")
        #expect(st.sonHata == nil)
        #expect(st.state.purchases[0].odeme!.taksitler[0].odendi)
    }

    @Test func eskiSurumdeArsivlenenKanalAcilincaGecmisUcretEklenmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.channels[0].setRates(ChannelRates(from: "2026-01-01", platformFeeMonthly: tl(1_200)))
        s.channels[0].archived = true   // önceki sürümde arşivlendi: dönem kaydı yok
        s.addSale("mar", "2026-03", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 1, gross: tl(100))
        let st = AppStore.inMemory(s)
        #expect(st.engine.companyMonth("2026-06").gercekKar == 0)
        st.setChannelArchived(ChannelIds.trendyol, false)
        #expect(st.engine.companyMonth("2026-06").gercekKar == 0)
        #expect(st.engine.companyMonth(Dates.currentMonth()).gercekKar == -tl(1_200))
    }

    @Test func devamiSilinenParcaYenidenBaslatilabilir() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.expenses.append(Expense(id: "k", date: "2026-01-05", name: "Kira", amount: tl(1_000),
                                  category: .sabit, recurrence: .aylik))
        let st = AppStore.inMemory(s)
        var e = st.state.expenses[0]; e.amount = tl(1_200)
        let yeniId = st.giderGuncelleAydanItibaren(e, ay: "2026-09")
        st.deleteExpense(yeniId)
        st.resumeExpense("k", buAy: "2026-09")
        #expect(st.engine.companyMonth("2026-09").ortakGider == tl(1_000))
        #expect(st.engine.companyMonth("2026-05").ortakGider == tl(1_000))
    }

    @Test func maliyetsizStokBitipEksiyeDusenAydaYalnizEksikKisimMaliyetlenir() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.materials = s.materials.map { var m = $0; if m.id == Fx.koliId { m.perOrder = false; m.openingQty = 100; m.openingDate = "2026-01-01" }; return m }
        s.products[1] = Fx.serum(cost: 0)
        s.products[1].recipe = [RecipeLine(id: "r", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.addSale("o", "2026-01", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 150, gross: tl(1_500))
        s.addPurchase("k", "2026-03-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.addSale("n", "2026-04", channel: ChannelIds.trendyol, product: Fx.serumId, qty: 50, gross: tl(500))
        let e = Engine(s)
        // Ocak: 100 maliyetsiz + 50 eksik (sonraki alımın 10 TL'si) = 500 (birim 3,33 TL'ye yuvarlanır:
        // 150 × 3,33 = 499,50; eksik değil tüm adet 10 TL'den sayılsaydı 1.500 olurdu); Nisan: 50 × 10 = 500
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").packagingCost == 49_950)
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-04").packagingCost == tl(500))
    }
}
