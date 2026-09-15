import Testing
import Foundation
@testable import MirissaCore

@Suite("Sabit / satışa bağlı gider sınıflandırması")
struct CostBehaviorTests {

    /// 100 sipariş, sipariş başına 400 TL katkı, 50.000 TL sabit gider
    private func kurulum() -> AppState {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        s.channels[0].shippingPerOrder = tl(60)
        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(70_000))
        s.channelMonths.append(ChannelMonth(id: "chm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 100))
        s.expenses.append(Expense(id: "e_sabit", date: "2026-09-01", name: "Ajans",
                                  amount: tl(50_000), category: .sabit))
        return s
    }

    /// Reklam varsayılan olarak satışa bağlı sayılır, zorla sabit kabul edilmez
    @Test func reklamVarsayilanOlarakSatisaBagli() {
        #expect(ExpenseCategory.reklam.defaultBehavior == .satisaBagli)
        #expect(ExpenseCategory.sabit.defaultBehavior == .sabit)
        #expect(ExpenseCategory.influencer.defaultBehavior == .sabit)
        #expect(ExpenseCategory.kargo.defaultBehavior == .satisaBagli)

        let e = Expense(date: "2026-09-01", name: "Meta reklam", amount: tl(10_000), category: .reklam)
        #expect(e.resolvedBehavior == .satisaBagli)
    }

    /// Kullanıcı seçimi varsayılanın yerine geçer
    @Test func kullaniciSeciminiEzer() {
        var e = Expense(date: "2026-09-01", name: "Marka reklamı", amount: tl(10_000), category: .reklam)
        e.behavior = .sabit
        #expect(e.resolvedBehavior == .sabit)
    }

    /// Satışa bağlı reklam sipariş başına kazancı düşürür, sabit gideri artırmaz
    @Test func satisaBagliReklamKatkiyiDusurur() {
        var s = kurulum()
        s.expenses.append(Expense(id: "e_rek", date: "2026-09-05", name: "Meta reklam",
                                  amount: tl(10_000), category: .reklam))   // varsayılan: satışa bağlı
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.fixedCosts == tl(50_000))
        #expect(approx(b.contributionPerOrder, Double(tl(300))))   // (40.000 − 10.000) / 100
        #expect(b.breakevenOrders == 167)                          // ceil(50.000 / 300)
    }

    /// Aynı gider sabit seçilirse başa baş noktası farklı çıkar
    @Test func sabitSecilenReklamBasaBasiDegistirir() {
        var s = kurulum()
        var rek = Expense(id: "e_rek", date: "2026-09-05", name: "Marka reklamı",
                          amount: tl(10_000), category: .reklam)
        rek.behavior = .sabit
        s.expenses.append(rek)
        let b = Engine(s).breakeven(month: "2026-09", today: "2026-09-20")
        #expect(b.fixedCosts == tl(60_000))
        #expect(approx(b.contributionPerOrder, Double(tl(400))))
        #expect(b.breakevenOrders == 150)                          // ceil(60.000 / 400)
    }

    /// EN ÖNEMLİSİ: sınıflandırma kârı asla değiştirmez, sadece başa başı değiştirir
    @Test func siniflandirmaKariDegistirmez() {
        var degisken = kurulum()
        degisken.expenses.append(Expense(id: "e_rek", date: "2026-09-05", name: "Reklam",
                                         amount: tl(10_000), category: .reklam))
        var sabit = kurulum()
        var rek = Expense(id: "e_rek", date: "2026-09-05", name: "Reklam",
                          amount: tl(10_000), category: .reklam)
        rek.behavior = .sabit
        sabit.expenses.append(rek)

        let a = Engine(degisken).companyMonth("2026-09")
        let b = Engine(sabit).companyMonth("2026-09")
        #expect(a.gercekKar == b.gercekKar)
        #expect(a.gercekKar == -tl(20_000))
        #expect(a.toplamGider == b.toplamGider)
        #expect(a.gercekCiro == b.gercekCiro)
        #expect(a.nakitCikisi == b.nakitCikisi)

        // Katkı + sabit gider = kâr eşitliği her iki sınıflandırmada da bozulmaz
        #expect(a.toplamKatki - a.toplamSabitGider == a.gercekKar)
        #expect(b.toplamKatki - b.toplamSabitGider == b.gercekKar)
    }

