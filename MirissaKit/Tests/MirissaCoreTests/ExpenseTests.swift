import Testing
import Foundation
@testable import MirissaCore

@Suite("Giderler ve düzenli giderler")
struct ExpenseTests {

    private func sabitGider(_ end: MonthKey? = nil) -> Expense {
        Expense(id: "exp_muh", date: "2026-01-05", name: "Muhasebeci",
                amount: tl(5000), category: .sabit, recurrence: .aylik, endMonth: end)
    }

    /// Bir kez girilen sabit gider sonraki aylara otomatik eklenir
    @Test func aylikGiderTekrarEder() {
        var s = Fx.base()
        s.expenses.append(sabitGider())
        let e = Fx.engine(s)
        for m in ["2026-01", "2026-05", "2026-12"] {
            #expect(e.expenseInstances(month: m).count == 1)
            #expect(e.expenseInstances(month: m).first?.amount == tl(5000))
        }
        #expect(e.expenseInstances(month: "2025-12").isEmpty)  // başlangıçtan önce yok
    }

    /// "Durdur": geçmiş aylar korunur, sonraki aylarda görünmez
    @Test func durdurGecmisiBozmaz() {
        var s = Fx.base()
        s.expenses.append(sabitGider("2026-06"))
        let e = Fx.engine(s)
        #expect(e.expenseInstances(month: "2026-01").count == 1)
        #expect(e.expenseInstances(month: "2026-06").count == 1)
        #expect(e.expenseInstances(month: "2026-07").isEmpty)
        #expect(e.companyMonth("2026-03").ortakGider == tl(5000))
        #expect(e.companyMonth("2026-08").ortakGider == 0)
    }

    /// Tek bir ayın tutarı değiştirilir, diğer aylar etkilenmez
    @Test func ayaOzelTutar() {
        var s = Fx.base()
        var exp = sabitGider()
        exp.overrides["2026-04"] = ExpenseOverride(amount: tl(7500))
        s.expenses.append(exp)
        let e = Fx.engine(s)
        #expect(e.expenseInstances(month: "2026-04").first?.amount == tl(7500))
        #expect(e.expenseInstances(month: "2026-05").first?.amount == tl(5000))
    }

    /// Bir ay atlanabilir
    @Test func ayAtlanabilir() {
        var s = Fx.base()
        var exp = sabitGider()
        exp.overrides["2026-04"] = ExpenseOverride(skipped: true)
        s.expenses.append(exp)
        #expect(Fx.engine(s).expenseInstances(month: "2026-04").isEmpty)
    }

    /// Yıllık gider: kâra her ay 1/12'si yazılır, para ödeme ayında çıkar
    @Test func yillikGider() {
        var s = Fx.base()
        s.expenses.append(Expense(
            id: "exp_y", date: "2026-03-15", name: "Alan adı",
            amount: tl(1200), category: .diger, recurrence: .yillik
        ))
        let e = Fx.engine(s)
        #expect(e.expenseInstances(month: "2026-02").isEmpty)         // başlamadan önce yok
        let mart = e.expenseInstances(month: "2026-03").first!
        #expect(mart.expenseAmount == tl(100))
        #expect(mart.cashAmount == tl(1200))                          // ödeme ayı
        let nisan = e.expenseInstances(month: "2026-04").first!
        #expect(nisan.expenseAmount == tl(100))
        #expect(nisan.cashAmount == 0)
        #expect(e.expenseInstances(month: "2027-03").first?.cashAmount == tl(1200))   // ertesi yıl
        // 12 ayın toplamı yıllık tutar
        let yil = (0..<12).reduce(0) { $0 + e.companyMonth(Dates.addMonths("2026-03", $1)).toplamGider }
        #expect(yil == tl(1200))
    }

    @Test func yillikKusuratIlkAylaraEklenir() {
        #expect((0..<12).map { Expenses.onIkideBiri(1_000_007, $0) }.reduce(0, +) == 1_000_007)
        #expect(Expenses.onIkideBiri(1_000_007, 0) == 83_334)
        #expect(Expenses.onIkideBiri(1_000_007, 11) == 83_333)
    }

    /// 29 Şubat çıpası olmayan yıllarda 28'e düşer
    @Test func artikYilCiplasi() {
        var s = Fx.base()
        s.expenses.append(Expense(
            id: "exp_y", date: "2028-02-29", name: "Yıllık",
            amount: tl(100), category: .diger, recurrence: .yillik
        ))
        let e = Fx.engine(s)
        #expect(e.expenseInstances(month: "2029-02").first?.date == "2029-02-28")
    }

