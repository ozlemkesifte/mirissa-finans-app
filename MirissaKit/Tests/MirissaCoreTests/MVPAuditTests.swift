import Testing
import Foundation
@testable import MirissaCore

/// MVP tamamlanma denetimi: listedeki her madde gerçekten çalışıyor mu?
@Suite("MVP denetimi")
struct MVPAuditTests {

    /// Gerçek bir Mirissa Lab ayı
    private func kurulum() -> AppState {
        var s = SeedData.initialState()

        // Ürün üretim maliyetleri
        s.products[0].costLines = [CostLine(id: "c1", label: "Üretim", amount: tl(132))]
        s.products[1].costLines = [CostLine(id: "c2", label: "Üretim", amount: tl(139))]

        // Uyarı eşikleri
        func esik(_ id: Id, _ min: Double, _ kritik: Double) {
            if let i = s.materials.firstIndex(where: { $0.id == id }) {
                s.materials[i].minQty = min
                s.materials[i].criticalQty = kritik
            }
        }
        esik(SeedData.M.koli, 900, 850)
        esik(SeedData.M.dolguKirpigi, 3000, 1500)

        // Stok alımları — koli iki farklı fiyattan
        func al(_ id: String, _ d: DateKey, _ item: ItemRef, _ q: Double, _ u: UnitCode, _ tutar: Double) {
            s.purchases.append(StockPurchase(id: id, date: d, item: item, qty: q, unit: u,
                                             totalPaid: tl(tutar)))
        }
        al("p_koli1", "2026-08-05", .material(SeedData.M.koli), 500, .adet, 5000)   // 10 TL
        al("p_koli2", "2026-08-20", .material(SeedData.M.koli), 500, .adet, 6000)   // 12 TL
        al("p_skutu", "2026-08-05", .material(SeedData.M.sampuanKutu), 400, .adet, 3200)
        al("p_rkutu", "2026-08-05", .material(SeedData.M.serumKutu), 300, .adet, 2400)
        al("p_setkutu", "2026-08-05", .material(SeedData.M.setKutu), 100, .adet, 1500)
        al("p_patpat", "2026-08-05", .material(SeedData.M.patpat), 600, .adet, 1200)
        al("p_etiket", "2026-08-05", .material(SeedData.M.kirilmazEtiket), 1000, .adet, 500)
        al("p_dolgu", "2026-08-06", .material(SeedData.M.dolguKirpigi), 10, .kg, 2000)
        al("p_kart", "2026-08-05", .material(SeedData.M.tesekkurKarti), 500, .adet, 750)
        al("p_sampuan", "2026-08-10", .product(SeedData.P.sampuan), 300, .adet, 39_600)
        al("p_serum", "2026-08-10", .product(SeedData.P.serum), 250, .adet, 34_750)

        // Kanal ayarları — Trendyol ve Shopify ayrı
        s.channels[0].commissionPct = 20
        s.channels[0].shippingPerOrder = tl(60)
        s.channels[1].paymentPct = 3
        s.channels[1].shippingPerOrder = tl(70)
        s.channels[1].platformFeeMonthly = tl(1500)

        // Aylık toplu satış girişi — aynı aya birden çok ürün
        s.addSale("s1", "2026-09", channel: ChannelIds.trendyol, product: SeedData.P.sampuan,
                  qty: 80, gross: tl(55_920), discount: tl(920), returnsAmount: tl(1398), returnsQty: 2)
        s.addSale("s2", "2026-09", channel: ChannelIds.trendyol, product: SeedData.P.serum,
                  qty: 50, gross: tl(37_500))
        s.addSale("s3", "2026-09", channel: ChannelIds.shopify, product: SeedData.P.set,
                  qty: 30, gross: tl(45_000))
        s.channelMonths.append(ChannelMonth(id: "cm_t", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 128))
        s.channelMonths.append(ChannelMonth(id: "cm_s", month: "2026-09",
                                            channelId: ChannelIds.shopify, orderCount: 30))

        // Giderler: sabit (düzenli), reklam (satışa bağlı), influencer
        s.expenses = [
            Expense(id: "e_muh", date: "2026-08-01", name: "Muhasebeci", amount: tl(5000),
                    category: .sabit, recurrence: .aylik),
            Expense(id: "e_ajans", date: "2026-08-01", name: "Ajans", amount: tl(20_000),
                    category: .sabit, recurrence: .aylik),
            Expense(id: "e_rek", date: "2026-09-10", name: "Trendyol reklamı", amount: tl(5000),
                    category: .reklam, scope: .channel(ChannelIds.trendyol),
                    attachment: "fatura_reklam.jpg"),
            Expense(id: "e_inf", date: "2026-09-15", name: "Influencer", amount: tl(8000),
                    category: .influencer),
        ]

        // Fire ve sayım
        s.adjustments.append(StockAdjustment(id: "a1", date: "2026-09-18",
                                             item: .material(SeedData.M.koli),
                                             qty: 10, unit: .adet, reason: .hasarli))
        s.counts.append(StockCount(id: "c_pat", date: "2026-09-20",
                                   item: .material(SeedData.M.patpat),
                                   countedQty: 420, unit: .adet, reason: .sayimFarki))
        return s
    }

