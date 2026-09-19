import SwiftUI
import MirissaCore

// MARK: - Stok satın alma

struct PurchaseForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var preselected: ItemRef?
    var editingId: Id?

    @State private var item: ItemRef?
    @State private var date: DateKey = Dates.today()
    @State private var qty: Double = 0
    @State private var unit: UnitCode = .adet
    @State private var paid: Kurus = 0
    @State private var shipping: Kurus = 0
    @State private var vendor = ""
    @State private var excludeFromExpenses = false
    @State private var invoiceNo = ""
    @State private var vatRate: VatRate = .yirmi
    @State private var vatIncluded = true
    @State private var picked: PickedFile?
    @State private var invoiceRemoved = false
    @State private var loaded = false

    init(preselected: ItemRef? = nil) {
        self.preselected = preselected
        self.editingId = nil
    }

    init(editing id: Id) {
        self.preselected = nil
        self.editingId = id
    }

    private var baseUnit: UnitCode { item.map { store.state.itemBaseUnit($0) } ?? .adet }
    private var packSizes: [UnitCode: Double] { item.map { store.state.itemPackSizes($0) } ?? [:] }
    private var allowedUnits: [UnitCode] { Units.allowedUnits(baseUnit: baseUnit, packSizes: packSizes) }

    private var baseQty: Double {
        guard let item else { return 0 }
        return Units.toBaseOrNil(qty: qty, unit: unit,
                                 baseUnit: store.state.itemBaseUnit(item),
                                 packSizes: store.state.itemPackSizes(item)) ?? 0
    }

    /// Stok maliyeti KDV hariç tutulur
    private var netTotal: Kurus {
        store.state.settings.vatEnabled
            ? Vat.net(paid + shipping, rate: vatRate, included: vatIncluded)
            : paid + shipping
    }

    private var unitCost: Kurus {
        baseQty > 0 ? Money.roundHalfAwayFromZero(Double(netTotal) / baseQty) : 0
    }

    /// Alım sonrası oluşacak yeni ağırlıklı ortalama maliyet
    private var newAverage: Kurus {
        guard let item, baseQty > 0 else { return 0 }
        // Düzenlenen alım mevcut stokta zaten var: onsuz bakiyeye eklenir (iki kez sayılmasın)
        var s = store.state
        if let id = editingId { s.purchases.removeAll { $0.id == id } }
        let b = editingId == nil ? store.engine.balance(item) : Engine(s).balance(item)
        let existingQty = max(b.qty, 0)
        let total = Double(b.value) + Double(netTotal)
        return Money.roundHalfAwayFromZero(total / (existingQty + baseQty))
    }

    var body: some View {
        FormShell(
            title: editingId == nil ? "Stok Satın Al" : "Alımı Düzenle",
            canSave: item != nil && qty > 0,
            issues: { taslak.map { Validation.purchase($0, state: store.state, editingId: editingId) } ?? [] },
            summary: { taslak.map { Validation.purchaseSummary($0, state: store.state) }
                       ?? SaveSummary(lines: []) },
            onSave: save
        ) {
            Section {
                ItemPicker(label: "Malzeme / ürün", selection: $item)
                DateRow(dateKey: $date)
            }

            Section {
                QtyField("Miktar", value: $qty)
                Picker("Birim", selection: $unit) {
                    ForEach(allowedUnits) { u in Text(u.displayName).tag(u) }
                }
                MoneyField("Ödenen toplam", value: $paid)
                MoneyField("Nakliye / kargo", value: $shipping)
                TextField("Satıcı (isteğe bağlı)", text: $vendor)
                TextField("Fatura no (isteğe bağlı)", text: $invoiceNo)
            }

            if baseQty > 0, paid + shipping > 0 {
                Section("Sistem hesaplıyor") {
                    LabeledRow("1 \(baseUnit.displayName) maliyeti", unitCost.tl, tone: Palette.accent, strong: true)
                    if let item {
                        LabeledRow("Stoğa eklenecek",
                                   Units.formatQty(baseQty, baseUnit: store.state.itemBaseUnit(item)))
                        LabeledRow("Yeni ortalama maliyet", newAverage.tl)
                    }
                }
            }

            Section {
                Toggle("Giderlere yazılmasın", isOn: $excludeFromExpenses)
            } footer: {
                Text(excludeFromExpenses
                     ? "Yalnızca stok artar. Nakit çıkışına ve indirilecek KDV'ye girmez — "
                       + "bedelsiz gelen ya da parası başka yerde takip edilen mal için."
                     : "Bu alım giderlere otomatik yazılır. Stoğa girdiği için kârdan doğrudan düşülmez; ürün satıldıkça maliyet olarak yansır.")
            }

            VatSection(rate: $vatRate, included: $vatIncluded, amount: paid + shipping, label: "Ödenen tutar")

            InvoiceSection(
                current: editingId.flatMap { id in store.state.purchases.first { $0.id == id }?.attachment },
                picked: $picked, removed: $invoiceRemoved
            )

            if let id = editingId {
                Section {
                    Button(role: .destructive) { store.deletePurchase(id); dismiss() } label: {
                        Label("Alımı sil", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: item) { _, _ in
            if !allowedUnits.contains(unit) { unit = baseUnit }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = editingId, let p = store.state.purchases.first(where: { $0.id == id }) {
            item = p.item; date = p.date; qty = p.qty; unit = p.unit
            paid = p.totalPaid; shipping = p.shippingCost; vendor = p.vendor ?? ""
            excludeFromExpenses = p.excludeFromExpenses
            vatRate = p.resolvedVatRate
            vatIncluded = p.resolvedVatIncluded
            invoiceNo = p.invoiceNo ?? ""
        } else {
            item = preselected
            unit = preselected.map { store.state.itemBaseUnit($0) } ?? .adet
            vatRate = store.state.settings.vatEnabled ? store.state.settings.defaultVatRate : .yok
            vatIncluded = store.state.settings.defaultVatIncluded
        }
    }

    /// Düzenlenen alım: KDV takibi kapalıyken bile kendi KDV bilgisi korunur
    private var mevcutKayit: StockPurchase? {
        editingId.flatMap { id in store.state.purchases.first { $0.id == id } }
    }

    private var taslak: StockPurchase? {
        guard let item else { return nil }
        return StockPurchase(
            id: editingId ?? "taslak",
            date: date, item: item, qty: qty, unit: unit,
            totalPaid: paid, shippingCost: shipping,
            vendor: vendor.isEmpty ? nil : vendor,
            excludeFromExpenses: excludeFromExpenses,
            invoiceNo: invoiceNo.isEmpty ? nil : invoiceNo,
            vatRate: store.state.settings.vatEnabled ? vatRate : mevcutKayit?.vatRate,
            vatIncluded: store.state.settings.vatEnabled ? vatIncluded : mevcutKayit?.vatIncluded
        )
    }

    private func save() {
        guard let item else { return }
        let mevcutEk = editingId.flatMap { id in store.state.purchases.first { $0.id == id }?.attachment }
        var p = StockPurchase(
            id: editingId ?? Ids.make(.purchase),
            date: date, item: item, qty: qty, unit: unit,
            totalPaid: paid, shippingCost: shipping,
            vendor: vendor.isEmpty ? nil : vendor,
            excludeFromExpenses: excludeFromExpenses,
            invoiceNo: invoiceNo.isEmpty ? nil : invoiceNo,
            attachment: invoiceRemoved ? nil : mevcutEk,
            vatRate: store.state.settings.vatEnabled ? vatRate : mevcutKayit?.vatRate,
            vatIncluded: store.state.settings.vatEnabled ? vatIncluded : mevcutKayit?.vatIncluded
        )
        // Düzenlerken vadeli ödeme planı korunur; tutar değiştiyse kalan taksitlere yansıtılır
        if let plan = mevcutKayit?.odeme {
            p.odeme = plan.tutariDuzelt(p.landedSplit.net + p.landedSplit.vat, bugun: Dates.today())
        }
        editingId == nil ? store.addPurchase(p) : store.updatePurchase(p)
        if let f = picked {
            store.attachInvoice(data: f.data, ext: f.ext, toPurchase: p.id)
        } else if invoiceRemoved {
            store.pruneAttachments()
        }
    }
}

// MARK: - Stok düzeltme (kırık, fire, numune...)

struct AdjustForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var preselected: ItemRef?
    var editingId: Id?
    @State private var item: ItemRef?
    @State private var date: DateKey = Dates.today()
    @State private var qty: Double = 0
    @State private var unit: UnitCode = .adet
    @State private var reason: AdjustReason = .hasarli
    @State private var isIncrease = false
    @State private var note = ""
    @State private var loaded = false

    init(preselected: ItemRef? = nil) {
        self.preselected = preselected
        self.editingId = nil
    }

    init(editing id: Id) {
        self.preselected = nil
        self.editingId = id
    }

    private var baseUnit: UnitCode { item.map { store.state.itemBaseUnit($0) } ?? .adet }
    private var allowedUnits: [UnitCode] {
        Units.allowedUnits(baseUnit: baseUnit, packSizes: item.map { store.state.itemPackSizes($0) } ?? [:])
    }

    private var baseQty: Double {
        guard let item else { return 0 }
        return Units.toBaseOrNil(qty: qty, unit: unit,
                                 baseUnit: store.state.itemBaseUnit(item),
                                 packSizes: store.state.itemPackSizes(item)) ?? 0
    }

    var body: some View {
        FormShell(title: editingId == nil ? "Stok Düzelt" : "Düzeltmeyi Değiştir",
                  canSave: item != nil && qty > 0,
                  issues: { taslak.map { Validation.adjustment($0, state: store.state,
                                                               editingId: editingId) } ?? [] },
                  onSave: save) {
            Section {
                ItemPicker(selection: $item)
                DateRow(dateKey: $date)
            }

            Section("Sebep") {
                Picker("Sebep", selection: $reason) {
                    ForEach(AdjustReason.userSelectable) { r in Text(r.displayName).tag(r) }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }

            Section {
                Picker("Yön", selection: $isIncrease) {
                    Text("Stoktan düş").tag(false)
                    Text("Stoğa ekle").tag(true)
                }
                .pickerStyle(.segmented)
                QtyField("Miktar", value: $qty)
                Picker("Birim", selection: $unit) {
                    ForEach(allowedUnits) { u in Text(u.displayName).tag(u) }
                }
            }

            if let item, baseQty > 0 {
                let current = store.engine.qty(item)
                let after = current + (isIncrease ? baseQty : -baseQty)
                Section("Sistem hesaplıyor") {
                    LabeledRow("Mevcut", Units.formatQty(current, baseUnit: baseUnit))
                    LabeledRow("İşlem sonrası", Units.formatQty(after, baseUnit: baseUnit),
                               tone: after < 0 ? Palette.zarar : Palette.accent, strong: true)
                }
            }

            Section {
                TextField("Not (isteğe bağlı)", text: $note)
            } footer: {
                Text("Bu işlem stok hareket geçmişine kaydedilir, sonradan görebilir ve düzeltebilirsin.")
            }

            if let id = editingId {
                Section {
                    Button(role: .destructive) { store.deleteAdjustment(id); dismiss() } label: {
                        Label("Düzeltmeyi sil", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = editingId, let a = store.state.adjustments.first(where: { $0.id == id }) {
                item = a.item; date = a.date; qty = a.qty; unit = a.unit
                isIncrease = a.isIncrease; reason = a.reason; note = a.note ?? ""
                return
            }
            item = preselected
            unit = preselected.map { store.state.itemBaseUnit($0) } ?? .adet
        }
        .onChange(of: item) { _, _ in if !allowedUnits.contains(unit) { unit = baseUnit } }
    }

    private var taslak: StockAdjustment? {
        guard let item else { return nil }
        return StockAdjustment(
            id: editingId ?? "taslak",
            date: date, item: item, qty: qty, unit: unit,
            isIncrease: isIncrease, reason: reason
        )
    }

    private func save() {
        guard let item else { return }
        let a = StockAdjustment(
            id: editingId ?? Ids.make(.adjustment),
            date: date, item: item, qty: qty, unit: unit,
            isIncrease: isIncrease, reason: reason,
            note: note.isEmpty ? nil : note
        )
        editingId == nil ? store.addAdjustment(a) : store.updateAdjustment(a)
    }
}

// MARK: - Stok sayımı

struct CountForm: View {
    @Environment(AppStore.self) private var store

    var preselected: ItemRef?
    @State private var item: ItemRef?
    @State private var date: DateKey = Dates.today()
    @State private var counted: Double = 0
    @State private var unit: UnitCode = .adet
    @State private var reason: AdjustReason = .sayimFarki
    @State private var note = ""
    @State private var loaded = false

    init(preselected: ItemRef? = nil) { self.preselected = preselected }

    private var baseUnit: UnitCode { item.map { store.state.itemBaseUnit($0) } ?? .adet }
    private var allowedUnits: [UnitCode] {
        Units.allowedUnits(baseUnit: baseUnit, packSizes: item.map { store.state.itemPackSizes($0) } ?? [:])
    }

    private var systemQty: Double { item.map { store.engine.qty($0) } ?? 0 }

    private var countedBase: Double {
        guard let item else { return 0 }
        return Units.toBaseOrNil(qty: counted, unit: unit,
                                 baseUnit: store.state.itemBaseUnit(item),
                                 packSizes: store.state.itemPackSizes(item)) ?? 0
    }

    private var fark: Double { countedBase - systemQty }

    var body: some View {
        FormShell(title: "Stok Sayımı", saveTitle: "Sayımı uygula", canSave: item != nil, onSave: save) {
            Section {
                ItemPicker(selection: $item)
                DateRow(dateKey: $date)
            }

            if item != nil {
                Section {
                    LabeledRow("Sisteme göre", Units.formatQty(systemQty, baseUnit: baseUnit))
                    QtyField("Gerçek sayım", value: $counted)
                    Picker("Birim", selection: $unit) {
                        ForEach(allowedUnits) { u in Text(u.displayName).tag(u) }
                    }
                }

                Section {
                    LabeledRow(
                        "FARK",
                        (fark > 0 ? "+" : "") + Units.formatQty(fark, baseUnit: baseUnit),
                        tone: fark == 0 ? Palette.inkSoft : (fark < 0 ? Palette.zarar : Palette.accent),
                        strong: true
                    )
                    if fark != 0 {
                        Picker("Fark sebebi", selection: $reason) {
                            Text("Sayım farkı").tag(AdjustReason.sayimFarki)
                            ForEach(AdjustReason.userSelectable) { r in Text(r.displayName).tag(r) }
                        }
                    }
                    TextField("Not (isteğe bağlı)", text: $note)
                } footer: {
                    Text("Sayımı uyguladığında stok, senin saydığın gerçek miktara sabitlenir. Birim maliyet değişmez. Sayım ait olduğu ayın son sözüdür: o ayın satışları düşüldükten sonra uygulanır.")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            item = preselected
            unit = preselected.map { store.state.itemBaseUnit($0) } ?? .adet
            counted = preselected.map { store.engine.qty($0) } ?? 0
        }
        .onChange(of: item) { _, new in
            if !allowedUnits.contains(unit) { unit = baseUnit }
            counted = new.map { store.engine.qty($0) } ?? 0
        }
    }

    private func save() {
        guard let item else { return }
        store.addCount(StockCount(
            date: date, item: item, countedQty: counted, unit: unit,
            reason: fark == 0 ? nil : reason,
            note: note.isEmpty ? nil : note
        ))
    }
}
