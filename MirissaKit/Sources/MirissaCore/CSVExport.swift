import Foundation

public struct ExportFile: Identifiable, Sendable {
    public var name: String
    public var contents: String
    public var id: String { name }
}

/// Excel'in Türkçe ayarlarıyla doğru açılması için noktalı virgül ayracı
/// ve virgüllü ondalık kullanılır; dosya başına BOM eklenir.
public enum CSVExport {
    static let sep = ";"

    static func esc(_ v: String) -> String {
        if v.contains(sep) || v.contains("\"") || v.contains("\n") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    static func num(_ v: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func money(_ k: Kurus) -> String { num(Money.toTL(k)) }

    static func row(_ cells: [String]) -> String {
        cells.map(esc).joined(separator: sep) + "\n"
    }

    static func file(_ name: String, _ header: [String], _ rows: [[String]]) -> ExportFile {
        var out = "\u{FEFF}" + row(header)
        for r in rows { out += row(r) }
        return ExportFile(name: name, contents: out)
    }

    // MARK: - Tablolar

    public static func sales(_ e: Engine) -> ExportFile {
        let rows = e.state.sales
            .sorted { $0.month == $1.month ? $0.id < $1.id : $0.month > $1.month }
            .map { s -> [String] in
                [
                    s.month,
                    e.state.channel(s.channelId)?.name ?? s.channelId,
                    e.state.product(s.productId)?.name ?? s.productId,
                    num(s.qty, digits: 0),
                    money(s.grossSales),
                    money(s.discount),
                    money(s.returnsAmount),
                    num(s.returnsQty, digits: 0),
                    money(s.netSales),
                    s.note ?? "",
                ]
            }
        return file("satislar.csv",
                    ["Ay", "Kanal", "Ürün", "Adet", "Brüt satış", "İndirim",
                     "İade tutarı", "İade adedi", "Net satış", "Not"], rows)
    }

    public static func expenses(_ e: Engine, from: MonthKey, to: MonthKey) -> ExportFile {
        let rows = e.expenseInstances(from: from, to: to).map { i -> [String] in
            [
                i.date,
                i.month,
                i.name,
                i.category.displayName,
                i.scope.channelId.map { e.state.channel($0)?.name ?? $0 } ?? "Ortak",
                money(i.amount),
                i.capitalized ? "Stoğa girdi" : "Gider",
                i.sourceKind == .duzenli ? "Düzenli" : (i.sourceKind == .stokAlimi ? "Stok alımı" : "Tek seferlik"),
            ]
        }
        return file("giderler.csv",
                    ["Tarih", "Ay", "Gider adı", "Kategori", "Bölüm",
                     "Tutar", "Kâra etkisi", "Tür"], rows)
    }

    public static func products(_ e: Engine) -> ExportFile {
        let rows = e.state.products.map { p -> [String] in
            let c = e.cost(of: p.id)
            let b = e.balance(.product(p.id))
            return [
                p.name,
                p.isBundle ? "Set" : "Ürün",
                num(b.qty, digits: 0),
                money(c.ownLines),
                money(c.components),
                money(c.packaging),
                money(c.total),
                money(b.value),
            ]
        }
        return file("urunler.csv",
                    ["Ürün", "Tür", "Stok", "Kendi maliyeti", "Bileşen maliyeti",
                     "Paketleme maliyeti", "Toplam birim maliyet", "Stok değeri"], rows)
    }

    public static func materials(_ e: Engine) -> ExportFile {
        let rows = e.state.materials.map { m -> [String] in
            let b = e.balance(.material(m.id))
            let ref = ItemRef.material(m.id)
            return [
                m.name,
                m.category.displayName,
                m.baseUnit.displayName,
                num(b.qty),
                money(Money.roundHalfAwayFromZero(b.unitCost)),
                money(b.value),
                m.minQty.map { num($0) } ?? "",
                m.criticalQty.map { num($0) } ?? "",
                e.status(ref).shortLabel,
                e.ordersLeft(ref).map(String.init) ?? "",
            ]
        }
        return file("stoklar.csv",
                    ["Malzeme", "Kategori", "Birim", "Mevcut", "Birim maliyet", "Stok değeri",
                     "Min. stok", "Kritik stok", "Durum", "Yaklaşık siparişlik"], rows)
    }

    public static func movements(_ e: Engine) -> ExportFile {
        let rows = e.ledger.rows.reversed().map { r -> [String] in
            [
                r.date,
                e.state.itemName(r.item),
                r.item.kind == .material ? "Malzeme" : "Ürün",
                r.label,
                num(r.delta),
                num(r.balanceAfter),
                money(Money.roundHalfAwayFromZero(r.unitCostAfter)),
                money(r.valueAfter),
            ]
        }
        return file("stok-hareketleri.csv",
                    ["Tarih", "Kalem", "Tür", "Hareket", "Değişim",
                     "Kalan", "Birim maliyet", "Stok değeri"], rows)
    }

    public static func monthlySummary(_ e: Engine, from: MonthKey, to: MonthKey) -> ExportFile {
        let rows = Dates.monthRange(from: from, to: to).map { m -> [String] in
            let r = e.companyMonth(m)
            return [
                m,
                money(r.gercekCiro),
                money(r.toplamGider),
                money(r.gercekKar),
                num(r.karMarjiPct, digits: 1),
                num(r.units, digits: 0),
            ]
        }
        return file("aylik-ozet.csv",
                    ["Ay", "Gerçek ciro", "Toplam gider", "Gerçek kâr", "Kâr marjı %", "Satılan adet"], rows)
    }

    public static func all(_ e: Engine, from: MonthKey, to: MonthKey) -> [ExportFile] {
        [
            monthlySummary(e, from: from, to: to),
            sales(e),
            expenses(e, from: from, to: to),
            products(e),
            materials(e),
            movements(e),
        ]
    }
}
