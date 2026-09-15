import SwiftUI
import MirissaCore

struct ExpenseForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editingId: Id?
    var contextMonth: MonthKey

    @State private var date: DateKey = Dates.today()
    @State private var name = ""
    @State private var amount: Kurus = 0
    @State private var category: ExpenseCategory = .diger
    @State private var scopeId: String = "ortak"
    @State private var recurrence: Recurrence = .tek
    @State private var behavior: CostBehavior = .sabit
    @State private var behaviorTouched = false
    @State private var invoiceNo = ""
    @State private var vatRate: VatRate = .yirmi
    @State private var vatIncluded = true
    @State private var picked: PickedFile?
    @State private var invoiceRemoved = false
    @State private var loaded = false
    @State private var showStopConfirm = false
    @State private var showDeleteConfirm = false
    @State private var onlyThisMonth = false

    init(month: MonthKey) {
        self.editingId = nil
        self.contextMonth = month
        self._date = State(initialValue: month == Dates.currentMonth()
                           ? Dates.today() : Dates.monthStart(month))
    }

    init(editing id: Id, month: MonthKey) {
        self.editingId = id
        self.contextMonth = month
    }

    private var editing: Expense? {
        editingId.flatMap { id in store.state.expenses.first { $0.id == id } }
    }

    var body: some View {
        FormShell(
            title: editingId == nil ? "Gider Ekle" : "Gideri Düzenle",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && amount != 0,
            issues: { Validation.expense(taslak, state: store.state, editingId: editingId) },
            summary: { Validation.expenseSummary(taslak, state: store.state) },
            onSave: save
        ) {
            Section {
                DateRow(dateKey: $date)
                TextField("Gider adı", text: $name)
                MoneyField("Tutar", value: $amount)
            }

            Section {
                Picker("Kategori", selection: $category) {
                    ForEach(ExpenseCategory.userSelectable) { c in
                        Label(c.displayName, systemImage: c.symbolName).tag(c)
                    }
                }
                .onChange(of: category) { _, yeni in
                    if !behaviorTouched { behavior = yeni.defaultBehavior }
                }
            }

            Section {
                Picker("Tekrar", selection: $recurrence) {
                    ForEach(Recurrence.allCases) { r in Text(r.displayName).tag(r) }
                }
                .pickerStyle(.segmented)
                if editing?.isRecurring == true {
                    Toggle("Sadece bu ayın tutarını değiştir", isOn: $onlyThisMonth)
                }
            } footer: {
                if recurrence == .aylik {
                    Text("Bir kez gir, her ay otomatik eklensin. İstediğin zaman durdurabilirsin.")
                } else if editing?.isRecurring == true && onlyThisMonth {
                    Text("Sadece \(Dates.displayMonth(contextMonth)) ayı değişir, diğer aylar aynı kalır.")
                }
            }

            if let e = editing, e.isRecurring {
                Section {
                    if e.isStopped {
                        LabeledRow("Durum", "\(Dates.displayMonth(e.endMonth!)) sonunda durduruldu", tone: Palette.uyari)
                        Button("Tekrar başlat") { store.resumeExpense(e.id); dismiss() }
                    } else {
                        Button("Bu aydan sonra durdur") { showStopConfirm = true }
                            .foregroundStyle(Palette.uyari)
                    }
                } footer: {
                    Text("Durdurmak geçmiş ayları bozmaz; sadece sonraki aylarda görünmez.")
                }
            }

            Section {
                DisclosureGroup("Gelişmiş") {
                    Picker("Hangi bölüme ait?", selection: $scopeId) {
                        Text("Ortak şirket gideri").tag("ortak")
                        ForEach(store.state.activeChannels) { c in Text(c.name).tag(c.id) }
                    }
                    Picker("Satış arttıkça artar mı?", selection: $behavior) {
                        ForEach(CostBehavior.allCases) { b in Text(b.displayName).tag(b) }
                    }
                    .onChange(of: behavior) { _, _ in behaviorTouched = true }
                    VatSection(rate: $vatRate, included: $vatIncluded, amount: amount,
                               asSection: false)
                    TextField("Fatura no (isteğe bağlı)", text: $invoiceNo)
                }
            } footer: {
                Text("Varsayılanlar çoğu gider için doğrudur; gerekmedikçe açman gerekmez.")
            }

            InvoiceSection(current: mevcutFatura, picked: $picked, removed: $invoiceRemoved)

            if editingId != nil {
                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Gideri sil", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Bu gider \(Dates.displayMonth(contextMonth)) ayından sonra eklenmesin mi?",
                            isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("Durdur") {
                store.stopExpense(editingId!, lastMonth: contextMonth)
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog(editing?.isRecurring == true
                            ? "Bu düzenli gider geçmiş aylardan da silinecek. Onun yerine durdurmak ister misin?"
                            : "Bu gider silinsin mi?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            if editing?.isRecurring == true {
                Button("Durdur (geçmiş korunur)") {
                    store.stopExpense(editingId!, lastMonth: contextMonth)
                    dismiss()
                }
            }
            Button("Tamamen sil", role: .destructive) {
                store.deleteExpense(editingId!)
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let e = editing else {
            vatRate = store.state.settings.vatEnabled ? store.state.settings.defaultVatRate : .yok
            vatIncluded = store.state.settings.defaultVatIncluded
            return
        }
        date = e.date
        recurrence = e.recurrence
        category = e.category
        scopeId = e.scope.channelId ?? "ortak"
        behavior = e.resolvedBehavior
        behaviorTouched = e.behavior != nil
        vatRate = e.resolvedVatRate
        vatIncluded = e.resolvedVatIncluded
        invoiceNo = e.invoiceNo ?? ""
        let ov = e.overrides[contextMonth]
        name = ov?.name ?? e.name
        amount = ov?.amount ?? e.amount
        // Düzenli giderlerde varsayılan "sadece bu ay": geçmiş aylar kazara bozulmasın
        onlyThisMonth = e.isRecurring
    }

    private var taslak: Expense {
        Expense(
            id: editingId ?? "taslak",
            date: date, name: name, amount: amount, category: category,
            scope: scopeId == "ortak" ? .ortak : .channel(scopeId),
            recurrence: recurrence,
            invoiceNo: invoiceNo.isEmpty ? nil : invoiceNo,
            behavior: behavior,
            vatRate: store.state.settings.vatEnabled ? vatRate : nil,
            vatIncluded: store.state.settings.vatEnabled ? vatIncluded : nil
        )
    }

    private func save() {
        let scope: ExpenseScope = scopeId == "ortak" ? .ortak : .channel(scopeId)
        let hedefId: Id
        var ayaOzel = false

        if let e = editing {
            hedefId = e.id
            if e.isRecurring && onlyThisMonth {
                store.overrideExpense(e.id, month: contextMonth, amount: amount)
                ayaOzel = true
            } else {
                var updated = e
                updated.date = date
                updated.name = name
                updated.amount = amount
                updated.category = category
                updated.scope = scope
                updated.recurrence = recurrence
                updated.behavior = behavior
                updated.invoiceNo = invoiceNo.isEmpty ? nil : invoiceNo
                updated.vatRate = store.state.settings.vatEnabled ? vatRate : nil
                updated.vatIncluded = store.state.settings.vatEnabled ? vatIncluded : nil
                if !updated.isRecurring { updated.endMonth = nil; updated.overrides = [:] }
                store.updateExpense(updated)
            }
        } else {
            let yeni = Expense(
                id: Ids.make(.expense),
                date: date, name: name, amount: amount,
                category: category, scope: scope, recurrence: recurrence,
                invoiceNo: invoiceNo.isEmpty ? nil : invoiceNo,
                behavior: behavior,
                vatRate: store.state.settings.vatEnabled ? vatRate : nil,
                vatIncluded: store.state.settings.vatEnabled ? vatIncluded : nil
            )
            store.addExpense(yeni)
            hedefId = yeni.id
        }

        let ay: MonthKey? = ayaOzel ? contextMonth : nil
        if let p = picked {
            store.attachInvoice(data: p.data, ext: p.ext, toExpense: hedefId, month: ay)
        } else if invoiceRemoved {
            store.removeInvoice(fromExpense: hedefId, month: ay)
        }
    }

    /// Bu ay için geçerli fatura — düzenli giderde aya özel fatura önceliklidir
    private var mevcutFatura: String? {
        guard let e = editing else { return nil }
        return e.overrides[contextMonth]?.attachment ?? e.attachment
    }
}
