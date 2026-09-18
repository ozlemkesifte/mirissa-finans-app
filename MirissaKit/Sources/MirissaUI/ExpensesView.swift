import SwiftUI
import MirissaCore

struct ExpensesView: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var sheet: AppSheet?

    private var instances: [ExpenseInstance] {
        store.engine.expenseInstances(from: period.from, to: period.to)
    }

    private var result: CompanyMonthResult { period.result(store.engine) }

    private var byCategory: [(ExpenseCategory, Kurus)] {
        result.expenseBreakdown
            .filter { $0.value != 0 }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    private var purchases: [StockPurchase] {
        store.state.purchases
            .filter { Dates.month(of: $0.date) >= period.from && Dates.month(of: $0.date) <= period.to }
            .sorted { $0.date > $1.date }
    }

    private var recurring: [Expense] {
        store.state.expenses.filter(\.isRecurring)
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    PeriodPicker(period: period)

                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text((period.scope == .month ? "Bu ay toplam gider" : "Bu yıl toplam gider").trUpper)
                                .font(.caption2.weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.inkFaint)
                            Text(result.toplamGider.tl)
                                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if result.stokAlimi != 0 {
                                Text("Ayrıca \(result.stokAlimi.tl) stok alımı yapıldı — kâra satıldıkça yansır.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }

                    BigButton("Gider Ekle", icon: "plus") { sheet = .expenseFlow }

                    BirSatisinMaliyetiKarti()
                    GiderAyrimiKarti()

                    if byCategory.isEmpty {
                        Card {
                            EmptyHint(
                                icon: "creditcard",
                                title: "Bu dönemde gider yok",
                                message: "Reklam, kargo, sabit gider ne varsa ekle — kâr anında yeniden hesaplanır."
                            )
                        }
                    } else {
                        SectionTitle("Kategoriler")
                        ForEach(byCategory, id: \.0) { cat, total in
                            CategoryCard(
                                category: cat,
                                total: total,
                                items: instances.filter { $0.category == cat && !$0.capitalized },
                                stoktan: store.engine.stoktanGider(from: period.from, to: period.to, category: cat),
                                onTap: { sheet = .editExpense($0.templateId ?? $0.id, $0.month) }
                            )
                        }
                    }

                    if !purchases.isEmpty {
                        SectionTitle("Stok Alımları")
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(purchases.enumerated()), id: \.element.id) { i, p in
                                    Button { sheet = .editPurchase(p.id) } label: {
                                        PurchaseRow(purchase: p)
                                            .padding(.horizontal, Metrics.pad)
                                            .padding(.vertical, 12)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if i < purchases.count - 1 {
                                        Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                                    }
                                }
                            }
                        }
                        Text("Stok alımları kasadan çıkar ama kâra doğrudan gider yazılmaz; ürün satıldıkça maliyet olarak yansır.")
                            .font(.caption)
                            .foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    if !recurring.isEmpty {
                        SectionTitle("Sabit Giderler")
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(recurring.enumerated()), id: \.element.id) { i, e in
                                    Button { sheet = .editExpense(e.id, period.month) } label: {
                                        RecurringRow(expense: e, month: period.month)
                                            .padding(.horizontal, Metrics.pad)
                                            .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                    if i < recurring.count - 1 {
                                        Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                                    }
                                }
                            }
                        }
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 4)
            }
            .screenBackground()
            .navigationTitle("Giderler")
            .largeTitleMode()
            .appSheets($sheet)
        }
    }
}

private struct CategoryCard: View {
    var category: ExpenseCategory
    var total: Kurus
    var items: [ExpenseInstance]
    /// Stok düzeltme ve sayımlarından gelen tutar (kırık, fire, numune, sayım farkı)
    var stoktan: Kurus = 0
    var onTap: (ExpenseInstance) -> Void

    /// Kategorinin, elle girilmiş satırlarla açıklanamayan kısmı
    /// (komisyon, ürün maliyeti, ambalaj gibi satıştan türeyen tutarlar).
    /// Kategori toplamı KDV hariç olduğu için satırlar da KDV hariç sayılır —
    /// aksi halde satırların toplamı başlıktaki rakamı tutmazdı.
    private var otomatik: Kurus {
        max(total - stoktan - items.reduce(0) { $0 + $1.expenseAmount }, 0)
    }

