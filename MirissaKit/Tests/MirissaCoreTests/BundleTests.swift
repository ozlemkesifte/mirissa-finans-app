import Testing
import Foundation
@testable import MirissaCore

/// Fiziksel ürün ile satış kombinasyonu (SKU/bundle) aynı şey değildir.
/// Set ve çoklu paketler kendi stoklarını tutmaz; bileşenlerden düşer,
/// maliyetleri bileşenlerden hesaplanır.
@Suite("Set ve çoklu paket (SKU)")
struct BundleTests {

    private static let ikiliId = "pro_ikili_sampuan"

    /// 2'li Şampuan Paketi: 1 adet satılınca 2 şampuan düşer
    private static func ikiliPaket() -> Product {
        Product(
            id: ikiliId, name: "2'li Şampuan Paketi", isBundle: true,
            components: [BundleComponent(productId: Fx.sampuanId, qty: 2)],
            recipe: [
                RecipeLine(id: "rcp_i1", materialId: Fx.koliId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_i2", materialId: Fx.patpatId, qty: 1, unit: .adet),
            ]
        )
    }

    private static func stoklu() -> AppState {
        var s = Fx.base()
        s.products.append(ikiliPaket())
        s.addPurchase("p1", "2026-08-01", .product(Fx.sampuanId), qty: 500, paid: tl(50_000))
        s.addPurchase("p2", "2026-08-01", .product(Fx.serumId), qty: 300, paid: tl(36_000))
        return s
    }

    // MARK: Stok

    @Test func cokluPaketBilesenAdediKadarDuser() {
        var s = Self.stoklu()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Self.ikiliId,
                  qty: 10, gross: tl(11_000))
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.sampuanId)) == 480)     // 500 − 10×2
        #expect(e.qty(.material(Fx.koliId)) == -10)       // paket başına 1 koli
        #expect(e.qty(.material(Fx.sampuanKutuId)) == 0)  // bileşen reçetesi uygulanmaz
    }

    @Test func setinKendiStoguTutulmaz() {
        var s = Self.stoklu()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.shopify, product: Fx.setId,
                  qty: 20, gross: tl(30_000))
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.setId)) == 0)
        #expect(e.qty(.product(Fx.sampuanId)) == 480)
        #expect(e.qty(.product(Fx.serumId)) == 280)
        // Set ve paket aynı anda satılsa bile şampuan tek kez düşer
        s.addSale("sal_2", "2026-09", channel: ChannelIds.trendyol, product: Self.ikiliId,
                  qty: 10, gross: tl(11_000))
        let e2 = Fx.engine(s)
        #expect(e2.qty(.product(Fx.sampuanId)) == 460)
    }

    // MARK: Hazırlanabilir adet

    @Test func bilesenStogundanKacSetHazirlanir() {
        let e = Fx.engine(Self.stoklu())
        // 500 şampuan + 300 serum -> en fazla 300 set
        #expect(e.buildable(Fx.setId) == 300)
        // 500 şampuan -> 2'li paketten en fazla 250
        #expect(e.buildable(Self.ikiliId) == 250)
        // Tekil ürün set değildir
        #expect(e.buildable(Fx.sampuanId) == nil)
    }

    @Test func hazirlanmayiSinirlayanBilesenGorunur() {
        let e = Fx.engine(Self.stoklu())
        let darBogaz = e.buildableBottleneck(Fx.setId)
        #expect(darBogaz?.productId == Fx.serumId)
        #expect(darBogaz?.adet == 300)
    }

    @Test func satisSonrasiHazirlanabilirAdetDuser() {
        var s = Self.stoklu()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.shopify, product: Fx.setId,
                  qty: 100, gross: tl(150_000))
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.serumId)) == 200)
        #expect(e.buildable(Fx.setId) == 200)
    }

    // MARK: Maliyet — çift sayım olmamalı

    @Test func setMaliyetiBilesenlerdenHesaplanir() {
        var s = Fx.base()
        s.products = [
            Fx.sampuan(cost: tl(100)),
            Fx.serum(cost: tl(140)),
            Fx.set(),                       // kendi maliyet kalemi yok
            Self.ikiliPaket(),
        ]
        let e = Fx.engine(s)
        #expect(e.cost(of: Fx.setId).components == tl(240))
        #expect(e.cost(of: Fx.setId).ownLines == 0)
        #expect(e.cost(of: Self.ikiliId).components == tl(200))   // 2 × 100
    }

    @Test func setinElleGirilenMaliyetiUyariVerir() {
        var set = Fx.set()
        set.costLines = [CostLine(id: "c1", label: "Set maliyeti", amount: tl(240))]
        let sorunlar = Validation.product(set, state: Fx.base())
        #expect(sorunlar.contains { $0.code == .setMaliyetiCiftSayim })
    }

    /// Bileşen maliyeti değişince setin maliyeti de değişir — elle güncelleme gerekmez
    @Test func bilesenMaliyetiDegisinceSetGuncellenir() {
        var s = Fx.base()
        s.products = [Fx.sampuan(cost: tl(100)), Fx.serum(cost: tl(140)), Fx.set()]
        #expect(Fx.engine(s).cost(of: Fx.setId).intrinsic == tl(240))
        s.products[0].costLines = [CostLine(id: "cst_s", label: "Üretim", amount: tl(130))]
        #expect(Fx.engine(s).cost(of: Fx.setId).intrinsic == tl(270))
    }

    /// Eski veride sete yanlışlıkla açılış stoğu girilmişse bile
    /// set stokta görünmez — aksi halde aynı mal iki kez sayılır.
    @Test func setinAcilisStoguYokSayilir() {
        var s = Fx.base()
        if let i = s.products.firstIndex(where: { $0.id == Fx.setId }) {
            s.products[i].openingQty = 50
            s.products[i].openingUnitCost = tl(240)
            s.products[i].openingDate = "2026-01-01"
        }
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.setId)) == 0)
        #expect(e.totalStockValue == 0)
    }

    /// Set ile çoklu paket aynı ürünü paylaşır — stok tek kez düşer
    @Test func farkliPaketlerAyniUrunuTekKezDuser() {
        var s = Self.stoklu()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.shopify, product: Fx.setId,
                  qty: 50, gross: tl(75_000))
        s.addSale("sal_2", "2026-09", channel: ChannelIds.trendyol, product: Self.ikiliId,
                  qty: 50, gross: tl(55_000))
        s.addSale("sal_3", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 50, gross: tl(35_000))
        let e = Fx.engine(s)
        // 500 − 50 (set) − 100 (2'li) − 50 (tekil)
        #expect(e.qty(.product(Fx.sampuanId)) == 300)
        #expect(e.qty(.product(Fx.serumId)) == 250)
        #expect(e.buildable(Fx.setId) == 250)
    }

    // MARK: SKU başına fiyat

    @Test func kanalaOzelFiyatEtiketFiyatininOnundeGelir() {
        var set = Fx.set()
        set.setPrice(tl(1_500), channelId: nil, from: "2026-09-01")
        set.setPrice(tl(1_699), channelId: ChannelIds.trendyol, from: "2026-09-01")
        #expect(set.price(for: ChannelIds.trendyol, on: "2026-09-15") == tl(1_699))
        #expect(set.price(for: ChannelIds.shopify, on: "2026-09-15") == tl(1_500))
        #expect(set.price(on: "2026-09-15") == tl(1_500))
    }

    @Test func fiyatGirilmemisseNilDoner() {
        let set = Fx.set()
        #expect(set.price(on: "2026-09-15") == nil)
        #expect(set.price(for: ChannelIds.trendyol, on: "2026-09-15") == nil)
    }

    /// Fiyat alanları eski yedeklerde yok — okuma bozulmamalı
    @Test func eskiYedekteFiyatAlaniYok() throws {
        let json = """
        {"id":"pro_x","name":"Şampuan","isBundle":false,"components":[],
         "costLines":[],"recipe":[],"costIncludesMaterials":[],"archived":false}
        """
        let p = try JSONDecoder().decode(Product.self, from: Data(json.utf8))
        #expect(p.listPrice == nil)
        #expect(p.channelPrices == nil)
        #expect(p.priceHistory == nil)
        #expect(p.price(for: ChannelIds.trendyol, on: "2026-09-15") == nil)
    }
}
