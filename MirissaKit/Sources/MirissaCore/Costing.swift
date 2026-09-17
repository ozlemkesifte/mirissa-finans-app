import Foundation

public struct CostBreakdown: Hashable, Sendable {
    /// Ürünün kendi maliyet kalemleri (üretim vb.)
    public var ownLines: Kurus
    /// Set ise bileşen ürünlerin maliyeti (paketlemeleri hariç)
    public var components: Kurus
    /// Paketleme reçetesinin malzeme maliyeti
    public var packaging: Kurus
    /// Ürünün kendi maliyeti girilen kalemlerden değil, gerçek alımların
    /// ağırlıklı ortalamasından geldi
    public var ownFromPurchases: Bool = false

    /// Paketleme hariç ürün maliyeti — satılan malın maliyeti (SMM) budur
    public var intrinsic: Kurus { ownLines + components }
    public var total: Kurus { intrinsic + packaging }

    public static let zero = CostBreakdown(ownLines: 0, components: 0, packaging: 0)
}

public enum CostingError: Error, CustomStringConvertible {
    case cycle([String])
    public var description: String {
        "Set tanımı kendini içeriyor: " + cycle.joined(separator: " → ")
    }
    private var cycle: [String] {
        if case let .cycle(c) = self { return c }
        return []
    }
}

public enum Costing {
    static let maxDepth = 8

    /// Bir ürünü stok tutan yaprak ürünlere açar.
    /// Set → bileşenleri (çarpanla). Normal ürün → kendisi.
    /// Kendini içeren set tanımında sonsuz döngüye girmez.
    public static func explodeToLeafProducts(
        products: [Id: Product],
        productId: Id,
        qty: Double,
        visiting: Set<Id> = [],
        depth: Int = 0
    ) -> [Id: Double] {
        guard depth < maxDepth, !visiting.contains(productId),
              let p = products[productId] else { return [:] }
        guard p.isBundle, !p.components.isEmpty else { return [productId: qty] }

        var out: [Id: Double] = [:]
        var next = visiting
        next.insert(productId)
        for c in p.components {
            let sub = explodeToLeafProducts(
                products: products, productId: c.productId,
                qty: qty * c.qty, visiting: next, depth: depth + 1
            )
            for (k, v) in sub { out[k, default: 0] += v }
        }
        return out
    }

    /// Setin kendini içerip içermediğini kontrol eder.
    public static func hasCycle(products: [Id: Product], productId: Id) -> Bool {
        func walk(_ id: Id, _ seen: Set<Id>, _ depth: Int) -> Bool {
            if seen.contains(id) { return true }
            if depth >= maxDepth { return true }
            guard let p = products[id], p.isBundle else { return false }
            var s = seen
            s.insert(id)
            return p.components.contains { walk($0.productId, s, depth + 1) }
        }
        return walk(productId, [], 0)
    }

    /// Paketleme reçetesinin maliyeti: her satır için (temel birim miktarı × malzeme birim maliyeti)
    public static func packagingCost(
        product: Product,
        materials: [Id: StockMaterial],
        unitCostOf: (Id) -> Double
    ) -> Kurus {
        var total = 0.0
        for line in product.recipe {
            // Üretim maliyetine zaten dahilse maliyeti tekrar sayma.
            // Stok hareketi bundan etkilenmez; yalnızca çift maliyet önlenir.
            guard line.resolvedAddsCost else { continue }
            guard let mat = materials[line.materialId] else { continue }
            guard let base = Units.toBaseOrNil(
                qty: line.qty, unit: line.unit,
                baseUnit: mat.baseUnit, packSizes: mat.packSizes
            ) else { continue }
            total += base * unitCostOf(mat.id)
        }
        return Money.roundHalfAwayFromZero(total)
    }

    /// Bir ürünün kendi (paketleme ve bileşen hariç) birim maliyeti.
    ///
    /// Kullanıcının girdiği maliyet kalemleri önceliklidir: yazdığı rakam
    /// sessizce başka bir rakamla değiştirilmez.
    /// Maliyet hiç girilmemiş ama ürün stok alımıyla alınmışsa (fason üretim,
    /// hazır ürün) ödenen tutarların ağırlıklı ortalaması kullanılır. Aksi halde
    /// maliyet 0 sayılır, alım da gider yazılmadığı için o para hiçbir yerde
    /// gider olarak görünmezdi. İkisi birbirini tutmuyorsa Integrity uyarır.
    static func ownCost(_ p: Product, asOf: DateKey?,
                        purchasedUnitCostOf: (Id) -> Double) -> (Kurus, Bool) {
        let girilen = p.costLines(on: asOf).reduce(0) { $0 + $1.amount }
        if girilen == 0, !p.isBundle, p.tracksOwnStock {
            let alim = purchasedUnitCostOf(p.id)
            if alim > 0 { return (Money.roundHalfAwayFromZero(alim), true) }
        }
        return (girilen, false)
    }

    /// Paketleme hariç ürün maliyeti (kendi kalemleri + bileşenlerin aynı şekilde hesaplanmışı)
    public static func intrinsicCost(
        products: [Id: Product],
        productId: Id,
        asOf: DateKey? = nil,
        visiting: Set<Id> = [],
        depth: Int = 0,
        purchasedUnitCostOf: (Id) -> Double = { _ in 0 }
    ) -> Kurus {
        guard depth < maxDepth, !visiting.contains(productId),
              let p = products[productId] else { return 0 }
        var total = ownCost(p, asOf: asOf, purchasedUnitCostOf: purchasedUnitCostOf).0
        if p.isBundle {
            var next = visiting
            next.insert(productId)
            for c in p.components {
                let sub = intrinsicCost(
                    products: products, productId: c.productId, asOf: asOf,
                    visiting: next, depth: depth + 1,
                    purchasedUnitCostOf: purchasedUnitCostOf
                )
                total += Money.roundHalfAwayFromZero(Double(sub) * c.qty)
            }
        }
        return total
    }

    public static func breakdown(
        products: [Id: Product],
        materials: [Id: StockMaterial],
        productId: Id,
        asOf: DateKey? = nil,
        unitCostOf: (Id) -> Double,
        purchasedUnitCostOf: (Id) -> Double = { _ in 0 }
    ) -> CostBreakdown {
        guard let p = products[productId] else { return .zero }
        let (own, alimdan) = ownCost(p, asOf: asOf, purchasedUnitCostOf: purchasedUnitCostOf)
        var comps = 0
        if p.isBundle {
            for c in p.components {
                let sub = intrinsicCost(products: products, productId: c.productId, asOf: asOf,
                                        visiting: [productId], depth: 1,
                                        purchasedUnitCostOf: purchasedUnitCostOf)
                comps += Money.roundHalfAwayFromZero(Double(sub) * c.qty)
            }
        }
        let pack = packagingCost(product: p, materials: materials, unitCostOf: unitCostOf)
        return CostBreakdown(ownLines: own, components: comps, packaging: pack,
                             ownFromPurchases: alimdan)
    }
}
