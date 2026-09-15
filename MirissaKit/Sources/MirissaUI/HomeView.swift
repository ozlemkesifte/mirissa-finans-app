import SwiftUI
import MirissaCore

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var sheet: AppSheet?

    private var result: CompanyMonthResult { period.result(store.engine) }
    private var alerts: [StockAlert] { store.engine.stockAlerts(endingAt: period.month) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    PeriodPicker(period: period)
                    // Satış girilmemiş bir ayda büyük kâr/zarar kartı gösterilmez:
                    // sadece gider girilmiş olması o ay zarar edildiği anlamına gelmez.
                    if !(period.scope == .month && satisGirilmedi) {
                        headline
                    }
                    if period.scope == .month {
                        BreakevenCard(month: period.month)
                    }
                    TrendChart(
                        points: trendPoints,
                        title: period.scope == .month ? "Son 6 Ay" : "\(period.year) Ayları"
                    )
                    channels
                    if !alerts.isEmpty { stockAlerts }
                    Color.clear.frame(height: 70)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 4)
            }
            .screenBackground()
            .navigationTitle(store.state.settings.companyName)
            .largeTitleMode()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .settings } label: { Image(systemName: "gearshape") }
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .overlay(alignment: .bottomTrailing) { quickAdd }
            .appSheets($sheet)
        }
    }

    // MARK: Büyük kartlar

    private var headline: some View {
        let kar = result.gercekKar
        let loss = kar < 0
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Metrics.gap), GridItem(.flexible(), spacing: Metrics.gap)],
            spacing: Metrics.gap
        ) {
            BigStat(title: "Gerçek Ciro", value: result.gercekCiro.tlCompact, tone: Palette.ink)
            BigStat(title: "Toplam Gider", value: result.toplamGider.tlCompact, tone: Palette.gider)
            BigStat(
                title: satisGirilmedi ? "Gerçek Kâr" : (loss ? "Gerçek Zarar" : "Gerçek Kâr"),
                value: satisGirilmedi ? "—" : kar.tlCompact,
                tone: satisGirilmedi ? Palette.inkFaint : (loss ? Palette.zarar : Palette.kar),
                caption: satisGirilmedi ? "satış girilmedi" : nil
            )
            BigStat(
                title: "Kâr Marjı",
                value: satisGirilmedi ? "—" : Money.formatPercent(result.karMarjiPct),
                tone: satisGirilmedi ? Palette.inkFaint : (loss ? Palette.zarar : Palette.kar),
                caption: !satisGirilmedi && result.nakitCikisi != result.toplamGider
                    ? "Kasa çıkışı \(result.nakitCikisi.tlCompact)" : nil
            )
        }
    }

    /// Dönemde hiç satış yoksa ve dönem geçmişte değilse, kâr rakamı
    /// henüz "sonuç" değildir — kullanıcı yanlış okumasın diye belirtilir.
    private var satisGirilmedi: Bool {
        result.units == 0 && result.gercekCiro == 0 && period.to >= Dates.currentMonth()
    }

    private var trendPoints: [TrendPoint] {
        period.scope == .month
            ? store.engine.trend(endingAt: period.month, months: 6)
            : store.engine.year(period.year).trend
    }

    // MARK: Kanal kartları

    private var channels: some View {
        VStack(spacing: Metrics.gap) {
            SectionTitle("Satış Kanalları")
            ForEach(result.channels) { c in
                ChannelCard(result: c) { sheet = .channelMonth(c.channelId, period.month) }
            }
        }
    }

    // MARK: Stok uyarıları

    private var stockAlerts: some View {
        VStack(spacing: Metrics.gap) {
            SectionTitle("Stok Uyarıları")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(alerts.enumerated()), id: \.element.id) { i, a in
                        StockAlertRow(alert: a)
                            .padding(.horizontal, Metrics.pad)
                            .padding(.vertical, 12)
                        if i < alerts.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }
        }
    }

    // MARK: Hızlı ekle

    private var quickAdd: some View {
        Menu {
            Button { sheet = .addSale(period.month) } label: { Label("Satış Ekle", systemImage: "cart") }
            Button { sheet = .addExpense(period.month) } label: { Label("Gider Ekle", systemImage: "creditcard") }
            Button { sheet = .addPurchase(nil) } label: { Label("Stok Satın Al", systemImage: "shippingbox") }
            Button { sheet = .adjustStock(nil) } label: { Label("Stok Düzelt", systemImage: "slider.horizontal.3") }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.onFilled)
                .frame(width: 54, height: 54)
                .background(Palette.accent)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .menuIndicator(.hidden)
        .padding(.trailing, Metrics.pad)
        .padding(.bottom, 14)
    }
}

