import Testing
import Foundation
@testable import MirissaCore

@Suite("Sipariş önerisi")
struct ReorderTests {
    /// Eylülde 60 koli kullanıldı (günde 2), elde 40 koli var → 20 gün yeter
    private func durum(tedarik: Int?, moq: Double? = nil) -> AppState {
        var s = Fx.base()
        let i = s.materials.firstIndex { $0.id == Fx.koliId }!
        s.materials[i].tedarikSuresiGun = tedarik
        s.materials[i].minSiparis = moq
        s.addPurchase("k", "2026-09-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 60, grossSales: tl(6_000)))
        return s
    }

    @Test func tedarikSuresiYoksaOneriYok() {
        #expect(Engine(durum(tedarik: nil)).siparisOnerisi(.material(Fx.koliId), bugun: "2026-09-18") == nil)
    }

    @Test func sonSiparisGunuVeMiktarElleHesaplananlaAyni() {
        // 18 Eylül'e kadar 60 koli: bu ayın satışı ayın o gününe kadardır → ayda 60 ÷ (18/30) = 100,
        // günde 3,33. Elde 40 → 12 gün yeter
        let o = Engine(durum(tedarik: 10)).siparisOnerisi(.material(Fx.koliId), bugun: "2026-09-18")!
        #expect(o.kalanGun == 12)
        // 12 gün − (10 tedarik + 7 güvenlik) = 5 gün önce: acil
        #expect(o.sonSiparisGunu == "2026-09-13")
        #expect(o.acil)
        // 40 gün yetecek kadar (10 + 30) × 3,33 = 133,3, elde 40 → 93,3 → 94
        #expect(o.miktar == 94)
    }

    @Test func enAzSiparisMiktariUygulanir() {
        let o = Engine(durum(tedarik: 10, moq: 500)).siparisOnerisi(.material(Fx.koliId), bugun: "2026-09-18")!
        #expect(o.miktar == 500)
    }

    @Test func gecikmisSiparisAcilSayilir() {
        let o = Engine(durum(tedarik: 25)).siparisOnerisi(.material(Fx.koliId), bugun: "2026-09-18")!
        #expect(o.acil)
    }

    @Test func stokBolkenOneriYok() {
        var s = durum(tedarik: 10)
        s.purchases[0].qty = 1_000
        #expect(Engine(s).siparisOnerisi(.material(Fx.koliId), bugun: "2026-09-18") == nil)
    }
}
