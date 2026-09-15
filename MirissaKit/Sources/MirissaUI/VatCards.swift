import SwiftUI
import MirissaCore

/// Aylık raporda açılır KDV kartı. Kapalıyken tek satır.
struct VatCard: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    var acik = false

    private var kdv: VatStatus { store.engine.vatStatus(month) }

    var body: some View {
        if store.state.settings.vatEnabled {
            Card {
                Disclosure(open: acik) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("KDV durumu".trUpper)
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.inkFaint)
                        Spacer(minLength: 8)
                        Text(ozetTutar)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ozetRengi)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } content: {
                    VStack(spacing: 9) {
                        Divider().overlay(Palette.separator)
                        LabeledRow("Hesaplanan KDV", kdv.hesaplanan.tl)
                        LabeledRow("İndirilecek KDV", kdv.indirilecek.tl)
                        if kdv.oncekiDevreden != 0 {
                            LabeledRow("Önceki aydan devreden", kdv.oncekiDevreden.tl,
                                       tone: Palette.inkSoft)
                        }
                        Divider().overlay(Palette.separator)
                        if kdv.odenecek > 0 {
                            LabeledRow("Tahmini ödenecek KDV", kdv.odenecek.tl,
                                       tone: Palette.gider, strong: true)
                        } else if kdv.devreden > 0 {
                            LabeledRow("Sonraki aya devreden KDV", kdv.devreden.tl,
                                       tone: Palette.accent, strong: true)
                        } else {
                            LabeledRow("Bu ay ödenecek KDV", "yok", tone: Palette.inkSoft, strong: true)
                        }
                        Text("Bu bir tahmindir, beyanname değildir. Tutarlar girdiğin kayıtlardan hesaplanır; kâr hesabına KDV karışmaz.")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var ozetTutar: String {
        if !kdv.hasData { return "—" }
        if kdv.odenecek > 0 { return "\(kdv.odenecek.tl) ödenecek" }
        if kdv.devreden > 0 { return "\(kdv.devreden.tl) devreden" }
        return "yok"
    }

    private var ozetRengi: Color {
        if kdv.odenecek > 0 { return Palette.gider }
        if kdv.devreden > 0 { return Palette.accent }
        return Palette.inkFaint
    }
}

/// Basit alacak / ödenecek listesi.
struct BalanceCard: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @Binding var sheet: AppSheet?
    var acik = false

    private var ozet: BalanceSummary { store.engine.balanceSummary(month: month) }

    var body: some View {
        Card {
            Disclosure(open: acik) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Alacak / Ödenecek".trUpper)
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    Spacer(minLength: 8)
                    if ozet.isEmpty {
                        Text("—").font(.subheadline).foregroundStyle(Palette.inkFaint)
                    } else {
                        Text(ozet.net.tl)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ozet.net < 0 ? Palette.zarar : Palette.kar)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } content: {
                VStack(spacing: 10) {
                    Divider().overlay(Palette.separator)

                    if ozet.isEmpty {
                        Text("Bekleyen tahsilat veya ödeme eklemedin.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        if !ozet.alacaklar.isEmpty {
                            baslik("Alacaklar")
                            ForEach(ozet.alacaklar) { satir($0, tone: Palette.kar) }
                            LabeledRow("Toplam alacak", ozet.toplamAlacak.tl, tone: Palette.kar, strong: true)
                        }
                        if !ozet.odenecekler.isEmpty || ozet.tahminiKdv != 0 {
                            baslik("Ödenecekler")
                            ForEach(ozet.odenecekler) { satir($0, tone: Palette.gider) }
                            if ozet.tahminiKdv != 0 {
                                LabeledRow("Tahmini KDV", ozet.tahminiKdv.tl,
                                           tone: Palette.gider, badge: "otomatik")
                            }
                            LabeledRow("Toplam ödenecek", ozet.toplamOdenecek.tl,
                                       tone: Palette.gider, strong: true)
                        }
                        Divider().overlay(Palette.separator)
                        LabeledRow("Net", ozet.net.tl,
                                   tone: ozet.net < 0 ? Palette.zarar : Palette.kar, strong: true)
                    }

                    Button { sheet = .addBalance } label: {
                        Label("Alacak / ödenecek ekle", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                }
            }
        }
    }

    private func baslik(_ t: String) -> some View {
        Text(t.trUpper)
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func satir(_ b: BalanceItem, tone: Color) -> some View {
        Button { sheet = .editBalance(b.id) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.name).font(.subheadline).foregroundStyle(Palette.ink)
                    HStack(spacing: 5) {
                        Text(b.source.displayName)
                        if let d = b.dueDate { Text("· \(Dates.displayDateShort(d))") }
                    }
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 8)
                Text(b.amount.tl)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tone)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alacak / ödenecek formu

struct BalanceForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editingId: Id?
    @State private var kind: BalanceKind = .alacak
    @State private var source: BalanceSource = .kanal
    @State private var name = ""
    @State private var amount: Kurus = 0
    @State private var hasDue = false
    @State private var dueDate: DateKey = Dates.today()
    @State private var note = ""
    @State private var loaded = false

    init() { self.editingId = nil }
    init(editing id: Id) { self.editingId = id }

    var body: some View {
        FormShell(
            title: editingId == nil ? "Alacak / Ödenecek Ekle" : "Düzenle",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && amount != 0,
            onSave: save
        ) {
            Section {
                Picker("", selection: $kind) {
                    ForEach(BalanceKind.allCases) { k in Text(k.displayName).tag(k) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text(kind == .alacak
                     ? "Sana gelecek para: kanal ödemesi, iade, vb."
                     : "Senin ödeyeceğin: tedarikçi faturası, vb.")
            }

            Section {
                Picker("Tür", selection: $source) {
                    ForEach(BalanceSource.allCases) { s in Text(s.displayName).tag(s) }
                }
                TextField(kind == .alacak ? "Kimden / ne için" : "Kime / ne için", text: $name)
                MoneyField("Tutar", value: $amount)
            }

            Section {
                Toggle("Vade tarihi var", isOn: $hasDue.animation())
                if hasDue { DateRow(label: "Vade", dateKey: $dueDate) }
                TextField("Not (isteğe bağlı)", text: $note)
            }

            if let id = editingId {
                Section {
                    Button {
                        store.settleBalance(id)
                        dismiss()
                    } label: {
                        Label(kind == .alacak ? "Tahsil edildi olarak işaretle" : "Ödendi olarak işaretle",
                              systemImage: "checkmark.circle")
                    }
                    .foregroundStyle(Palette.accent)

                    Button(role: .destructive) {
                        store.deleteBalance(id)
                        dismiss()
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = editingId, let b = store.state.balances.first(where: { $0.id == id }) else { return }
        kind = b.kind; source = b.source; name = b.name; amount = b.amount
        note = b.note ?? ""
        if let d = b.dueDate { hasDue = true; dueDate = d }
    }

    private func save() {
        let b = BalanceItem(
            id: editingId ?? Ids.make(.balance),
            kind: kind, source: source, name: name, amount: amount,
            dueDate: hasDue ? dueDate : nil,
            settled: false,
            note: note.isEmpty ? nil : note
        )
        editingId == nil ? store.addBalance(b) : store.updateBalance(b)
    }
}
