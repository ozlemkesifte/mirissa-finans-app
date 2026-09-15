import SwiftUI
import MirissaCore

struct SalesView: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var sheet: AppSheet?

    private var result: CompanyMonthResult { period.result(store.engine) }

    private var entries: [SalesEntry] {
        store.state.sales
            .filter { $0.month >= period.from && $0.month <= period.to }
            .sorted { a, b in
                a.month == b.month ? a.channelId < b.channelId : a.month > b.month
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    PeriodPicker(period: period)

                    BigButton("Aylık Satış Ekle", icon: "plus") {
                        sheet = .saleFlow
                    }

                    SectionTitle("Kanallar")
                    ForEach(result.channels) { c in
                        ChannelCard(result: c) {
                            sheet = .channelMonth(c.channelId, period.month)
                        }
                    }

                    if entries.isEmpty {
                        Card {
                            EmptyHint(
                                icon: "cart",
                                title: "Bu dönemde satış yok",
                                message: "Ay sonunda kanalın toplam rakamını girmen yeterli — sistem kârı, maliyeti ve stok düşümünü kendisi hesaplar."
                            )
                        }
                    } else {
                        SectionTitle("Satış Kayıtları")
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                                    Button { sheet = .editSale(e.id) } label: {
                                        SalesRow(entry: e)
                                            .padding(.horizontal, Metrics.pad)
                                            .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                    if i < entries.count - 1 {
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
            .navigationTitle("Satışlar")
            .largeTitleMode()
            .appSheets($sheet)
        }
    }
}

private struct SalesRow: View {
    var entry: SalesEntry
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.state.product(entry.productId)?.name ?? "—")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    Text(store.state.channel(entry.channelId)?.name ?? "—")
                    Text("·")
                    Text(Dates.displayMonthShort(entry.month))
                    Text("·")
                    Text("\(Int(entry.qty)) adet")
                }
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.netSales.tl)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if entry.returnsQty > 0 {
                    Text("\(Int(entry.returnsQty)) iade")
                        .font(.caption2)
                        .foregroundStyle(Palette.uyari)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.inkFaint)
        }
    }
}
