import Testing
import Foundation
@testable import MirissaCore

@Suite("Kanal ve şirket kârlılığı")
struct PnLTests {

    /// Kullanıcının tarif ettiği Trendyol örneği birebir doğrulanır
    @Test func trendyolKanaldaKalanOrnegi() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000), discount: tl(2000), returnsAmount: tl(3000))
        s.channelMonths.append(ChannelMonth(
            id: "chm_1", month: "2026-09", channelId: ChannelIds.trendyol,
            orderCount: 100,
            commissionActual: tl(3800),
            shippingActual: tl(12_000),
            serviceFeeActual: 0,
            otherDeductionActual: 0,
            adsActual: tl(5000)
        ))
        // ürün maliyeti 200 TL/adet × 100 = 20.000 TL
        s.products[0] = Fx.sampuan(cost: tl(200))
        s.products[0].recipe = []

        let r = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(r.netSales == tl(95_000))
        #expect(r.productCost == tl(20_000))
        #expect(r.kanaldaKalan == tl(54_200))
    }

    /// Elle girilen tutar otomatik hesabın üzerine yazar ve bu belli edilir
    @Test func elleGirilenTutarOtomatigiEzer() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 10, gross: tl(10_000))
        let auto = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(auto.commission.amount == tl(2000))     // %20
        #expect(!auto.commission.isManual)

        s.channelMonths.append(ChannelMonth(
            id: "chm_1", month: "2026-09", channelId: ChannelIds.trendyol,
            commissionActual: tl(1750)
        ))
        let manual = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(manual.commission.amount == tl(1750))
        #expect(manual.commission.isManual)
    }

    /// Sipariş sayısı girilmemişse adetten tahmin edilir ve bu işaretlenir
    @Test func siparisSayisiTahmini() {
        var s = Fx.base()
        s.channels[0].shippingPerOrder = tl(60)
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 50, gross: tl(25_000))
        let est = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(est.orders == 50)
        #expect(est.ordersIsEstimate)
        #expect(est.shipping.amount == tl(3000))

        s.channelMonths.append(ChannelMonth(id: "chm_1", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 40))
        let real = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(real.orders == 40)
        #expect(!real.ordersIsEstimate)
        #expect(real.shipping.amount == tl(2400))
    }

    /// Aylık platform ücreti ürün satırı sayısından bağımsız, ayda bir kez alınır
    @Test func aylikPlatformUcretiBirKez() {
        var s = Fx.base()
        s.channels[1].platformFeeMonthly = tl(1500)
        s.addSale("s1", "2026-09", channel: ChannelIds.shopify, product: Fx.sampuanId, qty: 10, gross: tl(5000))
        s.addSale("s2", "2026-09", channel: ChannelIds.shopify, product: Fx.serumId, qty: 10, gross: tl(5000))
        s.addSale("s3", "2026-09", channel: ChannelIds.shopify, product: Fx.setId, qty: 5, gross: tl(7500))
        let r = Fx.engine(s).channelResult(channelId: ChannelIds.shopify, month: "2026-09")
        // %3 ödeme komisyonu 17.500 üzerinden 525 TL, platform ücreti 1.500 TL
        #expect(r.otherDeduction.amount == tl(1500))
        #expect(r.commission.amount == tl(525))
    }

    /// Satış olmayan ay: sıfır gösterir, NaN üretmez
    @Test func satissizAySifir() {
        let r = Fx.engine(Fx.base()).companyMonth("2026-09")
        #expect(r.gercekCiro == 0)
        #expect(r.gercekKar == 0)
        #expect(r.karMarjiPct == 0)
        #expect(!r.isLoss)
        #expect(!r.hasData)
    }

    /// Zarar eden ay doğru hesaplanır ve zarar olarak işaretlenir
    @Test func zararEdenAy() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 10, gross: tl(10_000))
        s.expenses.append(Expense(id: "e1", date: "2026-09-01", name: "Ajans",
                                  amount: tl(28_000), category: .sabit))
        let r = Fx.engine(s).companyMonth("2026-09")
        #expect(r.isLoss)
        #expect(r.gercekKar < 0)
        #expect(r.karMarjiPct < 0)
    }

    /// Kâr marjı: 185.000 ciro, 132.000 gider -> 53.000 kâr, %28,6
    @Test func karMarjiHesabi() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.other, product: Fx.sampuanId,
                  qty: 100, gross: tl(185_000))
        s.expenses.append(Expense(id: "e1", date: "2026-09-01", name: "Giderler",
                                  amount: tl(132_000), category: .diger))
        let r = Fx.engine(s).companyMonth("2026-09")
        #expect(r.gercekCiro == tl(185_000))
        #expect(r.toplamGider == tl(132_000))
        #expect(r.gercekKar == tl(53_000))
        #expect(approx(r.karMarjiPct, 28.648, 0.01))
        #expect(Money.formatPercent(r.karMarjiPct) == "%28,6")
    }

    /// Yıllık rapor ayları toplar
    @Test func yillikToplam() {
        var s = Fx.base()
        for m in 1...12 {
            s.addSale("sal_\(m)", Dates.monthKey(2026, m), channel: ChannelIds.other,
                      product: Fx.sampuanId, qty: 10, gross: tl(10_000))
        }
        s.expenses.append(Expense(id: "e1", date: "2026-01-01", name: "Sabit",
                                  amount: tl(2000), category: .sabit, recurrence: .aylik))
        let y = Fx.engine(s).year(2026, today: "2026-12-31")
        #expect(y.gercekCiro == tl(120_000))
        #expect(y.toplamGider == tl(24_000))
        #expect(y.gercekKar == tl(96_000))
        #expect(y.trend.count == 12)
    }

    /// Son 6 ay trendi doğru aralığı verir
    @Test func altiAylikTrend() {
        let t = Fx.engine(Fx.base()).trend(endingAt: "2026-09", months: 6)
        #expect(t.count == 6)
        #expect(t.first?.month == "2026-04")
        #expect(t.last?.month == "2026-09")
    }

    /// Ürün maliyeti net adetten, ambalaj brüt adetten hesaplanır
    @Test func iadeMaliyetiDogruAyrisir() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = [RecipeLine(id: "r1", materialId: Fx.koliId, qty: 1, unit: .adet)]
        s.addPurchase("p1", "2026-08-01", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.other, product: Fx.sampuanId,
                  qty: 100, gross: tl(50_000), returnsQty: 10)
        let r = Fx.engine(s).channelResult(channelId: ChannelIds.other, month: "2026-09")
        #expect(r.productCost == tl(9000))     // 90 net adet × 100 TL
        #expect(r.packagingCost == tl(1000))   // 100 brüt adet × 10 TL koli
    }
}