    var body: some View {
        Card {
            Disclosure {
                HStack(spacing: 12) {
                    Image(systemName: category.symbolName)
                        .font(.subheadline)
                        .foregroundStyle(Palette.gider)
                        .frame(width: 30, height: 30)
                        .background(Palette.inset)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(category.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text(total.tl)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } content: {
                if items.isEmpty, stoktan != 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider().overlay(Palette.separator)
                        stoktanSatiri
                    }
                } else if items.isEmpty {
                    Text("Bu kalem satışlardan otomatik hesaplanıyor.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        Divider().overlay(Palette.separator)
                        if otomatik > 0 {
                            LabeledRow("Satışlardan hesaplanan", otomatik.tl, tone: Palette.inkSoft)
                        }
                        if stoktan != 0 { stoktanSatiri }
                        ForEach(items) { i in
                            Button { onTap(i) } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(i.name).font(.subheadline).foregroundStyle(Palette.ink)
                                        HStack(spacing: 5) {
                                            Text(Dates.displayDateShort(i.date))
                                            if i.behavior == .satisaBagli { Text("· satışa bağlı") }
                                        }
                                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                                    }
                                    if i.attachment != nil {
                                        Image(systemName: "paperclip")
                                            .font(.caption2)
                                            .foregroundStyle(Palette.inkFaint)
                                    }
                                    if i.sourceKind == .duzenli { Pill("düzenli") }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 1) {
                                        // Kâra etki eden tutar (KDV hariç)
                                        Text(i.expenseAmount.tl)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Palette.ink)
                                        if i.cashAmount != i.expenseAmount {
                                            // Aylara bölünen giderde para ödeme ayında çıkar
                                            Text(i.cashAmount == 0 ? "ödemesi başka ayda" : "\(i.cashAmount.tl) ödendi")
                                                .font(.caption2)
                                                .foregroundStyle(Palette.inkFaint)
                                        }
                                    }
                                    if i.editable {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Palette.inkFaint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!i.editable)
                        }
                    }
                }
            }
        }
    }
}

private extension CategoryCard {
    var stoktanSatiri: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledRow(category == .influencer ? "Stoktan verilen ürün (numune, PR)" : "Stoktan çıkan mal",
                       stoktan.tl, tone: Palette.inkSoft)
            Text(category == .influencer
                 ? "Stok düzeltmesinde numune, influencer ya da PR seçilen ürün ve malzemelerin maliyeti."
                 : "Kırık, hasarlı, fire, kayıp düzeltmeleri ve sayım farklarının maliyeti. Sayımda fazla çıkan mal bu tutarı azaltır.")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecurringRow: View {
    var expense: Expense
    var month: MonthKey

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.name).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    Text(expense.recurrence == .aylik ? "her ay"
                         : "yılda bir, \(Dates.displayMonth(expense.startMonth).split(separator: " ").first.map(String.init) ?? "") ayında")
                    if let end = expense.endMonth {
                        Text("·")
                        Text("\(Dates.displayMonthShort(end)) sonunda durduruldu")
                    }
                }
                .font(.caption)
                .foregroundStyle(expense.isStopped ? Palette.uyari : Palette.inkFaint)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(expense.amount.tl)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(expense.isStopped ? Palette.inkFaint : Palette.ink)
                if expense.recurrence == .yillik {
                    Text("ayda \(Money.roundHalfAwayFromZero(Double(expense.amount) / 12).tl)")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.inkFaint)
        }
    }
}

private struct PurchaseRow: View {
    var purchase: StockPurchase
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.state.itemName(purchase.item))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    Text(Dates.displayDateShort(purchase.date))
                    Text("·")
                    Text("\(NumberInput.display(purchase.qty)) \(purchase.unit.displayName)")
                }
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
            }
            if purchase.attachment != nil {
                Image(systemName: "paperclip")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
            }
            if purchase.excludeFromExpenses { Pill("hariç") } else { Pill("stoğa girdi") }
            Spacer(minLength: 8)
            Text(purchase.landedTotal.tl)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.inkFaint)
        }
    }
}
