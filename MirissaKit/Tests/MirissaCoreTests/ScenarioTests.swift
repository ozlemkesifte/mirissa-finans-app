import Testing
import Foundation
@testable import MirissaCore

/// Uçtan uca gerçekçi senaryo: ürün tanımla → stok al → satış gir →
/// stok düştü mü, kâr doğru mu, uyarılar çıkıyor mu?
@Suite("Uçtan uca senaryo")
struct ScenarioTests {

    private func kurulum() -> AppState {
        var s = SeedData.initialState()

        // 1) Ürün üretim maliyetleri
        s.products[0].costLines = [CostLine(id: "c1", label: "Üretim", amount: tl(132))]
        s.products[1].costLines = [CostLine(id: "c2", label: "Üretim", amount: tl(139))]

        // 2) Uyarı seviyeleri
        func esik(_ id: Id, min: Double, kritik: Double) {
            if let i = s.materials.firstIndex(where: { $0.id == id }) {
                s.materials[i].minQty = min
                s.materials[i].criticalQty = kritik
            }
        }
        esik(SeedData.M.koli, min: 150, kritik: 80)
        esik(SeedData.M.kirilmazEtiket, min: 300, kritik: 150)
        esik(SeedData.M.dolguKirpigi, min: 3000, kritik: 1500)
        esik(SeedData.M.tesekkurKarti, min: 150, kritik: 80)

        // 3) Ağustos: stok alımları
        s.addPurchase("pur_koli", "2026-08-05", .material(SeedData.M.koli), qty: 500, paid: tl(5000))
        s.addPurchase("pur_koli2", "2026-08-20", .material(SeedData.M.koli), qty: 500, paid: tl(6000))
        s.addPurchase("pur_skutu", "2026-08-05", .material(SeedData.M.sampuanKutu), qty: 400, paid: tl(3200))
        s.addPurchase("pur_rkutu", "2026-08-05", .material(SeedData.M.serumKutu), qty: 300, paid: tl(2400))
        s.addPurchase("pur_setkutu", "2026-08-05", .material(SeedData.M.setKutu), qty: 100, paid: tl(1500))
        s.addPurchase("pur_patpat", "2026-08-05", .material(SeedData.M.patpat), qty: 600, paid: tl(1200))
        s.addPurchase("pur_etiket", "2026-08-05", .material(SeedData.M.kirilmazEtiket), qty: 1000, paid: tl(500))
        s.addPurchase("pur_dolgu", "2026-08-06", .material(SeedData.M.dolguKirpigi), qty: 10, unit: .kg, paid: tl(2000))
        s.addPurchase("pur_kart", "2026-08-05", .material(SeedData.M.tesekkurKarti), qty: 500, paid: tl(750))
        s.addPurchase("pur_sampuan", "2026-08-10", .product(SeedData.P.sampuan), qty: 300, paid: tl(39_600))
        s.addPurchase("pur_serum", "2026-08-10", .product(SeedData.P.serum), qty: 250, paid: tl(34_750))

        // 4) Kanal oranları
        s.channels[0].commissionPct = 20      // Trendyol
        s.channels[0].shippingPerOrder = tl(60)
        s.channels[1].paymentPct = 3          // Shopify
        s.channels[1].shippingPerOrder = tl(70)
        s.channels[1].platformFeeMonthly = tl(1500)

        // 5) Eylül satışları
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: SeedData.P.sampuan,
                  qty: 80, gross: tl(55_920), discount: tl(920), returnsAmount: tl(1398), returnsQty: 2)
        s.addSale("sal_2", "2026-09", channel: ChannelIds.trendyol, product: SeedData.P.serum,
                  qty: 50, gross: tl(37_500))
        s.addSale("sal_3", "2026-09", channel: ChannelIds.shopify, product: SeedData.P.set,
                  qty: 30, gross: tl(45_000))
        s.channelMonths.append(ChannelMonth(id: "chm_ty", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 118))
        s.channelMonths.append(ChannelMonth(id: "chm_sh", month: "2026-09",
                                            channelId: ChannelIds.shopify, orderCount: 30))

