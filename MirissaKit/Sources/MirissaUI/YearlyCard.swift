import SwiftUI
import MirissaCore

/// Yılın tamamı için sade hedef: kaç kargo çıkarmam gerekiyor.
/// Teknik hesap gösterilmez; yalnızca sonuç.
struct YearlyCard: View {
    @Environment(AppStore.self) private var store
    var year: Int
    var sheet: Binding<AppSheet?>?

    @State private var hedefGirisi = false
    @State private var hedefTutar: Kurus = 0

    private var plan: YearlyPlan { store.engine.yearlyPlan(year: year) }

    var body: some View {
        let p = plan
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("YILLIK BAŞA BAŞ")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)

                if !p.missing.isEmpty {
                    // "0 kargo" gösterme: neyin eksik olduğunu söyle
                    Text("Yıllık hedefi hesaplamak için \(p.missing.count) bilgi eksik.")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(p.missing.prefix(5)) { m in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(Palette.uyari)
                                Text(m.title)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let sheet {
                        BigButton("Eksikleri Tamamla", icon: "checklist") {
                            sheet.wrappedValue = .eksikleriTamamla
                        }
                    }
                } else if let engel = p.blocking {
                    Text(engel.message)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(p.targets) { t in
                        hedefSatiri(t, ilk: t.isBreakeven)
                        if t.id != p.targets.last?.id {
                            Divider().overlay(Palette.separator)
                        }
                    }
                    if p.isApproximate {
                        Text("Yaklaşık. Kanal ve ürün karışımının gerçek ortalaması kullanıldı.")
                            .font(.caption)
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Eksik veri varsa hedef kesinmiş gibi gösterilmez
                    ForEach(p.notes) { n in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(Palette.uyari)
                            Text(n.message)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    hedefDuzenle(p)
                }
            }
        }
    }

    private func hedefSatiri(_ t: YearlyTarget, ilk: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.isBreakeven
                 ? "Yıllık masrafları karşılamak için"
                 : "\(Money.format(t.targetProfit)) yıllık kâr için")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("yaklaşık \(t.ordersPerYear) kargo / yıl")
                .font(.system(ilk ? .title3 : .body, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("≈ ayda \(t.ordersPerMonth) · günde \(t.ordersPerDay)")
                .font(.footnote)
                .foregroundStyle(Palette.uyari)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func hedefDuzenle(_ p: YearlyPlan) -> some View {
        if hedefGirisi {
            Card(background: Palette.inset) {
                VStack(spacing: 10) {
                    MoneyField("Yıllık kâr hedefin", value: $hedefTutar)
                    HStack(spacing: Metrics.gap) {
                        Button("Vazgeç") { hedefGirisi = false }
                            .foregroundStyle(Palette.inkSoft)
                        Spacer()
                        Button("Kaydet") {
                            store.setYearlyProfitGoal(hedefTutar > 0 ? hedefTutar : nil, for: year)
                            hedefGirisi = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
        } else {
            Button {
                hedefTutar = store.state.settings.yearlyProfitGoal(for: year) ?? 0
                hedefGirisi = true
            } label: {
                Label(store.state.settings.yearlyProfitGoal(for: year) == nil
                      ? "Kendi yıllık hedefimi yazayım"
                      : "Yıllık hedefi değiştir",
                      systemImage: "target")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
        }
    }
}

/// "Bu sonuç yaklaşık; Trendyol kargo gideri henüz girilmedi."
struct EksikBilgiNotu: View {
    var uyari: String?

    var body: some View {
        if let uyari {
            Card(background: Palette.inset) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.uyari)
                    Text(uyari)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
