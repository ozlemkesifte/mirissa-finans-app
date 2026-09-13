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
                            Text((period.scope == .month ? "Bu ay toplam gider" : "Bu yıl toplam gider").uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.inkFaint)
                            Text(result.toplamGider.tl)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
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

                    BigButton("Gider Ekle", icon: "plus") { sheet = .addExpense(period.month) }

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
                                onTap: { sheet = .editExpense($0.templateId ?? $0.id, $0.month) }
                            )
                        }
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
    var onTap: (ExpenseInstance) -> Void

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
                if items.isEmpty {
                    Text("Bu kalem satışlardan otomatik hesaplanıyor.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        Divider().overlay(Palette.separator)
                        ForEach(items) { i in
                            Button { onTap(i) } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(i.name).font(.subheadline).foregroundStyle(Palette.ink)
                                        Text(Dates.displayDateShort(i.date))
                                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                                    }
                                    if i.sourceKind == .duzenli { Pill("her ay") }
                                    Spacer(minLength: 8)
                                    Text(i.amount.tl)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Palette.ink)
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

private struct RecurringRow: View {
    var expense: Expense
    var month: MonthKey

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.name).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    Text(expense.recurrence == .aylik ? "her ay" : "her yıl")
                    if let end = expense.endMonth {
                        Text("·")
                        Text("\(Dates.displayMonthShort(end)) sonunda durduruldu")
                    }
                }
                .font(.caption)
                .foregroundStyle(expense.isStopped ? Palette.uyari : Palette.inkFaint)
            }
            Spacer(minLength: 8)
            Text(expense.amount.tl)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(expense.isStopped ? Palette.inkFaint : Palette.ink)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.inkFaint)
        }
    }
}