    /// Stok alımı giderlerde otomatik görünür; alım silinince gider de kaybolur
    @Test func stokAlimiGiderOlarakGorunur() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-09-13", .material(Fx.koliId), qty: 500, paid: tl(5000))
        let e = Fx.engine(s)
        let list = e.expenseInstances(month: "2026-09")
        #expect(list.count == 1)
        #expect(list[0].amount == tl(5000))
        #expect(list[0].sourceKind == .stokAlimi)
        #expect(list[0].category == .ambalaj)

        s.purchases.removeAll()
        #expect(Fx.engine(s).expenseInstances(month: "2026-09").isEmpty)
    }

    /// Stoğa giren alım kâra gider yazılmaz (satıldıkça maliyet olur), ama nakit çıkışıdır
    @Test func stokAlimiCiftSayilmaz() {
        var s = Fx.base()
        s.addPurchase("pur_1", "2026-09-01", .material(Fx.koliId), qty: 500, paid: tl(5000))
        let r = Fx.engine(s).companyMonth("2026-09")
        #expect(r.ortakGider == 0)
        #expect(r.stokAlimi == tl(5000))
        #expect(r.nakitCikisi == tl(5000))
        #expect(r.gercekKar == 0)
    }

    /// Giderlerden hariç tutulan alım stoğu yine de artırır
    @Test func haricTutulanAlimStoguYineArtirir() {
        var s = Fx.base()
        s.purchases.append(StockPurchase(
            id: "pur_1", date: "2026-09-01", item: .material(Fx.koliId),
            qty: 500, unit: .adet, totalPaid: tl(5000), excludeFromExpenses: true
        ))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 500)
        #expect(e.expenseInstances(month: "2026-09").isEmpty)
        #expect(e.companyMonth("2026-09").nakitCikisi == 0)
    }

    /// Kanala işaretlenen reklam gideri SADECE o kanalda sayılır, ortak gidere eklenmez
    @Test func kanalReklamiCiftSayilmaz() {
        var s = Fx.base()
        s.expenses.append(Expense(
            id: "exp_r", date: "2026-09-10", name: "Trendyol reklamı",
            amount: tl(5000), category: .reklam, scope: .channel(ChannelIds.trendyol)
        ))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 10, gross: tl(10000))
        let r = Fx.engine(s).companyMonth("2026-09")
        #expect(r.ortakGider == 0)
        let ty = r.channels.first { $0.channelId == ChannelIds.trendyol }!
        #expect(ty.ads.amount == tl(5000))
        #expect(r.expenseBreakdown[.reklam] == tl(5000))
    }

    /// Kapsam ortak -> kanal olarak değişince toplam gider aynı kalır
    @Test func kapsamDegisinceToplamGiderAyniKalir() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 10, gross: tl(10000))
        s.expenses.append(Expense(
            id: "exp_r", date: "2026-09-10", name: "Reklam",
            amount: tl(5000), category: .reklam, scope: .ortak
        ))
        let ortak = Fx.engine(s).companyMonth("2026-09")
        s.expenses[0].scope = .channel(ChannelIds.trendyol)
        let kanal = Fx.engine(s).companyMonth("2026-09")
        #expect(ortak.toplamGider == kanal.toplamGider)
        #expect(ortak.gercekKar == kanal.gercekKar)
    }

    /// Değişmez kural: gider dağılımının toplamı = toplam gider
    @Test func giderDagilimiToplamiTutar() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(132))
        s.addPurchase("pur_1", "2026-08-01", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.addPurchase("pur_2", "2026-08-01", .material(Fx.dolguId), qty: 10, unit: .kg, paid: tl(2000))
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 80, gross: tl(55920), discount: tl(920), returnsAmount: tl(1000), returnsQty: 2)
        s.addSale("sal_2", "2026-09", channel: ChannelIds.shopify, product: Fx.setId,
                  qty: 30, gross: tl(45000))
        s.expenses.append(Expense(id: "e1", date: "2026-09-02", name: "Ajans",
                                  amount: tl(20000), category: .sabit, recurrence: .aylik))
        s.expenses.append(Expense(id: "e2", date: "2026-09-03", name: "Trendyol reklamı",
                                  amount: tl(5000), category: .reklam, scope: .channel(ChannelIds.trendyol)))
        s.expenses.append(Expense(id: "e3", date: "2026-09-04", name: "Influencer",
                                  amount: tl(8000), category: .influencer, scope: .channel(ChannelIds.shopify)))

        let r = Fx.engine(s).companyMonth("2026-09")
        let sum = r.expenseBreakdown.values.reduce(0, +)
        #expect(sum == r.toplamGider)
        #expect(r.gercekKar == r.gercekCiro - r.toplamGider)
    }
}
