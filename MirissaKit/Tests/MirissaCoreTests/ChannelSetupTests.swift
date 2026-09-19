import Testing
import Foundation
@testable import MirissaCore

/// Kanal kesintileri tarihçelidir ve kanala özeldir.
/// Sistem yalnızca Trendyol/Shopify'a göre sabitlenmemiştir.
@Suite("Kanal kurulumu ve tarihçeli kesintiler")
struct ChannelSetupTests {

    private static func stokluDurum() -> AppState {
        var s = Fx.base()
        s.addPurchase("p1", "2026-08-01", .product(Fx.sampuanId), qty: 2000, paid: tl(200_000))
        return s
    }

    // MARK: Kanal listesi sabit değil

    @Test func hazirKanalListesiPazaryerleriniKapsar() {
        let adlar = ChannelPreset.hazir.map(\.name)
        #expect(adlar.contains("Trendyol"))
        #expect(adlar.contains("Hepsiburada"))
        #expect(adlar.contains("Amazon"))
        #expect(adlar.contains("ÇiçekSepeti"))
        #expect(adlar.contains("N11"))
        #expect(adlar.contains("Pazarama"))
        #expect(adlar.contains("Manuel / fiziksel satış"))
    }

    @Test func yeniKanalAyniMotorlaCalisir() {
        var s = Self.stokluDurum()
        var hb = Channel(id: "hepsiburada", name: "Hepsiburada", kind: .marketplace)
        hb.setRates(ChannelRates(from: "2026-09-01", commissionPct: 12,
                                 shippingPerOrder: tl(90)))
        s.channels.append(hb)
        s.addSale("sal_1", "2026-09", channel: "hepsiburada", product: Fx.sampuanId,
                  qty: 100, gross: tl(70_000))
        let r = Fx.engine(s).channelResult(channelId: "hepsiburada", month: "2026-09")
        // KDV kapalı fikstürde net = brüt
        #expect(r.commission.amount == tl(8_400))      // 70.000 × %12
        #expect(r.shipping.amount == tl(9_000))        // 100 sipariş × 90
    }

    // MARK: Tarihçeli komisyon

