import Testing
import Foundation
@testable import MirissaCore
@testable import MirissaUI
import MirissaTestSupport

/// UI → taslak → kalıcı model → finans motoru → rapor → kapat/aç zinciri.
/// Akışların kaydetme yolları birebir taklit edilir: ekranda doğru görünmesi
/// yetmez, modelde ve raporda da doğru olmalı.
@Suite("Uçtan uca zincir", .serialized)
@MainActor
struct ChainTests {

    private typealias G = Golden.G

    private func dosya() -> FileStore {
        FileStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mirissa-chain-\(UUID().uuidString).json"))
    }

    /// Kaydet → kapat → aç
    private func yenidenAc(_ st: AppStore, _ f: FileStore) -> AppStore {
        st.flush()
        return AppStore(file: f)
    }

    // MARK: Ürün maliyeti — "110 yazdım, modelde 5 kalmasın"

    @Test func urunMaliyetiUiDanRaporaKadarAyniKalir() {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())

        // Kullanıcı ürün formunda 110 TL yazdı (KDV hariç)
        var p = st.state.product(G.sampuan)!
        p.applyCostLines([CostLine(id: "cst_g_s", label: "Üretim", amount: tl(110))],
                         today: "2026-10-05")
        st.updateProduct(p)

        // Model
        #expect(st.state.product(G.sampuan)?.costLines(on: "2026-10-05")
            .reduce(0) { $0 + $1.amount } == tl(110))
        // Motor — bugünkü maliyet
        #expect(st.engine.cost(of: G.sampuan, asOf: "2026-10-05").intrinsic == tl(110))
        // Geçmiş ay eski maliyetle kalır
        #expect(st.engine.cost(of: G.sampuan, asOf: "2026-09-30").intrinsic == tl(100))
        // Kapat/aç
        let yeni = yenidenAc(st, f)
        #expect(yeni.engine.cost(of: G.sampuan, asOf: "2026-10-05").intrinsic == tl(110))
        #expect(yeni.engine.companyMonth("2026-09").gercekKar == tl(76_150))
    }

    // MARK: Stok alımı akışı

    @Test func alimAkisiZinciri() {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())
        let onceKoli = st.engine.qty(.material(G.koli))

        // PurchaseFlow.kaydet ile birebir aynı çağrı
        st.addPurchase(StockPurchase(
            id: "pur_zincir", date: "2026-09-20", item: .material(G.koli),
            qty: 200, unit: .adet, totalPaid: tl(2_400),
            vatRate: .yirmi, vatIncluded: true))

        #expect(st.engine.qty(.material(G.koli)) == onceKoli + 200)
        // 2.400 KDV dahil -> net 2.000 -> birim 10 TL; ortalama bozulmaz
        #expect(st.engine.unitCost(.material(G.koli)) == Double(tl(10)))
        #expect(st.engine.vatStatus("2026-09").indirilecek == tl(7_400))

        let yeni = yenidenAc(st, f)
        #expect(yeni.engine.qty(.material(G.koli)) == onceKoli + 200)
        #expect(yeni.engine.unitCost(.material(G.koli)) == Double(tl(10)))
    }

    // MARK: Gider akışı

    @Test func giderAkisiZinciri() {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())

        st.addExpense(Expense(
            id: "exp_zincir", date: "2026-09-15", name: "Kargo firması",
            amount: tl(6_000), category: .kargo, recurrence: .tek,
            vatRate: .yirmi, vatIncluded: true))

        // Net 5.000 kâra, 1.000 indirilecek KDV'ye, 6.000 kasadan
        #expect(st.engine.companyMonth("2026-09").ortakGider == tl(15_000))
        #expect(st.engine.companyMonth("2026-09").gercekKar == tl(71_150))
        #expect(st.engine.vatStatus("2026-09").indirilecek == tl(8_000))

        let yeni = yenidenAc(st, f)
        #expect(yeni.engine.companyMonth("2026-09").gercekKar == tl(71_150))
    }

    // MARK: Satış akışı (elle kesinti otomatiğin yerine geçer)

    @Test func satisAkisiElleKesintiOtomatiginYerineGecer() {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())
        let otomatik = st.engine.channelResult(channelId: G.trendyol, month: "2026-09")
        #expect(otomatik.commission.amount == tl(39_600))
        #expect(otomatik.commission.isManual == false)

        // SaleFlow'un "gerçek kesintileri biliyorum" dalı
        st.upsertChannelMonth(ChannelMonth(
            id: "chm_zincir", month: "2026-09", channelId: G.trendyol,
            orderCount: 120, commissionActual: tl(30_000), shippingActual: tl(12_000)))

        let elle = st.engine.channelResult(channelId: G.trendyol, month: "2026-09")
        // Üstüne eklenmez, yerine geçer
        #expect(elle.commission.amount == tl(30_000))
        #expect(elle.commission.isManual)
        #expect(elle.shipping.amount == tl(12_000))
        #expect(elle.orders == 120)
        #expect(elle.ordersIsEstimate == false)

        let yeni = yenidenAc(st, f)
        #expect(yeni.engine.channelResult(channelId: G.trendyol, month: "2026-09")
            .commission.amount == tl(30_000))
    }

    // MARK: Fiyat güncelleme akışı

    @Test func fiyatAkisiGecmisiBozmadanZincirdenGecer() {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())

        var p = st.state.product(G.sampuan)!
        p.setPrice(tl(699), channelId: G.trendyol, from: "2026-09-01")
        st.updateProduct(p)
        let eylulKar = st.engine.companyMonth("2026-09").gercekKar

        // PriceUpdateFlow.kaydet
        var p2 = st.state.product(G.sampuan)!
        p2.setPrice(tl(799), channelId: G.trendyol, from: "2026-10-01")
        st.updateProduct(p2)
        st.markPriceCheck("2026-10-01")

        // Geçmiş ay değişmedi
        #expect(st.engine.companyMonth("2026-09").gercekKar == eylulKar)
        // Fiyatlar kendi dönemlerinde
        let g = st.state.product(G.sampuan)!
        #expect(g.price(for: G.trendyol, on: "2026-09-15") == tl(699))
        #expect(g.price(for: G.trendyol, on: "2026-10-15") == tl(799))
        #expect(st.state.settings.lastPriceCheck == "2026-10-01")

        let yeni = yenidenAc(st, f)
        #expect(yeni.state.product(G.sampuan)?
            .price(for: G.trendyol, on: "2026-09-15") == tl(699))
        #expect(yeni.engine.companyMonth("2026-09").gercekKar == eylulKar)
    }

    // MARK: Kanal kurulumu akışı

    @Test func kanalKurulumuZinciri() {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())
        let eylulOnce = st.engine.channelResult(channelId: G.trendyol, month: "2026-09")
            .commission.amount

        // ChannelSetupFlow.kaydet: bugünden geçerli yeni oranlar
        st.applyChannelRates(G.trendyol, ChannelRates(
            from: "2026-10-01", commissionPct: 25, shippingPerOrder: tl(110),
            extras: [ChannelExtraFee(label: "Kampanya katkısı", basis: .yuzde, value: 5)],
            unknownFields: ["hizmet bedeli"]
        ))
        var p = st.state.product(G.sampuan)!
        p.applyCurrentPrice(tl(749), channelId: G.trendyol, today: "2026-10-01")
        st.updateProduct(p)

        // Geçmiş ay eski oranla kalır
        #expect(st.engine.channelResult(channelId: G.trendyol, month: "2026-09")
            .commission.amount == eylulOnce)
        // Eksik bilgi kullanıcıya bildirilir
        let kasim = st.engine.companyMonth("2026-11")
        #expect(kasim.yaklasikUyarisi?.contains("hizmet bedeli") == true)

        let yeni = yenidenAc(st, f)
        #expect(yeni.state.channel(G.trendyol)?.rates(on: "2026-09-15").commissionPct == 20)
        #expect(yeni.state.channel(G.trendyol)?.rates(on: "2026-10-15").commissionPct == 25)
        #expect(yeni.state.product(G.sampuan)?
            .price(for: G.trendyol, on: "2026-10-15") == tl(749))
    }

    // MARK: Stok sayımı akışı

    @Test func sayimAkisiZinciri() {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())

        st.addCount(StockCount(id: "cnt_zincir", date: "2026-09-25",
                               item: .material(G.kutu), countedQty: 800,
                               unit: .adet, reason: .fire))
        #expect(st.engine.qty(.material(G.kutu)) == 800)
        // Sayım birim maliyeti değiştirmez
        #expect(st.engine.unitCost(.material(G.kutu)) == Double(tl(5)))

        let yeni = yenidenAc(st, f)
        #expect(yeni.engine.qty(.material(G.kutu)) == 800)
    }

    // MARK: Yarım akış

    @Test func yarimAkisZinciri() throws {
        let f = dosya()
        let st = AppStore(file: f, saveDelay: .zero)
        st.replace(Golden.senaryo())
        st.saveDraft(try #require(WizardDraft.make(
            kind: .kanalKurulumu, subjectId: G.trendyol, title: "Trendyol kurulumu",
            step: 5, totalSteps: 12, state: ["komisyon": 25])))

        let yeni = yenidenAc(st, f)
        let d = try #require(yeni.draft(.kanalKurulumu, subjectId: G.trendyol))
        #expect(d.step == 5)
        #expect(d.decode([String: Int].self)?["komisyon"] == 25)
        // Tamamlanınca temizlenir
        yeni.clearDraft(.kanalKurulumu, subjectId: G.trendyol)
        #expect(yenidenAc(yeni, f).state.drafts.isEmpty)
    }

    // MARK: Ekranda görünen rakam motorun rakamıdır

    /// Ana sayfa kartları ve rapor aynı motordan beslenir
    @Test func ekranKartlariMotorlaAyniRakamiKullanir() {
        let st = AppStore.inMemory(Golden.senaryo())
        let ay = st.engine.companyMonth("2026-09")

        // Period.result ile doğrudan companyMonth aynı sonucu vermeli
        let period = Period(month: "2026-09")
        #expect(period.result(st.engine) == ay)

        // Yıl görünümü aylık sonuçların toplamı
        let yilPeriod = Period(month: "2026-09")
        yilPeriod.scope = .year
        let yil = yilPeriod.result(st.engine)
        #expect(yil.gercekCiro == st.engine.year(2026).gercekCiro)
        #expect(yil.gercekKar == st.engine.year(2026).gercekKar)

        // Grafik de aynı motordan
        let nokta = st.engine.trend(endingAt: "2026-09", months: 6)
            .first { $0.month == "2026-09" }
        #expect(nokta?.kar == ay.gercekKar)
    }
}

