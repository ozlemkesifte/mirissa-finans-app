import Foundation

public enum IssueSeverity: String, Sendable, Hashable {
    /// Kayıt engellenir; kullanıcı açıkça zorlamadıkça oluşmaz
    case engel
    /// Kayıt yapılabilir ama kullanıcı onaylamalı
    case uyari
}

public enum IssueCode: String, Sendable, Hashable {
    case receteMaliyetiCiftSayim
    case setMaliyetiCiftSayim
    case baslangicStoguTekrarAlim
    case mukerrerFatura
    case sabitGiderTekrari
    case kanalKesintisiCiftSayim
    case negatifStok
    case gecersizMiktar
    case gecersizTutar
    case gecersizOran
    case eksikBilgi
}

public extension IssueCode {
    /// Kodun genel davranışı: geçersiz veri asla, çift sayım riski onayla geçilebilir
    var defaultOverridable: Bool {
        switch self {
        case .gecersizMiktar, .gecersizTutar, .gecersizOran, .eksikBilgi:
            return false
        case .mukerrerFatura, .receteMaliyetiCiftSayim, .setMaliyetiCiftSayim,
             .baslangicStoguTekrarAlim, .sabitGiderTekrari,
             .kanalKesintisiCiftSayim, .negatifStok:
            return true
        }
    }
}

public struct ValidationIssue: Identifiable, Hashable, Sendable {
    public var code: IssueCode
    public var severity: IssueSeverity
    public var title: String
    public var detail: String

    public var id: String { "\(code.rawValue)-\(title)" }

    /// Kullanıcı açıkça zorlarsa kaydedilebilir mi.
    /// Geçersiz veri hiçbir şekilde kaydedilmez; çift sayım riski
    /// genelde bilinçli onayla geçilebilir. Bazı durumlar (aynı tedarikçinin
    /// aynı faturası) hiçbir şekilde geçilemez — onaylansa bile para iki kez sayılır.
    public var allowsOverride: Bool { overridable ?? code.defaultOverridable }

    /// Kurala özel istisna; nil ise kodun genel davranışı geçerli
    private var overridable: Bool?

    public init(_ code: IssueCode, _ severity: IssueSeverity, _ title: String, _ detail: String,
                overridable: Bool? = nil) {
        self.code = code
        self.severity = severity
        self.title = title
        self.detail = detail
        self.overridable = overridable
    }
}

public extension Array where Element == ValidationIssue {
    var blocking: [ValidationIssue] { filter { $0.severity == .engel } }
    var warnings: [ValidationIssue] { filter { $0.severity == .uyari } }
    var hasBlocking: Bool { contains { $0.severity == .engel } }
    /// Hiçbir şekilde geçilemeyen sorunlar
    var hardBlocking: [ValidationIssue] { blocking.filter { !$0.allowsOverride } }
    /// Onayla geçilebilen engeller
    var overridable: [ValidationIssue] { blocking.filter(\.allowsOverride) }
}

/// Kayıt öncesi kullanıcıya gösterilen kısa sonuç özeti.
public struct SaveSummary: Hashable, Sendable {
    public var lines: [String]
    public var note: String?

    public init(lines: [String], note: String? = nil) {
        self.lines = lines
        self.note = note
    }

    public var isEmpty: Bool { lines.isEmpty && note == nil }
}

/// Veri girişinde yanlış hesap üretecek durumları yakalar.
public enum Validation {

    // MARK: - Ortak yardımcılar

    /// Taslak uygulandıktan sonra stok eksiye düşen kalemler
    static func negativeItems(after state: AppState) -> [(ItemRef, BaseQty)] {
        let e = Engine(state)
        return e.ledger.balances.values
            .filter { $0.qty < 0 }
            .map { ($0.item, $0.qty) }
            .sorted { $0.0.id < $1.0.id }
    }

