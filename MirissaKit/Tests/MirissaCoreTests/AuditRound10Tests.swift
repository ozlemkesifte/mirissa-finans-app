import Testing
import Foundation
@testable import MirissaCore

/// Denetim 10: tarihli paket boyutu kontrolleri, nakit tahmininde ayın gün sayısı,
/// sipariş numarasız rapor satırı, kilitli ayın kârının korunması.
@Suite("Denetim 10 — bütünlük, nakit, içe aktarma, kilit")
struct AuditRound10Tests {

    /// Koli paket boyutu (1 paket = 10 adet) 2026-06-01'de kaldırıldı
    private func paketiKaldirilmisKoli() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        let i = s.materials.firstIndex { $0.id == Fx.koliId }!
        s.materials[i].packSizesRaw = [:]
        s.materials[i].eskiAyarlar = [MalzemeSurumu(gecerliSon: "2026-05-31", perOrder: nil,
                                                    packSizesRaw: ["paket": 10])]
        return s
    }

    @Test func eskiPaketBirimliAlimBozukSayilmaz() {
        var s = paketiKaldirilmisKoli()
        s.addPurchase("p", "2026-03-10", .material(Fx.koliId), qty: 5, unit: .paket, paid: tl(500))
        let e = Engine(s)
        // Alım o günkü ayarla stoğa girdi: 5 paket = 50 adet
        #expect(e.qty(.material(Fx.koliId)) == 50)
        // Bugünkü ayara bakıp "hesaba hiç girmiyor" denmez
        #expect(!Integrity.check(s).contains { $0.recordId == "p" })
    }

    @Test func gercektenCevrilemeyenAlimBugunBirimTanimlansaDaBildirilir() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        // Alım günü "paket" tanımsız: stoğa hiç girmedi
        s.addPurchase("p", "2026-03-10", .material(Fx.koliId), qty: 5, unit: .paket, paid: tl(500))
        #expect(Engine(s).qty(.material(Fx.koliId)) == 0)
        #expect(Integrity.check(s).contains { $0.recordId == "p" })
        // Bugün paket tanımlansa bile o alım hâlâ hesaba girmiyor: uyarı kaybolmaz
        let i = s.materials.firstIndex { $0.id == Fx.koliId }!
        s.materials[i].packSizesRaw = ["paket": 10]
        s.materials[i].eskiAyarlar = [MalzemeSurumu(gecerliSon: Dates.addDays(Dates.today(), -1),
                                                    perOrder: nil, packSizesRaw: [:])]
        #expect(Engine(s).qty(.material(Fx.koliId)) == 0)
        #expect(Integrity.check(s).contains { $0.recordId == "p" })
    }

    @Test func geriTarihliAlimdaEskiBirimEngellenmez() {
        let s = paketiKaldirilmisKoli()
        let taslak = StockPurchase(id: "yeni", date: "2026-03-10", item: .material(Fx.koliId),
                                   qty: 5, unit: .paket, totalPaid: tl(500))
        #expect(!Validation.purchase(taslak, state: s).contains { $0.title == "Birim karşılığı tanımsız" })
        // Bugünkü tarihle aynı alım engellenir: bugün böyle bir birim yok
        var bugun = taslak; bugun.date = Dates.today()
        #expect(Validation.purchase(bugun, state: s).contains { $0.title == "Birim karşılığı tanımsız" })
    }

    // MARK: Nakit tahmini: ayın kendi gün sayısı

    @Test func tahminiTahsilatAyinGunSayisinaBolunur() throws {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        // Kasım–Ocak aylık 31.000 TL tahsilat; şubat 28 gün
        for ay in ["2025-11", "2025-12", "2026-01"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 10, grossSales: tl(28_000)))
        }
        s.settings.ek.kasaBakiye = tl(100_000)
        s.settings.ek.kasaTarih = "2026-02-01"
        let t = try #require(Engine(s).nakitTahmini(bugun: "2026-02-01"))
        // 2–8 Şubat: 7 gün × 28.000/28 = 7.000 (sabit 30'a bölünseydi 6.533 çıkardı)
        #expect(t.haftalar[0].giris == tl(7_000))
    }

    // MARK: Rapor içe aktarma: numarasız satır

    @Test func siparisNumarasiOlmayanSatirHataOlarakBildirilir() {
        let csv = """
        Name,Financial Status,Created at,Lineitem quantity,Lineitem name,Lineitem price,Lineitem sku
        ,paid,2026-09-02 10:00:00 +0300,1,Şampuan,100.00,S1
        ,paid,2026-09-03 10:00:00 +0300,1,Şampuan,100.00,S1
        """
        let t = RaporIceAktarma.oku(csv)
        let (kalemler, hatalar) = RaporIceAktarma.kalemler(t, sutun: RaporIceAktarma.sutunlariBul(t.basliklar))
        // Numarasız satırlar aynı anahtara düşüp sessizce kaybolmaz: hata olarak söylenir
        #expect(kalemler.isEmpty)
        #expect(hatalar.count == 2)
        #expect(hatalar.allSatisfy { $0.neden == "Sipariş numarası yok" })
    }

    @Test func numarasiTekrarEdenDevamSatiriTarihiDevralir() {
        let csv = """
        Name,Financial Status,Created at,Lineitem quantity,Lineitem name,Lineitem price,Lineitem sku
        #1001,paid,2026-09-02 10:00:00 +0300,1,Şampuan,100.00,S1
        #1001,,,1,Serum,150.00,S2
        ,,,1,Serum,150.00,S2
        """
        let t = RaporIceAktarma.oku(csv)
        let (kalemler, hatalar) = RaporIceAktarma.kalemler(t, sutun: RaporIceAktarma.sutunlariBul(t.basliklar))
        #expect(hatalar.isEmpty)
        #expect(kalemler.count == 3)
        #expect(kalemler.allSatisfy { $0.siparisNo == "#1001" && $0.tarih == "2026-09-02" })
    }

    // MARK: Kilitli ayın kârı korunur

    @MainActor
    @Test func kilitliAydanOncekiAlimiDuzenlemekEngellenir() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addPurchase("eski", "2026-07-01", .product(Fx.sampuanId), qty: 100, paid: tl(1_000))
        s.addSale("a", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(5_000))
        s.settings.ek.kilitliAylar = ["2026-09"]
        let st = AppStore.inMemory(s)
        let eylulKar = st.engine.companyMonth("2026-09").gercekKar
        var p = st.state.purchases[0]; p.totalPaid = tl(3_000)
        st.updatePurchase(p)
        #expect(st.sonHata != nil)
        #expect(st.engine.companyMonth("2026-09").gercekKar == eylulKar)
    }

    @MainActor
    @Test func kilitliAydanSonrakiKayitEngellenmez() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Fx.sampuan(cost: 0); s.products[0].recipe = []
        s.addPurchase("eski", "2026-07-01", .product(Fx.sampuanId), qty: 100, paid: tl(1_000))
        s.addSale("a", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId, qty: 10, gross: tl(5_000))
        s.settings.ek.kilitliAylar = ["2026-09"]
        let st = AppStore.inMemory(s)
        st.addExpense(Expense(id: "e", date: "2026-10-05", name: "Kira", amount: tl(1_000), category: .sabit))
        #expect(st.sonHata == nil)
    }

    // MARK: Stok sayımı düzenlenebilir

    @MainActor
    @Test func stokSayimiDuzenlenebilir() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.addPurchase("p", "2026-05-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.counts.append(StockCount(id: "c", date: "2026-06-10", item: .material(Fx.koliId),
                                   countedQty: 80, unit: .adet))
        let st = AppStore.inMemory(s)
        #expect(st.engine.qty(.material(Fx.koliId)) == 80)
        var c = st.state.counts[0]; c.countedQty = 75
        st.updateCount(c)
        #expect(st.sonHata == nil)
        #expect(st.state.counts.count == 1)
        #expect(st.engine.qty(.material(Fx.koliId)) == 75)
    }

    @MainActor
    @Test func isletmeAdiDegistirilebilir() {
        let st = AppStore.inMemory(Fx.base())
        st.setCompanyName("Mirissa Lab Kozmetik")
        #expect(st.state.settings.companyName == "Mirissa Lab Kozmetik")
        // Boş ad kaydedilmez
        st.setCompanyName("   ")
        #expect(st.state.settings.companyName == "Mirissa Lab Kozmetik")
    }
}