@Suite("Tarih ve para")
struct DateMoneyTests {

    @Test func ayAritmetigi() {
        #expect(Dates.addMonths("2026-12", 1) == "2027-01")
        #expect(Dates.addMonths("2026-01", -1) == "2025-12")
        #expect(Dates.addMonths("2026-09", 12) == "2027-09")
        #expect(Dates.monthsBetween("2026-01", "2026-12") == 11)
        #expect(Dates.monthRange(from: "2026-01", to: "2026-03") == ["2026-01", "2026-02", "2026-03"])
    }

    @Test func ayBasiVeSonu() {
        #expect(Dates.monthEnd("2026-02") == "2026-02-28")
        #expect(Dates.monthEnd("2028-02") == "2028-02-29")
        #expect(Dates.monthEnd("2026-09") == "2026-09-30")
        #expect(Dates.monthStart("2026-09") == "2026-09-01")
    }

    @Test func ayaSigmayanGunKirpilir() {
        #expect(Dates.dateIn(month: "2026-02", dayOfMonth: 31) == "2026-02-28")
        #expect(Dates.dateIn(month: "2026-09", dayOfMonth: 15) == "2026-09-15")
    }

    /// Gece yarısına yakın saatlerde tarih kaymaz (UTC dönüşümü kullanılmıyor)
    @Test func gecYatarkenTarihKaymaz() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let d = cal.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 23, minute: 30))!
        #expect(Dates.today(d, calendar: cal) == "2026-09-13")
    }

    @Test func turkceGosterim() {
        #expect(Dates.displayMonth("2026-09") == "Eylül 2026")
        #expect(Dates.displayDate("2026-09-13") == "13 Eylül 2026")
        #expect(Money.format(tl(185_000)) == "185.000 TL")
        #expect(Money.format(tl(1234.56)) == "1.234,56 TL")
        #expect(Money.format(-tl(18_000)) == "-18.000 TL")
        #expect(Money.formatPercent(28.64) == "%28,6")
    }

    @Test func kurusHassasiyeti() {
        #expect(Money.fromTL(141) == 14100)
        #expect(Money.fromTL(0.20) == 20)
        #expect(Money.roundHalfAwayFromZero(-2.5) == -3)
        #expect(Money.roundHalfAwayFromZero(2.5) == 3)
    }
}
