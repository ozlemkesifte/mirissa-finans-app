import Testing
import Foundation
@testable import MirissaCore

@Suite("Nakit akışı ve kaç hafta yeter")
struct CashFlowTests {
    /// Haziran–Ağustos her ay 30.000 TL tahsilat (günde ~1.000), her ayın 1'inde kira
    private func durum(kasa: Kurus, kira: Kurus) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        for ay in ["2026-06", "2026-07", "2026-08"] {
            s.sales.append(SalesEntry(id: ay, month: ay, channelId: ChannelIds.trendyol,
                                      productId: Fx.sampuanId, qty: 30, grossSales: tl(30_000)))
        }
        s.expenses.append(Expense(id: "k", date: "2026-01-01", name: "Kira", amount: kira,
                                  category: .sabit, recurrence: .aylik))
        s.settings.ek.kasaBakiye = kasa
        s.settings.ek.kasaTarih = "2026-09-15"
        return s
    }

    @Test func kasaGirilmemisseTahminYok() {
        var s = durum(kasa: 0, kira: 0); s.settings.ek.kasaBakiye = nil
        #expect(Engine(s).nakitTahmini(bugun: "2026-09-15") == nil)
    }

    @Test func haftalikBakiyeElleHesaplananlaAyni() {
        let t = Engine(durum(kasa: tl(20_000), kira: tl(14_000))).nakitTahmini(bugun: "2026-09-15")!
        #expect(t.aylikTahsilat == tl(30_000))
        // 1. hafta (16–22 Eylül): +7.000 → 27.000
        #expect(t.haftalar[0].bakiye == tl(27_000))
        #expect(t.haftalar[1].bakiye == tl(34_000))
        // 3. hafta (30 Eylül–6 Ekim): 1 Ekim kira −14.000, +7.000 → 27.000
        #expect(t.haftalar[2].cikis == tl(14_000))
        #expect(t.haftalar[2].bakiye == tl(27_000))
        #expect(t.bittigiHafta == nil)
    }

    @Test func paraBittigiHaftaSoylenir() {
        let t = Engine(durum(kasa: tl(5_000), kira: tl(40_000))).nakitTahmini(bugun: "2026-09-15")!
        // 5.000 + 7.000 + 7.000 + 7.000 − 40.000 = −14.000 → 3. hafta
        #expect(t.bittigiHafta == 3)
    }

    @Test func girilenKanalAlacagiVarsaTahminiTahsilatOndanSonraBaslar() {
        var s = durum(kasa: tl(20_000), kira: 0)
        s.balances.append(BalanceItem(id: "a", kind: .alacak, source: .kanal, name: "Trendyol hakedişi",
                                      amount: tl(25_000), dueDate: "2026-10-05"))
        let t = Engine(s).nakitTahmini(bugun: "2026-09-15")!
        #expect(t.tahsilatBaslangici == "2026-10-05")
        // İlk iki hafta tahmini tahsilat yok (çifte sayım olmasın)
        #expect(t.haftalar[0].giris == 0)
        #expect(t.haftalar[1].giris == 0)
        // 3. hafta: 5 Ekim alacağı 25.000 + 6 Ekim bir günlük tahsilat 1.000
        #expect(t.haftalar[2].giris == tl(26_000))
    }

    @Test func kdvIzleyenAyin28indeOdenir() {
        var s = durum(kasa: tl(100_000), kira: 0)
        s.settings.vatEnabled = true
        s.sales.append(SalesEntry(id: "eyl", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 1, grossSales: tl(12_000),
                                  vatRate: .yirmi, vatIncluded: true))
        let t = Engine(s).nakitTahmini(bugun: "2026-09-15")!
        let kdv = t.bilinenKalemler.first { $0.id == "kdv:2026-09" }
        #expect(kdv?.gun == "2026-10-28")
        #expect(kdv?.tutar == -tl(2_000))
    }
}
