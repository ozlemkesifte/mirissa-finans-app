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
    @State private var vendor = ""
    @State private var vatRate: VatRate = .yirmi
    @State private var vatIncluded = true
    @State private var picked: PickedFile?
    @State private var invoiceRemoved = false
    @State private var loaded = false
    @State private var showStopConfirm = false
    @State private var showDeleteConfirm = false
    @State private var onlyThisMonth = false
    /// Düzenli giderin tamamı değiştirilirken geçmiş aylar da değişsin mi (varsayılan: hayır)
    @State private var gecmisDeDegissin = false
    /// Tek seferlik gider kâra kaç aya bölünerek yazılsın (1 = tamamı ödendiği ay)
    @State private var yayilanAy = 1

    private var yayilan: Int? { recurrence == .tek && yayilanAy > 1 ? yayilanAy : nil }

    /// Kâra her ay yazılan pay: KDV hariç tutarın 1/n'i
    private func aylikPay(_ n: Int) -> Kurus {
        let net = store.state.settings.vatEnabled
            ? Vat.net(amount, rate: vatRate, included: vatIncluded) : amount
        return Money.roundHalfAwayFromZero(Double(net) / Double(n))
    }
    private var kdvNotu: String {
        store.state.settings.vatEnabled && vatRate != .yok ? ", KDV hariç" : ""
    }

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

    /// Aya özel tutarın saklandığı ay: yıllık giderde o yılın ödeme ayı, tek seferlikte ödeme ayı
    private var hedefAy: MonthKey {
        guard let e = editing else { return contextMonth }
        switch e.recurrence {
        case .aylik: return contextMonth
        case .yillik:
            let k = max(Dates.monthsBetween(e.startMonth, contextMonth), 0)
            return Dates.addMonths(e.startMonth, (k / 12) * 12)
        case .tek: return e.startMonth
        }
    }

    /// "Bu aydan itibaren" değişikliğin başladığı ay. Yıllık giderde bu yılın ödemesi geçtiyse
    /// bir sonraki ödeme: yoksa bu yıl zaten ödenmiş tutar ve payları geriye dönük değişirdi.
    private var itibarenAy: MonthKey {
        guard editing?.recurrence == .yillik, contextMonth > hedefAy else { return hedefAy }
        return Dates.addMonths(hedefAy, 12)
    }

    /// Formu "sadece bu ay" ya da "giderin tamamı" değerleriyle doldurur
    private func degerleriYukle(_ e: Expense, ayaOzel: Bool) {
        let ov = ayaOzel ? e.overrides[hedefAy] : nil
        name = ov?.name ?? e.name
        amount = ov?.amount ?? e.amount
        vatRate = ov?.vatRate ?? e.resolvedVatRate
        vatIncluded = ov?.vatIncluded ?? e.resolvedVatIncluded
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
                if recurrence == .tek {
                    Picker("Kâra nasıl yazılsın?", selection: $yayilanAy) {
                        Text("Tamamı bu ay").tag(1)
                        ForEach([3, 6, 12, 24], id: \.self) { n in Text("\(n) aya böl").tag(n) }
                    }
                }
                if editing?.isRecurring == true && recurrence == editing?.recurrence {
                    Toggle(recurrence == .yillik ? "Sadece bu yılın tutarını değiştir" : "Sadece bu ayın tutarını değiştir",
                           isOn: $onlyThisMonth)
                        .onChange(of: onlyThisMonth) { _, yeni in
                            if let e = editing { degerleriYukle(e, ayaOzel: yeni) }
                        }
                    if !onlyThisMonth {
                        Toggle("Geçmiş aylar da değişsin", isOn: $gecmisDeDegissin)
                    }
                }
            } footer: {
                if recurrence != editing?.recurrence, editing?.isRecurring == true {
                    Text("Tekrar şekli değişince gider baştan bu şekilde hesaplanır (geçmiş aylar da).")
                } else if recurrence == .yillik {
                    Text("Yılda bir ödenen tutarı yaz. Kâra her ay 1/12'si yazılır (ayda \(aylikPay(12).tl)\(kdvNotu)); "
                         + "para ve KDV ödeme ayında (tarihteki ay) çıkar.")
                } else if recurrence == .aylik {
                    Text("Bir kez gir, her ay otomatik eklensin. İstediğin zaman durdurabilirsin.")
                } else if recurrence == .tek && yayilanAy > 1 {
                    Text("Kâra \(yayilanAy) ay boyunca her ay \(aylikPay(yayilanAy).tl)\(kdvNotu) yazılır; "
                         + "para ve KDV ödediğin ayda çıkar. Web sitesi, ekipman, yıllık yazılım gibi "
                         + "birkaç ay işine yarayan büyük harcamalar tek bir ayı zarara sokmasın diye.")
                } else if recurrence == .tek {
                    Text("Birkaç ay işine yarayacak büyük bir harcamaysa aylara bölmek başa baş hesabını gerçekçi yapar.")
                } else if editing?.isRecurring == true && onlyThisMonth {
                    Text(recurrence == .yillik
                         ? "Sadece \(Dates.displayMonth(hedefAy)) ödemesi (o yılın tutarı) değişir, diğer yıllar aynı kalır."
                         : "Sadece \(Dates.displayMonth(contextMonth)) ayı değişir, diğer aylar aynı kalır.")
                } else if let e = editing, e.isRecurring, !gecmisDeDegissin,
                          let son = e.endMonth, son < itibarenAy {
                    Text("Bu gider \(Dates.displayMonth(son)) sonunda durduruldu; sonrasında ayı yok. "
                         + "Tutar ve KDV değişikliği ancak \"Geçmiş aylar da değişsin\" açıkken uygulanır.")
                } else if editing?.isRecurring == true && !gecmisDeDegissin {
                    Text("Değişiklik \(Dates.displayMonth(itibarenAy)) ayından itibaren geçerli olur; önceki aylar olduğu gibi kalır.")
                } else if editing?.isRecurring == true {
                    Text("Bu giderin bütün ayları (geçmiş aylar dahil) yeni bilgilerle hesaplanır.")
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
                    TextField("Tedarikçi (isteğe bağlı)", text: $vendor)
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
        invoiceNo = e.invoiceNo ?? ""
        vendor = e.vendor ?? ""
        // Düzenli giderlerde varsayılan "sadece bu ay": geçmiş aylar kazara bozulmasın
        onlyThisMonth = e.isRecurring
        degerleriYukle(e, ayaOzel: e.isRecurring)
        yayilanAy = e.yayilanAy ?? 1
    }

    private var taslak: Expense {
        Expense(
            id: editingId ?? "taslak",
            date: date, name: name, amount: amount, category: category,
            scope: scopeId == "ortak" ? .ortak : .channel(scopeId),
            recurrence: recurrence,
            invoiceNo: invoiceNo.isEmpty ? nil : invoiceNo,
            vendor: vendor.isEmpty ? nil : vendor,
            behavior: behavior,
            vatRate: store.state.settings.vatEnabled ? vatRate : nil,
            vatIncluded: store.state.settings.vatEnabled ? vatIncluded : nil,
            yayilanAy: yayilan
        )
    }

    private func save() {
        let scope: ExpenseScope = scopeId == "ortak" ? .ortak : .channel(scopeId)
        var hedefId: Id
        var ayaOzel = false

        if let e = editing {
            hedefId = e.id
            if e.isRecurring && onlyThisMonth && recurrence == e.recurrence {
                // KDV bu ay farklı girildiyse o da aya özel saklanır
                let kdvFarkli = store.state.settings.vatEnabled
                    && (vatRate != e.resolvedVatRate || vatIncluded != e.resolvedVatIncluded)
                // Yıllık giderde tutar ödeme ayına bağlıdır: o yılın ödeme ayına yazılır
                store.overrideExpense(e.id, month: hedefAy, amount: amount,
                                      vatRate: kdvFarkli ? vatRate : nil,
                                      vatIncluded: kdvFarkli ? vatIncluded : nil)
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
                updated.vendor = vendor.isEmpty ? nil : vendor
                // KDV takibi kapalıyken düzenleme, kayıtta yazan KDV bilgisini silmez:
                // yoksa eski ayların kârı ve KDV'si kendiliğinden değişirdi.
                updated.vatRate = store.state.settings.vatEnabled ? vatRate : updated.vatRate
                updated.vatIncluded = store.state.settings.vatEnabled ? vatIncluded : updated.vatIncluded
                updated.yayilanAy = yayilan
                if !updated.isRecurring { updated.endMonth = nil; updated.overrides = [:] }
                if e.isRecurring && recurrence == e.recurrence && !gecmisDeDegissin {
                    // Bu aydan itibaren: eski gider bir önceki ayda biter, yenisi bu aydan başlar
                    hedefId = store.giderGuncelleAydanItibaren(updated, ay: itibarenAy)
                } else {
                    store.updateExpense(updated)
                }
            }
        } else {
            let yeni = Expense(
                id: Ids.make(.expense),
                date: date, name: name, amount: amount,
                category: category, scope: scope, recurrence: recurrence,
                invoiceNo: invoiceNo.isEmpty ? nil : invoiceNo,
                vendor: vendor.isEmpty ? nil : vendor,
                behavior: behavior,
                vatRate: store.state.settings.vatEnabled ? vatRate : nil,
                vatIncluded: store.state.settings.vatEnabled ? vatIncluded : nil,
                yayilanAy: yayilan
            )
            store.addExpense(yeni)
            hedefId = yeni.id
        }

        let ay: MonthKey? = ayaOzel ? hedefAy : nil
        if let p = picked {
            store.attachInvoice(data: p.data, ext: p.ext, toExpense: hedefId, month: ay)
        } else if invoiceRemoved {
            store.removeInvoice(fromExpense: hedefId, month: ay)
        }
    }

    /// Bu ay için geçerli fatura — düzenli giderde aya özel fatura önceliklidir
    private var mevcutFatura: String? {
        guard let e = editing else { return nil }
        return e.overrides[hedefAy]?.attachment ?? e.attachment
    }
}
