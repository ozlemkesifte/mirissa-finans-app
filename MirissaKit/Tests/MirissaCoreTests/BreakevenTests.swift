import Testing
import Foundation
@testable import MirissaCore

@Suite("Başa baş ve kâr hedefleri")
struct BreakevenTests {

    /// 100 sipariş × 700 TL, %20 komisyon, 60 TL kargo, 100 TL ürün maliyeti
    /// -> sipariş başına katkı 400 TL. Sabit gider 50.000 TL.
    private func kurulum() -> AppState {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []                 // ambalaj karıştırmasın
        s.channels[0].commissionPct = 20
        s.channels[0].shippingPerOrder = tl(60)

        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(70_000))
        s.channelMonths.append(ChannelMonth(id: "chm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 100))
        s.expenses.append(Expense(id: "e_sabit", date: "2026-09-01", name: "Sabit giderler",
                                  amount: tl(50_000), category: .sabit))
        return s
    }

    @Test func siparisBasinaKatkiVeBasaBas() {
        let b = Engine(kurulum()).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.contribution == tl(40_000))
        #expect(b.fixedCosts == tl(50_000))
        #expect(b.profitSoFar == -tl(10_000))
        #expect(approx(b.contributionPerOrder, Double(tl(400))))
        #expect(b.breakevenOrders == 125)
        #expect(b.ordersToBreakeven == 25)
        #expect(!b.reachedBreakeven)
        #expect(b.canCompute)
        #expect(b.blocking == nil)
    }