    @Test func komisyonDegisikligiGecmisiBozmaz() {
        var s = Self.stokluDurum()
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(from: "2026-01-01", commissionPct: 4))
        }
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000))
        s.addSale("sal_2", "2026-11", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000))

        let eylulOnce = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol,
                                                   month: "2026-09").commission.amount
        #expect(eylulOnce == tl(4_000))

        // Ekimde komisyon %6'ya çıkıyor
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(from: "2026-10-01", commissionPct: 6))
        }
        let e = Fx.engine(s)
        #expect(e.channelResult(channelId: ChannelIds.trendyol,
                                month: "2026-09").commission.amount == tl(4_000))
        #expect(e.channelResult(channelId: ChannelIds.trendyol,
                                month: "2026-11").commission.amount == tl(6_000))
    }

    @Test func oranTarihcesiEskiKaydiSilmez() {
        var ch = Channel(id: "n11", name: "N11", kind: .marketplace)
        ch.setRates(ChannelRates(from: "2026-01-01", commissionPct: 10))
        ch.setRates(ChannelRates(from: "2026-07-01", commissionPct: 14))
        // İlk kayıttan önceki dönem için de bir başlangıç satırı açılır
        #expect(ch.rateHistory?.count == 3)
        #expect(ch.rates(on: "2025-12-31").commissionPct == 0)
        #expect(ch.rates(on: "2026-06-30").commissionPct == 10)
        #expect(ch.rates(on: "2026-07-01").commissionPct == 14)
    }

    /// Kanal ilk kez düzenlendiğinde eski oran geçmişe yazılır:
    /// aksi halde geçmiş aylar yeni oranla hesaplanırdı
    @Test func ilkDuzenlemeGecmisiYeniOranlaHesaplamaz() {
        var s = Self.stokluDurum()   // Trendyol düz alanda %20
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000))
        let once = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol,
                                              month: "2026-09").commission.amount
        #expect(once == tl(20_000))

        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(from: "2026-10-01", commissionPct: 6))
        }
        let sonra = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol,
                                               month: "2026-09").commission.amount
        #expect(sonra == tl(20_000))
    }

    @Test func tarihceYoksaDuzAlanlarKullanilir() {
        let ch = Channel(id: "x", name: "X", commissionPct: 15, shippingPerOrder: tl(50))
        #expect(ch.rates(on: "2026-09-01").commissionPct == 15)
        #expect(ch.rates(on: "2026-09-01").shippingPerOrder == tl(50))
    }

    // MARK: Kullanıcının eklediği kesintiler

    @Test func kullaniciTanimliKesintilerHesabaGirer() {
        var s = Self.stokluDurum()
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(
                from: "2026-09-01", commissionPct: 0,
                extras: [
                    ChannelExtraFee(label: "Kampanya katkısı", basis: .yuzde, value: 5),
                    ChannelExtraFee(label: "İşlem bedeli", basis: .siparisBasi, value: Double(tl(6))),
                    ChannelExtraFee(label: "Mağaza aboneliği", basis: .aylikSabit,
                                    value: Double(tl(500))),
                ]
            ))
        }
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000))
        let r = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        // %5 = 5.000 + 100×6 = 600 + aylık 500
        #expect(r.otherDeduction.amount == tl(6_100))
        // Aylık sabit kısım başa baş için ayrı tutulur
        #expect(r.fixedDeduction == tl(500))
    }

    @Test func elleGirilecekKesintiOtomatikHesabaGirmez() {
        var s = Self.stokluDurum()
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(
                from: "2026-09-01",
                extras: [ChannelExtraFee(label: "Kupon katkısı", basis: .elleAylik)]
            ))
        }
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000))
        let r = Fx.engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(r.otherDeduction.amount == 0)
    }

    // MARK: "Şimdilik bilmiyorum"

    @Test func bilinmeyenKesintiUydurulmazAmaSoylenir() {
        var s = Self.stokluDurum()
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(
                from: "2026-09-01", commissionPct: 20,
                extras: [ChannelExtraFee(label: "Hizmet bedeli", basis: .siparisBasi,
                                         value: Double(tl(10)), unknown: true)],
                unknownFields: ["kargo gideri"]
            ))
        }
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000))
        let r = Fx.engine(s).companyMonth("2026-09")
        // Bilinmeyen kalem hesaba katılmadı
        #expect(r.channels.first { $0.channelId == ChannelIds.trendyol }?
            .otherDeduction.amount == 0)
        // Ama kullanıcıya açıkça söyleniyor
        let uyari = try? #require(r.yaklasikUyarisi)
        #expect(uyari?.contains("yaklaşık") == true)
        #expect(uyari?.contains("kargo gideri") == true)
        #expect(uyari?.contains("Hizmet bedeli") == true)
    }

    @Test func eksikBilgiYoksaUyariCikmaz() {
        var s = Self.stokluDurum()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(100_000))
        #expect(Fx.engine(s).companyMonth("2026-09").yaklasikUyarisi == nil)
    }

    // MARK: Kanal bazlı katkı

    /// Aynı ürün iki kanalda farklı katkı bırakır
    @Test func ayniUrunFarkliKanaldaFarkliKatkiBirakir() {
        var s = Self.stokluDurum()
        s.products = [Fx.sampuan(cost: tl(100)), Fx.serum(), Fx.set()]
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(from: "2026-01-01", commissionPct: 20,
                                                shippingPerOrder: tl(107)))
        }
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.shopify }) {
            s.channels[i].setRates(ChannelRates(from: "2026-01-01", paymentPct: 3,
                                                shippingPerOrder: tl(60)))
        }
        s.addSale("sal_t", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(74_900))
        s.addSale("sal_s", "2026-09", channel: ChannelIds.shopify, product: Fx.sampuanId,
                  qty: 100, gross: tl(69_900))
        let e = Fx.engine(s)
        let t = e.channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        let sh = e.channelResult(channelId: ChannelIds.shopify, month: "2026-09")
        #expect(t.contribution != sh.contribution)
        // Shopify daha düşük fiyata rağmen daha çok bırakıyor: komisyon ve kargo düşük
        #expect(sh.contribution > t.contribution)
    }

    /// Başa baş, kanal + ürün karışımının ağırlıklı ortalamasını kullanır
    @Test func basaBasKarisimAgirlikliOrtalamaKullanir() {
        var s = Self.stokluDurum()
        s.products = [Fx.sampuan(cost: tl(100)), Fx.serum(), Fx.set()]
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(from: "2026-01-01", commissionPct: 20,
                                                shippingPerOrder: tl(107)))
        }
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.shopify }) {
            s.channels[i].setRates(ChannelRates(from: "2026-01-01", paymentPct: 3,
                                                shippingPerOrder: tl(60)))
        }
        s.addSale("sal_t", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(74_900))
        s.addSale("sal_s", "2026-09", channel: ChannelIds.shopify, product: Fx.sampuanId,
                  qty: 100, gross: tl(69_900))
        s.expenses.append(Expense(id: "exp_1", date: "2026-09-01", name: "Muhasebeci",
                                  amount: tl(20_000), category: .sabit, recurrence: .aylik))

        let e = Fx.engine(s)
        let eylul = e.companyMonth("2026-09")
        let plan = e.plan(month: "2026-10", today: "2026-10-01")
        let beklenen = Double(eylul.toplamKatki) / Double(eylul.orders)
        #expect(abs(plan.contributionPerOrder - beklenen) < 1)
        // İki kanalın ortalaması, tek tek kanalların arasında kalır
        let t = eylul.channels.first { $0.channelId == ChannelIds.trendyol }!
        let sh = eylul.channels.first { $0.channelId == ChannelIds.shopify }!
        let tBirim = Double(t.contribution) / Double(t.orders)
        let sBirim = Double(sh.contribution) / Double(sh.orders)
        #expect(plan.contributionPerOrder > min(tBirim, sBirim))
        #expect(plan.contributionPerOrder < max(tBirim, sBirim))
    }
}