    static func stockIssues(before: AppState, after: AppState) -> [ValidationIssue] {
        let oncekiEksiler = Dictionary(
            uniqueKeysWithValues: negativeItems(after: before).map { ($0.0.id, $0.1) }
        )
        var out: [ValidationIssue] = []
        for (ref, miktar) in negativeItems(after: after) {
            // Zaten eksideyse ve daha da kötüleşmiyorsa yeni bir sorun değil
            if let onceki = oncekiEksiler[ref.id], miktar >= onceki { continue }
            let birim = after.itemBaseUnit(ref)
            let mevcut = Engine(before).qty(ref)
            out.append(ValidationIssue(
                .negatifStok, .engel,
                "\(after.itemName(ref)) stoğu eksiye düşüyor",
                "Bu işlemden sonra \(after.itemName(ref)) stoğu "
                    + "\(Units.formatQty(miktar, baseUnit: birim)) olacak. "
                    + "Mevcut stok \(Units.formatQty(mevcut, baseUnit: birim)). "
                    + "Önce stok alımı veya stok düzeltmesi gir."
            ))
        }
        return out
    }

    static func normalized(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !t.isEmpty else { return nil }
        return t
    }

    // MARK: - Reçete satırı

    /// Aynı malzeme reçetede ikinci kez yer alırsa stoktan iki kez düşer.
    /// Maliyete dahil olup olmaması artık satırın kendi ayarıdır; engel değildir.
    public static func recipeLine(materialId: Id, in product: Product, state: AppState) -> [ValidationIssue] {
        guard product.recipe.contains(where: { $0.materialId == materialId }) else { return [] }
        let ad = state.material(materialId)?.name ?? "Bu malzeme"
        return [ValidationIssue(
            .receteMaliyetiCiftSayim, .uyari,
            "\(ad) reçetede zaten var",
            "İkinci bir satır eklersen \(ad) her satışta iki kez stoktan düşer. "
                + "Miktarı değiştirmek istiyorsan mevcut satırı düzenle."
        )]
    }

    // MARK: - Ürün (Kural 1, 8)

    public static func product(_ draft: Product, state: AppState) -> [ValidationIssue] {
        var out: [ValidationIssue] = []

        if draft.costLines.contains(where: { $0.amount < 0 }) {
            out.append(ValidationIssue(.gecersizTutar, .engel,
                "Maliyet eksi olamaz", "Maliyet kalemlerinden biri eksi değer taşıyor."))
        }

        // Aynı malzemenin birden çok satırı stoktan iki kez düşer
        let tekrarlayan = Dictionary(grouping: draft.recipe, by: \.materialId)
            .filter { $0.value.count > 1 }
            .keys
            .compactMap { state.material($0)?.name }
        if !tekrarlayan.isEmpty {
            out.append(ValidationIssue(
                .receteMaliyetiCiftSayim, .uyari,
                "Aynı malzeme reçetede birden çok kez var",
                "\(tekrarlayan.joined(separator: ", ")) için birden fazla satır var; "
                    + "her satışta üst üste stoktan düşer."
            ))
        }

        // Set kendi maliyet kalemi taşıyorsa bileşenlerle çakışabilir
        if draft.isBundle, !draft.components.isEmpty,
           draft.costLines(on: nil).contains(where: { $0.amount > 0 }) {
            out.append(ValidationIssue(
                .setMaliyetiCiftSayim, .uyari,
                "Setin kendi maliyet kalemi var",
                "Bu setin bileşenlerinin maliyeti zaten ayrı ayrı hesaplanıyor. Buraya "
                    + "yalnızca sete özel ek maliyet (ör. paketleme işçiliği) yaz; "
                    + "bileşen maliyetlerini tekrar yazma."
            ))
        }
        return out
    }

    // MARK: - Kanal ayarı (Kural 11)

    public static func channel(_ draft: Channel) -> [ValidationIssue] {
        var out: [ValidationIssue] = []
        let toplamOran = draft.commissionPct + draft.paymentPct + draft.otherDeductionPct
        if draft.commissionPct < 0 || draft.paymentPct < 0 || draft.otherDeductionPct < 0 {
            out.append(ValidationIssue(.gecersizOran, .engel,
                "Oran eksi olamaz", "Komisyon ve kesinti oranları sıfırdan küçük olamaz."))
        }
        if toplamOran > 100 {
            out.append(ValidationIssue(.gecersizOran, .engel,
                "Kesinti oranı %100'ü aşıyor",
                "Toplam kesinti oranı \(Money.formatPercent(toplamOran)). "
                    + "Satışın tamamından fazlasını kesemezsin."))
        } else if toplamOran > 50 {
            out.append(ValidationIssue(.gecersizOran, .uyari,
                "Kesinti oranı alışılmadık derecede yüksek",
                "Toplam \(Money.formatPercent(toplamOran)) kesinti giriyorsun. Doğru mu?"))
        }
        if draft.shippingPerOrder < 0 || draft.serviceFeePerOrder < 0
            || draft.platformFeeMonthly < 0 || draft.otherDeductionMonthly < 0 {
            out.append(ValidationIssue(.gecersizTutar, .engel,
                "Tutar eksi olamaz", "Kesinti tutarları sıfırdan küçük olamaz."))
        }
        return out
    }
}

