import Testing
import Foundation
@testable import MirissaCore

/// Reklam karnesi: ROAS (panel gibi ve gerçek), kâr bazlı ROAS, sipariş başı reklam ve reklam tavanı.
/// Rakamlar elle hesaplandı.
@Suite("Reklam karnesi")
struct ReklamKarnesiTests {

    /// KDV'siz, komisyonsuz. Şampuan 1.000 TL, üretim 400 TL, reçetesiz.
    /// Eylül: 20 satış (20 sipariş), 2.000 TL indirim, 1.000 TL iade; reklam 4.000 TL; kira 5.000 TL.
    private func durum() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.channels[0].commissionPct = 0
        s.products[0] = Fx.sampuan(cost: tl(400)); s.products[0].recipe = []
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.sales.append(SalesEntry(id: "a", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 20, grossSales: tl(20_000),
                                  discount: tl(2_000), returnsAmount: tl(1_000), returnsQty: 1))
        s.channelMonths.append(ChannelMonth(month: "2026-09", channelId: ChannelIds.trendyol, orderCount: 20))
        s.expenses.append(Expense(id: "r", date: "2026-09-05", name: "Meta reklam", amount: tl(4_000),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol), recurrence: .tek))
        s.expenses.append(Expense(id: "k", date: "2026-09-01", name: "Kira", amount: tl(5_000),
                                  category: .sabit, recurrence: .aylik))
        return s
    }

    @Test func roasVeKarBazliRoas() {
        let a = Engine(durum()).reklamAyi("2026-09")
        #expect(a.harcama == tl(4_000))
        // Net satış: 20.000 − 2.000 indirim − 1.000 iade = 17.000
        #expect(a.ciro == tl(17_000))
        #expect(a.iadeIndirim == tl(3_000))
        // Panelde görünene yakın: (17.000 + 3.000) / 4.000 = 5,00
        #expect(a.brutRoas == 5)
        // Gerçek: 17.000 / 4.000 = 4,25
        #expect(a.roas == 4.25)
        // Katkı (reklam düşülmeden): 17.000 − ürün maliyeti (19 net adet × 400 = 7.600) = 9.400
        #expect(a.katkiReklamsiz == tl(9_400))
        // Kâr bazlı ROAS: 9.400 / 4.000 = 2,35
        #expect(a.poas == 2.35)
        // Sipariş başına reklam: 4.000 / 20 = 200
        #expect(a.cpa == tl(200))
        #expect(!a.siparisTahmini)
        // Reklamdan sonra katkıda kalan: 9.400 − 4.000 = 5.400
        #expect(a.reklamSonrasiKatki == tl(5_400))
        #expect(!a.katkiyiYedi)
        // Gerçek kâr: 5.400 − 5.000 kira = 400
        #expect(a.gercekKar == tl(400))
    }

    @Test func reklamTavani() {
        let e = Engine(durum())
        let a = e.reklamAyi("2026-09")
        // Başa baş: katkı 9.400 − sabit gider 5.000 = 4.400
        #expect(a.sabitGider == tl(5_000))
        #expect(a.tavan(hedefKar: 0) == tl(4_400))
        // 3.000 TL kâr hedefi: 9.400 − 5.000 − 3.000 = 1.400
        #expect(a.tavan(hedefKar: tl(3_000)) == tl(1_400))
        // Katkıdan büyük hedef: tavan eksiye düşmez
        #expect(a.tavan(hedefKar: tl(50_000)) == 0)
    }

    @Test func reklamKatkiyiYersaSoylenir() {
        var s = durum()
        s.expenses[0].amount = tl(12_000)      // katkı 9.400'ün üstünde reklam
        let a = Engine(s).reklamAyi("2026-09")
        #expect(a.katkiyiYedi)
        #expect(a.reklamSonrasiKatki == -tl(2_600))
        #expect(a.poas != nil && a.poas! < 1)
        #expect(a.tavan(hedefKar: 0) == tl(4_400))   // tavan harcamadan bağımsız
    }

    @Test func sabitReklamKatkiyaGeriEklenmez() {
        var s = durum()
        // Satıştan bağımsız (sabit) işaretlenen reklam: katkıya değil sabit gidere girer
        s.expenses[0].behavior = .sabit
        let a = Engine(s).reklamAyi("2026-09")
        #expect(a.sabitReklam == tl(4_000))
        #expect(a.degiskenReklam == 0)
        // Katkı yine reklamsız 9.400; sabit gider reklam hariç 5.000
        #expect(a.katkiReklamsiz == tl(9_400))
        #expect(a.sabitGider == tl(5_000))
        #expect(a.tavan(hedefKar: 0) == tl(4_400))
    }

    @Test func reklamYoksaOranHesaplanmaz() {
        var s = durum()
        s.expenses.removeAll { $0.id == "r" }
        let a = Engine(s).reklamAyi("2026-09")
        #expect(a.harcama == 0)
        #expect(a.roas == nil && a.brutRoas == nil && a.poas == nil && a.cpa == nil)
        #expect(!a.katkiyiYedi)
    }

    @Test func aylikTabloVeKanalDagilimi() {
        var s = durum()
        s.sales.append(SalesEntry(id: "b", month: "2026-08", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(10_000)))
        s.expenses.append(Expense(id: "r8", date: "2026-08-05", name: "Meta reklam", amount: tl(2_000),
                                  category: .reklam, scope: .channel(ChannelIds.trendyol), recurrence: .tek))
        let e = Engine(s)
        let tablo = e.reklamTablosu(endingAt: "2026-09", months: 6)
        #expect(tablo.count == 6)
        #expect(tablo.last?.month == "2026-09")
        let agustos = tablo.first { $0.month == "2026-08" }!
        // Ağustos: 10.000 satış, 4.000 ürün maliyeti → katkı 6.000; reklam 2.000 → kâr bazlı 3,00
        #expect(agustos.katkiReklamsiz == tl(6_000))
        #expect(agustos.poas == 3)
        #expect(agustos.roas == 5)
        let kanal = e.kanalReklamlari(month: "2026-09")
        #expect(kanal.count == 1)
        #expect(kanal[0].harcama == tl(4_000))
        #expect(kanal[0].katkiReklamsiz == tl(9_400))
    }
}
