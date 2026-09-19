import Foundation

public enum ExpenseSourceKind: String, Sendable {
    case tekSeferlik, duzenli, stokAlimi
    /// Vadeli alımın sonradan ödenen taksiti: yalnızca nakit çıkışıdır
    case taksit
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
    /// Bu ay kasadan çıkan tutar farklıysa (vadeli alımda peşinat, taksit ayında taksit)
    public var nakitTutari: Kurus? = nil

    /// Kâr hesabına bu ay giren tutar (KDV hariç)
    public var expenseAmount: Kurus { capitalized ? 0 : net }
    /// Faturadaki indirilemeyen KDV (gidere eklendi, indirilecek KDV'ye girmedi) — ödeme ayında
    public var indirilemeyenKdv: Kurus = 0
    /// Kanunen kabul edilmeyen gider: vergi matrahına eklenir
    public var kkeg: Bool = false

    /// Kasadan bu ay çıkan tutar (KDV dahil, gerçekten ödenen).
    /// Tutar KDV hariç girilmişse KDV'si de ödenir; "amount" o durumda eksik kalır.
    public var cashAmount: Kurus { nakitTutari ?? (net + inputVat) }
}

public extension Expense {
    /// Düzenli gideri `ay`dan itibaren ikiye böler: bu kayıt bir önceki ayda biter, devamı
    /// (yeni kimlikle, `yeniHali` bilgileriyle) o aydan başlar. O aydan sonraki aya özel tutarlar devama geçer.
    func bol(ay: MonthKey, yeniHali: Expense) -> (eski: Expense, devam: Expense) {
        var eski = self
        var devam = yeniHali
        devam.id = Ids.make(.expense)
        devam.date = Dates.dateIn(month: ay, dayOfMonth: Dates.day(of: date))
        devam.overrides = overrides.filter { $0.key >= ay }
        // Düzenlenen parçanın kendi devamı varsa (daha önce bölünmüştü) yeni parça ona bağlanır
        devam.devamId = yeniHali.devamId
        eski.overrides = overrides.filter { $0.key < ay }
        eski.endMonth = Dates.addMonths(ay, -1)
        eski.devamId = devam.id
        return (eski, devam)
    }

    /// Yıllık giderde verilen ayın ait olduğu ödeme ayı (başlangıçtan itibaren her 12 ayda bir).
    /// O yılın tutarı ve aya özel değişiklikleri bu aya bağlıdır.
    func yillikOdemeAyi(_ ay: MonthKey) -> MonthKey {
        Dates.addMonths(startMonth, (max(Dates.monthsBetween(startMonth, ay), 0) / 12) * 12)
    }
}