// MARK: - Gider (Kural 3, 4, 5, 11)

public extension Validation {

    static func expense(_ draft: Expense, state: AppState, editingId: Id? = nil) -> [ValidationIssue] {
        var out: [ValidationIssue] = []

        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(ValidationIssue(.eksikBilgi, .engel,
                "Gider adı boş", "Neyin gideri olduğunu yaz."))
        }
        if draft.amount < 0 {
            out.append(ValidationIssue(.gecersizTutar, .engel,
                "Tutar eksi olamaz", "Gider tutarı sıfırdan küçük olamaz."))
        } else if draft.amount == 0 {
            out.append(ValidationIssue(.gecersizTutar, .engel,
                "Tutar girilmedi", "Sıfır tutarlı gider kaydedilmez."))
        }

        out += invoiceDuplicates(invoiceNo: draft.invoiceNo, vendor: draft.vendor, state: state,
                                 excludingExpense: editingId, excludingPurchase: nil)

        // Aynı tarih + tutar + benzer ad (Kural 3 ve 11)
        let ad = normalized(draft.name)
        let benzerGider = state.expenses.first {
            $0.id != editingId && $0.amount == draft.amount && $0.date == draft.date
                && normalized($0.name) == ad
        }
        if let benzerGider {
            out.append(ValidationIssue(
                .mukerrerFatura, .uyari,
                "Bu gider zaten girilmiş",
                "\(Dates.displayDate(benzerGider.date)) tarihli \(Money.format(benzerGider.amount)) "
                    + "tutarında \"\(benzerGider.name)\" gideri zaten var. İki farklı gerçek "
                    + "fatura olabilir; aynıysa ikinci kez ekleme."
            ))
        }

        // Aynı faturanın stok alımı olarak girilmiş olması (Kural 3)
        let benzerAlim = state.purchases.first {
            $0.landedTotal == draft.amount && $0.date == draft.date && !$0.excludeFromExpenses
        }
        if let benzerAlim {
            out.append(ValidationIssue(
                .mukerrerFatura, .uyari,
                "Bu tutar stok alımı olarak zaten girilmiş",
                "\(Dates.displayDate(benzerAlim.date)) tarihinde \(state.itemName(benzerAlim.item)) "
                    + "için \(Money.format(benzerAlim.landedTotal)) tutarında stok alımı var. "
                    + "Stok alımları giderlere kendiliğinden yazılır; buradan tekrar ekleme."
            ))
        }

        // Aynı ay için aynı sabit gider (Kural 4)
        if let ad, draft.recurrence == .tek {
            let ay = Dates.month(of: draft.date)
            let duzenli = Engine(state).expenseInstances(month: ay).first {
                $0.sourceKind == .duzenli && normalized($0.name) == ad && $0.templateId != editingId
            }
            if let duzenli {
                out.append(ValidationIssue(
                    .sabitGiderTekrari, .uyari,
                    "Bu ay için aynı sabit gider zaten var",
                    "\"\(duzenli.name)\" \(Money.format(duzenli.amount)) olarak "
                        + "\(Dates.displayMonth(ay)) ayına zaten düzenli gider olarak eklenmiş. "
                        + "Yine de eklemek istiyor musun?"
                ))
            }
        }

