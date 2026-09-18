import SwiftUI
import MirissaCore

public enum PeriodScope: String, CaseIterable, Identifiable, Sendable {
    case month, year
    public var id: String { rawValue }
    public var label: String { self == .month ? "Bu Ay" : "Bu Yıl" }
}

/// Ekranların üstündeki dönem seçici için ortak durum.
@MainActor
@Observable
public final class Period {
    public var month: MonthKey
    public var scope: PeriodScope

    public init(month: MonthKey = Dates.currentMonth(), scope: PeriodScope = .month) {
        self.month = month
        self.scope = scope
    }

    public var year: Int { Dates.year(of: month) }

    public var title: String {
        scope == .month ? Dates.displayMonth(month) : "\(year)"
    }

    public var from: MonthKey { scope == .month ? month : Dates.monthKey(year, 1) }
    public var to: MonthKey { scope == .month ? month : Dates.monthKey(year, 12) }

    public func step(_ n: Int) {
        month = scope == .month ? Dates.addMonths(month, n) : Dates.addMonths(month, n * 12)
    }

    public func goToToday() { month = Dates.currentMonth() }

    public var isCurrent: Bool {
        scope == .month ? month == Dates.currentMonth()
                        : year == Dates.year(of: Dates.currentMonth())
    }

    /// Seçili dönemin toplamı
    public func result(_ e: Engine) -> CompanyMonthResult {
        scope == .month ? e.companyMonth(month) : e.periodTotals(from: from, to: to)
    }
}

public struct PeriodPicker: View {
    @Bindable var period: Period

    public init(period: Period) { self._period = Bindable(period) }

    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                stepButton("chevron.left", -1)
                Spacer(minLength: 0)
                VStack(spacing: 1) {
                    Text(period.title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    if !period.isCurrent {
                        Button("Bugüne dön") { withAnimation { period.goToToday() } }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Spacer(minLength: 0)
                stepButton("chevron.right", 1)
            }
            Picker("", selection: $period.scope) {
                ForEach(PeriodScope.allCases) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.vertical, 10)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func stepButton(_ icon: String, _ n: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { period.step(n) }
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 42, height: 34)
                .background(Palette.inset)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
