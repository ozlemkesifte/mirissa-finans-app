import Testing
import Foundation
@testable import MirissaCore

/// Denetim 8: vergi motoru (2026 kuralları), KDV kayıtları, ödeme komisyonu BSMV, hakediş,
/// elle reklamın nakdi, vergi öncesi/sonrası hedef. Rakamlar elle hesaplandı.
@Suite("Denetim 8 — vergi ve muhasebe")
struct AuditRound8Tests {

    /// KDV'siz, komisyonsuz; ocak–mart her ay 10 × 10.000 TL satış (maliyet yok) → 3 ayda 300.000 TL kâr
    private func karliDurum() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        for ay in ["2026-01", "2026-02", "2026-03"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 10, grossSales: tl(100_000)))
        }
        return s
    }

    // MARK: Vergi türü seçilmeden vergi yok

    @Test func vergiTuruYoksaVergiRakamiYok() {
        #expect(Engine(karliDurum()).vergiKarsiligi(month: "2026-03", today: "2026-04-01") == nil)
    }

    // MARK: Kurumlar vergisi %25 ve asgari %10

    @Test func kurumlarVergisiYuzdeYirmiBes() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(v.yilBasindanKar == tl(300_000))
        #expect(v.matrah == tl(300_000))
        #expect(v.yilBasindanVergi == tl(75_000))       // %25
        #expect(!v.asgariUygulandi)
        #expect(v.vergiSonrasiNetKar == tl(225_000))
        #expect(v.ceyrekGeciciVergi == tl(75_000))
        #expect(v.ceyrekSonOdeme == "2026-05-17")
    }

    @Test func istisnaYuksekseAsgariKurumlarVergisi() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        s.settings.ek.istisnaIndirim = ["2026": tl(250_000)]
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        // Normal: (300.000 − 250.000) × %25 = 12.500; asgari: 300.000 × %10 = 30.000 → 30.000
        #expect(v.matrah == tl(50_000))
        #expect(v.yilBasindanVergi == tl(30_000))
        #expect(v.asgariUygulandi)
    }

    @Test func ilkUcYildaAsgariUygulanmaz() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2024      // 2024, 2025, 2026 ilk üç hesap dönemi
        s.settings.ek.istisnaIndirim = ["2026": tl(250_000)]
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(v.yilBasindanVergi == tl(12_500))
        #expect(!v.asgariUygulandi)
        #expect(!v.eksikler.contains { $0.hasPrefix("şirketin kuruluş yılı") })
    }

    @Test func kurulusYiliGirilmediyseTahminiDenir() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(v.eksikler.contains { $0.hasPrefix("şirketin kuruluş yılı") })
    }

    @Test func gecmisYilZarariVeKkegMatrahaGirer() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        s.settings.ek.gecmisYilZarari = ["2026": tl(300_000)]
        // KKEG işaretli 10.000 TL vergi cezası: kârdan düşer, matraha geri eklenir
        var ceza = Expense(id: "ceza", date: "2026-02-10", name: "Vergi cezası", amount: tl(10_000), category: .diger)
        ceza.kkeg = true
        s.expenses.append(ceza)
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(v.yilBasindanKar == tl(290_000))
        #expect(v.kkegGiderler == tl(10_000))
        // Matrah: 290.000 + 10.000 − 300.000 = 0; asgari: (290.000 + 10.000 − 300.000) × %10 = 0
        #expect(v.matrah == 0)
        #expect(v.yilBasindanVergi == 0)
    }

    // MARK: Gelir vergisi 2026 tarifesi (GVK 103, GVT 332)

    @Test func gelirVergisiTarifesi2026() {
        let t = VergiKurallari.tarife(2026).tarife
        #expect(VergiKurallari.gelirVergisi(tl(190_000), tarife: t) == tl(28_500))
        #expect(VergiKurallari.gelirVergisi(tl(400_000), tarife: t) == tl(70_500))
        #expect(VergiKurallari.gelirVergisi(tl(500_000), tarife: t) == tl(97_500))
        #expect(VergiKurallari.gelirVergisi(tl(1_000_000), tarife: t) == tl(232_500))
        #expect(VergiKurallari.gelirVergisi(tl(5_300_000), tarife: t) == tl(1_737_500))
        #expect(VergiKurallari.gelirVergisi(tl(6_000_000), tarife: t) == tl(2_017_500))
        #expect(VergiKurallari.tarife(2026).kesin)
        #expect(!VergiKurallari.tarife(2025).kesin)   // 2025 tarifesi uygulamada doğrulanmış değil
    }

    @Test func sahisGeciciVergiYuzdeOnBesYillikTarife() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sahis"
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        // Yıllık tarife: 300.000 → 28.500 + (110.000 × %20) = 50.500
        #expect(v.yilBasindanVergi == tl(50_500))
        // Geçici vergi %15: 45.000
        #expect(v.ceyrekGeciciVergi == tl(45_000))
        #expect(v.yillikSonOdeme == "2027-03-31")
    }

    // MARK: 4. çeyrek geçici vergi (7566 sayılı Kanun)

    @Test func dorduncuCeyrekGeciciVergiVar() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        s.sales.append(SalesEntry(id: "k", month: "2026-11", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(40_000)))
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-12", today: "2027-01-05"))
        #expect(v.ceyrek == 4)
        // Yıl: 340.000 × %25 = 85.000; önceki çeyrekler 75.000 → 4. çeyrek 10.000
        #expect(v.ceyrekGeciciVergi == tl(10_000))
        #expect(v.ceyrekSonOdeme == "2027-02-17")
        #expect(v.yillikSonOdeme == "2027-04-30")
        #expect(v.yillikBeyandaOdenecek == 0)
    }

    @Test func stopajMahsupEdilirFazlasiIadeDiyeGosterilir() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        s.settings.ek.istisnaIndirim = ["2026": tl(299_000)]
        s.settings.ek.kurulusYili = 2025    // asgari yok
        s.channels[0].stopajPct = 1
        s.channels[0].stopajBaslangic = "2025-01-01"
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        // Stopaj %1 × 300.000 = 3.000; vergi (1.000 × %25) = 250 → fazla 2.750 (iade/mahsup)
        #expect(v.yilBasindanStopaj == tl(3_000))
        #expect(v.yilBasindanVergi == tl(250))
        #expect(v.kalanVergiBorcu == 0)
        #expect(v.mahsupFazlasi == tl(2_750))
    }

    // MARK: Vergi sonrası hedef

    @Test func vergiSonrasiHedefVergiOncesineCevrilir() {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        let e = Engine(s)
        // %25 kurumlar vergisinde 75.000 net için 100.000 vergi öncesi gerekir
        #expect(e.vergiOncesiKar(netKar: tl(75_000), yil: 2026) == tl(100_000))
        s.settings.yearlyProfitGoals = ["2026": tl(750_000)]
        s.settings.ek.vergiSonrasiHedef = ["2026": true]
        let e2 = Engine(s)
        #expect(e2.yillikHedefVergiOncesi(year: 2026) == tl(1_000_000))
        #expect(e2.yillikKarHedefiBasligi(year: 2026) == "Vergi sonrası yıllık 750.000 TL net kâr için")
        #expect(e2.yillikKarHedefiHesaplanamadi(year: 2026) == nil)
    }

    @Test func vergiSonrasiHedefVergiTuruYoksaHesaplanmaz() {
        var s = karliDurum()
        s.settings.profitGoals = ["2026-04": tl(50_000)]
        s.settings.ek.vergiSonrasiHedef = ["2026-04": true]
        let e = Engine(s)
        #expect(e.aylikHedefVergiOncesi(month: "2026-04") == nil)
        #expect(e.karHedefiHesaplanamadi(month: "2026-04") != nil)
        // Vergi öncesi hedef olduğu gibi kullanılır ve öyle yazılır
        s.settings.ek.vergiSonrasiHedef = ["2026-04": false]
        let e2 = Engine(s)
        #expect(e2.aylikHedefVergiOncesi(month: "2026-04") == tl(50_000))
        #expect(e2.karHedefiBasligi(month: "2026-04") == "Vergi öncesi aylık 50.000 TL kâr için")
    }

    @Test func sahisVergiSonrasiHedefTarifeyleCevrilir() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sahis"
        let p = try #require(Engine(s).vergiOncesiKar(netKar: tl(429_500), yil: 2026))
        // 500.000 − 70.500 − 27% × 100.000 = 402.500 ... ters kontrol: P − GV(P) ≥ net ve en küçüğü
        let t = VergiKurallari.tarife(2026).tarife
        #expect(p - VergiKurallari.gelirVergisi(p, tarife: t) >= tl(429_500))
        #expect((p - 1) - VergiKurallari.gelirVergisi(p - 1, tarife: t) < tl(429_500))
    }

    // MARK: KDV kayıtları ve indirilemeyen KDV

    @Test func kdvKayitlariToplamlariKdvDurumuylaAyni() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.sales.append(SalesEntry(id: "a", month: "2026-05", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(12_000),
                                  vatRate: .yirmi, vatIncluded: true))
        s.expenses.append(Expense(id: "m", date: "2026-05-10", name: "Muhasebe", amount: tl(1_200),
                                  category: .sabit, vatRate: .yirmi, vatIncluded: true))
        var arac = Expense(id: "b", date: "2026-05-12", name: "Binek araç yakıt (KKEG kısmı)", amount: tl(600),
                           category: .diger, vatRate: .yirmi, vatIncluded: true)
        arac.kdvIndirilemez = true
        arac.kkeg = true
        s.expenses.append(arac)
        let e = Engine(s)
        let k = e.kdvKayitlari("2026-05")
        let v = e.vatStatus("2026-05")
        #expect(k.filter { $0.tur == .hesaplanan }.reduce(0) { $0 + $1.tutar } == v.hesaplanan)
        #expect(k.filter { $0.tur == .indirilecek }.reduce(0) { $0 + $1.tutar } == v.indirilecek)
        // İndirilemeyen KDV: 600 TL'nin 100 TL'si; indirilecek KDV'ye girmez, gidere eklenir
        #expect(k.first { $0.tur == .indirilemeyen }?.tutar == tl(100))
        #expect(!k.contains { $0.tur == .indirilecek && $0.ad.hasPrefix("Binek") })
        // Gider: muhasebe 1.000 (KDV hariç) + araç 600 (KDV dahil tamamı)
        #expect(e.companyMonth("2026-05").ortakGider == tl(1_600))
        // Nakit: ödenen 1.200 + 600
        #expect(e.kkegGiderleri(from: "2026-05", to: "2026-05") == tl(600))
    }

    // MARK: Ödeme komisyonu BSMV'li (KDV yok)

    @Test func bsmvliOdemeKomisyonununKdvsiYok() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        let shop = s.channels.firstIndex { $0.id == ChannelIds.shopify }!
        s.channels[shop].paymentPct = 3
        s.channels[shop].feeVatRate = .yirmi
        s.sales.append(SalesEntry(id: "a", month: "2026-05", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(120_000),
                                  vatRate: .yirmi, vatIncluded: true))
        let once = Engine(s).channelResult(channelId: ChannelIds.shopify, month: "2026-05")
        // Eski ayar (KDV'li): 3.600 TL'nin 3.000'i gider, 600'ü indirilecek KDV
        #expect(once.commission.amount == tl(3_000))
        #expect(once.feeVat == tl(600))
        s.channels[shop].odemeKesintisiBsmv = true
        let sonra = Engine(s).channelResult(channelId: ChannelIds.shopify, month: "2026-05")
        // BSMV'li: 120.000 × %3 = 3.600 TL tamamı gider, KDV yok
        #expect(sonra.commission.amount == tl(3_600))
        #expect(sonra.feeVat == 0)
    }

    @Test func bsmvAyariTarihliGecmisAyDegismez() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        let shop = s.channels.firstIndex { $0.id == ChannelIds.shopify }!
        s.channels[shop].paymentPct = 3
        s.channels[shop].feeVatRate = .yirmi
        var r = ChannelRates(from: "2026-06-01", paymentPct: 3)
        r.odemeKesintisiBsmv = true
        r.feeVatRate = .yirmi
        s.channels[shop].setRates(ChannelRates(from: "1970-01-01", paymentPct: 3))
        s.channels[shop].setRates(r)
        for ay in ["2026-05", "2026-06"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.shopify,
                                      productId: Fx.sampuanId, qty: 10, grossSales: tl(120_000),
                                      vatRate: .yirmi, vatIncluded: true))
        }
        let e = Engine(s)
        #expect(e.channelResult(channelId: ChannelIds.shopify, month: "2026-05").feeVat == tl(600))
        #expect(e.channelResult(channelId: ChannelIds.shopify, month: "2026-06").feeVat == 0)
    }

    @Test func bsmvKanaldaElleKomisyonOdemeyiKapsamaz() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        let shop = s.channels.firstIndex { $0.id == ChannelIds.shopify }!
        s.channels[shop].commissionPct = 0
        s.channels[shop].paymentPct = 3
        s.channels[shop].feeVatRate = .yirmi
        s.channels[shop].feesIncludeVat = true
        s.channels[shop].odemeKesintisiBsmv = true
        s.sales.append(SalesEntry(id: "a", month: "2026-05", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(120_000),
                                  vatRate: .yirmi, vatIncluded: true))
        // Faturadaki (KDV dahil) 1.200 TL komisyon elle girildi; ödeme komisyonu 3.600 BSMV'li otomatik
        s.channelMonths.append(ChannelMonth(month: "2026-05", channelId: ChannelIds.shopify, commissionActual: tl(1_200)))
        let r = Engine(s).channelResult(channelId: ChannelIds.shopify, month: "2026-05")
        #expect(r.odemeKdvsizTutar == tl(3_600))
        #expect(r.commission.amount == tl(1_000) + tl(3_600))
        #expect(r.feeVat == tl(200))
    }

    @Test func kendiSiteAbonelikKurusuKurusunaDusulur() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        let shop = s.channels.firstIndex { $0.id == ChannelIds.shopify }!
        s.channels[shop].paymentPct = 0
        s.channels[shop].platformFeeMonthly = 9_999          // 99,99 TL KDV dahil
        s.channels[shop].feeVatRate = .yirmi
        s.channels[shop].feesIncludeVat = true
        s.sales.append(SalesEntry(id: "a", month: "2026-05", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(12_000),
                                  vatRate: .yirmi, vatIncluded: true))
        let e = Engine(s)
        let r = e.channelResult(channelId: ChannelIds.shopify, month: "2026-05")
        #expect(r.sabitKesintiBrut == 9_999)
        // Kesinti yalnızca abonelik: beklenen hakediş müşterinin ödediğinin tamamı
        #expect(e.beklenenHakedis(month: "2026-05", channelId: ChannelIds.shopify) == r.netSalesIncVat)
    }

    @Test func elleOranSinirlanirTersHesapBiter() {
        var s = karliDurum()
        s.settings.ek.vergiOrani = 150       // elle düzenlenmiş yedek
        let e = Engine(s)
        // %60 ile sınırlı: 40.000 net için ~100.000 vergi öncesi (kuruş yuvarlamasıyla en küçük yeterli tutar)
        let p = e.vergiOncesiKar(netKar: tl(40_000), yil: 2026) ?? 0
        #expect(abs(p - tl(100_000)) <= 1)
    }

    // MARK: Hakediş: kendi sitede aylık abonelik ödemeden kesilmez

    @Test func kendiSiteAylikUcretBeklenenHakedistenDusulmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        let shop = s.channels.firstIndex { $0.id == ChannelIds.shopify }!
        s.channels[shop].paymentPct = 3
        s.channels[shop].platformFeeMonthly = tl(1_200)
        s.sales.append(SalesEntry(id: "a", month: "2026-05", channelId: ChannelIds.shopify,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        let e = Engine(s)
        // 10.000 − %3 (300) = 9.700; 1.200 TL abonelik kartla ayrıca ödenir
        #expect(e.beklenenHakedis(month: "2026-05", channelId: ChannelIds.shopify) == tl(9_700))
        // Pazaryerinde aylık ücret hakedişten kesilir
        s.channels[0].commissionPct = 0
        s.channels[0].platformFeeMonthly = tl(500)
        s.sales.append(SalesEntry(id: "t", month: "2026-05", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(2_000)))
        #expect(Engine(s).beklenenHakedis(month: "2026-05", channelId: ChannelIds.trendyol) == tl(1_500))
    }

    // MARK: Elle girilen reklamın nakdi (net ile net)

    @Test func elleReklamNakdiNetIleNetKarsilastirilir() {
        var s = Fx.base()
        s.settings.vatEnabled = true
        s.expenses.append(Expense(id: "r", date: "2026-05-05", name: "Reklam", amount: tl(1_200),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol),
                                  vatRate: .yirmi, vatIncluded: true))
        let e0 = Engine(s)
        let once = e0.companyMonth("2026-05").nakitCikisi
        s.channelMonths.append(ChannelMonth(month: "2026-05", channelId: ChannelIds.trendyol, adsActual: tl(1_100)))
        let sonra = Engine(s).companyMonth("2026-05").nakitCikisi
        // Kayıt: 1.000 net (1.200 ödendi). Elle 1.100 net → yalnızca 100 TL fazlası eklenir
        #expect(sonra - once == tl(100))
    }

    // MARK: Bitmemiş ayın yarım verisi aylık hedefin temeli olmaz

    @Test func bitmemisAyYarimVeriAylikHedefTemeliOlmaz() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.products[0].costLines = [CostLine(id: "c", label: "Üretim", amount: tl(200))]
        s.products[0].recipe = []
        s.sales.append(SalesEntry(id: "a", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        s.expenses.append(Expense(id: "kira", date: "2026-08-01", name: "Kira", amount: tl(10_000),
                                  category: .sabit, recurrence: .aylik))
        s.sales.append(SalesEntry(id: "e", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 2, grossSales: tl(2_000)))
        s.expenses.append(Expense(id: "rk", date: "2026-09-01", name: "Reklam", amount: tl(5_000),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol),
                                  behavior: .satisaBagli))
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.basis == .gecmisAy("2026-08"))
        // Ağustos katkısı 800 TL: ceil(10.000 / 800) = 13
        #expect(p.targets.first { $0.isBreakeven }?.orders == 13)
        // Ayın son günü: ay bitti, kendi verisi kullanılır
        #expect(Engine(s).plan(month: "2026-09", today: "2026-09-30").basis == .ayinKendisi)
    }

    // MARK: Nakit tahmini: yıllık kurumlar vergisi ve 4. çeyrek geçici vergi

    @Test func nakitTahmindeYillikVergiVeDorduncuCeyrek() throws {
        var s = karliDurum()
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        s.settings.ek.istisnaIndirim = ["2026": 0]
        s.settings.ek.kasaBakiye = tl(500_000)
        s.settings.ek.kasaTarih = "2027-01-10"
        s.sales.append(SalesEntry(id: "k", month: "2026-11", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(40_000)))
        let t = try #require(Engine(s).nakitTahmini(bugun: "2027-01-10", hafta: 20))
        let q4 = t.bilinenKalemler.first { $0.id == "vergi:2026-12" }
        #expect(q4?.gun == "2027-02-17")
        #expect(q4?.tutar == -tl(10_000))
    }

    // MARK: Stok kapasitesi hedefi değiştirmez, yalnızca bilgi

    @Test func stokKapasitesiEnKucukKalem() throws {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0].recipe = [RecipeLine(id: "k", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.addPurchase("u", "2026-05-01", .product(Fx.sampuanId), qty: 1_000, paid: tl(1_000))
        s.addPurchase("k", "2026-05-01", .material(Fx.koliId), qty: 200, paid: tl(200))
        s.addSale("a", "2026-06", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 100, gross: tl(10_000))
        s.channelMonths.append(ChannelMonth(month: "2026-06", channelId: ChannelIds.trendyol, orderCount: 100))
        let e = Engine(s)
        let k = try #require(e.stokKapasitesi())
        // Koli 100 kaldı, siparişte 1 → 100 kargo; ürün 900 kaldı → 900. En küçüğü koli.
        #expect(k.kargo == 100)
        #expect(k.darbogaz == "Kargo kolisi")
    }
}