public enum Expenses {
    /// Verilen ay aralığı için tüm gider satırlarını üretir.
    public static func instances(_ s: AppState, from: MonthKey, to: MonthKey) -> [ExpenseInstance] {
        var out: [ExpenseInstance] = []
        guard Dates.monthsBetween(from, to) >= 0 else { return out }

        for e in s.expenses {
            switch e.recurrence {
            case .tek where (e.yayilanAy ?? 1) > 1:
                out += tekAylaraBol(e, aySayisi: e.yayilanAy!, from: from, to: to)

            case .tek:
                let m = e.startMonth
                guard m >= from, m <= to else { continue }
                if let ov = e.overrides[m], ov.skipped { continue }
                out.append(instance(e, month: m, date: e.date))

            case .aylik:
                out += expand(e, step: 1, from: from, to: to)

            case .yillik:
                out += yillikAylaraBol(e, from: from, to: to)
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
                editable: false,
                // Vadeli alımda alım günü yalnızca peşinat ödenir
                nakitTutari: p.odeme?.pesinat
            ))
        }
        // Vadeli alımların taksitleri: ödendiği (ya da vadesi geldiği) ayda nakit çıkışı
        for p in s.purchases where !p.excludeFromExpenses {
            for t in p.odeme?.taksitler ?? [] {
                let m = Dates.month(of: t.nakitGunu)
                guard m >= from, m <= to, t.tutar != 0 else { continue }
                out.append(ExpenseInstance(
                    id: "taksit:\(p.id):\(t.id)", templateId: nil, sourceKind: .taksit,
                    date: t.nakitGunu, month: m,
                    name: "\(s.itemName(p.item)) alımı taksiti" + (t.odendi ? "" : " (vadesi)"),
                    amount: 0, category: p.resolvedCategory, scope: p.expenseScope,
                    behavior: .satisaBagli, attachment: nil, net: 0, inputVat: 0,
                    capitalized: true, editable: false, nakitTutari: t.tutar))
            }
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

    /// Yılda bir ödenen gider: kâra her ay 1/12'si yazılır (bir ay şişip diğerleri
    /// boş kalmasın, başa baş hedefi doğru çıksın). Para ve KDV ödeme ayındadır.
    private static func yillikAylaraBol(_ e: Expense, from: MonthKey, to: MonthKey) -> [ExpenseInstance] {
        let start = e.startMonth
        // Durdurulan yıllık giderde son ödenen yılın payları yılın sonuna kadar yazılır:
        // para ödendi, kalan 11/12 kârdan hiç düşmeden kaybolmasın. Yeni ödeme olmaz.
        let payBitisi = e.endMonth.map { son -> MonthKey in
            // Başlamadan durdurulduysa hiç ödenmedi
            if son < start { return Dates.addMonths(start, -1) }
            return Dates.addMonths(e.yillikOdemeAyi(son), 11)
        }
        let hardEnd = payBitisi.map { min($0, to) } ?? to
        guard from <= hardEnd else { return [] }
        let anchorDay = Dates.day(of: e.date)
        var out: [ExpenseInstance] = []
        var m = max(from, start)
        while m <= hardEnd {
            let odemeAyi = e.yillikOdemeAyi(m)
            let sira = Dates.monthsBetween(odemeAyi, m)
            defer { m = Dates.addMonths(m, 1) }
            let ov = e.overrides[odemeAyi]
            if ov?.skipped == true { continue }
            let yillik = ov?.amount ?? e.amount
            let bolum = kdvBolumu(e, yillik, ov)
            let pay = onIkideBiri(bolum.net, sira)
            let brutPay = onIkideBiri(yillik, sira)
            let odemeAyinda = m == odemeAyi
            out.append(ExpenseInstance(
                id: "\(e.id)#\(m)", templateId: e.id, sourceKind: .duzenli,
                date: Dates.dateIn(month: m, dayOfMonth: anchorDay), month: m,
                name: (ov?.name ?? e.name) + (odemeAyinda ? " (yıllık ödeme)" : " (yıllık payı)"),
                amount: brutPay, category: e.category, scope: e.scope, behavior: e.resolvedBehavior,
                attachment: odemeAyinda ? (ov?.attachment ?? e.attachment) : nil,
                net: pay, inputVat: odemeAyinda ? bolum.vat : 0,
                capitalized: false, editable: true,
                nakitTutari: odemeAyinda ? bolum.net + bolum.vat : 0,
                indirilemeyenKdv: odemeAyinda ? bolum.indirilemeyen : 0, kkeg: e.kkeg == true))
            if out.count > 2400 { break }
        }
        return out
    }

    /// Kâra her ay yazılan pay: KDV hariç tutarın 1/n'i, motorla aynı bölme (ilk ayın payı).
    /// Ekranlardaki "ayda X" açıklamaları bunu kullanır.
    public static func aylikKarPayi(_ tutar: Kurus, rate: VatRate, included: Bool, aySayisi n: Int) -> Kurus {
        esitPay(Vat.net(tutar, rate: rate, included: included), max(n, 1), 0)
    }

    /// Yıllık tutarın `sira`'ncı ayın payı: eşit bölünür, artan kuruşlar ilk aylara (toplam birebir tutar)
    static func onIkideBiri(_ t: Kurus, _ sira: Int) -> Kurus { esitPay(t, 12, sira) }

    /// `t` tutarını `n` eşit paya böler; artan kuruşlar ilk paylara (paylar toplamı birebir `t`)
    static func esitPay(_ t: Kurus, _ n: Int, _ sira: Int) -> Kurus {
        let taban = t / n
        let artan = t - taban * n
        return taban + (sira < abs(artan) ? (artan > 0 ? 1 : -1) : 0)
    }

    /// Tek seferlik gider N aya bölünür: kâra her ay 1/N'i yazılır; para ve KDV ödeme ayında.
    private static func tekAylaraBol(_ e: Expense, aySayisi n: Int, from: MonthKey, to: MonthKey) -> [ExpenseInstance] {
        let start = e.startMonth
        let ov = e.overrides[start]
        if ov?.skipped == true { return [] }
        let tutar = ov?.amount ?? e.amount
        let bolum = kdvBolumu(e, tutar, ov)
        let anchorDay = Dates.day(of: e.date)
        var out: [ExpenseInstance] = []
        for sira in 0..<min(n, 600) {
            let m = Dates.addMonths(start, sira)
            guard m >= from else { continue }
            if m > to { break }
            let odemeAyinda = sira == 0
            out.append(ExpenseInstance(
                id: odemeAyinda ? e.id : "\(e.id)#\(m)", templateId: e.id, sourceKind: .tekSeferlik,
                date: odemeAyinda ? e.date : Dates.dateIn(month: m, dayOfMonth: anchorDay), month: m,
                name: (ov?.name ?? e.name) + " (\(sira + 1)/\(n). ay payı)",
                amount: esitPay(tutar, n, sira), category: e.category, scope: e.scope,
                behavior: e.resolvedBehavior,
                attachment: odemeAyinda ? (ov?.attachment ?? e.attachment) : nil,
                net: esitPay(bolum.net, n, sira), inputVat: odemeAyinda ? bolum.vat : 0,
                capitalized: false, editable: true,
                nakitTutari: odemeAyinda ? bolum.net + bolum.vat : 0,
                indirilemeyenKdv: odemeAyinda ? bolum.indirilemeyen : 0, kkeg: e.kkeg == true))
        }
        return out
    }

    private static func instance(_ e: Expense, month: MonthKey, date: DateKey) -> ExpenseInstance {
        let ov = e.overrides[month]
        let tutar = ov?.amount ?? e.amount
        // O ay için ayrı KDV girilmişse o kullanılır (ör. bir ay KDV'siz fatura)
        let bolum = kdvBolumu(e, tutar, ov)
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
            editable: true,
            indirilemeyenKdv: bolum.indirilemeyen,
            kkeg: e.kkeg == true
        )
    }

    /// Giderin KDV bölümü. KDV'si indirilemeyen giderde KDV gidere eklenir (net), indirilecek KDV 0 olur.
    static func kdvBolumu(_ e: Expense, _ tutar: Kurus, _ ov: ExpenseOverride?) -> (net: Kurus, vat: Kurus, indirilemeyen: Kurus) {
        let b = Vat.split(tutar, rate: ov?.vatRate ?? e.resolvedVatRate,
                          included: ov?.vatIncluded ?? e.resolvedVatIncluded)
        return e.kdvIndirilemez == true ? (b.net + b.vat, 0, b.vat) : (b.net, b.vat, 0)
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
