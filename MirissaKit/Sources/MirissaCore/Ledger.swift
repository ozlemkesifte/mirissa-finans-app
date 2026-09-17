import Foundation

public struct ItemBalance: Hashable, Sendable {
    public var item: ItemRef
    public var qty: BaseQty
    /// Temel birim başına ağırlıklı ortalama maliyet (kuruş, kesirli)
    public var unitCost: Double
    /// Stok değeri (kuruş). Eksi stokta 0.
    public var value: Kurus
    public var wentNegative: Bool
    public var lastMovementDate: DateKey?

    public static func zero(_ item: ItemRef) -> ItemBalance {
        .init(item: item, qty: 0, unitCost: 0, value: 0, wentNegative: false, lastMovementDate: nil)
    }
}

public struct LedgerRow: Identifiable, Hashable, Sendable {
    public var movement: Movement
    public var balanceAfter: BaseQty
    public var unitCostAfter: Double
    public var valueAfter: Kurus

    public var id: String { movement.id }
    public var date: DateKey { movement.date }
    public var item: ItemRef { movement.item }
    /// Sayımda katlama sırasında hesaplanan fark
    public var delta: BaseQty { movement.delta }
    public var label: String { movement.label }
    public var kind: MovementKind { movement.kind }
}

public struct LedgerResult: Sendable {
    public var rows: [LedgerRow]
    public var balances: [Id: ItemBalance]

    public func balance(_ item: ItemRef) -> ItemBalance {
        balances[item.id] ?? .zero(item)
    }

    public func rows(for item: ItemRef) -> [LedgerRow] {
        rows.filter { $0.item.id == item.id }
    }
}

public enum Ledger {
    /// Hareketleri kronolojik katlayarak stok ve ağırlıklı ortalama maliyeti üretir.
    ///
    /// Ortalama maliyet sıraya bağlıdır: 500 adet 10 TL'den, sonra 500 adet
    /// 12 TL'den alınırsa birim maliyet 11 TL olur. Bu yüzden stok saklanmaz,
    /// her zaman baştan katlanarak hesaplanır — böylece geçmişteki bir kayıt
    /// düzeltildiğinde sonraki bütün değerler kendiliğinden doğru hale gelir.
    public static func fold(_ movements: [Movement]) -> LedgerResult {
        var rows: [LedgerRow] = []
        rows.reserveCapacity(movements.count)

        var qty: [Id: BaseQty] = [:]
        var totalValue: [Id: Double] = [:]     // kuruş, kesirli
        var lastCost: [Id: Double] = [:]       // stok sıfırlandığında korunan son birim maliyet
        var negative: Set<Id> = []
        var lastDate: [Id: DateKey] = [:]
        var refs: [Id: ItemRef] = [:]

        for var mv in movements {
            let key = mv.item.id
            refs[key] = mv.item
            var q = qty[key] ?? 0
            var v = totalValue[key] ?? 0
            let currentCost = q > 0 ? v / q : (lastCost[key] ?? 0)

            switch mv.kind {
            case .opening, .purchase:
                let giris = Double(mv.inCost ?? 0)
                if q < 0, mv.delta > 0 {
                    // Stok eksideyken gelen alım: önce eksik kapanır. Kalan stok
                    // (ya da hâlâ eksik olan kısım) bu alımın birim fiyatıyla
                    // değerlenir. Eski eksi değere alım tutarını eklemek, bu
                    // alımın parasını az sayıda adede bölüp birim maliyeti
                    // şişiriyor, bazen de eksiye düşürüyordu.
                    let fiyat = giris / mv.delta
                    q += mv.delta
                    v = q * fiyat
                    if q <= 0 { lastCost[key] = fiyat }
                } else {
                    q += mv.delta
                    v += giris
                }

            case .satis, .duzeltme, .iade:
                if mv.delta >= 0 {
                    // Stoğa giriş (iade, bulunan mal): güncel birim maliyetle değerlenir
                    q += mv.delta
                    v += mv.delta * currentCost
                } else {
                    q += mv.delta
                    v += mv.delta * currentCost
                }

            case .sayim:
                // Sayım bir ADET gerçeğidir, fiyat gerçeği değil: birim maliyet değişmez.
                let target = mv.absoluteTo ?? q
                let diff = target - q
                mv.delta = diff
                v += diff * currentCost
                q = target
            }

            if q <= 0 {
                // Sıfıra bölmeyi ve NaN yayılmasını engelle: son geçerli maliyeti sakla.
                // Değeri sıfıra kırpmak yerine miktarla orantılı tut — aksi halde
                // eksiye düşmüş bir stoğa alım yapıldığında birim maliyet şişer.
                let alimFiyati = (mv.kind == .purchase || mv.kind == .opening) && mv.delta > 0
                    ? lastCost[key] : nil
                let c = alimFiyati ?? (currentCost > 0 ? currentCost : (lastCost[key] ?? 0))
                lastCost[key] = c
                v = q * c
            } else {
                lastCost[key] = v / q
            }
            if q < 0 { negative.insert(key) }

            qty[key] = q
            totalValue[key] = v
            lastDate[key] = mv.date

            let unitAfter = q > 0 ? v / q : (lastCost[key] ?? 0)
            rows.append(LedgerRow(
                movement: mv,
                balanceAfter: q,
                unitCostAfter: unitAfter,
                valueAfter: Money.roundHalfAwayFromZero(max(v, 0))
            ))
        }

        var balances: [Id: ItemBalance] = [:]
        for (key, ref) in refs {
            let q = qty[key] ?? 0
            let v = totalValue[key] ?? 0
            balances[key] = ItemBalance(
                item: ref,
                qty: q,
                unitCost: q > 0 ? v / q : (lastCost[key] ?? 0),
                value: Money.roundHalfAwayFromZero(max(v, 0)),
                wentNegative: negative.contains(key),
                lastMovementDate: lastDate[key]
            )
        }

        return LedgerResult(rows: rows, balances: balances)
    }
}