    /// Kanala işaretlenen reklam da sınıflandırmaya uyar, kanalda kalan değişmez
    @Test func kanalReklamiSiniflandirmasi() {
        func kur(_ davranis: CostBehavior?) -> Engine {
            var s = kurulum()
            var rek = Expense(id: "e_rek", date: "2026-09-05", name: "Trendyol reklamı",
                              amount: tl(10_000), category: .reklam,
                              scope: .channel(ChannelIds.trendyol))
            rek.behavior = davranis
            s.expenses.append(rek)
            return Engine(s)
        }
        let degisken = kur(nil).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        let sabit = kur(.sabit).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")

        #expect(degisken.adsFixed == 0)
        #expect(degisken.adsVariable == tl(10_000))
        #expect(degisken.contribution == tl(30_000))
        #expect(degisken.fixedCost == 0)

        #expect(sabit.adsFixed == tl(10_000))
        #expect(sabit.adsVariable == 0)
        #expect(sabit.contribution == tl(40_000))
        #expect(sabit.fixedCost == tl(10_000))

        // Kanalda kalan iki durumda da aynı
        #expect(degisken.kanaldaKalan == sabit.kanaldaKalan)
        #expect(degisken.kanaldaKalan == tl(30_000))
    }

    /// Elle girilen aylık reklam tutarı, altındaki giderlerin oranını korur
    @Test func elleGirilenReklamOraniKorur() {
        var s = kurulum()
        s.expenses.append(Expense(id: "e1", date: "2026-09-05", name: "Performans",
                                  amount: tl(6000), category: .reklam,
                                  scope: .channel(ChannelIds.trendyol)))          // satışa bağlı
        var marka = Expense(id: "e2", date: "2026-09-05", name: "Marka",
                            amount: tl(4000), category: .reklam,
                            scope: .channel(ChannelIds.trendyol))
        marka.behavior = .sabit
        s.expenses.append(marka)
        s.channelMonths[0].adsActual = tl(20_000)      // gerçek fatura iki katı çıktı

        let r = Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(r.ads.amount == tl(20_000))
        #expect(r.ads.isManual)
        #expect(r.adsVariable == tl(12_000))   // %60 satışa bağlıydı
        #expect(r.adsFixed == tl(8000))
    }

    /// Reklam gideri yokken elle girilen aylık tutar sabit sayılır
    @Test func gidersizElleGirilenReklamSabitSayilir() {
        var s = kurulum()
        s.channelMonths[0].adsActual = tl(7000)
        let r = Engine(s).channelResult(channelId: ChannelIds.trendyol, month: "2026-09")
        #expect(r.adsFixed == tl(7000))
        #expect(r.adsVariable == 0)
    }

    /// Stok alımları satışa bağlı sayılır ama zaten kâra girmez
    @Test func stokAlimiKarHesabinaGirmez() {
        var s = kurulum()
        s.addPurchase("pur", "2026-09-03", .material(Fx.koliId), qty: 500, paid: tl(5000))
        let r = Engine(s).companyMonth("2026-09")
        #expect(r.ortakGider == tl(50_000))
        #expect(r.stokAlimi == tl(5000))
        #expect(r.toplamKatki - r.toplamSabitGider == r.gercekKar)
    }

    /// Eski yedekte sınıflandırma alanı yoksa kategori varsayılanı kullanılır
    @Test func eskiKayitVarsayilanaDuser() throws {
        var s = kurulum()
        s.expenses.append(Expense(id: "e_rek", date: "2026-09-05", name: "Reklam",
                                  amount: tl(10_000), category: .reklam))
        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri.expenses.first { $0.id == "e_rek" }?.behavior == nil)
        #expect(geri.expenses.first { $0.id == "e_rek" }?.resolvedBehavior == .satisaBagli)
    }
}

@Suite("Dönem toplamları")
struct AggregateTests {
    /// Yıl/dönem toplamında da katkı + sabit gider = kâr eşitliği bozulmamalı
    @Test func donemToplamindaKatkiEsitligiKorunur() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(100))
        s.products[0].recipe = []
        s.channels[0].commissionPct = 20
        for ay in 1...3 {
            s.addSale("s\(ay)", Dates.monthKey(2026, ay), channel: ChannelIds.trendyol,
                      product: Fx.sampuanId, qty: 100, gross: tl(70_000))
            s.channelMonths.append(ChannelMonth(id: "c\(ay)", month: Dates.monthKey(2026, ay),
                                                channelId: ChannelIds.trendyol, orderCount: 100))
        }
        s.expenses.append(Expense(id: "e1", date: "2026-01-01", name: "Ajans",
                                  amount: tl(20_000), category: .sabit, recurrence: .aylik))
        s.expenses.append(Expense(id: "e2", date: "2026-01-01", name: "Reklam",
                                  amount: tl(5000), category: .reklam, recurrence: .aylik))

        let e = Engine(s)
        let toplam = e.companyTotals(from: "2026-01", to: "2026-03")
        #expect(toplam.ortakGiderDegisken == tl(15_000))          // 3 ay × 5.000 reklam
        #expect(toplam.ortakGiderSabit == tl(60_000))             // 3 ay × 20.000 ajans
        #expect(toplam.toplamKatki - toplam.toplamSabitGider == toplam.gercekKar)

        let aylarToplami = (1...3).reduce(0) { $0 + e.companyMonth(Dates.monthKey(2026, $1)).gercekKar }
        #expect(toplam.gercekKar == aylarToplami)
    }
}