// MARK: - Kanal kartı

struct ChannelCard: View {
    var result: ChannelMonthResult
    var onEdit: (() -> Void)?

    var body: some View {
        Card {
            Disclosure {
                VStack(alignment: .leading, spacing: 10) {
                    Text(result.channelName.trUpper)
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Satış").font(.caption2).foregroundStyle(Palette.inkFaint)
                            Text(result.netSales.tlCompact)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Kanalda kalan").font(.caption2).foregroundStyle(Palette.inkFaint)
                            Text(result.kanaldaKalan.tlCompact)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(result.kanaldaKalan < 0 ? Palette.zarar : Palette.kar)
                        }
                    }
                }
            } content: {
                VStack(spacing: 9) {
                    Divider().overlay(Palette.separator)
                    LabeledRow("Satılan", "\(Int(result.units)) ürün")
                    if result.orders > 0 {
                        LabeledRow("Sipariş", "\(result.orders)",
                                   badge: result.ordersIsEstimate ? "tahmini" : nil)
                    }
                    if result.discount != 0 { LabeledRow("İndirim", "-" + result.discount.tl) }
                    if result.returnsAmount != 0 { LabeledRow("İade", "-" + result.returnsAmount.tl) }
                    figureRow("Komisyon", result.commission)
                    figureRow("Kargo", result.shipping)
                    figureRow("Hizmet bedeli", result.serviceFee)
                    figureRow("Diğer kesinti", result.otherDeduction)
                    figureRow("Reklam", result.ads)
                    ForEach(result.otherChannelExpenses.sorted { $0.key.rawValue < $1.key.rawValue }, id: \.key) { k, v in
                        LabeledRow(k.displayName, "-" + v.tl)
                    }
                    if result.productCost != 0 { LabeledRow("Ürün maliyeti", "-" + result.productCost.tl) }
                    if result.packagingCost != 0 { LabeledRow("Ambalaj", "-" + result.packagingCost.tl) }
                    Divider().overlay(Palette.separator)
                    LabeledRow("KANALDA KALAN", result.kanaldaKalan.tl,
                               tone: result.kanaldaKalan < 0 ? Palette.zarar : Palette.kar, strong: true)
                    if result.netSales > 0 {
                        LabeledRow("Kanal marjı", Money.formatPercent(result.marginPct),
                                   tone: Palette.inkSoft)
                    }
                    if let onEdit {
                        Button(action: onEdit) {
                            Label("Gerçek kesintileri gir", systemImage: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Palette.inset)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func figureRow(_ label: String, _ f: Figure) -> some View {
        if f.amount != 0 {
            LabeledRow(label, "-" + f.amount.tl, badge: f.isManual ? "gerçek" : "otomatik")
        }
    }
}

// MARK: - Stok uyarı satırı

struct StockAlertRow: View {
    var alert: StockAlert

    private var tone: Color {
        switch alert.status {
        case .kritik, .negatif: return Palette.zarar
        case .azaliyor: return Palette.uyari
        case .normal: return Palette.inkSoft
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(tone).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.name).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                Text(alert.status.displayName).font(.caption).foregroundStyle(tone)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(alert.qtyText) kaldı")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if let n = alert.ordersLeft {
                    Text("yaklaşık \(n) siparişlik")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
        }
    }
}
