import Testing
import Foundation
@testable import MirissaCore

/// Denetim 9: KDV dönemi (kanuni kayıt) ile ödeme tarihinin ayrılması, gerçekten ödenen geçici vergi,
/// asgari kurumlar vergisi matrahı, %5 vergiye uyum indirimi. Rakamlar elle hesaplandı.
@Suite("Denetim 9 — vergi dönemleri ve ödemeler")
struct AuditRound9Tests {

    /// Ağustos tarihli 12.000 TL (KDV dahil %20) fatura: 10.000 gider + 2.000 KDV
    private func faturaDurumu(odeme: DateKey?, kdvDonemi: MonthKey?) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = true
        var e = Expense(id: "f", date: "2026-08-20", name: "Danışmanlık", amount: tl(12_000),
                        category: .diger, vatRate: .yirmi, vatIncluded: true)
        e.odemeTarihi = odeme
        e.kdvDonemi = kdvDonemi
        s.expenses.append(e)
        return s
    }

    @Test func faturaAgustosOdemeEylulKdvAgustosta() {
        let e = Engine(faturaDurumu(odeme: "2026-09-10", kdvDonemi: nil))
        let agu = e.companyMonth("2026-08"), eyl = e.companyMonth("2026-09")
        // İndirilecek KDV Ağustos'ta
        #expect(e.vatStatus("2026-08").indirilecek == tl(2_000))
        #expect(e.vatStatus("2026-09").indirilecek == 0)
        // Nakit çıkışı Eylül'de
        #expect(agu.nakitCikisi == 0)
        #expect(eyl.nakitCikisi == tl(12_000))
        // Gider (kâr) fatura ayında
        #expect(agu.toplamGider == tl(10_000))
        #expect(eyl.toplamGider == 0)
    }

    @Test func kanuniKayitSonrakiDonemdeyseKdvOradaIndirilir() {
        let e = Engine(faturaDurumu(odeme: nil, kdvDonemi: "2026-10"))
        #expect(e.vatStatus("2026-08").indirilecek == 0)
        #expect(e.vatStatus("2026-10").indirilecek == tl(2_000))
        // Ödeme fatura tarihinde: nakit Ağustos'ta, KDV dahil
        #expect(e.companyMonth("2026-08").nakitCikisi == tl(12_000))
        #expect(e.companyMonth("2026-10").nakitCikisi == 0)
        #expect(e.companyMonth("2026-08").toplamGider == tl(10_000))
        // KDV kayıtları nedeniyle birlikte o dönemde
        #expect(e.kdvKayitlari("2026-10").first?.tur == .indirilecek)
    }

    @Test func odemeTarihiKdvyiEtkilemez() {
        let a = Engine(faturaDurumu(odeme: nil, kdvDonemi: nil))
        let b = Engine(faturaDurumu(odeme: "2026-12-01", kdvDonemi: nil))
        for ay in ["2026-08", "2026-09", "2026-10", "2026-11", "2026-12"] {
            #expect(a.vatStatus(ay) == b.vatStatus(ay), "\(ay)")
            #expect(a.companyMonth(ay).toplamGider == b.companyMonth(ay).toplamGider, "\(ay)")
        }
        #expect(b.companyMonth("2026-12").nakitCikisi == tl(12_000))
    }

    @Test func kdvDonemiFaturadanOnceVeSureSonrasiEngellenir() {
        var e = Expense(id: "f", date: "2026-08-20", name: "X", amount: tl(100), category: .diger, vatRate: .yirmi)
        e.kdvDonemi = "2026-07"
        #expect(Validation.expense(e, state: Fx.base()).contains { $0.title == "KDV dönemi faturadan önce olamaz" })
        e.kdvDonemi = "2028-01"
        #expect(Validation.expense(e, state: Fx.base()).contains { $0.title == "KDV indirim süresi geçmiş" })
        e.kdvDonemi = "2027-12"
        #expect(!Validation.expense(e, state: Fx.base()).contains { $0.title.hasPrefix("KDV") })
    }

    @Test func nakitTahminiOdemeGunundeGosterir() throws {
        var s = faturaDurumu(odeme: "2026-09-10", kdvDonemi: nil)
        s.settings.ek.kasaBakiye = tl(50_000)
        s.settings.ek.kasaTarih = "2026-09-01"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-09-01"))
        let k = t.bilinenKalemler.filter { $0.ad.hasPrefix("Danışmanlık") }
        #expect(k.count == 1)
        #expect(k.first?.gun == "2026-09-10")
        #expect(k.first?.tutar == -tl(12_000))
    }

    // MARK: Geçici vergi: yalnız gerçekten ödenen mahsup edilir

    /// Ocak–Mart 300.000 TL kâr, kurumlar vergisi (asgari yok: kuruluş 2025)
    private func sirket() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        for ay in ["2026-01", "2026-02", "2026-03"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 10, grossSales: tl(100_000)))
        }
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2025
        return s
    }

    @Test func odenmemisGeciciVergiMahsupEdilmez() throws {
        let v = try #require(Engine(sirket()).vergiKarsiligi(month: "2026-12", today: "2026-12-31"))
        let q1 = try #require(v.geciciDonemler.first { $0.ceyrek == 1 })
        #expect(q1.tahakkuk == tl(75_000))
        #expect(q1.odenen == 0)
        #expect(q1.kalan == tl(75_000))
        #expect(q1.vade == "2026-05-17")
        // Sonraki dönemlerde kâr yok: tahakkuk 0 (önceki dönemin hesaplanan geçici vergisi düşülür)
        #expect(v.geciciDonemler.dropFirst().allSatisfy { $0.tahakkuk == 0 })
        #expect(v.odenmisGeciciVergiler == 0)
        #expect(v.kalanVergiBorcu == tl(75_000))
        #expect(v.odenmemisGecici(bugun: "2026-12-31") == tl(75_000))
    }

    @Test func odenenGeciciVergiMahsupEdilir() throws {
        var s = sirket()
        s.settings.ek.geciciVergiOdemeleri = ["2026-1": VergiOdemesi(tutar: tl(50_000), tarih: "2026-05-15")]
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-12", today: "2026-12-31"))
        let q1 = try #require(v.geciciDonemler.first { $0.ceyrek == 1 })
        #expect(q1.odenen == tl(50_000))
        #expect(q1.kalan == tl(25_000))
        #expect(v.odenmisGeciciVergiler == tl(50_000))
        // Yıllık 75.000 − ödenen 50.000 = 25.000 (ödenmeyen 25.000 mahsup edilmez)
        #expect(v.kalanVergiBorcu == tl(25_000))
        // Ödeme tahakkuku değiştirmez
        #expect(q1.tahakkuk == tl(75_000))
    }

    @Test func nakitTahmindeGerceklesenVePlanlananAyri() throws {
        var s = sirket()
        s.settings.ek.kasaBakiye = tl(500_000)
        s.settings.ek.kasaTarih = "2026-05-01"
        s.settings.ek.geciciVergiOdemeleri = ["2026-1": VergiOdemesi(tutar: tl(50_000), tarih: "2026-05-10")]
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-05-01"))
        let odeme = t.bilinenKalemler.first { $0.id == "vergiodeme:2026-1" }
        #expect(odeme?.tutar == -tl(50_000))
        #expect(odeme?.tahmini == false)
        #expect(odeme?.gun == "2026-05-10")
        let plan = t.bilinenKalemler.first { $0.id == "vergi:2026-1" }
        #expect(plan?.tutar == -tl(25_000))
        #expect(plan?.tahmini == true)
        #expect(plan?.gun == "2026-05-17")
        #expect(plan?.ad.hasPrefix("Planlanan vergi ödemesi") == true)
    }

    @Test func tamOdenenDonemPlanlanmaz() throws {
        var s = sirket()
        s.settings.ek.kasaBakiye = tl(500_000)
        s.settings.ek.kasaTarih = "2026-05-01"
        s.settings.ek.geciciVergiOdemeleri = ["2026-1": VergiOdemesi(tutar: tl(75_000), tarih: "2026-05-12")]
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-05-01"))
        #expect(!t.bilinenKalemler.contains { $0.id == "vergi:2026-1" })
        #expect(t.bilinenKalemler.contains { $0.id == "vergiodeme:2026-1" })
    }

    // MARK: Asgari kurumlar vergisi matrahı (KVK 32/C-6, GİB 2026 rehberi)

    /// 300.000 TL kâr, 300.000 TL geçmiş yıl zararı, kuruluş 2020
    private func zararli() -> AppState {
        var s = sirket()
        s.settings.ek.kurulusYili = 2020
        s.settings.ek.gecmisYilZarari = ["2026": tl(300_000)]
        return s
    }

    @Test func asgariMatrahtanGecmisYilZarariVarsayilandaDusulmez() throws {
        let v = try #require(Engine(zararli()).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        // Normal matrah: 300.000 − 300.000 = 0 → normal KV 0
        #expect(v.matrah == 0)
        #expect(v.normalVergi == 0)
        // Asgari matrah: ticari kâr + KKEG = 300.000 → %10 = 30.000
        #expect(v.asgariMatrah == tl(300_000))
        #expect(v.asgariVergi == tl(30_000))
        #expect(v.yilBasindanVergi == tl(30_000))
        #expect(!v.asgariZararIndirildi)
    }

    @Test func muhasebeciUygulamasiSecilirseZararAsgaridenDusulur() throws {
        var s = zararli()
        s.settings.ek.asgariZararIndirimi = true
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(v.asgariMatrah == 0)
        #expect(v.yilBasindanVergi == 0)
        #expect(v.asgariZararIndirildi)
    }

    @Test func asgariMatrahSifirdanBuyukDegilseAsgariVergiYok() throws {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.settings.ek.vergiTuru = "sirket"
        s.settings.ek.kurulusYili = 2020
        s.expenses.append(Expense(id: "g", date: "2026-02-01", name: "Gider", amount: tl(10_000), category: .diger))
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(v.asgariMatrah == 0)
        #expect(v.yilBasindanVergi == 0)
    }

    // MARK: %5 vergiye uyumlu mükellef indirimi (GVK mük. 121)

    @Test func uyumIndirimiBilinmiyorsaUygulanmazTahminiDenir() throws {
        let v = try #require(Engine(sirket()).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(v.uyumDurumu == .bilinmiyor)
        #expect(v.uyumIndirimi == 0)
        #expect(v.eksikler.contains("%5 uyum indirimi şartları (hesaba katılmadı)"))
        var s = sirket(); s.settings.ek.uyumIndirimi = "hayir"
        let h = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        #expect(h.uyumIndirimi == 0)
        #expect(!h.eksikler.contains { $0.hasPrefix("%5") })
    }

    @Test func uyumIndirimiEvetseOdenecektenDusulur() throws {
        var s = sirket()
        s.settings.ek.uyumIndirimi = "evet"
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        // 75.000 × %5 = 3.750
        #expect(v.uyumIndirimi == tl(3_750))
        #expect(v.kullanilanUyumIndirimi == tl(3_750))
        #expect(v.kalanVergiBorcu == tl(71_250))
        #expect(v.vergiSonrasiNetKar == tl(300_000) - tl(71_250))
        // 2026 kazancı için üst sınır henüz yayımlanmadı: söylenir
        #expect(v.uyumUstSiniriBilinmiyor)
    }

    @Test func uyumIndirimiAsgariVergiyeDeUygulanir() throws {
        var s = zararli()
        s.settings.ek.uyumIndirimi = "evet"
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-03", today: "2026-04-01"))
        // Asgari 30.000 × %5 = 1.500 → 28.500 (asgarinin altına inebilir: KVGT 23 §32.5.4)
        #expect(v.uyumIndirimi == tl(1_500))
        #expect(v.kalanVergiBorcu == tl(28_500))
    }

    @Test func uyumIndirimiTevkifatVeGecicidenSonraKalanlaSinirli() throws {
        var s = sirket()
        s.settings.ek.uyumIndirimi = "evet"
        s.settings.ek.geciciVergiOdemeleri = ["2026-1": VergiOdemesi(tutar: tl(73_000), tarih: "2026-05-15")]
        let v = try #require(Engine(s).vergiKarsiligi(month: "2026-12", today: "2026-12-31"))
        // Ödenmesi gereken: 75.000 − 73.000 = 2.000; indirim 3.750'nin 2.000'i kullanılır, 1.750 devreder
        #expect(v.odenmesiGereken == tl(2_000))
        #expect(v.kullanilanUyumIndirimi == tl(2_000))
        #expect(v.uyumIndirimiDevreden == tl(1_750))
        #expect(v.kalanVergiBorcu == 0)
        // Devreden kısım kullanılacağı bilinmediği için net kâra eklenmez
        #expect(v.vergiSonrasiNetKar == tl(300_000) - tl(73_000))
    }

    @Test func uyumUstSiniri2025() throws {
        #expect(VergiKurallari.bilinen[2025]?.uyumIndirimiUstSiniri == tl(12_000_000))
        #expect(VergiKurallari.bilinen[2026]?.uyumIndirimiUstSiniri == nil)
    }

    // MARK: Ödeme tarihi aynı ayda farklı gün / kilitli ay

    @Test func ayniAyFarkliOdemeGunuNakitteOGunde() throws {
        var s = faturaDurumu(odeme: "2026-08-28", kdvDonemi: nil)
        s.settings.ek.kasaBakiye = tl(50_000)
        s.settings.ek.kasaTarih = "2026-08-25"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-08-25"))
        let k = t.bilinenKalemler.filter { $0.ad.hasPrefix("Danışmanlık") }
        #expect(k.count == 1)
        #expect(k.first?.gun == "2026-08-28")
        #expect(Engine(s).companyMonth("2026-08").nakitCikisi == tl(12_000))
        #expect(Engine(s).vatStatus("2026-08").indirilecek == tl(2_000))
    }

    @MainActor @Test func kilitliAyaYalnizcaOdemeTasimakKilidiBozmaz() {
        var s = faturaDurumu(odeme: nil, kdvDonemi: nil)
        s.settings.ek.kilitliAylar = ["2026-08"]
        let st = AppStore.inMemory(s)
        var e = st.state.expenses[0]
        e.odemeTarihi = "2026-09-15"
        st.updateExpense(e)
        #expect(st.sonHata == nil)
        // KDV'yi kilitli aydan çıkarmak engellenir
        e.kdvDonemi = "2026-09"
        st.updateExpense(e)
        #expect(st.sonHata != nil)
    }

    // MARK: Geçen yılın vergisi: beyan süresi geçince

    @Test func beyanSuresiGecinceGeciciAyricaPlanlanmazYillikKalanPlanlanir() throws {
        var s = sirket()
        s.settings.ek.kasaBakiye = tl(500_000)
        s.settings.ek.kasaTarih = "2027-05-05"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2027-05-05"))
        #expect(!t.bilinenKalemler.contains { $0.id.hasPrefix("vergi:2026-") })
        let y = t.bilinenKalemler.first { $0.id == "yillikvergi:2026:0" }
        #expect(y?.tutar == -tl(75_000))
        #expect(y?.tahmini == true)
        // Yıllık ödeme girilince planlanmaz
        s.settings.ek.geciciVergiOdemeleri = ["2026-yillik": VergiOdemesi(tutar: tl(75_000), tarih: "2027-04-28")]
        let t2 = try #require(Engine(s).nakitTahmini(bugun: "2027-05-05"))
        #expect(!t2.bilinenKalemler.contains { $0.id.hasPrefix("yillikvergi:") })
    }
}