        // Kanalın otomatik hesapladığı kalemi elle girme (Kural 5)
        if let chId = draft.scope.channelId, let ch = state.channel(chId) {
            let otomatik: String?
            switch draft.category {
            case .kargo:
                otomatik = (ch.shippingPerOrder > 0 || ch.serviceFeePerOrder > 0) ? "kargo ve hizmet bedeli" : nil
            case .komisyon:
                otomatik = (ch.commissionPct > 0 || ch.paymentPct > 0) ? "komisyon" : nil
            default:
                otomatik = nil
            }
            if let otomatik {
                out.append(ValidationIssue(
                    .kanalKesintisiCiftSayim, .uyari,
                    "\(ch.name) \(otomatik) zaten otomatik hesaplanıyor",
                    "Bu kalemi buradan girersen otomatik hesabın üstüne eklenir ve iki kez düşülür. "
                        + "Gerçek tutarı kullanmak istiyorsan \(ch.name) kartından "
                        + "\"Gerçek kesintileri gir\" ile gir — o zaman otomatik hesap devre dışı kalır."
                ))
            }
        }
        return out
    }

    // MARK: - Stok alımı (Kural 2, 3, 11)

    static func purchase(_ draft: StockPurchase, state: AppState, editingId: Id? = nil) -> [ValidationIssue] {
        var out: [ValidationIssue] = []

        guard state.itemExists(draft.item) else {
            return [ValidationIssue(.eksikBilgi, .engel, "Kalem seçilmedi",
                                    "Hangi ürün veya malzeme için alım yaptığını seç.")]
        }
        if draft.qty <= 0 {
            out.append(ValidationIssue(.gecersizMiktar, .engel,
                "Miktar girilmedi", "Sıfır veya eksi miktarla stok alımı kaydedilmez."))
        }
        if draft.totalPaid < 0 || draft.shippingCost < 0 {
            out.append(ValidationIssue(.gecersizTutar, .engel,
                "Tutar eksi olamaz", "Ödenen tutar sıfırdan küçük olamaz."))
        } else if draft.landedTotal == 0 && draft.qty > 0 {
            out.append(ValidationIssue(.gecersizTutar, .uyari,
                "Ödenen tutar girilmedi",
                "Bu alım stoğa eklenecek ama birim maliyeti sıfır olacak; ürün maliyetin eksik çıkar."))
        }
        if let base = Units.toBaseOrNil(qty: draft.qty, unit: draft.unit,
                                        baseUnit: state.itemBaseUnit(draft.item),
                                        packSizes: state.itemPackSizes(draft.item)), base == 0,
           draft.qty > 0 {
            out.append(ValidationIssue(.gecersizMiktar, .engel,
                "Birim karşılığı tanımsız",
                "1 \(draft.unit.displayName) kaç \(state.itemBaseUnit(draft.item).displayName) "
                    + "eder tanımlı değil. Malzeme ayarlarından gir."))
        }

        out += invoiceDuplicates(invoiceNo: draft.invoiceNo, vendor: draft.vendor, state: state,
                                 excludingExpense: nil, excludingPurchase: editingId)

        // Aynı kalem, aynı tarih, aynı tutar (Kural 3, 11)
        if let benzer = state.purchases.first(where: {
            $0.id != editingId && $0.item == draft.item && $0.date == draft.date
                && $0.landedTotal == draft.landedTotal && draft.landedTotal > 0
        }) {
            out.append(ValidationIssue(
                .mukerrerFatura, .uyari,
                "Aynı tarih ve tutarda bir alım daha var",
                "\(Dates.displayDate(benzer.date)) tarihinde \(state.itemName(benzer.item)) için "
                    + "\(Money.format(benzer.landedTotal)) tutarında alım kaydın var."
            ))
        }

        // Başlangıç stoğunun ikinci kez alım olarak girilmesi (Kural 2)
        out += openingStockConflict(draft, state: state, editingId: editingId)
        return out
    }

    /// Elde zaten başlangıç stoğu olarak girilmiş miktar, tekrar alım gibi giriliyorsa
    static func openingStockConflict(_ draft: StockPurchase, state: AppState,
                                     editingId: Id?) -> [ValidationIssue] {
        let acilis: BaseQty?
        switch draft.item.kind {
        case .material: acilis = state.material(draft.item.id)?.openingQty
        case .product: acilis = state.product(draft.item.id)?.openingQty
        }
        guard let acilis, acilis > 0 else { return [] }

        let baskaAlimVar = state.purchases.contains { $0.id != editingId && $0.item == draft.item }
        guard !baskaAlimVar else { return [] }

        guard let base = Units.toBaseOrNil(qty: draft.qty, unit: draft.unit,
                                            baseUnit: state.itemBaseUnit(draft.item),
                                            packSizes: state.itemPackSizes(draft.item)),
              abs(base - acilis) < max(acilis * 0.05, 1) else { return [] }

        let birim = state.itemBaseUnit(draft.item)
        return [ValidationIssue(
            .baslangicStoguTekrarAlim, .uyari,
            "Bu miktar başlangıç stoğu olarak zaten girilmiş",
            "\(state.itemName(draft.item)) için kurulumda "
                + "\(Units.formatQty(acilis, baseUnit: birim)) başlangıç stoğu girmiştin. "
                + "Aynı malı ikinci kez alım olarak girersen stok iki katına çıkar ve "
                + "bu ay olmayan bir nakit çıkışı oluşur. Gerçekten yeni bir alım mı?"
        )]
    }

    // MARK: - Satış (Kural 9, 10, 11)

    static func sale(_ draft: SalesEntry, state: AppState, editingId: Id? = nil) -> [ValidationIssue] {
        var out: [ValidationIssue] = []

        guard state.product(draft.productId) != nil else {
            return [ValidationIssue(.eksikBilgi, .engel, "Ürün seçilmedi", "Hangi ürünü sattığını seç.")]
        }
        if draft.qty < 0 || draft.returnsQty < 0 {
            out.append(ValidationIssue(.gecersizMiktar, .engel,
                "Adet eksi olamaz", "Satılan veya iade edilen adet sıfırdan küçük olamaz."))
        }
        if draft.qty == 0 && draft.grossSales == 0 {
            out.append(ValidationIssue(.eksikBilgi, .engel,
                "Adet ve tutar girilmedi", "En az satılan adedi veya toplam satışı gir."))
        }
        if draft.grossSales < 0 || draft.discount < 0 || draft.returnsAmount < 0 {
            out.append(ValidationIssue(.gecersizTutar, .engel,
                "Tutar eksi olamaz", "Satış, indirim ve iade tutarları sıfırdan küçük olamaz."))
        }
        if draft.returnsQty > draft.qty, draft.qty > 0 {
            out.append(ValidationIssue(.gecersizMiktar, .engel,
                "İade adedi satıştan fazla",
                "\(Int(draft.qty)) adet satıp \(Int(draft.returnsQty)) adet iade alamazsın."))
        }
        if draft.discount + draft.returnsAmount > draft.grossSales, draft.grossSales > 0 {
            out.append(ValidationIssue(.gecersizTutar, .engel,
                "İndirim ve iade satıştan fazla",
                "İndirim + iade toplamı \(Money.format(draft.discount + draft.returnsAmount)), "
                    + "satış \(Money.format(draft.grossSales)). Net satış eksi çıkar."))
        }

        // Aynı ay, aynı kanal, aynı ürün (Kural 11)
        if let benzer = state.sales.first(where: {
            $0.id != editingId && $0.month == draft.month && $0.channelId == draft.channelId
                && $0.productId == draft.productId
        }) {
            out.append(ValidationIssue(
                .mukerrerFatura, .uyari,
                "Bu ay için aynı satır zaten var",
                "\(Dates.displayMonth(draft.month)) ayında "
                    + "\(state.channel(draft.channelId)?.name ?? "bu kanal") için "
                    + "\(state.product(draft.productId)?.name ?? "bu ürün") satışı zaten girilmiş "
                    + "(\(Int(benzer.qty)) adet). Ay toplamını ikinci kez girersen satışlar iki katına çıkar."
            ))
        }

        // Stok eksiye düşüyor mu (Kural 10)
        var sonra = state
        if let i = sonra.sales.firstIndex(where: { $0.id == editingId ?? draft.id }) {
            sonra.sales[i] = draft
        } else {
            sonra.sales.append(draft)
        }
        out += stockIssues(before: state, after: sonra)
        return out
    }

    // MARK: - Stok düzeltme (Kural 10, 11)

    static func adjustment(_ draft: StockAdjustment, state: AppState,
                           editingId: Id? = nil) -> [ValidationIssue] {
        var out: [ValidationIssue] = []
        guard state.itemExists(draft.item) else {
            return [ValidationIssue(.eksikBilgi, .engel, "Kalem seçilmedi", "Hangi kalemi düzelttiğini seç.")]
        }
        if draft.qty <= 0 {
            out.append(ValidationIssue(.gecersizMiktar, .engel,
                "Miktar girilmedi", "Sıfır veya eksi miktarla düzeltme kaydedilmez."))
        }
        var sonra = state
        if let i = sonra.adjustments.firstIndex(where: { $0.id == editingId ?? draft.id }) {
            sonra.adjustments[i] = draft
        } else {
            sonra.adjustments.append(draft)
        }
        out += stockIssues(before: state, after: sonra)
        return out
    }

    // MARK: - Fatura numarası çakışması

    /// Aynı fatura numarası VE aynı tedarikçi kesin engeldir.
    /// Numara aynı ama tedarikçi farklı/bilinmiyorsa yalnızca uyarı verilir —
    /// farklı firmalar aynı numarayı kullanabilir.
    static func invoiceDuplicates(invoiceNo: String?, vendor: String?, state: AppState,
                                  excludingExpense: Id?, excludingPurchase: Id?) -> [ValidationIssue] {
        guard let no = normalized(invoiceNo) else { return [] }
        let tedarikci = normalized(vendor)

        func sorun(_ nerede: String, _ tarih: DateKey, _ karsiTedarikci: String?) -> ValidationIssue {
            let ayniTedarikci = tedarikci != nil && karsiTedarikci != nil && tedarikci == karsiTedarikci
            if ayniTedarikci {
                return ValidationIssue(
                    .mukerrerFatura, .engel,
                    "Bu fatura zaten kayıtlı",
                    "\(no.uppercased()) numaralı \(vendor ?? "") faturası \(nerede) olarak "
                        + "\(Dates.displayDate(tarih)) tarihinde girilmiş. Aynı faturayı ikinci kez "
                        + "kaydedemezsin.",
                    overridable: false
                )
            }
            return ValidationIssue(
                .mukerrerFatura, .uyari,
                "Aynı fatura numarası başka bir kayıtta var",
                "\(no.uppercased()) numarası \(nerede) olarak \(Dates.displayDate(tarih)) "
                    + "tarihinde kullanılmış. Tedarikçiler farklıysa sorun yok; aynı faturaysa "
                    + "ikinci kez girme."
            )
        }

        if let g = state.expenses.first(where: {
            $0.id != excludingExpense && normalized($0.invoiceNo) == no
        }) {
            return [sorun("\"\(g.name)\" gideri", g.date, normalized(g.vendor))]
        }
        if let p = state.purchases.first(where: {
            $0.id != excludingPurchase && normalized($0.invoiceNo) == no
        }) {
            return [sorun("\(state.itemName(p.item)) alımı", p.date, normalized(p.vendor))]
        }
        return []
    }
}