    /// Ayın kalan günü ve günlük hedef
    @Test func gunlukHedef() {
        let b = Engine(kurulum()).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.daysInMonth == 30)
        #expect(b.elapsedDays == 20)
        #expect(b.remainingDays == 11)          // bugün dahil
        #expect(b.dailyOrdersToBreakeven == 3)  // 25 sipariş / 11 gün
    }

    /// Geride kalındıkça günlük hedef kendini yukarı çeker
    @Test func geriKalincaGunlukHedefYukselir() {
        let s = kurulum()
        let erken = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        let gec = Engine(s).breakeven(month: "2026-09", today: "2026-09-26")
        #expect(erken.dailyOrdersToBreakeven == 3)
        #expect(gec.remainingDays == 5)
        #expect(gec.dailyOrdersToBreakeven == 5)
        #expect(gec.dailyOrdersToBreakeven! > erken.dailyOrdersToBreakeven!)
    }

    /// Mevcut tempoyla ay sonu tahmini
    @Test func aySonuTahmini() {
        let b = Engine(kurulum()).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.projectedOrders == 150)        // günde 5 sipariş × 30 gün
        #expect(b.projectedRevenue == tl(105_000))
        #expect(b.projectedProfit == tl(10_000)) // 150 × 400 − 50.000
        #expect(b.projectionSentence == "Mevcut tempoyla ay sonunda yaklaşık 10.000 TL kâr görünüyorsun.")
    }

    /// Zarar beklenen ay açıkça söylenir
    @Test func zararTahminiAcikcaSoylenir() {
        var s = kurulum()
        s.expenses[0].amount = tl(80_000)
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.projectedProfit == -tl(20_000))
        #expect(b.projectionSentence == "Mevcut tempoyla ay sonunda yaklaşık 20.000 TL zarar görünüyorsun.")
    }

    /// Kâr hedefleri: (sabit gider + hedef) / sipariş başına katkı
    @Test func karHedefleri() {
        let b = Engine(kurulum()).breakeven(month: "2026-09", today: "2026-09-20")
        let g25 = b.goals.first { $0.targetProfit == tl(25_000) }!
        let g50 = b.goals.first { $0.targetProfit == tl(50_000) }!
        let g100 = b.goals.first { $0.targetProfit == tl(100_000) }!
        #expect(g25.orders == 188)      // ceil(75.000 / 400)
        #expect(g50.orders == 250)
        #expect(g100.orders == 375)
        #expect(g25.remainingOrders == 88)
        #expect(g25.dailyOrders == 8)   // ceil(88 / 11)
        #expect(g25.revenue == tl(132_000))   // 188 × 700 = 131.600, bine yuvarlanır
        #expect(approx(g25.products, 188))
        // 150 siparişlik tempo 25.000 hedefinin gerisinde
        #expect(!g25.onTrack)
    }

    /// Kendi hedefine göre önde mi geride mi olduğu açıkça yazılır
    @Test func hedefeGoreDurumCumlesi() {
        var s = kurulum()
        s.settings.profitGoals["2026-09"] = tl(40_000)
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        // Tempo 10.000 TL kâr getiriyor, hedef 40.000 -> 30.000 geride
        #expect(b.customGoalSentence == "Mevcut tempoyla 40.000 TL hedefinin yaklaşık 30.000 TL gerisinde kalıyorsun.")

        var s2 = kurulum()
        s2.settings.profitGoals["2026-09"] = tl(5000)
        let b2 = Engine(s2).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b2.customGoalSentence == "Mevcut tempoyla 5.000 TL hedefini yaklaşık 5.000 TL aşıyorsun.")
    }

    /// Kullanıcı kendi hedefini yazabilir
    @Test func kullaniciHedefi() {
        var s = kurulum()
        s.settings.profitGoals["2026-09"] = tl(75_000)
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        let ozel = b.goals.first { $0.isCustom }
        #expect(ozel != nil)
        #expect(ozel?.targetProfit == tl(75_000))
        #expect(ozel?.orders == 313)    // ceil(125.000 / 400)
    }

    /// Kanal karışımı: bütün siparişler aynı kârlılıktaymış gibi varsayılmaz
    @Test func kanalKarisimiKullanilir() {
        var s = kurulum()
        // Shopify: %3 ödeme komisyonu, kargo yok -> sipariş başına katkı çok daha yüksek
        s.channels[1].paymentPct = 3
        s.addSale("sal_sh", "2026-09", channel: ChannelIds.shopify, product: Fx.sampuanId,
                  qty: 100, gross: tl(90_000))
        s.channelMonths.append(ChannelMonth(id: "chm_sh", month: "2026-09",
                                            channelId: ChannelIds.shopify, orderCount: 100))
        let e = Engine(s)
        let b = e.breakeven(month: "2026-09", today: "2026-09-20")

        let ty = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        let sh = e.channelResult(channelId: ChannelIds.shopify, month: "2026-09")
        #expect(ty.contribution == tl(40_000))
        #expect(sh.contribution == tl(90_000 - 2700 - 10_000))  // 77.300

        // Harman: (40.000 + 77.300) / 200 sipariş
        #expect(b.ordersSoFar == 200)
        #expect(approx(b.contributionPerOrder, Double(tl(117_300)) / 200))
        // Tek kanalın rakamı değil
        #expect(!approx(b.contributionPerOrder, Double(tl(400))))
    }

    /// Aylık platform ücreti sabit gider sayılır, sipariş başına katkıyı düşürmez
    @Test func aylikPlatformUcretiSabitSayilir() {
        var s = kurulum()
        s.channels[1].platformFeeMonthly = tl(1500)
        s.addSale("sal_sh", "2026-09", channel: ChannelIds.shopify, product: Fx.sampuanId,
                  qty: 10, gross: tl(9000))
        s.channelMonths.append(ChannelMonth(id: "chm_sh", month: "2026-09",
                                            channelId: ChannelIds.shopify, orderCount: 10))
        let e = Engine(s)
        let sh = e.channelResult(channelId: ChannelIds.shopify, month: "2026-09")
        #expect(sh.fixedDeduction == tl(1500))
        // Değişken olan: %3 ödeme komisyonu (270 TL) + ürün maliyeti (1.000 TL)
        #expect(sh.contribution == tl(9000 - 270 - 1000))
        let b = e.breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.fixedCosts == tl(51_500))
    }

    /// Stok alımı kârı ve başa baş noktasını bozmaz, sadece nakit çıkışını artırır
    @Test func stokAlimiBasaBasiBozmaz() {
        let s = kurulum()
        let once = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")

        var s2 = s
        s2.addPurchase("pur_koli", "2026-09-05", .material(Fx.koliId), qty: 500, paid: tl(5000))
        let sonra = Engine(s2).breakeven(month: "2026-09", today: "2026-09-20")

        #expect(sonra.profitSoFar == once.profitSoFar)
        #expect(sonra.breakevenOrders == once.breakevenOrders)
        #expect(sonra.fixedCosts == once.fixedCosts)
        #expect(sonra.cashOut - once.cashOut == tl(5000))
    }

    /// Sipariş başına kazanç eksiyse başa baş hesaplanmaz, sebebi söylenir
    @Test func katkiNegatifseUyarir() {
        var s = kurulum()
        s.products[0] = Fx.sampuan(cost: tl(800))   // maliyet fiyatın üstünde
        s.products[0].recipe = []
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(!b.canCompute)
        #expect(b.blocking == .katkiNegatif)
        #expect(b.goals.isEmpty)
        // Tahmin yine de gösterilir — ne kadar zarar edileceği görünsün
        #expect(b.projectedProfit != nil)
        #expect(b.projectedProfit! < 0)
    }

    /// Satış yoksa uydurma rakam verilmez
    @Test func satisYoksaKesinSonucVerilmez() {
        let b = Engine(SeedData.initialState()).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(!b.canCompute)
        #expect(b.blocking == .satisYok)
        #expect(b.goals.isEmpty)
        #expect(b.projectedProfit == nil)
    }

    /// Eksik veriler engellemiyorsa not olarak bildirilir
    @Test func eksikVeriNotOlarakBildirilir() {
        var s = kurulum()
        s.expenses = []                              // sabit gider yok
        s.channelMonths = []                         // sipariş sayısı girilmemiş
        s.products[0] = Fx.sampuan(cost: 0)          // ürün maliyeti yok
        s.products[0].recipe = []
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.canCompute)
        #expect(b.notes.contains(.sabitGiderYok))
        #expect(b.notes.contains(.siparisSayisiTahmini))
        #expect(b.notes.contains(.urunMaliyetiYok))
    }

    /// Geçmiş ayda günlük hedef gösterilmez, tahmin gerçekleşen rakamdır
    @Test func gecmisAydaGunlukHedefYok() {
        let b = Engine(kurulum()).breakeven(month: "2026-09", today: "2026-11-05")
        #expect(b.isPast)
        #expect(b.remainingDays == 0)
        #expect(b.dailyOrdersToBreakeven == nil)
        #expect(b.projectedOrders == 100)
        #expect(b.projectionSentence == "Bu ay yaklaşık 10.000 TL zarar edildi.")
    }

    /// Başa baş aşıldıysa ayrıca belirtilir
    @Test func basaBasAsildiysaBelirtilir() {
        var s = kurulum()
        s.sales[0].qty = 200
        s.sales[0].grossSales = tl(140_000)
        s.channelMonths[0].orderCount = 200
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.reachedBreakeven)
        #expect(b.ordersToBreakeven == 0)
        #expect(b.profitSoFar > 0)
    }

    /// Eski yedekte olmayan ayar alanı okumayı bozmaz
    @Test func eskiYedekOkunabilir() throws {
        let json = """
        {"schemaVersion":1,"savedAt":"2026-09-01T00:00:00Z","state":{
          "materials":[],"products":[],"channels":[],"channelMonths":[],
          "sales":[],"expenses":[],"purchases":[],"adjustments":[],"counts":[],
          "settings":{"consumptionWindowMonths":3,"capitalizePurchases":true,"companyName":"Mirissa Lab"}
        }}
        """
        let back = try Persistence.decode(Data(json.utf8))
        #expect(back.settings.profitGoals.isEmpty)
        #expect(back.settings.companyName == "Mirissa Lab")
    }
}