/// Ekrandaki satırların toplamı, başlıktaki motor rakamını tutmalı
@Suite("Ekran ile motor aynı rakamı gösterir")
@MainActor
struct ScreenEngineMatchTests {

    private typealias G = Golden.G

    /// Gider kategorisi başlığı KDV hariç; satırlar da KDV hariç toplanmalı
    @Test func giderKategorisiSatirlarlaTutar() {
        let st = AppStore.inMemory(Golden.senaryo())
        let r = st.engine.companyMonth("2026-09")
        let instances = st.engine.expenseInstances(month: "2026-09")

        for (kategori, toplam) in r.expenseBreakdown where toplam != 0 {
            let satirlar = instances.filter { $0.category == kategori && !$0.capitalized }
            let satirToplam = satirlar.reduce(0) { $0 + $1.expenseAmount }
            // Elle girilen satırlar kategori toplamını aşamaz;
            // aradaki fark satışlardan türeyen otomatik kısımdır
            #expect(satirToplam <= toplam,
                    "\(kategori.displayName): satırlar başlıktan büyük")
        }
    }

    /// Sabit gider kategorisinde satır toplamı başlığa eşit (otomatik kısım yok)
    @Test func sabitGiderKategorisindeSatirlarBasligaEsit() {
        let st = AppStore.inMemory(Golden.senaryo())
        let r = st.engine.companyMonth("2026-09")
        let sabitToplam = r.expenseBreakdown[.sabit] ?? 0
        let satirlar = st.engine.expenseInstances(month: "2026-09")
            .filter { $0.category == .sabit && !$0.capitalized }
        #expect(satirlar.reduce(0) { $0 + $1.expenseAmount } == sabitToplam)
        // 12.000 TL KDV dahil ödendi, kâra 10.000 TL yazıldı
        #expect(satirlar.first?.amount == tl(12_000))
        #expect(satirlar.first?.expenseAmount == tl(10_000))
    }

    /// Ürün detayındaki maliyet kalemleri, motorun toplamıyla tutmalı
    @Test func urunMaliyetKalemleriToplamaEsit() {
        var s = Golden.senaryo()
        let i = s.products.firstIndex { $0.id == G.sampuan }!
        // Maliyet değişti: eski kalem kapandı, yenisi açıldı
        s.products[i].applyCostLines(
            [CostLine(id: "cst_g_s", label: "Üretim", amount: tl(130))], today: "2026-10-01")
        let p = s.products[i]
        let e = Engine(s)
        // Ekranda gösterilen kalemler (bugün geçerli olanlar) motorun rakamını verir
        let gosterilen = p.costLines(on: nil).reduce(0) { $0 + $1.amount }
        #expect(gosterilen == e.cost(of: G.sampuan, asOf: Dates.today()).ownLines)
        // Kapanmış eski kalem ekranda görünmez ama geçmişte geçerlidir
        #expect(p.costLines.count == 2)
        #expect(p.costLines(on: nil).count == 1)
        #expect(e.cost(of: G.sampuan, asOf: "2026-09-30").ownLines == tl(100))
    }
}
