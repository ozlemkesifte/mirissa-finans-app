import SwiftUI
import MirissaCore

public enum AppSheet: Identifiable, Hashable {
    case addSale(MonthKey)
    case editSale(Id)
    case addExpense(MonthKey)
    case editExpense(Id, MonthKey)
    case addPurchase(ItemRef?)
    case editPurchase(Id)
    case adjustStock(ItemRef?)
    case editAdjustment(Id)
    case countStock(ItemRef?)
    case addMaterial
    case editMaterial(Id)
    case addProduct
    case editProduct(Id)
    case channelSetup(Id)
    case channelMonth(Id, MonthKey)
    case addBalance
    case editBalance(Id)
    case settings

    public var id: String {
        switch self {
        case let .addSale(m): return "addSale-\(m)"
        case let .editSale(i): return "editSale-\(i)"
        case let .addExpense(m): return "addExpense-\(m)"
        case let .editExpense(i, m): return "editExpense-\(i)-\(m)"
        case let .addPurchase(r): return "addPurchase-\(r?.id ?? "-")"
        case let .editPurchase(i): return "editPurchase-\(i)"
        case let .editAdjustment(i): return "editAdjustment-\(i)"
        case let .adjustStock(r): return "adjust-\(r?.id ?? "-")"
        case let .countStock(r): return "count-\(r?.id ?? "-")"
        case .addMaterial: return "addMaterial"
        case let .editMaterial(i): return "editMaterial-\(i)"
        case .addProduct: return "addProduct"
        case let .editProduct(i): return "editProduct-\(i)"
        case let .channelSetup(i): return "channelSetup-\(i)"
        case let .channelMonth(i, m): return "channelMonth-\(i)-\(m)"
        case .addBalance: return "addBalance"
        case let .editBalance(i): return "editBalance-\(i)"
        case .settings: return "settings"
        }
    }
}

public extension View {
    func appSheets(_ sheet: Binding<AppSheet?>) -> some View {
        self.sheet(item: sheet) { s in
            switch s {
            case let .addSale(m): SaleForm(month: m)
            case let .editSale(i): SaleForm(editing: i)
            case let .addExpense(m): ExpenseForm(month: m)
            case let .editExpense(i, m): ExpenseForm(editing: i, month: m)
            case let .addPurchase(r): PurchaseForm(preselected: r)
            case let .editPurchase(i): PurchaseForm(editing: i)
            case let .editAdjustment(i): AdjustForm(editing: i)
            case let .adjustStock(r): AdjustForm(preselected: r)
            case let .countStock(r): CountForm(preselected: r)
            case .addMaterial: MaterialForm()
            case let .editMaterial(i): MaterialForm(editing: i)
            case .addProduct: ProductForm()
            case let .editProduct(i): ProductForm(editing: i)
            case let .channelSetup(i): ChannelForm(channelId: i)
            case let .channelMonth(i, m): ChannelMonthForm(channelId: i, month: m)
            case .addBalance: BalanceForm()
            case let .editBalance(i): BalanceForm(editing: i)
            case .settings: SettingsView()
            }
        }
    }
}

// MARK: - Form iskeleti

struct FormShell<Content: View>: View {
    var title: String
    var saveTitle: String = "Kaydet"
    var canSave: Bool = true
    var onSave: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(title)
                .inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Vazgeç") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveTitle) { onSave(); dismiss() }
                            .font(.body.weight(.semibold))
                            .disabled(!canSave)
                    }
                }
        }
    }
}

// MARK: - Ay seçici satırı

struct MonthRow: View {
    var label: String = "Ay"
    @Binding var month: MonthKey

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button { month = Dates.addMonths(month, -1) } label: {
                Image(systemName: "chevron.left").font(.footnote.weight(.bold))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
            Text(Dates.displayMonth(month))
                .font(.body.weight(.medium))
                .frame(minWidth: 128)
                .multilineTextAlignment(.center)
            Button { month = Dates.addMonths(month, 1) } label: {
                Image(systemName: "chevron.right").font(.footnote.weight(.bold))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }
    }
}

struct DateRow: View {
    var label: String = "Tarih"
    @Binding var dateKey: DateKey

    var body: some View {
        DatePicker(label, selection: Binding(
            get: { Self.toDate(dateKey) },
            set: { dateKey = Dates.today($0) }
        ), displayedComponents: .date)
    }

    static func toDate(_ k: DateKey) -> Date {
        var c = DateComponents()
        c.year = Dates.year(of: Dates.month(of: k))
        c.month = Dates.monthNumber(of: Dates.month(of: k))
        c.day = Dates.day(of: k)
        c.hour = 12
        return Calendar.current.date(from: c) ?? Date()
    }
}

/// Ürün veya malzeme seçici
struct ItemPicker: View {
    var label: String = "Kalem"
    @Binding var selection: ItemRef?
    @Environment(AppStore.self) private var store

    var body: some View {
        Picker(label, selection: $selection) {
            Text("Seç").tag(ItemRef?.none)
            if !store.state.activeProducts.filter(\.tracksOwnStock).isEmpty {
                Section("Ürünler") {
                    ForEach(store.state.activeProducts.filter(\.tracksOwnStock)) { p in
                        Text(p.name).tag(ItemRef?.some(.product(p.id)))
                    }
                }
            }
            Section("Ambalaj & sarf") {
                ForEach(store.state.activeMaterials) { m in
                    Text(m.name).tag(ItemRef?.some(.material(m.id)))
                }
            }
        }
    }
}
