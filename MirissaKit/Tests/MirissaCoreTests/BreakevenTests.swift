import Testing
import Foundation
@testable import MirissaCore

@Suite("Aylık hedef ve ay sonu sonucu")
struct BreakevenTests {

    /// Ağustos tamamlanmış: 100 sipariş × 700 TL, %20 komisyon, 60 TL kargo,
    /// 100 TL ürün maliyeti -> sipariş başına 400 TL katkı.
    /// Aylık 50.000 TL sabit gider.
    private func kurulum(eylulSatisi: Bool = false) -> AppState {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].shippingPerOrder = tl(60)

        s.addSale("sal_ag", "2026-08", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(70_000))
        s.channelMonths.append(ChannelMonth(id: "chm_ag", month: "2026-08",
                                            channelId: ChannelIds.trendyol, orderCount: 100))
        s.expenses.append(Expense(id: "e_sabit", date: "2026-08-01", name: "Ajans",
                                  amount: tl(50_000), category: .sabit, recurrence: .aylik))
        if eylulSatisi {
            s.addSale("sal_ey", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                      qty: 140, gross: tl(98_000))
            s.channelMonths.append(ChannelMonth(id: "chm_ey", month: "2026-09",
                                                channelId: ChannelIds.trendyol, orderCount: 140))
        }
        return s
    }

    // MARK: Ay başı — hedef

    /// Satış girilmemişken aylık hedef gösterilir, gerçek zamanlı ifade kullanılmaz
    @Test func ayBasindaHedefGosterilir() {
        let p = Engine(kurulum()).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.mode == .hedef)
        #expect(p.basis == .gecmisAy("2026-08"))
        #expect(p.isApproximate)
        #expect(p.actual == nil)
        #expect(p.progressOrders == nil)          // tempo tahmini yapılmaz
        #expect(p.remainingDays == nil)
        #expect(approx(p.contributionPerOrder, Double(tl(400))))
        #expect(p.fixedCosts == tl(50_000))
    }

    /// Hedef rakamları: ayın tamamı ve günlük ortalama
    @Test func hedefRakamlari() {
        let p = Engine(kurulum()).plan(month: "2026-09", today: "2026-09-03")
        func hedef(_ kar: Kurus) -> MonthlyTarget { p.targets.first { $0.targetProfit == kar }! }

        let basaBas = hedef(0)
        #expect(basaBas.isBreakeven)
        #expect(basaBas.orders == 125)            // 50.000 / 400
        #expect(basaBas.dailyOrders == 5)         // 125 / 30 gün

        #expect(hedef(tl(25_000)).orders == 188)  // 75.000 / 400
        #expect(hedef(tl(25_000)).dailyOrders == 7)
        #expect(hedef(tl(50_000)).orders == 250)
        #expect(hedef(tl(50_000)).dailyOrders == 9)
        #expect(hedef(tl(100_000)).orders == 375)
        #expect(hedef(tl(100_000)).dailyOrders == 13)
    }

    /// Günlük rakam ayın gerçek gün sayısına bölünür
    @Test func gunlukRakamAyinGunSayisinaBolunur() {
        let e = Engine(kurulum())
        let eylul = e.plan(month: "2026-09", today: "2026-09-03")   // 30 gün
        let ekim = e.plan(month: "2026-10", today: "2026-09-03")    // 31 gün
        #expect(eylul.daysInMonth == 30)
        #expect(ekim.daysInMonth == 31)
        let a = eylul.targets.first { $0.isBreakeven }!
        let b = ekim.targets.first { $0.isBreakeven }!
        #expect(a.orders == b.orders)
        #expect(a.dailyOrders == 5)      // ceil(125/30)
        #expect(b.dailyOrders == 5)      // ceil(125/31) = 5 (4,03 -> 5)
    }

    /// Hedef, o ayda satış olup olmamasından bağımsızdır
    @Test func hedefSatistanBagimsiz() {
        let bos = Engine(kurulum()).plan(month: "2026-09", today: "2026-09-03")
        var s = kurulum()
        s.settings.progressAsOf["2026-09"] = "2026-09-10"
        s.addSale("ara", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 30, gross: tl(21_000))
        s.channelMonths.append(ChannelMonth(id: "chm_ara", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 30))
        let ara = Engine(s).plan(month: "2026-09", today: "2026-09-10")
        #expect(bos.targets.first { $0.isBreakeven }?.orders
                == ara.targets.first { $0.isBreakeven }?.orders)
    }

    // MARK: Ara durum

    /// Ara satış girilmişse kalan gün ve kalan sipariş hesaplanır
    @Test func araDurumGirilirseKalanHesaplanir() {
        var s = kurulum()
        s.settings.progressAsOf["2026-09"] = "2026-09-15"
        s.addSale("ara", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 40, gross: tl(28_000))
        s.channelMonths.append(ChannelMonth(id: "chm_ara", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 40))
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-15")

        #expect(p.mode == .hedef)                 // sonuç değil, hâlâ hedef
        #expect(p.hasProgress)
        #expect(p.progressOrders == 40)
        #expect(p.remainingDays == 15)            // 30 − 15
        let basaBas = p.targets.first { $0.isBreakeven }!
        #expect(basaBas.remainingOrders == 85)    // 125 − 40
        #expect(basaBas.remainingDailyOrders == 6) // ceil(85/15)
    }

    /// Ara durum işareti yoksa kalan sipariş/gün tahmini yapılmaz
    @Test func araDurumYoksaTahminYok() {
        let p = Engine(kurulum()).plan(month: "2026-09", today: "2026-09-15")
        #expect(!p.hasProgress)
        #expect(p.targets.allSatisfy { $0.remainingOrders == nil })
    }

    // MARK: Ay sonu — gerçekleşen

    /// Satışlar girildiğinde hedef yerine gerçek sonuç gösterilir
    @Test func satisGirilinceSonucaDoner() {
        let p = Engine(kurulum(eylulSatisi: true)).plan(month: "2026-09", today: "2026-09-30")
        #expect(p.mode == .gerceklesen)
        #expect(p.basis == .ayinKendisi)
        #expect(!p.isApproximate)
        #expect(p.targets.isEmpty)

        let a = p.actual!
        #expect(a.orders == 140)
        #expect(a.revenue == tl(98_000))
        #expect(a.profit == a.revenue - a.expenses)
        #expect(a.breakevenOrders == 125)
        #expect(a.ordersVsBreakeven == 15)
        #expect(a.reachedBreakeven)
        #expect(a.breakevenSentence == "Başa baş hedefinin 15 sipariş üzerinde kalındı.")
    }

    /// Başa başın altında kalınan ay
    @Test func basaBasAltindaKalinanAy() {
        var s = kurulum()
        s.addSale("sal_ey", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(70_000))
        s.channelMonths.append(ChannelMonth(id: "chm_ey", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 100))
        let a = Engine(s).plan(month: "2026-09", today: "2026-09-30").actual!
        #expect(a.ordersVsBreakeven == -25)
        #expect(!a.reachedBreakeven)
        #expect(a.breakevenSentence == "Başa baş hedefinin 25 sipariş altında kalındı.")
        #expect(a.profit == -tl(10_000))
        #expect(a.summarySentence == "Bu ay yaklaşık 10.000 TL zarar edildi.")
    }

    /// Geçmiş ay her zaman sonuç gösterir
    @Test func gecmisAySonucGosterir() {
        let p = Engine(kurulum()).plan(month: "2026-08", today: "2026-09-15")
        #expect(p.mode == .gerceklesen)
        #expect(p.actual?.orders == 100)
    }

    /// Bu ay bitmeden girilen satışlar sonuç sayılır ama not düşülür
    @Test func ayBitmedenGirilenSatisNotDuser() {
        let p = Engine(kurulum(eylulSatisi: true)).plan(month: "2026-09", today: "2026-09-12")
        #expect(p.mode == .gerceklesen)
        #expect(p.notes.contains(.ayHenuzBitmedi))
    }

    // MARK: Varsayım kaynağı

    /// Geçmiş veri yoksa kesin rakam verilmez, beklenen profil istenir
    @Test func gecmisVeriYoksaReferansYok() {
        let p = Engine(SeedData.initialState()).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.mode == .hedef)
        #expect(p.blocking == .referansYok)
        #expect(p.targets.isEmpty)
        #expect(p.basis == .yok)
    }

    /// Beklenen sipariş profili girilirse hedef hesaplanır ve varsayım belirtilir
    @Test func beklenenProfilIleHedefHesaplanir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].shippingPerOrder = tl(60)
        s.expenses.append(Expense(id: "e", date: "2026-09-01", name: "Ajans",
                                  amount: tl(50_000), category: .sabit, recurrence: .aylik))
        s.settings.expectedMix = ExpectedMix(
            channelId: ChannelIds.trendyol, productId: Fx.sampuanId,
            averageOrderValue: tl(700)
        )
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.basis == .beklenenDagilim)
        #expect(p.isApproximate)
        // 700 − 140 komisyon − 60 kargo − 100 ürün = 400 TL
        #expect(approx(p.contributionPerOrder, Double(tl(400))))
        #expect(p.targets.first { $0.isBreakeven }?.orders == 125)
    }

    /// Gerçek geçmiş veri, beklenen profilden önce gelir
    @Test func gecmisAyBeklenenProfildenOnceGelir() {
        var s = kurulum()
        s.settings.expectedMix = ExpectedMix(
            channelId: ChannelIds.trendyol, productId: Fx.sampuanId,
            averageOrderValue: tl(2000)
        )
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.basis == .gecmisAy("2026-08"))
    }

    /// Boş aylar atlanır, en yakın dolu ay referans alınır
    @Test func bosAylarAtlanir() {
        let p = Engine(kurulum()).plan(month: "2026-12", today: "2026-12-02")
        #expect(p.basis == .gecmisAy("2026-08"))
    }

    // MARK: Ayrıntılar

    /// Satış olmasa da kanalın aylık sabit ücreti hedefe dahil edilir
    @Test func aylikPlatformUcretiHedefeDahil() {
        var s = kurulum()
        s.channels[1].platformFeeMonthly = tl(1500)     // Shopify
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.fixedCosts == tl(51_500))
        #expect(p.targets.first { $0.isBreakeven }?.orders == 129)  // ceil(51.500/400)
    }

    /// Sipariş başına kazanç eksiyse hedef verilmez
    @Test func katkiNegatifseHedefYok() {
        var s = kurulum()
        s.products[0] = Fx.sampuan(cost: tl(800))
        s.products[0].recipe = []
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.blocking == .katkiNegatif)
        #expect(p.targets.isEmpty)
    }

    /// Kullanıcının kendi hedefi listede görünür
    @Test func ozelHedefListedeGorunur() {
        var s = kurulum()
        s.settings.profitGoals["2026-09"] = tl(75_000)
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-03")
        let ozel = p.targets.first { $0.isCustom }
        #expect(ozel?.targetProfit == tl(75_000))
        #expect(ozel?.orders == 313)              // ceil(125.000/400)
        #expect(ozel?.dailyOrders == 11)          // ceil(313/30)
        // Hedefler küçükten büyüğe sıralı
        #expect(p.targets.map(\.targetProfit) == p.targets.map(\.targetProfit).sorted())
    }

    /// Sabit gider girilmemişse söylenir ama hesap yapılır
    @Test func sabitGiderYoksaNotDuser() {
        var s = kurulum()
        s.expenses = []
        let p = Engine(s).plan(month: "2026-09", today: "2026-09-03")
        #expect(p.notes.contains(.sabitGiderYok))
        #expect(p.fixedCosts == 0)
        #expect(p.targets.first { $0.isBreakeven }?.orders == 0)
    }
}