    // 1 — Aylık toplu satış girişi
    @Test func madde01_aylikSatisGirisi() {
        let e = Engine(kurulum())
        let r = e.companyMonth("2026-09")
        #expect(r.channels.filter { !$0.isEmpty }.count == 2)
        #expect(r.units == 160)                       // 80 + 50 + 30
        #expect(r.gercekCiro == tl(55_920 - 920 - 1398 + 37_500 + 45_000))
    }

    // 2 — Trendyol ve Shopify ayrı kârlılık
    @Test func madde02_kanallarAyriHesaplanir() {
        let e = Engine(kurulum())
        let ty = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        let sh = e.channelResult(channelId: ChannelIds.shopify, month: "2026-09")

        // Kesinti tutarları KDV hariç raporlanır; KDV'leri indirilecek KDV'ye gider
        func netKesinti(_ brut: Kurus) -> Kurus { Vat.net(brut, rate: .yirmi, included: true) }

        #expect(ty.commission.amount
                == netKesinti(Money.roundHalfAwayFromZero(Double(ty.netSalesIncVat) * 0.20)))
        #expect(ty.shipping.amount == netKesinti(tl(60) * 128))
        #expect(ty.otherDeduction.amount == 0)         // Trendyol'da aylık ücret yok

        #expect(sh.commission.amount
                == netKesinti(Money.roundHalfAwayFromZero(Double(sh.netSalesIncVat) * 0.03)))
        #expect(sh.shipping.amount == netKesinti(tl(70) * 30))
        #expect(sh.otherDeduction.amount == netKesinti(tl(1500)))  // Shopify aylık ücreti

        #expect(ty.marginPct != sh.marginPct)
        // Şirket kârı iki kanalın kalanından ortak giderler düşülerek bulunur
        let r = e.companyMonth("2026-09")
        #expect(r.gercekKar == ty.kanaldaKalan + sh.kanaldaKalan - r.ortakGider)
    }

    // 3 — Manuel gider ve fatura eki
    @Test func madde03_giderVeFaturaEki() {
        let s = kurulum()
        let e = Engine(s)
        let liste = e.expenseInstances(month: "2026-09")
        #expect(liste.contains { $0.name == "Influencer" && $0.amount == tl(8000) })
        let reklam = liste.first { $0.name == "Trendyol reklamı" }
        #expect(reklam?.attachment == "fatura_reklam.jpg")
        #expect(s.attachmentNames.contains("fatura_reklam.jpg"))
    }

    // 4 — Sabit giderler: tekrar eder, durdurulabilir, aya özel değiştirilebilir
    @Test func madde04_sabitGiderler() {
        var s = kurulum()
        let e = Engine(s)
        for ay in ["2026-08", "2026-09", "2026-12"] {
            #expect(e.expenseInstances(month: ay).contains { $0.name == "Ajans" })
        }
        s.expenses[1].endMonth = "2026-09"                       // durdur
        s.expenses[1].overrides["2026-08"] = ExpenseOverride(amount: tl(25_000))
        let e2 = Engine(s)
        #expect(e2.expenseInstances(month: "2026-08").first { $0.name == "Ajans" }?.amount == tl(25_000))
        #expect(e2.expenseInstances(month: "2026-09").contains { $0.name == "Ajans" })
        #expect(!e2.expenseInstances(month: "2026-10").contains { $0.name == "Ajans" })
    }

    // 5 + 6 — Stok satın alma ve ağırlıklı birim maliyet
    @Test func madde05_06_alimVeAgirlikliMaliyet() {
        let e = Engine(kurulum())
        // 500 adet 10 TL + 500 adet 12 TL -> 11 TL
        #expect(approx(e.unitCost(.material(SeedData.M.koli), asOf: "2026-08-31"), Double(tl(11))))
        // Alım giderlerde görünür ama kâra gider yazılmaz
        let alimlar = e.expenseInstances(month: "2026-08").filter { $0.sourceKind == .stokAlimi }
        #expect(alimlar.count == 11)
        #expect(alimlar.allSatisfy { $0.capitalized && $0.expenseAmount == 0 })
    }

    // 7 + 8 — Satışla otomatik stok düşümü ve paketleme reçeteleri
    @Test func madde07_08_otomatikStokDusumuVeRecete() {
        let e = Engine(kurulum())
        // Koli sipariş başına: Trendyol 128 sipariş (130 ürün, hiçbirinde 3+ ürün olamaz: 130 ≤ 2×128)
        // → 128 koli; Shopify 30 sipariş → 30 koli; 10 tanesi hasarlı
        #expect(e.qty(.material(SeedData.M.koli)) == 1000 - 128 - 30 - 10)
        // Set kendi kutusunu kullanır, bileşenlerin kutuları harcanmaz
        #expect(e.qty(.material(SeedData.M.sampuanKutu)) == 400 - 80)
        #expect(e.qty(.material(SeedData.M.serumKutu)) == 300 - 50)
        #expect(e.qty(.material(SeedData.M.setKutu)) == 100 - 30)
        // Sipariş başına 2 etiket
        #expect(e.qty(.material(SeedData.M.kirilmazEtiket)) == 1000 - 320)
        // Dolgu: 80×20 + 50×20 + 30×30 gram
        #expect(e.qty(.material(SeedData.M.dolguKirpigi)) == 10_000 - 3500)
        // Set satılınca bileşen ürünler düşer, iade edilen 2 şampuan geri gelir
        #expect(e.qty(.product(SeedData.P.sampuan)) == 300 - 80 + 2 - 30)
        #expect(e.qty(.product(SeedData.P.serum)) == 250 - 50 - 30)
        #expect(e.qty(.product(SeedData.P.set)) == 0)   // set kendi stoğunu tutmaz
    }

    // 9 — Fire ve sayım düzeltmesi
    @Test func madde09_fireVeSayim() {
        let e = Engine(kurulum())
        let koliGecmis = e.history(.material(SeedData.M.koli))
        #expect(koliGecmis.contains { $0.movement.reason == .hasarli && $0.delta == -10 })

        // Patpat: 600 alındı, 160 kullanıldı = 440; sayımda 420 bulundu -> fark -20
        #expect(e.qty(.material(SeedData.M.patpat)) == 420)
        let sayim = e.history(.material(SeedData.M.patpat)).first { $0.kind == .sayim }
        #expect(sayim?.delta == -20)
        // Sayım birim maliyeti değiştirmez
        #expect(approx(e.unitCost(.material(SeedData.M.patpat)), Double(tl(2))))
    }

    // 10 — Kritik stok uyarıları
    @Test func madde10_stokUyarilari() {
        let e = Engine(kurulum())
        let uyarilar = e.stockAlerts(endingAt: "2026-09")
        let koli = uyarilar.first { $0.item.id == SeedData.M.koli }
        #expect(koli?.status == .kritik)          // 830 adet, kritik eşik 850
        #expect(koli?.ordersLeft != nil)
        // Eşiği olmayan ve bol olan malzemeler ekranı doldurmaz
        #expect(!uyarilar.contains { $0.item.id == SeedData.M.tesekkurKarti })
    }

    // 11 — Aylık ve yıllık raporlar
    @Test func madde11_raporlar() {
        let e = Engine(kurulum())
        let ay = e.companyMonth("2026-09")
        #expect(ay.expenseBreakdown.values.reduce(0, +) == ay.toplamGider)
        #expect(ay.gercekKar == ay.gercekCiro - ay.toplamGider)

        let yil = e.year(2026)
        #expect(yil.months.count == 12)
        #expect(yil.gercekCiro == yil.months.reduce(0) { $0 + $1.gercekCiro })
        #expect(yil.toplamGider == yil.months.reduce(0) { $0 + $1.toplamGider })
        #expect(yil.gercekKar == yil.gercekCiro - yil.toplamGider)
        #expect(e.trend(endingAt: "2026-09", months: 6).count == 6)

        // Kanal raporu aylık sonuçların toplamı
        let tyYil = e.channelTotals(from: "2026-01", to: "2026-12", channelId: ChannelIds.trendyol)
        #expect(tyYil.netSales == e.channelResult(channelId: ChannelIds.trendyol, month: "2026-09").netSales)
    }

    // 12 — Nakit çıkışı ile kâr ayrı
    @Test func madde12_nakitCikisiKarDegildir() {
        let agustos = Engine(kurulum()).companyMonth("2026-08")
        // Ağustos: satış yok, sadece stok alımı var
        #expect(agustos.gercekCiro == 0)
        #expect(agustos.stokAlimi == tl(96_900))      // alımların toplamı
        #expect(agustos.nakitCikisi > agustos.toplamGider)
        // Alımlar kârdan düşmedi, sadece sabit giderler düştü
        #expect(agustos.gercekKar == -tl(25_000))     // muhasebeci + ajans
    }

    // 13 — Aylık hedef (ay başı) ve gerçekleşen sonuç (ay sonu)
    @Test func madde13_hedefVeGerceklesen() {
        var s = kurulum()
        s.settings.profitGoals["2026-10"] = tl(50_000)
        let e = Engine(s)

        // Eylül satışları girilmiş -> gerçekleşen sonuç
        let eylul = e.plan(month: "2026-09", today: "2026-09-30")
        #expect(eylul.mode == .gerceklesen)
        let a = eylul.actual!
        #expect(a.orders == 158)
        #expect(a.revenue == eylul.actual!.revenue)
        #expect(a.profit == a.revenue - a.expenses)
        #expect(a.breakevenOrders != nil)
        #expect(a.breakevenSentence != nil)

        // Ekim'de satış yok -> aylık hedef, Eylül dağılımına göre, "yaklaşık"
        let ekim = e.plan(month: "2026-10", today: "2026-09-30")
        #expect(ekim.mode == .hedef)
        #expect(ekim.basis == .gecmisAy("2026-09"))
        #expect(ekim.isApproximate)
        #expect(ekim.daysInMonth == 31)
        #expect(ekim.actual == nil)
        #expect(ekim.progressOrders == nil)          // tempo tahmini yok
        let basaBas = ekim.targets.first { $0.isBreakeven }!
        #expect(basaBas.orders > 0)
        #expect(basaBas.dailyOrders == Int(ceil(Double(basaBas.orders) / 31)))
        #expect(ekim.targets.contains { $0.isCustom && $0.targetProfit == tl(50_000) })
    }

    // 14 — Sabit / satışa bağlı sınıflandırma kullanıcıda
    @Test func madde14_giderSiniflandirmasiDegistirilebilir() {
        var degisken = kurulum()                               // reklam varsayılan: satışa bağlı
        var sabit = kurulum()
        sabit.expenses[2].behavior = .sabit

        // Ekim hedefi, Eylül dağılımına dayanır -> sınıflandırma hedefi değiştirir
        let a = Engine(degisken).plan(month: "2026-10", today: "2026-09-30")
        let b = Engine(sabit).plan(month: "2026-10", today: "2026-09-30")

        #expect(a.contributionPerOrder < b.contributionPerOrder)  // satışa bağlıyken katkı düşük
        #expect(a.targets.first { $0.isBreakeven }!.orders
                != b.targets.first { $0.isBreakeven }!.orders)

        // Ama Eylül kârı ikisinde de aynı
        #expect(Engine(degisken).companyMonth("2026-09").gercekKar
                == Engine(sabit).companyMonth("2026-09").gercekKar)

        degisken.expenses[2].behavior = .satisaBagli
        #expect(Engine(degisken).companyMonth("2026-09").gercekKar
                == Engine(sabit).companyMonth("2026-09").gercekKar)
    }

    // Bütün kayıtlar düzenlenebilir ve silinebilir olmalı
    @Test func madde15_kayitlarDuzenlenebilirVeSilinebilir() {
        var s = kurulum()
        let once = Engine(s).companyMonth("2026-09")

        s.sales[0].qty = 100                                    // satış düzenle
        s.expenses.removeAll { $0.id == "e_inf" }               // gider sil
        s.purchases.removeAll { $0.id == "p_koli2" }            // alım sil
        s.adjustments.removeAll()                               // fire sil
        let sonra = Engine(s)

        #expect(sonra.companyMonth("2026-09").gercekKar != once.gercekKar)
        // Koli sipariş sayısına göre: 128 + 30 = 158 (şampuan adedi artsa da sipariş sayısı aynı)
        #expect(sonra.qty(.material(SeedData.M.koli)) == 500 - 158)   // yeniden hesaplandı
        #expect(approx(sonra.unitCost(.material(SeedData.M.koli), asOf: "2026-08-31"), Double(tl(10))))
    }

    /// Denetim özeti
    @Test func denetimOzeti() {
        var s = kurulum()
        s.settings.profitGoals["2026-10"] = tl(50_000)
        let e = Engine(s)
        let r = e.companyMonth("2026-09")
        let sonuc = e.plan(month: "2026-09", today: "2026-09-30")
        let hedef = e.plan(month: "2026-10", today: "2026-09-30")

        print("\n========= MVP DENETİMİ — EYLÜL 2026 =========")
        func satir(_ a: String, _ v: String) {
            print("  \(a.padding(toLength: 28, withPad: " ", startingAt: 0)) \(v)")
        }
        satir("Gerçek ciro", Money.format(r.gercekCiro))
        satir("Toplam gider", Money.format(r.toplamGider))
        satir("Gerçek kâr", Money.format(r.gercekKar))
        satir("Kâr marjı", Money.formatPercent(r.karMarjiPct))
        satir("Nakit çıkışı", Money.format(r.nakitCikisi))
        satir("Stok değeri", Money.format(e.totalStockValue))
        print("  --- kanallar ---")
        for c in r.channels where !c.isEmpty {
            satir(c.channelName + " kalan", Money.format(c.kanaldaKalan)
                  + "  (" + Money.formatPercent(c.marginPct) + ")")
        }
        print("  --- eylül sonucu ---")
        if let a = sonuc.actual {
            satir("Gerçekleşen sipariş", "\(a.orders)")
            satir("Başa baş hedefi", "\(a.breakevenOrders ?? 0) sipariş")
            satir("Sonuç", a.breakevenSentence ?? "-")
        }
        print("  --- ekim hedefi (yaklaşık) ---")
        for t in hedef.targets {
            satir(t.label, "\(t.orders) sipariş · günde ~\(t.dailyOrders)")
        }
        print("  --- stok ---")
        for u in e.stockAlerts(endingAt: "2026-09") {
            satir(u.name, "\(u.qtyText) — \(u.status.shortLabel)")
        }
        print("=============================================\n")
        #expect(r.expenseBreakdown.values.reduce(0, +) == r.toplamGider)
    }
}
