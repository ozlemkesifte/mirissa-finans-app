import Testing
import Foundation
@testable import MirissaCore

/// E-ticaret stopajı, komisyon tabanı (KDV hariç fiyattan) ve bir satışın hakediş dökümü.
/// Beklenen rakamların hepsi elle hesaplandı.
@Suite("Stopaj ve komisyon tabanı")
@MainActor
struct StopajKomisyonTests {
    private func durum(kdv: VatRate = .yirmi, tutar: Double = 12_000) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.settings.defaultVatRate = .yirmi
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.sales.append(SalesEntry(id: "s", month: "2026-01", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(tutar),
                                  vatRate: kdv, vatIncluded: true))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-01", channelId: ChannelIds.trendyol,
                                            orderCount: 10))
        return s
    }

    private func trendyol(_ s: AppState, _ ay: MonthKey = "2026-01") -> ChannelMonthResult {
        Engine(s).channelResult(channelId: ChannelIds.trendyol, month: ay)
    }

    // MARK: Komisyon tabanı

    @Test func yuzdeYirmiKdvdeIkiYontemAyni() {
        let eski = trendyol(durum())
        var s = durum(); s.channels[0].komisyonKdvHaric = true
        let yeni = trendyol(s)
        // 12.000 KDV dahil → %20 = 2.400 (KDV dahil) → 2.000 net + 400 KDV
        #expect(eski.commission.amount == tl(2_000))
        #expect(yeni.commission.amount == eski.commission.amount)
        #expect(yeni.feeVat == eski.feeVat)
        #expect(yeni.kanaldaKalan == eski.kanaldaKalan)
    }

    @Test func yuzdeOnKdvliUrundeKomisyonKdvHaricFiyattan() {
        // 11.000 KDV dahil, %10 KDV → 10.000 net satış
        let eski = trendyol(durum(kdv: .on, tutar: 11_000))
        // Eski yöntem: 11.000 × %20 = 2.200 KDV dahil → 1.833,33 net
        #expect(eski.commission.amount == 183_333)
        var s = durum(kdv: .on, tutar: 11_000); s.channels[0].komisyonKdvHaric = true
        let yeni = trendyol(s)
        // Trendyol: 10.000 × %20 = 2.000 + %20 KDV = 2.400 fatura
        #expect(yeni.commission.amount == tl(2_000))
        #expect(yeni.feeVat == tl(400))
    }

    @Test func komisyonTabaniDegisinceGecmisAyDegismez() {
        let st = AppStore.inMemory(durum(kdv: .on, tutar: 11_000))
        let once = st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-01")
        var ch = st.state.channel(ChannelIds.trendyol)!
        ch.komisyonKdvHaric = true
        st.updateChannel(ch)
        let sonra = st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-01")
        #expect(sonra.commission.amount == once.commission.amount)
        #expect(st.state.channel(ChannelIds.trendyol)!.komisyonKdvHaric(on: Dates.today()))
        #expect(!st.state.channel(ChannelIds.trendyol)!.komisyonKdvHaric(on: "2026-01-31"))
        // Geri kapatınca da bugünden başlar; ocak yine aynı
        ch = st.state.channel(ChannelIds.trendyol)!
        ch.komisyonKdvHaric = false
        st.updateChannel(ch)
        #expect(st.engine.channelResult(channelId: ChannelIds.trendyol, month: "2026-01").commission.amount
                == once.commission.amount)
        #expect(!st.state.channel(ChannelIds.trendyol)!.komisyonKdvHaric(on: Dates.today()))
    }

    // MARK: Stopaj

    @Test func stopajKariDegistirmezHakedisVeNakdiAzaltir() {
        let e0 = Engine(durum())
        var s = durum()
        s.channels[0].stopajPct = 1
        s.channels[0].stopajBaslangic = "2025-01-01"
        let e1 = Engine(s)
        let r = e1.channelResult(channelId: ChannelIds.trendyol, month: "2026-01")
        // KDV hariç 10.000 × %1 = 100 TL (komisyon düşülmeden)
        #expect(r.stopaj == tl(100))
        #expect(e1.companyMonth("2026-01").gercekKar == e0.companyMonth("2026-01").gercekKar)
        #expect(e1.companyMonth("2026-01").toplamGider == e0.companyMonth("2026-01").toplamGider)
        // 12.000 − 2.400 komisyon − 100 stopaj
        #expect(e1.beklenenHakedis(month: "2026-01", channelId: ChannelIds.trendyol) == tl(9_500))
        #expect(e1.companyMonth("2026-01").nakitCikisi - e0.companyMonth("2026-01").nakitCikisi == tl(100))
    }

    @Test func stopajBaslangicTarihindenOnceKesilmez() {
        var s = durum()
        s.channels[0].stopajPct = 1
        s.channels[0].stopajBaslangic = "2026-02-01"
        #expect(trendyol(s).stopaj == 0)
    }

    @Test func stopajVergiKarsiligindanDusulur() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.channels[0].stopajPct = 1
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        for (ay, tutar) in [("2026-01", 10_000.0), ("2026-03", 6_000), ("2026-04", 8_000)] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 1, grossSales: tl(tutar)))
        }
        s.expenses.append(Expense(id: "g", date: "2026-02-10", name: "Gider", amount: tl(4_000), category: .diger))
        s.settings.ek.vergiOrani = 25
        let e = Engine(s)
        let mart = e.vergiKarsiligi(month: "2026-03", today: "2026-09-15")!
        // Kâr 12.000 × %25 = 3.000; stopaj 100 + 60 = 160 → 2.840
        #expect(mart.yilBasindanVergi == tl(3_000))
        #expect(mart.yilBasindanStopaj == tl(160))
        #expect(mart.yilBasindanKarsilik == tl(2_840))
        // Şubat sonu: 6.000 × %25 − 100 = 1.400 → mart payı 1.440
        #expect(mart.ayinPayi == tl(1_440))
        #expect(mart.ceyrekGeciciVergi == tl(2_840))
        let nisan = e.vergiKarsiligi(month: "2026-04", today: "2026-09-15")!
        // 20.000 × %25 − 240 = 4.760; 1. çeyrekte 2.840 → 1.920
        #expect(nisan.yilBasindanKarsilik == tl(4_760))
        #expect(nisan.ceyrekGeciciVergi == tl(1_920))
    }

    // MARK: Bir satışın hakediş dökümü

    private func fiyatli(kdv: VatRate = .yirmi, fiyat: Double = 1_200) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.settings.defaultVatRate = .yirmi
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.channels[0].shippingPerOrder = tl(60)
        s.channels[0].serviceFeePerOrder = tl(10)
        s.channels[0].stopajPct = 1
        s.products[0] = Fx.sampuan(cost: tl(300)); s.products[0].recipe = []
        s.products[0].kdvOrani = kdv
        s.products[0].priceHistory = [PricePoint(channelId: ChannelIds.trendyol, amount: tl(fiyat), from: "1970-01-01")]
        return s
    }

    @Test func birSatisinDokumuElleHesapla() throws {
        let e = Engine(fiyatli())
        let d = try #require(e.satisHakedisDokumu(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                                  on: "2026-09-15"))
        #expect(d.satisKdv == tl(200))
        #expect(d.kdvHaricSatis == tl(1_000))
        let k = Dictionary(uniqueKeysWithValues: d.kesintiler.map { ($0.id, $0) })
        #expect(k["komisyon"]?.brut == tl(240)); #expect(k["komisyon"]?.net == tl(200))
        #expect(k["kargo"]?.brut == tl(60)); #expect(k["kargo"]?.net == tl(50))
        #expect(k["hizmet"]?.brut == tl(10)); #expect(k["hizmet"]?.net == 833)
        #expect(d.stopaj == tl(10))
        // 1.200 − 310 kesinti − 10 stopaj
        #expect(d.hesabinaYatan == tl(880))
        // 200 − (40 + 10 + 1,67)
        #expect(d.odenecekKdv == 14_833)
        // 1.000 − 258,33 − 300
        #expect(d.netKalan == 44_167)
        // İki yoldan aynı sonuç ve kâr hesabıyla tutarlı
        #expect(d.hesabinaYatan - d.odenecekKdv + d.stopaj - d.maliyet == d.netKalan)
        let u = try #require(e.unitContribution(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                                on: "2026-09-15"))
        #expect(d.netKalan == u.contribution)
        #expect(d.eksikler.isEmpty)
    }

    @Test func yuzdeOnKdvliUrunDokumu() throws {
        var s = fiyatli(kdv: .on, fiyat: 1_100)
        s.channels[0].komisyonKdvHaric = true
        let e = Engine(s)
        let d = try #require(e.satisHakedisDokumu(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                                  on: "2026-09-15"))
        #expect(d.satisKdv == tl(100))
        #expect(d.kdvHaricSatis == tl(1_000))
        // 1.000 × %20 = 200 + KDV 40
        #expect(d.kesintiler.first { $0.id == "komisyon" }?.brut == tl(240))
        #expect(d.netKalan == tl(1_000) - tl(200) - tl(50) - 833 - tl(300))
        let u = try #require(e.unitContribution(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                                on: "2026-09-15"))
        #expect(d.netKalan == u.contribution)
    }

    @Test func urunKdvOraniYeniSatisaVarsayilanOlur() {
        let s = fiyatli(kdv: .on)
        #expect(s.satisKdvOrani(Fx.sampuanId) == .on)
        #expect(s.satisKdvOrani(Fx.serumId) == .yirmi)
    }
}

