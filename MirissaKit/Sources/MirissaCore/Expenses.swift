import Foundation

public enum ExpenseSourceKind: String, Sendable {
    case tekSeferlik, duzenli, stokAlimi
}

/// Ekranlarda gösterilen tek bir gider satırı.
/// Düzenli giderler ve stok alımları buraya "sanal" olarak açılır.
public struct ExpenseInstance: Identifiable, Hashable, Sendable {
    public var id: String
    public var templateId: Id?
    public var sourceKind: ExpenseSourceKind
    public var date: DateKey
    public var month: MonthKey
    public var name: String
    public var amount: Kurus
    public var category: ExpenseCategory
    public var scope: ExpenseScope
    /// Satış arttıkça artar mı — başa baş hesabında kullanılır
    public var behavior: CostBehavior
    /// Fatura/fiş dosyası
    public var attachment: String?
    /// Tutarın KDV hariç kısmı — kâr hesabı bunu kullanır
    public var net: Kurus
    /// İndirilebilecek KDV
    public var inputVat: Kurus
    /// Stoğa giren alım: nakit çıkışıdır ama kâra satıldıkça maliyet olarak yansır.
    public var capitalized: Bool
    /// Doğrudan düzenlenebilir mi (stok alımları kendi ekranından düzenlenir)
    public var editable: Bool

    /// Kâr hesabına bu ay giren tutar (KDV hariç)
    public var expenseAmount: Kurus { capitalized ? 0 : net }
    /// Kasadan bu ay çıkan tutar (KDV dahil, gerçekten ödenen).
    /// Tutar KDV hariç girilmişse KDV'si de ödenir; "amount" o durumda eksik kalır.
    public var cashAmount: Kurus { net + inputVat }
}

public enum Expenses {
    /// Verilen ay aralığı için tüm gider satırlarını üretir.
    public static func instances(_ s: AppState, from: MonthKey, to: MonthKey) -> [ExpenseInstance] {
        var out: [ExpenseInstance] = []
        guard Dates.monthsBetween(from, to) >= 0 else { return out }

        for e in s.expenses {
            switch e.recurrence {
            case .tek:
                let m = e.startMonth
                guard m >= from, m <= to else { continue }
                if let ov = e.overrides[m], ov.skipped { continue }
                out.append(instance(e, month: m, date: e.date))

            case .aylik:
                out += expand(e, step: 1, from: from, to: to)

            case .yillik:
                out += expand(e, step: 12, from: from, to: to)
            }
        }

        for p in s.purchases where !p.excludeFromExpenses {
            let m = Dates.month(of: p.date)
            guard m >= from, m <= to, p.landedTotal != 0 else { continue }
            out.append(ExpenseInstance(
                id: "pur:\(p.id)",
                templateId: nil,
                sourceKind: .stokAlimi,
                date: p.date,
                month: m,
                name: "\(s.itemName(p.item)) alımı",
                amount: p.landedTotal,
                category: p.resolvedCategory,
                scope: p.expenseScope,
                behavior: .satisaBagli,
                attachment: p.attachment,
                net: p.landedSplit.net,
                inputVat: p.landedSplit.vat,
                capitalized: s.settings.capitalizePurchases,
                editable: false
            ))
        }

        out.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        return out
    }

    private static func expand(_ e: Expense, step: Int, from: MonthKey, to: MonthKey) -> [ExpenseInstance] {
        let start = e.startMonth
        // Şablonun kendi bitişi ile istenen aralığın kesişimi
        let hardEnd = e.endMonth.map { min($0, to) } ?? to
        guard Dates.monthsBetween(start, hardEnd) >= 0 else { return [] }

        var out: [ExpenseInstance] = []
        let anchorDay = Dates.day(of: e.date)
        var k = 0
        while true {
            let m = Dates.addMonths(start, k * step)
            if Dates.monthsBetween(m, hardEnd) < 0 { break }
            k += 1
            guard m >= from else { continue }
            if let ov = e.overrides[m], ov.skipped { continue }
            out.append(instance(e, month: m, date: Dates.dateIn(month: m, dayOfMonth: anchorDay)))
            if k > 2400 { break } // güvenlik freni
        }
        return out
    }

    private static func instance(_ e: Expense, month: MonthKey, date: DateKey) -> ExpenseInstance {
        let ov = e.overrides[month]
        let tutar = ov?.amount ?? e.amount
        // O ay için ayrı KDV girilmişse o kullanılır (ör. bir ay KDV'siz fatura)
        let bolum = Vat.split(tutar,
                              rate: ov?.vatRate ?? e.resolvedVatRate,
                              included: ov?.vatIncluded ?? e.resolvedVatIncluded)
        return ExpenseInstance(
            id: e.recurrence == .tek ? e.id : "\(e.id)#\(month)",
            templateId: e.id,
            sourceKind: e.recurrence == .tek ? .tekSeferlik : .duzenli,
            date: date,
            month: month,
            name: ov?.name ?? e.name,
            amount: ov?.amount ?? e.amount,
            category: e.category,
            scope: e.scope,
            behavior: e.resolvedBehavior,
            attachment: ov?.attachment ?? e.attachment,
            net: bolum.net,
            inputVat: bolum.vat,
            capitalized: false,
            editable: true
        )
    }

    /// Kategori dağılımı (kâra etki eden tutarlar)
    public static func breakdown(_ items: [ExpenseInstance]) -> [ExpenseCategory: Kurus] {
        var out: [ExpenseCategory: Kurus] = [:]
        for i in items where i.expenseAmount != 0 {
            out[i.category, default: 0] += i.expenseAmount
        }
        return out
    }
}