/// Yıllık başa baş: kaç kargo / yıl, ay, gün
@Suite("Yıllık başa baş")
struct YearlyPlanTests {

    private static func veriliDurum() -> AppState {
        var s = Fx.base()
        s.products = [Fx.sampuan(cost: tl(100)), Fx.serum(), Fx.set()]
        s.addPurchase("p1", "2026-08-01", .product(Fx.sampuanId), qty: 5000, paid: tl(500_000))
        if let i = s.channels.firstIndex(where: { $0.id == ChannelIds.trendyol }) {
            s.channels[i].setRates(ChannelRates(from: "2026-01-01", commissionPct: 20,
                                                shippingPerOrder: tl(107)))
        }
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(74_900))
        s.expenses.append(Expense(id: "exp_1", date: "2026-01-01", name: "Muhasebeci",
                                  amount: tl(10_000), category: .sabit, recurrence: .aylik))
        return s
    }

    @Test func yillikHedefAylikVeGunlugeBolunur() {
        let plan = Fx.engine(Self.veriliDurum()).yearlyPlan(year: 2026, today: "2026-10-01")
        let be = try? #require(plan.targets.first { $0.isBreakeven })
        #expect(be?.ordersPerYear ?? 0 > 0)
        #expect(be!.ordersPerYear == be!.aylik.values.reduce(0, +))
        #expect(be!.ordersPerMonth == Int(ceil(Double(be!.ordersPerYear) / 12)))
        #expect(be!.ordersPerDay == Int(ceil(Double(be!.ordersPerYear) / 365)))
    }

    @Test func yillikSabitGiderOnIkiAyinToplami() {
        let e = Fx.engine(Self.veriliDurum())
        let plan = e.yearlyPlan(year: 2026, today: "2026-10-01")
        let aylik = (1...12).reduce(0) { $0 + e.plannedFixedCosts(month: Dates.monthKey(2026, $1)) }
        #expect(plan.fixedCosts == aylik)
    }

    @Test func kullaniciYillikKarHedefiYazabilir() {
        var s = Self.veriliDurum()
        s.settings.yearlyProfitGoals = ["2026": tl(500_000)]
        let plan = Fx.engine(s).yearlyPlan(year: 2026, today: "2026-10-01")
        let ozel = try? #require(plan.targets.first { $0.isCustom })
        #expect(ozel?.targetProfit == tl(500_000))
        let be = plan.targets.first { $0.isBreakeven }!
        #expect(ozel!.ordersPerYear > be.ordersPerYear)
    }

    @Test func hedefHerSiparisAyniKarVarsayimiylaHesaplanmaz() {
        let plan = Fx.engine(Self.veriliDurum()).yearlyPlan(year: 2026, today: "2026-10-01")
        let eylul = Fx.engine(Self.veriliDurum()).companyMonth("2026-09")
        #expect(abs(plan.contributionPerOrder
                    - Double(eylul.toplamKatki) / Double(eylul.orders)) < 1)
        #expect(plan.isApproximate)
    }

    @Test func veriYoksaHedefUretilmez() {
        let plan = Fx.engine(Fx.base()).yearlyPlan(year: 2026, today: "2026-10-01")
        #expect(plan.targets.isEmpty)
        #expect(plan.blocking == .referansYok)
    }

    @Test func yillikGerceklesenDegerlerDoldurulur() {
        let plan = Fx.engine(Self.veriliDurum()).yearlyPlan(year: 2026, today: "2026-10-01")
        #expect(plan.actualRevenue == tl(74_900))
        #expect(plan.actualOrders == 100)
    }
}
