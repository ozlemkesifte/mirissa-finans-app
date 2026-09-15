import Foundation
import MirissaCore

/// Testlerde kullanılan 10 TL -> 1000 kuruş kısaltması
public func tl(_ v: Double) -> Kurus { Money.fromTL(v) }

/// ALTIN SENARYO — bütün rakamları elle hesaplanmış örnek işletme.
/// Hem motor hem arayüz testleri aynı veriyi kullanır ki iki taraf
/// birbirinden kopmasın.
public enum Golden {
    public enum G {
        public static let sampuan = "pro_g_sampuan"
        public static let serum = "pro_g_serum"
        public static let set = "pro_g_set"
        public static let ikili = "pro_g_ikili"
        public static let kutu = "mat_g_kutu"
        public static let koli = "mat_g_koli"
        public static let setKutu = "mat_g_setkutu"
        public static let trendyol = "chn_g_trendyol"
        public static let shopify = "chn_g_shopify"
    }

    public static func senaryo() -> AppState {
        var s = AppState()

        s.materials = [
            StockMaterial(id: G.kutu, name: "Şampuan kutusu", baseUnit: .adet,
                          openingQty: 1000, openingUnitCost: tl(5), openingDate: "2026-08-01"),
            StockMaterial(id: G.koli, name: "Kargo kolisi", baseUnit: .adet,
                          openingQty: 1000, openingUnitCost: tl(10), openingDate: "2026-08-01"),
            StockMaterial(id: G.setKutu, name: "Set kutusu", baseUnit: .adet,
                          openingQty: 500, openingUnitCost: tl(15), openingDate: "2026-08-01"),
        ]

        s.products = [
            Product(
                id: G.sampuan, name: "Şampuan",
                costLines: [CostLine(id: "cst_g_s", label: "Üretim", amount: tl(100))],
                recipe: [
                    RecipeLine(id: "r_s1", materialId: G.kutu, qty: 1, unit: .adet),
                    RecipeLine(id: "r_s2", materialId: G.koli, qty: 1, unit: .adet),
                ],
                openingQty: 500, openingUnitCost: tl(100), openingDate: "2026-08-01"
            ),
            Product(
                id: G.serum, name: "Serum",
                costLines: [CostLine(id: "cst_g_r", label: "Üretim", amount: tl(140))],
                recipe: [RecipeLine(id: "r_r1", materialId: G.koli, qty: 1, unit: .adet)],
                openingQty: 300, openingUnitCost: tl(140), openingDate: "2026-08-01"
            ),
            Product(
                id: G.set, name: "Set", isBundle: true,
                components: [
                    BundleComponent(productId: G.sampuan, qty: 1),
                    BundleComponent(productId: G.serum, qty: 1),
                ],
                recipe: [
                    RecipeLine(id: "r_t1", materialId: G.setKutu, qty: 1, unit: .adet),
                    RecipeLine(id: "r_t2", materialId: G.koli, qty: 1, unit: .adet),
                ]
            ),
            Product(
                id: G.ikili, name: "2'li Şampuan Paketi", isBundle: true,
                components: [BundleComponent(productId: G.sampuan, qty: 2)],
                recipe: [
                    RecipeLine(id: "r_i1", materialId: G.kutu, qty: 2, unit: .adet),
                    RecipeLine(id: "r_i2", materialId: G.koli, qty: 1, unit: .adet),
                ]
            ),
        ]

        s.channels = [
            Channel(id: G.trendyol, name: "Trendyol", kind: .marketplace,
                    commissionPct: 20, shippingPerOrder: tl(100)),
            Channel(id: G.shopify, name: "Shopify", kind: .ownStore,
                    paymentPct: 3, shippingPerOrder: tl(60)),
        ]

        // 500 koli alındı, 6.000 TL KDV dahil -> net 5.000 -> birim 10 TL
        // (mevcut ortalama da 10 TL olduğu için ağırlıklı ortalama değişmez)
        s.purchases = [
            StockPurchase(id: "pur_g1", date: "2026-09-05", item: .material(G.koli),
                          qty: 500, unit: .adet, totalPaid: tl(6_000),
                          vatRate: .yirmi, vatIncluded: true),
        ]

        // Satışlar KDV dahil girilir
        s.sales = [
            // Trendyol / Şampuan: 100 adet, 120.000 KDV dahil -> net 100.000
            // 10 adet iade, 12.000 KDV dahil -> net 10.000, ürün stoğa döner
            SalesEntry(id: "sal_g1", month: "2026-09", channelId: G.trendyol,
                       productId: G.sampuan, qty: 100, grossSales: tl(120_000),
                       returnsAmount: tl(12_000), returnsQty: 10,
                       vatRate: .yirmi, vatIncluded: true),
            // Trendyol / Set: 50 adet, 90.000 KDV dahil -> net 75.000
            SalesEntry(id: "sal_g2", month: "2026-09", channelId: G.trendyol,
                       productId: G.set, qty: 50, grossSales: tl(90_000),
                       vatRate: .yirmi, vatIncluded: true),
            // Shopify / 2'li: 20 adet, 36.000 KDV dahil -> net 30.000
            // 6.000 KDV dahil indirim -> net 5.000
            SalesEntry(id: "sal_g3", month: "2026-09", channelId: G.shopify,
                       productId: G.ikili, qty: 20, grossSales: tl(36_000),
                       discount: tl(6_000), vatRate: .yirmi, vatIncluded: true),
        ]

        s.expenses = [
            // Ortak sabit gider: 12.000 KDV dahil -> net 10.000
            Expense(id: "exp_g1", date: "2026-09-01", name: "Muhasebeci",
                    amount: tl(12_000), category: .sabit, recurrence: .aylik,
                    vatRate: .yirmi, vatIncluded: true),
            // Trendyol reklamı: 24.000 KDV dahil -> net 20.000, satışa bağlı
            Expense(id: "exp_g2", date: "2026-09-10", name: "Trendyol reklam",
                    amount: tl(24_000), category: .reklam, scope: .channel(G.trendyol),
                    recurrence: .tek, vatRate: .yirmi, vatIncluded: true),
        ]
        return s
    }

}