/// Denetimde bulunan hataların düzeltmeleri
@Suite("Stopaj ve KDV denetim düzeltmeleri")
@MainActor
struct StopajDenetimTests {
    @Test func nakitTahminiStopajiDuser() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.channels[0].stopajPct = 1
        for ay in ["2026-06", "2026-07", "2026-08"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 30, grossSales: tl(30_000)))
        }
        s.settings.ek.kasaBakiye = tl(1_000)
        s.settings.ek.kasaTarih = "2026-09-15"
        // 30.000 − %1 stopaj = 29.700
        #expect(Engine(s).nakitTahmini(bugun: "2026-09-15")?.aylikTahsilat == tl(29_700))
    }

    @Test func urunKdvOraniGecmisAyinHedefiniDegistirmez() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.sales.append(SalesEntry(id: "h", month: "2026-06", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(1_200),
                                  vatRate: .yirmi, vatIncluded: true))
        s.products[0].kdvOrani = .on
        let e = Engine(s)
        #expect(e.satisKdvOrani(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                on: "2026-06-30", today: "2026-09-18") == .yirmi)
        #expect(e.satisKdvOrani(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                on: "2026-09-18", today: "2026-09-18") == .on)
        // KDV takibi kapalıyken ürün oranı kullanılmaz
        s.settings.vatEnabled = false; s.sales = []
        #expect(Engine(s).satisKdvOrani(productId: Fx.sampuanId, channelId: ChannelIds.trendyol,
                                        on: "2026-09-18", today: "2026-09-18") == .yok)
    }

    @Test func iceAktarmaUrununKdvOraniniKullanir() {
        let k = [RaporIceAktarma.Kalem(siparisNo: "1", tarih: "2026-09-02", urunAnahtari: "a", urunAdi: "A",
                                        adet: 1, tutar: tl(1_100), indirim: 0, iptal: false),
                 RaporIceAktarma.Kalem(siparisNo: "2", tarih: "2026-09-02", urunAnahtari: "b", urunAdi: "B",
                                        adet: 1, tutar: tl(1_200), indirim: 0, iptal: false)]
        let r = RaporIceAktarma.donustur(k, kanalId: "ty", eslesme: ["a": "pa", "b": "pb"], mevcutAylar: [],
                                         urunKdvOrani: { $0 == "pa" ? .on : .yirmi })
        #expect(r.satislar.first { $0.productId == "pa" }?.vatRate == .on)
        #expect(r.satislar.first { $0.productId == "pb" }?.vatRate == .yirmi)
    }

    @Test func stopajKapatilincaGecmisAylarKorunur() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.channels[0].stopajPct = 1
        s.channels[0].stopajBaslangic = "2026-01-01"
        s.channels[0].stopajBitis = "2026-05"
        for ay in ["2026-05", "2026-06"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 1, grossSales: tl(10_000)))
        }
        let e = Engine(s)
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-05").stopaj == tl(100))
        #expect(e.channelResult(channelId: ChannelIds.trendyol, month: "2026-06").stopaj == 0)
        #expect(!s.channels[0].stopajAcik)
    }
}
