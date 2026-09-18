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
        // "\r\n" Swift'te tek karakterdir; satır sonu skaler düzeyde aranır
        let satirSonu = v.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
        if v.contains(sep) || v.contains("\"") || satirSonu {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    static func num(_ v: Double, digits: Int = 2) -> String {
        var s = String(format: "%.\(digits)f", v)
        // Sıfıra yuvarlanan eksi değer "-0,0" yazılmasın
        if s.hasPrefix("-"), s.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) { s.removeFirst() }
        return s.replacingOccurrences(of: ".", with: ",")
    }

    /// Adet: tam sayıysa ondalıksız, değilse ondalığıyla (0,5 adet 0 ya da 1 yazılmasın)
    static func adet(_ v: Double) -> String {
        abs(v - v.rounded()) < 1e-9 ? num(v, digits: 0) : num(v, digits: 3)
    }

    /// Birim maliyet: gram/ml başına kuruşun altında kalabilir; 4 basamak TL
    static func birimMaliyet(_ kurus: Double) -> String { num(kurus / 100, digits: 4) }

    /// Dışa aktarılacak dönemin sonu: henüz gelmemiş aylar yazılmaz
    static func bugune(_ to: MonthKey, today: DateKey) -> MonthKey { min(to, Dates.month(of: today)) }

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
                    adet(s.qty),
                    money(s.grossSales),
                    money(s.discount),
                    money(s.returnsAmount),
                    adet(s.returnsQty),
                    money(s.netSales),
                    money(s.vatSplit.net),
                    money(s.vatSplit.vat),
                    s.resolvedVatRate.displayName,
                    s.note ?? "",
                ]
            }
        return file("satislar.csv",
                    ["Ay", "Kanal", "Ürün", "Adet", "Brüt satış", "İndirim",
                     "İade tutarı", "İade adedi", "Net satış",
                     "KDV hariç", "KDV", "KDV oranı", "Not"], rows)
    }

    public static func expenses(_ e: Engine, from: MonthKey, to: MonthKey) -> ExportFile {
        let rows = e.expenseInstances(from: from, to: to).map { i -> [String] in
            [
                i.date,
                i.month,
                i.name,
                i.category.displayName,
                i.scope.channelId.map { e.state.channel($0)?.name ?? $0 } ?? "Ortak",
                money(i.cashAmount),
                money(i.net),
                money(i.inputVat),
                i.capitalized ? "Stoğa girdi" : "Gider",
                i.sourceKind == .duzenli ? "Düzenli" : (i.sourceKind == .stokAlimi ? "Stok alımı" : "Tek seferlik"),
            ]
        }
        return file("giderler.csv",
                    ["Tarih", "Ay", "Gider adı", "Kategori", "Bölüm",
                     "Ödenen (KDV dahil)", "KDV hariç", "İndirilecek KDV", "Kâra etkisi", "Tür"], rows)
    }

    public static func products(_ e: Engine) -> ExportFile {
        let rows = e.state.products.map { p -> [String] in
            let c = e.cost(of: p.id)
            let b = e.balance(.product(p.id))
            return [
                p.name,
                p.isBundle ? "Set" : "Ürün",
                adet(b.qty),
                money(c.ownLines),
                money(c.components),
                money(c.packaging),
                money(c.orderPackaging),
                money(c.total),
                money(b.value),
            ]
        }
        return file("urunler.csv",
                    ["Ürün", "Tür", "Stok", "Kendi maliyeti", "Bileşen maliyeti",
                     "Paketleme maliyeti", "Koli (sipariş başı)", "Toplam birim maliyet", "Stok değeri"], rows)
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
                birimMaliyet(b.unitCost),
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
                birimMaliyet(r.unitCostAfter),
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

    public static func vatSummary(_ e: Engine, from: MonthKey, to: MonthKey) -> ExportFile {
        let rows = Dates.monthRange(from: from, to: to).map { m -> [String] in
            let v = e.vatStatus(m)
            return [
                m,
                money(v.hesaplanan),
                money(v.indirilecek),
                money(v.oncekiDevreden),
                money(v.odenecek),
                money(v.devreden),
            ]
        }
        return file("kdv-ozeti.csv",
                    ["Ay", "Hesaplanan KDV", "İndirilecek KDV", "Önceki aydan devreden",
                     "Tahmini ödenecek", "Sonraki aya devreden"], rows)
    }

    public static func all(_ e: Engine, from: MonthKey, to: MonthKey,
                           today: DateKey = Dates.today()) -> [ExportFile] {
        let to = max(bugune(to, today: today), from)
        var out = [
            monthlySummary(e, from: from, to: to),
            sales(e),
            expenses(e, from: from, to: to),
            products(e),
            materials(e),
            movements(e),
        ]
        if e.state.settings.vatEnabled { out.append(vatSummary(e, from: from, to: to)) }
        return out
    }
}