// MARK: - Kayıt öncesi özet (Kural 12)

public extension Validation {

    static func purchaseSummary(_ draft: StockPurchase, state: AppState) -> SaveSummary {
        guard state.itemExists(draft.item) else { return SaveSummary(lines: []) }
        let birim = state.itemBaseUnit(draft.item)
        let base = Units.toBaseOrNil(qty: draft.qty, unit: draft.unit,
                                     baseUnit: birim,
                                     packSizes: state.itemPackSizes(draft.item)) ?? 0
        let net = draft.landedSplit.net
        var lines = ["+\(Units.formatQty(base, baseUnit: birim)) \(state.itemName(draft.item))"]
        if draft.landedTotal > 0 {
            lines.append("\(Money.format(draft.landedTotal)) nakit çıkışı")
        }
        if draft.resolvedVatRate != .yok, draft.landedTotal > 0 {
            lines.append("\(Money.format(draft.landedTotal)) KDV "
                + (draft.resolvedVatIncluded ? "dahil" : "hariç")
                + " → \(Money.format(net)) net + "
                + "\(Money.format(draft.landedSplit.vat)) KDV")
        }
        if base > 0, net > 0 {
            let birimMaliyet = Money.roundHalfAwayFromZero(Double(net) / base)
            lines.append("\(Money.format(birimMaliyet)) / \(birim.displayName) maliyet"
                         + (draft.resolvedVatRate == .yok ? "" : " (KDV hariç)"))
        }
        if draft.resolvedVatRate != .yok, draft.landedSplit.vat > 0 {
            lines.append("\(Money.format(draft.landedSplit.vat)) indirilecek KDV")
        }
        return SaveSummary(
            lines: lines,
            note: draft.excludeFromExpenses
                ? "Bu alım giderlere yazılmayacak."
                : "Bu ayın kârına doğrudan \(Money.format(net)) gider yazılmayacak; "
                  + "ürün satıldıkça maliyet olarak yansıyacak."
        )
    }