        // 6) Giderler
        s.expenses.append(Expense(id: "e_muh", date: "2026-08-01", name: "Muhasebeci",
                                  amount: tl(5000), category: .sabit, recurrence: .aylik))
        s.expenses.append(Expense(id: "e_ajans", date: "2026-08-01", name: "Ajans",
                                  amount: tl(20_000), category: .sabit, recurrence: .aylik))
        s.expenses.append(Expense(id: "e_klaviyo", date: "2026-08-01", name: "Klaviyo",
                                  amount: tl(2000), category: .sabit, recurrence: .aylik))
        s.expenses.append(Expense(id: "e_tyreklam", date: "2026-09-10", name: "Trendyol reklamı",
                                  amount: tl(5000), category: .reklam, scope: .channel(ChannelIds.trendyol)))
        s.expenses.append(Expense(id: "e_meta", date: "2026-09-12", name: "Meta reklam",
                                  amount: tl(12_000), category: .reklam, scope: .channel(ChannelIds.shopify)))
        s.expenses.append(Expense(id: "e_inf", date: "2026-09-15", name: "Influencer iş birliği",
                                  amount: tl(8000), category: .influencer))

        // 7) Fire
        s.adjustments.append(StockAdjustment(id: "adj_1", date: "2026-09-18",
                                             item: .material(SeedData.M.koli),
                                             qty: 10, unit: .adet, reason: .hasarli))
        return s
    }

    @Test func uctanUcaSenaryo() {
        let s = kurulum()
        let e = Engine(s)
        let r = e.companyMonth("2026-09")

        // --- Stok düşümü doğru mu ---
        // Koli: 1000 alındı, 80 şampuan + 50 serum + 30 set = 160 kullanıldı, 10 hasarlı
        #expect(e.qty(.material(SeedData.M.koli)) == 830)
        // Şampuan kutusu sadece tekil şampuan satışında kullanılır (set kendi kutusunu kullanır)
        #expect(e.qty(.material(SeedData.M.sampuanKutu)) == 400 - 80)
        #expect(e.qty(.material(SeedData.M.setKutu)) == 100 - 30)
        // Etiket: her siparişte 2 adet
        #expect(e.qty(.material(SeedData.M.kirilmazEtiket)) == 1000 - 320)
        // Dolgu: 80×20 + 50×20 + 30×30 = 3500 gram
        #expect(e.qty(.material(SeedData.M.dolguKirpigi)) == 10000 - 3500)
        // Ürün stokları: set 30 adet satıldı -> şampuan ve serumdan 30'ar düşer
        #expect(e.qty(.product(SeedData.P.sampuan)) == 300 - 80 + 2 - 30)
        #expect(e.qty(.product(SeedData.P.serum)) == 250 - 50 - 30)
        // Set kendi stoğunu tutmaz
        #expect(e.qty(.product(SeedData.P.set)) == 0)

        // --- Ortalama maliyet ---
        #expect(approx(e.unitCost(.material(SeedData.M.koli)), Double(tl(11))))

        // --- Çifte sayım yok ---
        let toplamDagilim = r.expenseBreakdown.values.reduce(0, +)
        #expect(toplamDagilim == r.toplamGider)
        #expect(r.gercekKar == r.gercekCiro - r.toplamGider)
        #expect(r.gercekKar == r.toplamKanaldaKalan - r.ortakGider)

        // Kanal reklamları ortak gidere eklenmemiş: ortak = 5000+20000+2000+8000
        #expect(r.ortakGider == tl(35_000))

        // --- Kanal hesapları ---
        let ty = r.channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(ty.netSales == tl(55_920 - 920 - 1398 + 37_500))
        // Kesintiler KDV dahil alınır; kâra yalnızca KDV hariç kısmı girer
        #expect(ty.commission.amount
                == Vat.net(Money.roundHalfAwayFromZero(Double(ty.netSalesIncVat) * 0.20),
                           rate: .yirmi, included: true))
        #expect(ty.shipping.amount == Vat.net(tl(60) * 118, rate: .yirmi, included: true))
        #expect(ty.feeVat > 0)
        #expect(ty.ads.amount == tl(5000))

        let sh = r.channels.first { $0.channelId == ChannelIds.shopify }!
        #expect(sh.netSales == tl(45_000))
        #expect(sh.otherDeduction.amount
                == Vat.net(tl(1500), rate: .yirmi, included: true))   // aylık Shopify ücreti bir kez
        #expect(sh.ads.amount == tl(12_000))

        // --- Uyarılar ---
        let alerts = e.stockAlerts(endingAt: "2026-09")
        #expect(!alerts.contains { $0.item.id == SeedData.M.koli })  // 830 adet, bol

        // --- Rapor yazdır ---
        yazdir(e, s)
    }

    /// Stok azaldığında uyarı ve "kaç siparişlik kaldı" doğru çalışıyor
    @Test func stokAzalincaUyariCikar() {
        var s = SeedData.initialState()
        func esik(_ id: Id, min: Double, kritik: Double) {
            if let i = s.materials.firstIndex(where: { $0.id == id }) {
                s.materials[i].minQty = min
                s.materials[i].criticalQty = kritik
            }
        }
        esik(SeedData.M.koli, min: 150, kritik: 80)
        esik(SeedData.M.kirilmazEtiket, min: 300, kritik: 150)
        esik(SeedData.M.dolguKirpigi, min: 3000, kritik: 1500)

        // 930 siparişe yetecek kadar alım
        s.addPurchase("p_koli", "2026-09-01", .material(SeedData.M.koli), qty: 1000, paid: tl(10_000))
        s.addPurchase("p_etiket", "2026-09-01", .material(SeedData.M.kirilmazEtiket), qty: 2000, paid: tl(1000))
        s.addPurchase("p_dolgu", "2026-09-01", .material(SeedData.M.dolguKirpigi), qty: 20, unit: .kg, paid: tl(4000))
        s.addPurchase("p_kutu", "2026-09-01", .material(SeedData.M.sampuanKutu), qty: 1000, paid: tl(8000))
        s.addPurchase("p_patpat", "2026-09-01", .material(SeedData.M.patpat), qty: 1000, paid: tl(2000))
        s.addPurchase("p_kart", "2026-09-01", .material(SeedData.M.tesekkurKarti), qty: 1000, paid: tl(1500))
        s.addPurchase("p_urun", "2026-09-01", .product(SeedData.P.sampuan), qty: 1000, paid: tl(132_000))

        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 930, gross: tl(650_000))
        s.channelMonths.append(ChannelMonth(id: "chm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 930))
        let e = Engine(s)

        // Sipariş başına: 1 koli, 2 etiket, 20 gram dolgu
        #expect(e.qty(.material(SeedData.M.koli)) == 70)
        #expect(e.status(.material(SeedData.M.koli)) == .kritik)
        #expect(e.qty(.material(SeedData.M.kirilmazEtiket)) == 140)
        #expect(e.status(.material(SeedData.M.kirilmazEtiket)) == .kritik)
        #expect(e.qty(.material(SeedData.M.dolguKirpigi)) == 1400)
        #expect(e.status(.material(SeedData.M.dolguKirpigi)) == .kritik)

        let alerts = e.stockAlerts(endingAt: "2026-09")
        let koli = alerts.first { $0.item.id == SeedData.M.koli }
        let etiket = alerts.first { $0.item.id == SeedData.M.kirilmazEtiket }
        let dolgu = alerts.first { $0.item.id == SeedData.M.dolguKirpigi }

        #expect(koli?.qtyText == "70 adet")
        #expect(koli?.ordersLeft == 70)          // sipariş başına 1 koli
        #expect(etiket?.qtyText == "140 adet")
        #expect(etiket?.ordersLeft == 70)        // sipariş başına 2 etiket
        #expect(dolgu?.qtyText == "1,4 kg")      // gram cinsinden tutulur, kg olarak gösterilir
        #expect(dolgu?.ordersLeft == 70)         // sipariş başına 20 gram

        // Sorunu olmayan malzemeler ekranı doldurmaz
        #expect(!alerts.contains { $0.item.id == SeedData.M.patpat })

        print("\n--- STOK UYARILARI (Eylül 2026) ---")
        for a in alerts {
            let ek = a.ordersLeft.map { "  ~\($0) siparişlik" } ?? ""
            print("  \(a.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(a.qtyText.padding(toLength: 12, withPad: " ", startingAt: 0)) \(a.status.displayName)\(ek)")
        }
    }

    /// Bir gider eklendiğinde bütün rakamlar anında değişir
    @Test func giderEklenincebutunRakamlarDegisir() {
        var s = kurulum()
        let once = Engine(s).companyMonth("2026-09")

        s.expenses.append(Expense(id: "e_yeni", date: "2026-09-20", name: "Ek reklam",
                                  amount: tl(5000), category: .reklam))
        let sonra = Engine(s).companyMonth("2026-09")

        #expect(sonra.toplamGider - once.toplamGider == tl(5000))
        #expect(once.gercekKar - sonra.gercekKar == tl(5000))
        #expect(sonra.karMarjiPct < once.karMarjiPct)
        #expect(sonra.gercekCiro == once.gercekCiro)
        #expect(Engine(s).year(2026).toplamGider - Engine(kurulum()).year(2026).toplamGider == tl(5000))
    }

    private func yazdir(_ e: Engine, _ s: AppState) {
        let r = e.companyMonth("2026-09")
        func satir(_ a: String, _ b: String) {
            print("  \(a.padding(toLength: 26, withPad: " ", startingAt: 0)) \(b)")
        }
        print("\n=========== EYLÜL 2026 ===========")
        satir("GERÇEK CİRO", r.gercekCiro.tlText)
        satir("TOPLAM GİDER", r.toplamGider.tlText)
        satir(r.isLoss ? "GERÇEK ZARAR" : "GERÇEK KÂR", r.gercekKar.tlText)
        satir("KÂR MARJI", Money.formatPercent(r.karMarjiPct))
        satir("Kasadan çıkan", r.nakitCikisi.tlText)

        print("\n--- KANALLAR ---")
        for c in r.channels where !c.isEmpty {
            print("  \(c.channelName)")
            satir("  Satış", c.netSales.tlText)
            satir("  Komisyon", "-" + c.commission.amount.tlText)
            satir("  Kargo", "-" + c.shipping.amount.tlText)
            satir("  Reklam", "-" + c.ads.amount.tlText)
            satir("  Ürün maliyeti", "-" + c.productCost.tlText)
            satir("  Ambalaj", "-" + c.packagingCost.tlText)
            satir("  KANALDA KALAN", c.kanaldaKalan.tlText + "  (" + Money.formatPercent(c.marginPct) + ")")
        }

        print("\n--- GİDER DAĞILIMI ---")
        for (k, v) in r.expenseBreakdown.sorted(by: { $0.value > $1.value }) {
            satir("  " + k.displayName, v.tlText)
        }

        print("\n--- ÜRÜN MALİYETLERİ ---")
        for p in s.products {
            let c = e.cost(of: p.id)
            satir("  " + p.name, "\(c.total.tlText)  (üretim \(c.intrinsic.tlText) + ambalaj \(c.packaging.tlText))")
        }

        print("\n--- STOK DEĞERİ ---")
        satir("  Toplam", e.totalStockValue.tlText)
        print("==================================\n")
    }
}

private extension Kurus {
    var tlText: String { Money.format(self) }
}
