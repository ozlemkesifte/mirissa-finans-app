import Testing
import Foundation
@testable import MirissaCore

@Suite("Çift sayım koruması")
struct GuardTests {

    private func temel() -> AppState {
        var s = SeedData.initialState()
        s.settings.setupCompleted = true
        return s
    }

    // MARK: Kural 1 — ürün maliyeti + ambalaj reçetesi

    /// Üretim maliyetine dahil malzeme reçetede ikinci kez sayılmaz
    @Test func kural1_uretimMaliyetineDahilKalemTekrarSayilmaz() {
        var s = temel()
        s.purchases.append(StockPurchase(id: "p1", date: "2026-08-01",
                                         item: .material(SeedData.M.sampuanKutu),
                                         qty: 100, unit: .adet, totalPaid: tl(800), vatRate: .yok))
        guard let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) else { return }
        s.products[i].costLines = [CostLine(label: "Üretim (şişe+kapak+etiket dahil)", amount: tl(132))]

        // Kutu hem reçetede hem üretim maliyetine dahil DEĞİLKEN sayılır
        let oncesi = Engine(s).cost(of: SeedData.P.sampuan).packaging
        #expect(oncesi >= tl(8))

        // "Bu üretim maliyetine dahil" işaretlenince maliyeti bir daha sayılmaz
        s.products[i].costIncludesMaterials = [SeedData.M.sampuanKutu]
        let sonrasi = Engine(s).cost(of: SeedData.P.sampuan).packaging
        #expect(oncesi - sonrasi == tl(8))
    }

    /// Ama malzeme stoktan yine de düşer — fiziksel olarak kullanılıyor
    @Test func kural1_dahilKalemStoktanYineDuser() {
        var s = temel()
        s.purchases.append(StockPurchase(id: "p1", date: "2026-08-01",
                                         item: .material(SeedData.M.sampuanKutu),
                                         qty: 100, unit: .adet, totalPaid: tl(800), vatRate: .yok))
        guard let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) else { return }
        s.products[i].costIncludesMaterials = [SeedData.M.sampuanKutu]
        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 10, gross: tl(7000))
        #expect(Engine(s).qty(.material(SeedData.M.sampuanKutu)) == 90)
    }

    /// Reçeteye eklemeye çalışınca engellenir
    @Test func kural1_receteyeEklemeEngellenir() {
        var s = temel()
        guard let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) else { return }
        s.products[i].costIncludesMaterials = [SeedData.M.sampuanKutu]
        let sorunlar = Validation.recipeLine(materialId: SeedData.M.sampuanKutu,
                                             in: s.products[i], state: s)
        #expect(sorunlar.hasBlocking)
        #expect(sorunlar.first?.code == .receteMaliyetiCiftSayim)

        // Başka bir malzeme serbest
        #expect(Validation.recipeLine(materialId: SeedData.M.koli,
                                      in: s.products[i], state: s).isEmpty)
    }

    // MARK: Kural 2 — başlangıç stoğu

    /// Başlangıç stoğu gider, nakit çıkışı veya KDV oluşturmaz
    @Test func kural2_baslangicStoguGiderOlusturmaz() {
        var s = temel()
        guard let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) else { return }
        s.products[i].openingQty = 740
        s.products[i].openingUnitCost = tl(141)
        s.products[i].openingDate = "2026-09-01"
        let r = Engine(s).companyMonth("2026-09")
        #expect(Engine(s).qty(.product(SeedData.P.sampuan)) == 740)
        #expect(r.toplamGider == 0)
        #expect(r.nakitCikisi == 0)
        #expect(Engine(s).vatStatus("2026-09").hasData == false)
    }

    /// Aynı miktar sonradan alım gibi girilirse uyarır
    @Test func kural2_tekrarAlimUyarir() {
        var s = temel()
        guard let i = s.materials.firstIndex(where: { $0.id == SeedData.M.koli }) else { return }
        s.materials[i].openingQty = 380
        s.materials[i].openingDate = "2026-09-01"

        let taslak = StockPurchase(date: "2026-09-10", item: .material(SeedData.M.koli),
                                   qty: 380, unit: .adet, totalPaid: tl(4180))
        let sorunlar = Validation.purchase(taslak, state: s)
        #expect(sorunlar.contains { $0.code == .baslangicStoguTekrarAlim })
        #expect(!sorunlar.hasBlocking)   // engel değil, uyarı

        // Farklı miktar uyarı vermez
        var farkli = taslak
        farkli.qty = 500
        #expect(!Validation.purchase(farkli, state: s).contains { $0.code == .baslangicStoguTekrarAlim })
    }

    // MARK: Kural 3 — stok alımı + gider

    /// Aynı fatura numarası ikinci kez girilemez
    @Test func kural3_ayniFaturaIkiKezGirilemez() {
        var s = temel()
        s.purchases.append(StockPurchase(id: "p1", date: "2026-09-05",
                                         item: .material(SeedData.M.koli), qty: 500,
                                         unit: .adet, totalPaid: tl(6000), invoiceNo: "ABC-123"))
        let gider = Expense(date: "2026-09-05", name: "Koli faturası", amount: tl(6000),
                            category: .ambalaj, invoiceNo: "abc-123")
        let sorunlar = Validation.expense(gider, state: s)
        #expect(sorunlar.hasBlocking)
        #expect(sorunlar.contains { $0.code == .mukerrerFatura })
    }

    /// Fatura numarası olmasa da aynı tarih ve tutar yakalanır
    @Test func kural3_ayniTarihTutarYakalanir() {
        var s = temel()
        s.purchases.append(StockPurchase(id: "p1", date: "2026-09-05",
                                         item: .material(SeedData.M.koli), qty: 500,
                                         unit: .adet, totalPaid: tl(6000)))
        let gider = Expense(date: "2026-09-05", name: "Koli alımı", amount: tl(6000), category: .ambalaj)
        #expect(Validation.expense(gider, state: s).hasBlocking)
    }

    /// Stok alımı zaten giderlerde görünür — ikinci kayda gerek yok
    @Test func kural3_alimGiderlerdeZatenGorunur() {
        var s = temel()
        s.purchases.append(StockPurchase(id: "p1", date: "2026-09-05",
                                         item: .material(SeedData.M.koli), qty: 500,
                                         unit: .adet, totalPaid: tl(6000), vatRate: .yok))
        let liste = Engine(s).expenseInstances(month: "2026-09")
        #expect(liste.count == 1)
        #expect(liste[0].sourceKind == .stokAlimi)
        #expect(liste[0].expenseAmount == 0)      // kâra gider yazılmaz
        #expect(liste[0].cashAmount == tl(6000))  // nakit çıkışı olarak görünür
    }

    // MARK: Kural 4 — sabit gider

    /// Aynı ay için aynı sabit gider elle girilirse uyarır, engellemez
    @Test func kural4_sabitGiderTekrariUyarir() {
        var s = temel()
        s.expenses.append(Expense(id: "e_muh", date: "2026-01-05", name: "Muhasebeci",
                                  amount: tl(5000), category: .sabit, recurrence: .aylik))
        let elle = Expense(date: "2026-09-10", name: "muhasebeci", amount: tl(5000), category: .sabit)
        let sorunlar = Validation.expense(elle, state: s)
        #expect(sorunlar.contains { $0.code == .sabitGiderTekrari })
        #expect(!sorunlar.hasBlocking)

        // Farklı adla uyarı yok
        let baska = Expense(date: "2026-09-10", name: "Kargo faturası", amount: tl(5000), category: .kargo)
        #expect(!Validation.expense(baska, state: s).contains { $0.code == .sabitGiderTekrari })
    }

    // MARK: Kural 5 — pazaryeri kesintileri

    /// Elle girilen gerçek tutar otomatik hesabın yerine geçer, üstüne eklenmez
    @Test func kural5_manuelKesintiOtomatiginYerineGecer() {
        var s = temel()
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yok
        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 100, gross: tl(100_000))

        let otomatik = Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(otomatik.commission.amount == tl(20_000))
        #expect(!otomatik.commission.isManual)

        s.channelMonths.append(ChannelMonth(month: "2026-09", channelId: ChannelIds.trendyol,
                                            commissionActual: tl(18_500)))
        let manuel = Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(manuel.commission.amount == tl(18_500))   // 20.000 + 18.500 DEĞİL
        #expect(manuel.commission.isManual)
        #expect(manuel.kanaldaKalan == otomatik.kanaldaKalan + tl(1500))
    }

    /// Bütün kesinti kalemleri için tek kaynak kuralı geçerli
    @Test func kural5_butunKalemlerdeTekKaynak() {
        var s = temel()
        s.channels[0].commissionPct = 20
        s.channels[0].shippingPerOrder = tl(60)
        s.channels[0].serviceFeePerOrder = tl(10)
        s.channels[0].otherDeductionMonthly = tl(500)
        s.channels[0].feeVatRate = .yok
        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 100, gross: tl(100_000))
        s.channelMonths.append(ChannelMonth(
            month: "2026-09", channelId: ChannelIds.trendyol, orderCount: 100,
            commissionActual: tl(1), shippingActual: tl(2),
            serviceFeeActual: tl(3), otherDeductionActual: tl(4), adsActual: tl(5)
        ))
        let r = Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(r.commission.amount == tl(1))
        #expect(r.shipping.amount == tl(2))
        #expect(r.serviceFee.amount == tl(3))
        #expect(r.otherDeduction.amount == tl(4))
        #expect(r.ads.amount == tl(5))
        #expect(r.channelFees == tl(10))   // hiçbiri otomatikle toplanmadı
    }

    /// Kanalın otomatik hesapladığı kalemi gider olarak girmek uyarı verir
    @Test func kural5_kanalGideriUyarir() {
        var s = temel()
        s.channels[0].shippingPerOrder = tl(60)
        let gider = Expense(date: "2026-09-10", name: "Trendyol kargo", amount: tl(7000),
                            category: .kargo, scope: .channel(ChannelIds.trendyol))
        let sorunlar = Validation.expense(gider, state: s)
        #expect(sorunlar.contains { $0.code == .kanalKesintisiCiftSayim })

        // Ortak gider olarak girilirse uyarı yok
        var ortak = gider
        ortak.scope = .ortak
        #expect(!Validation.expense(ortak, state: s).contains { $0.code == .kanalKesintisiCiftSayim })
    }

    // MARK: Kural 6 — KDV

    /// KDV dahil tutar bir kez ayrılır, net üzerine tekrar eklenmez
    @Test func kural6_kdvTekKezAyrilir() {
        let bolum = Vat.split(tl(12_000), rate: .yirmi, included: true)
        #expect(bolum.net == tl(10_000))
        #expect(bolum.vat == tl(2000))
        #expect(bolum.net + bolum.vat == tl(12_000))
        // Net tutarı tekrar ayırmaya kalkarsan net değişmez
        #expect(Vat.split(bolum.net, rate: .yirmi, included: false).net == tl(10_000))
    }

    // MARK: Kural 7 — kâr ile nakit çıkışı

    @Test func kural7_stokAlimiKaraTopluYazilmaz() {
        var s = temel()
        guard let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) else { return }
        s.products[i].costLines = [CostLine(label: "Üretim", amount: tl(100))]
        s.products[i].recipe = []
        s.purchases.append(StockPurchase(id: "p1", date: "2026-09-01",
                                         item: .product(SeedData.P.sampuan),
                                         qty: 100, unit: .adet, totalPaid: tl(10_000), vatRate: .yok))
        s.addSale("sal", "2026-09", channel: ChannelIds.other,
                  product: SeedData.P.sampuan, qty: 10, gross: tl(20_000))
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.nakitCikisi == tl(10_000))   // 100 adet için ödendi
        #expect(r.urunVeAmbalajMaliyeti == tl(1000))  // yalnızca satılan 10 adet
        #expect(r.gercekKar == tl(19_000))
    }

    // MARK: Kural 8 — set bileşenleri

    @Test func kural8_setUcuncuMaliyetOlusturmaz() {
        var s = temel()
        for id in [SeedData.P.sampuan, SeedData.P.serum] {
            if let i = s.products.firstIndex(where: { $0.id == id }) {
                s.products[i].costLines = [CostLine(label: "Üretim", amount: tl(100))]
                s.products[i].recipe = []
            }
        }
        if let i = s.products.firstIndex(where: { $0.id == SeedData.P.set }) {
            s.products[i].recipe = []
            s.products[i].costLines = []
        }
        s.addSale("sal", "2026-09", channel: ChannelIds.shopify,
                  product: SeedData.P.set, qty: 10, gross: tl(30_000))
        let e = Engine(s)
        // Bileşenler birer kez düşer, set kendi stoğunu tutmaz
        #expect(e.qty(.product(SeedData.P.sampuan)) == -10)
        #expect(e.qty(.product(SeedData.P.serum)) == -10)
        #expect(e.qty(.product(SeedData.P.set)) == 0)
        // Maliyet yalnızca bileşenlerden: 10 × (100 + 100)
        let r = e.channelResult(channelId: ChannelIds.shopify, month: "2026-09")
        #expect(r.productCost == tl(2000))
    }

    /// Set ambalajı ayrıysa yalnızca set ambalajı düşer
    @Test func kural8_yalnizcaSetAmbalajiDuser() {
        var s = temel()
        s.addSale("sal", "2026-09", channel: ChannelIds.shopify,
                  product: SeedData.P.set, qty: 10, gross: tl(30_000))
        let e = Engine(s)
        #expect(e.qty(.material(SeedData.M.setKutu)) == -10)
        #expect(e.qty(.material(SeedData.M.sampuanKutu)) == 0)  // bileşen kutusu kullanılmaz
        #expect(e.qty(.material(SeedData.M.serumKutu)) == 0)
        #expect(e.qty(.material(SeedData.M.koli)) == -10)       // sadece bir koli
    }

    // MARK: Kural 9 — iade

    @Test func kural9_iadeIkiKezEtkilemez() {
        var s = temel()
        guard let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) else { return }
        s.products[i].costLines = [CostLine(label: "Üretim", amount: tl(100))]
        s.products[i].recipe = []
        s.sales.append(SalesEntry(id: "sal", month: "2026-09", channelId: ChannelIds.other,
                                  productId: SeedData.P.sampuan, qty: 100,
                                  grossSales: tl(70_000), returnsAmount: tl(7000),
                                  returnsQty: 10, returnsRestock: true))
        let e = Engine(s)
        let r = e.channelResult(channelId: ChannelIds.other, month: "2026-09")
        #expect(r.netSales == tl(63_000))            // bir kez düşüldü
        #expect(r.productCost == tl(9000))           // 90 net adet
        #expect(e.qty(.product(SeedData.P.sampuan)) == -90)  // 100 çıktı, 10 geri geldi
    }

    /// Hasarlı iade stoğa geri girmez ve fire olarak kaydedilir
    @Test func kural9_hasarliIadeFireOlur() {
        var s = temel()
        s.sales.append(SalesEntry(id: "sal", month: "2026-09", channelId: ChannelIds.other,
                                  productId: SeedData.P.sampuan, qty: 100,
                                  grossSales: tl(70_000), returnsAmount: tl(7000),
                                  returnsQty: 10, returnsRestock: false))
        let e = Engine(s)
        #expect(e.qty(.product(SeedData.P.sampuan)) == -100)   // geri gelmedi
        let gecmis = e.history(.product(SeedData.P.sampuan))
        #expect(gecmis.contains { $0.kind == .iade && $0.delta == 10 })
        #expect(gecmis.contains { $0.movement.reason == .hasarli && $0.delta == -10 })
    }

    // MARK: Kural 10 — negatif stok

    @Test func kural10_negatifStokEngellenir() {
        var s = temel()
        s.purchases.append(StockPurchase(id: "p1", date: "2026-09-01",
                                         item: .material(SeedData.M.koli),
                                         qty: 8, unit: .adet, totalPaid: tl(100), vatRate: .yok))
        let taslak = SalesEntry(month: "2026-09", channelId: ChannelIds.trendyol,
                                productId: SeedData.P.sampuan, qty: 20, grossSales: tl(14_000))
        let sorunlar = Validation.sale(taslak, state: s)
        #expect(sorunlar.hasBlocking)
        let negatif = sorunlar.first { $0.code == .negatifStok }
        #expect(negatif != nil)
        #expect(negatif!.detail.contains("Mevcut stok"))
    }

    @Test func kural10_yeterliStoktaEngelYok() {
        var s = temel()
        for id in [SeedData.M.koli, SeedData.M.patpat, SeedData.M.kirilmazEtiket,
                   SeedData.M.tesekkurKarti, SeedData.M.sampuanKutu] {
            s.purchases.append(StockPurchase(id: "p_\(id)", date: "2026-09-01",
                                             item: .material(id), qty: 1000,
                                             unit: .adet, totalPaid: tl(1000), vatRate: .yok))
        }
        s.purchases.append(StockPurchase(id: "p_dolgu", date: "2026-09-01",
                                         item: .material(SeedData.M.dolguKirpigi),
                                         qty: 50, unit: .kg, totalPaid: tl(5000), vatRate: .yok))
        s.purchases.append(StockPurchase(id: "p_urun", date: "2026-09-01",
                                         item: .product(SeedData.P.sampuan), qty: 100,
                                         unit: .adet, totalPaid: tl(10_000), vatRate: .yok))
        let taslak = SalesEntry(month: "2026-09", channelId: ChannelIds.trendyol,
                                productId: SeedData.P.sampuan, qty: 20, grossSales: tl(14_000))
        #expect(!Validation.sale(taslak, state: s).hasBlocking)
    }

    // MARK: Kural 11 — mantıksız değerler

    @Test func kural11_gecersizDegerlerEngellenir() {
        let s = temel()
        #expect(Validation.purchase(StockPurchase(date: "2026-09-01",
                                                  item: .material(SeedData.M.koli),
                                                  qty: 0, unit: .adet, totalPaid: tl(100)),
                                    state: s).hasBlocking)
        #expect(Validation.purchase(StockPurchase(date: "2026-09-01",
                                                  item: .material(SeedData.M.koli),
                                                  qty: 10, unit: .adet, totalPaid: -tl(100)),
                                    state: s).hasBlocking)
        #expect(Validation.sale(SalesEntry(month: "2026-09", channelId: ChannelIds.other,
                                           productId: SeedData.P.sampuan, qty: -5,
                                           grossSales: tl(100)), state: s).hasBlocking)
        #expect(Validation.expense(Expense(date: "2026-09-01", name: "", amount: tl(100),
                                           category: .diger), state: s).hasBlocking)
        #expect(Validation.expense(Expense(date: "2026-09-01", name: "X", amount: 0,
                                           category: .diger), state: s).hasBlocking)

        var kanal = Channel(id: "k", name: "K", commissionPct: 80, paymentPct: 30)
        #expect(Validation.channel(kanal).hasBlocking)
        kanal = Channel(id: "k", name: "K", commissionPct: 20)
        #expect(!Validation.channel(kanal).hasBlocking)
    }

    /// İade satıştan fazla olamaz
    @Test func kural11_iadeSatistanFazlaOlamaz() {
        let s = temel()
        let taslak = SalesEntry(month: "2026-09", channelId: ChannelIds.other,
                                productId: SeedData.P.sampuan, qty: 10,
                                grossSales: tl(7000), returnsAmount: tl(8000), returnsQty: 15)
        let sorunlar = Validation.sale(taslak, state: s)
        #expect(sorunlar.filter { $0.code == .gecersizMiktar }.count >= 1)
        #expect(sorunlar.contains { $0.code == .gecersizTutar })
    }

    // MARK: Kural 12 — kayıt öncesi özet

    @Test func kural12_alimOzetiGosterilir() {
        let s = temel()
        let taslak = StockPurchase(date: "2026-09-05", item: .material(SeedData.M.koli),
                                   qty: 500, unit: .adet, totalPaid: tl(6000),
                                   vatRate: .yok)
        let ozet = Validation.purchaseSummary(taslak, state: s)
        #expect(ozet.lines.contains { $0.contains("+500 adet") })
        #expect(ozet.lines.contains { $0.contains("6.000 TL nakit çıkışı") })
        #expect(ozet.lines.contains { $0.contains("12 TL") })
        #expect(ozet.note?.contains("doğrudan") == true)
    }

    @Test func kural12_kdvOzetiNetVeKdvGosterir() {
        let s = temel()
        let gider = Expense(date: "2026-09-05", name: "Ajans", amount: tl(12_000),
                            category: .sabit, vatRate: .yirmi, vatIncluded: true)
        let ozet = Validation.expenseSummary(gider, state: s)
        #expect(ozet.lines.contains { $0.contains("12.000 TL nakit çıkışı") })
        #expect(ozet.lines.contains { $0.contains("10.000 TL kâra gider") })
        #expect(ozet.lines.contains { $0.contains("2.000 TL indirilecek KDV") })
    }

    // MARK: Kural 13 — düzenleme eski etkiyi bırakmaz

    @Test func kural13_duzenlemeEskiEtkiyiBirakmaz() {
        var s = temel()
        s.purchases.append(StockPurchase(id: "p1", date: "2026-09-01",
                                         item: .material(SeedData.M.koli), qty: 500,
                                         unit: .adet, totalPaid: tl(5000), vatRate: .yok))
        #expect(Engine(s).qty(.material(SeedData.M.koli)) == 500)
        #expect(approx(Engine(s).unitCost(.material(SeedData.M.koli)), Double(tl(10))))

        // Aynı kayıt düzenleniyor
        s.purchases[0].qty = 300
        s.purchases[0].totalPaid = tl(3600)
        #expect(Engine(s).qty(.material(SeedData.M.koli)) == 300)          // 800 değil
        #expect(approx(Engine(s).unitCost(.material(SeedData.M.koli)), Double(tl(12))))

        // Silinince tamamen kalkar
        s.purchases.removeAll()
        #expect(Engine(s).qty(.material(SeedData.M.koli)) == 0)
        #expect(Engine(s).companyMonth("2026-09").nakitCikisi == 0)
    }

    /// Satış düzenlenince stok ve kâr ikisi birden yeniden hesaplanır
    @Test func kural13_satisDuzenlemesiTamYeniden() {
        var s = temel()
        guard let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) else { return }
        s.products[i].costLines = [CostLine(label: "Üretim", amount: tl(100))]
        s.products[i].recipe = []
        s.addSale("sal", "2026-09", channel: ChannelIds.other,
                  product: SeedData.P.sampuan, qty: 100, gross: tl(70_000))
        let once = Engine(s).companyMonth("2026-09")

        s.sales[0].qty = 60
        s.sales[0].grossSales = tl(42_000)
        let sonra = Engine(s).companyMonth("2026-09")

        #expect(sonra.gercekCiro == tl(42_000))
        #expect(sonra.units == 60)
        #expect(Engine(s).qty(.product(SeedData.P.sampuan)) == -60)   // −160 değil
        #expect(once.gercekCiro != sonra.gercekCiro)
    }
}
