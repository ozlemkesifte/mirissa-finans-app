import Testing
import Foundation
@testable import MirissaCore

@Suite("Hakediş eşleştirme")
@MainActor
struct PayoutTests {
    private func durum(yatan: Kurus?) -> AppState {
        var s = Fx.base()
        s.channels[0].commissionPct = 20
        s.channels[0].feeVatRate = .yirmi
        s.channels[0].feesIncludeVat = true
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 10, grossSales: tl(12_000),
                                  vatRate: .yirmi, vatIncluded: true))
        s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                            orderCount: 10, payoutActual: yatan))
        return s
    }

    @Test func beklenenHakedisElleHesaplananlaAyni() {
        let e = Engine(durum(yatan: nil))
        // 12.000 − %20 komisyon (2.400, KDV dahil) = 9.600
        #expect(e.beklenenHakedis(month: "2026-09", channelId: ChannelIds.trendyol) == tl(9_600))
        #expect(e.hakedis(month: "2026-09", channelId: ChannelIds.trendyol) == nil)
    }

    @Test func farkGosterilirVeKesintiyeYazilincaKapanir() {
        let st = AppStore.inMemory(durum(yatan: tl(9_000)))
        let k = st.engine.hakedis(month: "2026-09", channelId: ChannelIds.trendyol)!
        #expect(k.fark == tl(600))
        #expect(k.onemli)
        let onceKar = st.engine.companyMonth("2026-09").gercekKar
        st.hakedisFarkiniKesintiyeYaz(month: "2026-09", channelId: ChannelIds.trendyol)
        let sonra = st.engine.hakedis(month: "2026-09", channelId: ChannelIds.trendyol)!
        #expect(abs(sonra.fark) <= 1)
        // 600 TL KDV dahil ek kesinti: kâr 500 TL azalır
        #expect(onceKar - st.engine.companyMonth("2026-09").gercekKar == tl(500))
    }
}