    static func saleSummary(_ draft: SalesEntry, state: AppState) -> SaveSummary {
        guard let p = state.product(draft.productId) else { return SaveSummary(lines: []) }
        let e = Engine(state)
        let maliyet = e.cost(of: draft.productId, asOf: Dates.monthEnd(draft.month))
        let bolum = draft.vatSplit
        var lines = ["\(Int(draft.qty)) adet \(p.name) satışı"]
        lines.append("\(Money.format(bolum.net)) gerçek satış"
                     + (draft.resolvedVatRate == .yok ? "" : " (KDV hariç)"))
        if bolum.vat > 0 { lines.append("\(Money.format(bolum.vat)) hesaplanan KDV") }

        let leaves = Costing.explodeToLeafProducts(
            products: Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            productId: draft.productId, qty: draft.qty
        )
        let urunler = leaves.compactMap { id, adet -> String? in
            guard let l = state.product(id), l.tracksOwnStock else { return nil }
            return "\(l.name) −\(Int(adet))"
        }.sorted()
        if !urunler.isEmpty { lines.append("Stoktan: " + urunler.joined(separator: ", ")) }
        let dusecek = p.recipe.filter(\.resolvedConsumesStock).count
        if dusecek > 0 { lines.append("Ayrıca \(dusecek) paketleme malzemesi düşecek") }

        let toplamMaliyet = Money.roundHalfAwayFromZero(Double(maliyet.intrinsic) * draft.netQty)
            + Money.roundHalfAwayFromZero(Double(maliyet.packaging) * draft.qty)
        if toplamMaliyet > 0 {
            lines.append("\(Money.format(toplamMaliyet)) ürün + ambalaj maliyeti")
        }
        return SaveSummary(lines: lines, note: nil)
    }

