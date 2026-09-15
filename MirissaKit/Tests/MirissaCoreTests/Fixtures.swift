import Foundation
@testable import MirissaCore
@_exported import MirissaTestSupport

enum Fx {
    static let koliId = "mat_koli"
    static let patpatId = "mat_patpat"
    static let etiketId = "mat_etiket"
    static let dolguId = "mat_dolgu"
    static let sampuanKutuId = "mat_skutu"
    static let setKutuId = "mat_setkutu"

    static let sampuanId = "pro_sampuan"
    static let serumId = "pro_serum"
    static let setId = "pro_set"

    static func materials() -> [StockMaterial] {
        [
            StockMaterial(id: koliId, name: "Kargo kolisi", baseUnit: .adet),
            StockMaterial(id: patpatId, name: "Patpat", baseUnit: .adet),
            StockMaterial(id: etiketId, name: "Kırılmaz etiketi", baseUnit: .adet,
                     packSizesRaw: ["paket": 50]),
            StockMaterial(id: dolguId, name: "Dolgu kırpığı", baseUnit: .gram),
            StockMaterial(id: sampuanKutuId, name: "Şampuan kutusu", baseUnit: .adet),
            StockMaterial(id: setKutuId, name: "Set kutusu", baseUnit: .adet),
        ]
    }

    /// Şampuan: 1 kutu + 1 koli + 1 patpat + 2 etiket + 20 g dolgu
    static func sampuan(cost: Kurus = 0) -> Product {
        Product(
            id: sampuanId, name: "Şampuan",
            costLines: cost == 0 ? [] : [CostLine(id: "cst_s", label: "Üretim", amount: cost)],
            recipe: [
                RecipeLine(id: "rcp_s1", materialId: sampuanKutuId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_s2", materialId: koliId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_s3", materialId: patpatId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_s4", materialId: etiketId, qty: 2, unit: .adet),
                RecipeLine(id: "rcp_s5", materialId: dolguId, qty: 20, unit: .gram),
            ]
        )
    }

    static func serum(cost: Kurus = 0) -> Product {
        Product(
            id: serumId, name: "Serum",
            costLines: cost == 0 ? [] : [CostLine(id: "cst_r", label: "Üretim", amount: cost)],
            recipe: [
                RecipeLine(id: "rcp_r1", materialId: koliId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_r2", materialId: patpatId, qty: 1, unit: .adet),
            ]
        )
    }

    /// Set: 1 Şampuan + 1 Serum, kendi reçetesi (set kutusu + koli + patpat + 2 etiket + 30 g dolgu)
    static func set() -> Product {
        Product(
            id: setId, name: "Set", isBundle: true,
            components: [
                BundleComponent(productId: sampuanId, qty: 1),
                BundleComponent(productId: serumId, qty: 1),
            ],
            recipe: [
                RecipeLine(id: "rcp_t1", materialId: setKutuId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_t2", materialId: koliId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_t3", materialId: patpatId, qty: 1, unit: .adet),
                RecipeLine(id: "rcp_t4", materialId: etiketId, qty: 2, unit: .adet),
                RecipeLine(id: "rcp_t5", materialId: dolguId, qty: 30, unit: .gram),
            ]
        )
    }

    static func channels() -> [Channel] {
        [
            Channel(id: ChannelIds.trendyol, name: "Trendyol", kind: .marketplace, commissionPct: 20),
            Channel(id: ChannelIds.shopify, name: "Shopify", kind: .ownStore, paymentPct: 3),
            Channel(id: ChannelIds.other, name: "Diğer", kind: .other),
        ]
    }

    static func base() -> AppState {
        AppState(
            materials: materials(),
            products: [sampuan(), serum(), set()],
            channels: channels()
        )
    }

    static func engine(_ s: AppState) -> Engine { Engine(s) }
}

extension AppState {
    mutating func addPurchase(
        _ id: Id, _ date: DateKey, _ item: ItemRef,
        qty: Double, unit: UnitCode = .adet, paid: Kurus, shipping: Kurus = 0
    ) {
        purchases.append(StockPurchase(
            id: id, date: date, item: item, qty: qty, unit: unit,
            totalPaid: paid, shippingCost: shipping
        ))
    }

    mutating func addSale(
        _ id: Id, _ month: MonthKey, channel: Id, product: Id,
        qty: Double, gross: Kurus, discount: Kurus = 0,
        returnsAmount: Kurus = 0, returnsQty: Double = 0, restock: Bool = true
    ) {
        sales.append(SalesEntry(
            id: id, month: month, channelId: channel, productId: product,
            qty: qty, grossSales: gross, discount: discount,
            returnsAmount: returnsAmount, returnsQty: returnsQty, returnsRestock: restock
        ))
    }
}