    static func expenseSummary(_ draft: Expense, state: AppState) -> SaveSummary {
        let bolum = Vat.split(draft.amount, rate: draft.resolvedVatRate,
                              included: draft.resolvedVatIncluded)
        var lines = ["\(Money.format(draft.amount)) nakit çıkışı"]
        if draft.resolvedVatRate != .yok, draft.amount > 0 {
            lines.append("\(Money.format(draft.amount)) KDV "
                + (draft.resolvedVatIncluded ? "dahil" : "hariç")
                + " → \(Money.format(bolum.net)) net + \(Money.format(bolum.vat)) KDV")
        }
        if bolum.vat > 0 {
            lines.append("\(Money.format(bolum.net)) kâra gider (KDV hariç)")
            lines.append("\(Money.format(bolum.vat)) indirilecek KDV")
        } else {
            lines.append("\(Money.format(bolum.net)) kâra gider")
        }
        if draft.recurrence == .aylik {
            lines.append("Her ay otomatik eklenecek")
        } else if draft.recurrence == .yillik {
            lines.append("Her yıl otomatik eklenecek")
        }
        let not = draft.scope.channelId.flatMap { state.channel($0)?.name }
            .map { "Yalnızca \($0) kârlılığından düşülecek." }
        return SaveSummary(lines: lines, note: not)
    }
}

// MARK: - Ad kontrolü

/// Yeni ürün, malzeme, kanal veya kesinti adı girilirken kullanılır.
/// Türkçe büyük/küçük harf kuralları gözetilir: "ŞAMPUAN" ile "şampuan" aynıdır.
public enum NameCheck {
    /// Karşılaştırma için sadeleştirilmiş hâl
    public static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "tr_TR"))
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    public static func isBlank(_ name: String) -> Bool { key(name).isEmpty }

    public static func isDuplicate(_ name: String, among others: [String]) -> Bool {
        let k = key(name)
        guard !k.isEmpty else { return false }
        return others.contains { key($0) == k }
    }

    /// Kaydedilebilir mi; değilse sebebi.
    public static func issue(_ name: String, among others: [String]) -> ValidationIssue? {
        if isBlank(name) {
            return ValidationIssue(.eksikBilgi, .engel, "Ad girilmedi",
                                   "Devam etmek için bir ad yazman gerekiyor.")
        }
        if isDuplicate(name, among: others) {
            return ValidationIssue(.eksikBilgi, .engel, "Bu kayıt zaten var.",
                                   "Aynı adla bir kayıt bulunuyor. Farklı bir ad yaz "
                                       + "veya mevcut kaydı düzenle.")
        }
        return nil
    }
}
