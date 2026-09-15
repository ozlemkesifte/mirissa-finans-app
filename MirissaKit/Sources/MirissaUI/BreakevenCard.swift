import SwiftUI
import MirissaCore

/// "BU AY NEREDEYİZ?" — başa baş noktası, günlük tempo ve ay sonu tahmini.
/// Ekranı doldurmamak için hedefler açılır bölümde durur.
struct BreakevenCard: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    /// Önizleme ve ekran görüntüsü için hedefleri açık göstermeye yarar
    var hedeflerAcik = false

    private var b: Breakeven { store.engine.breakeven(month: month) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let engel = b.blocking {
                    Text(engel.message)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if engel == .katkiNegatif { durum; tahmin }
                } else {
                    durum
                    basaBas
                    tahmin
                    hedefler
                    notlar
                }
            }
        }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text((b.isPast ? "O ay nerede kalındı?" : "Bu ay neredeyiz?").trUpper)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkFaint)
            Spacer()
            if b.remainingDays > 0 {
                Pill("\(b.remainingDays) gün kaldı")
            }
        }
    }

    // MARK: Şu anki durum

    private var durum: some View {
        VStack(spacing: 9) {
            LabeledRow("Şu ana kadar", "\(b.ordersSoFar) sipariş",
                       badge: b.notes.contains(.siparisSayisiTahmini) ? "tahmini" : nil)
            HStack(alignment: .firstTextBaseline) {
                Text("Şu anki sonuç")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                Spacer(minLength: 8)
                Text(b.profitSoFar.tl)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(b.profitSoFar < 0 ? Palette.zarar : Palette.kar)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: Başa baş

    @ViewBuilder
    private var basaBas: some View {
        if let be = b.breakevenOrders {
            Divider().overlay(Palette.separator)
            VStack(spacing: 9) {
                LabeledRow("Başa baş noktası", "\(be) sipariş")
                if b.reachedBreakeven {
                    LabeledRow("Durum", "Başa baş geçildi", tone: Palette.kar, strong: true)
                } else if let kalan = b.ordersToBreakeven {
                    LabeledRow("Başa baş için kalan", "\(kalan) sipariş", tone: Palette.uyari, strong: true)
                }
            }
            if !b.reachedBreakeven, let gunluk = b.dailyOrdersToBreakeven {
                vurgu(
                    "Başa baş için günde \(gunluk) sipariş gerekiyor.",
                    detay: "Kalan \(b.remainingDays) günde toplam \(b.ordersToBreakeven ?? 0) sipariş.",
                    tone: Palette.uyari,
                    background: Palette.uyariYumusak
                )
            }
        }
    }

    // MARK: Ay sonu tahmini

    @ViewBuilder
    private var tahmin: some View {
        if let cumle = b.projectionSentence {
            Divider().overlay(Palette.separator)
            VStack(alignment: .leading, spacing: 6) {
                Text((b.isPast ? "Ay sonucu" : "Ay sonu tahmini").trUpper)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)
                Text(cumle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle((b.projectedProfit ?? 0) < 0 ? Palette.zarar : Palette.kar)
                    .fixedSize(horizontal: false, vertical: true)
                if let o = b.projectedOrders, let c = b.projectedRevenue {
                    Text("\(o) sipariş · \(c.tl) ciro")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                }
                if let hedefCumle = b.customGoalSentence {
                    Text(hedefCumle)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Hedefler (açılır)

    @ViewBuilder
    private var hedefler: some View {
        if !b.goals.isEmpty {
            Divider().overlay(Palette.separator)
            Disclosure(open: hedeflerAcik) {
                HStack {
                    Text("Kâr hedefleri")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                }
            } content: {
                VStack(spacing: 12) {
                    LabeledRow("Sipariş başına ortalama kazanç",
                               Money.roundHalfAwayFromZero(b.contributionPerOrder).tl,
                               tone: Palette.accent)
                    Text("Bu rakam, bu ayki gerçek kanal ve ürün karışımından hesaplandı.")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(b.goals) { g in GoalRow(goal: g, remainingDays: b.remainingDays) }

                    CustomGoalRow(month: month)

                    if b.cashOut != b.profitSoFar {
                        Divider().overlay(Palette.separator)
                        VStack(alignment: .leading, spacing: 3) {
                            LabeledRow("Bu ay ödenen (nakit çıkışı)", b.cashOut.tl, tone: Palette.inkSoft)
                            Text("Stok alımları bu tutara dahildir ama kâr hesabına girmez; ürün satıldıkça maliyet olarak yansır.")
                                .font(.caption2)
                                .foregroundStyle(Palette.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Eksik veri notları

    @ViewBuilder
    private var notlar: some View {
        if !b.notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(b.notes) { n in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkFaint)
                        Text(n.message)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func vurgu(_ title: String, detay: String, tone: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
            Text(detay)
                .font(.caption2)
                .foregroundStyle(tone.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Hedef satırı

private struct GoalRow: View {
    var goal: GoalLine
    var remainingDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(goal.targetProfit.tl) kâr")
                    .font(.subheadline.weight(goal.isCustom ? .semibold : .regular))
                    .foregroundStyle(goal.isCustom ? Palette.ink : Palette.inkSoft)
                if goal.isCustom { Pill("hedefim", tone: Palette.accent, background: Palette.karYumusak) }
                Spacer(minLength: 8)
                if goal.onTrack && !goal.alreadyReached {
                    Pill("tempoda", tone: Palette.kar, background: Palette.karYumusak)
                }
                Text("\(goal.orders) sipariş")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text(altSatir)
                .font(.caption2)
                .foregroundStyle(goal.alreadyReached ? Palette.kar : Palette.inkFaint)
        }
    }

    private var altSatir: String {
        if goal.alreadyReached { return "Bu hedefe ulaşıldı" }
        var parcalar: [String] = []
        if remainingDays > 0 { parcalar.append("günde \(goal.dailyOrders) sipariş") }
        if urunFarkli { parcalar.append("~\(Int(goal.products.rounded())) ürün") }
        parcalar.append("~\(goal.revenue.tl) ciro")
        return parcalar.joined(separator: " · ")
    }

    /// Sipariş başına birden fazla ürün çıkıyorsa ürün adedini de göster
    private var urunFarkli: Bool {
        abs(goal.products - Double(goal.orders)) > 0.5
    }
}

// MARK: - Kendi hedefini yaz

private struct CustomGoalRow: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    /// Önizleme ve ekran görüntüsü için hedefleri açık göstermeye yarar
    var hedeflerAcik = false

    @State private var deger: Kurus = 0
    @State private var yuklendi = false

    private var kayitli: Kurus { store.state.settings.profitGoal(for: month) ?? 0 }
    private var degisti: Bool { deger != kayitli }

    var body: some View {
        VStack(spacing: 8) {
            Divider().overlay(Palette.separator)
            MoneyField("Bu ay hedefim", placeholder: "örn. 75.000", value: $deger)
            if degisti {
                HStack(spacing: 10) {
                    Button("Uygula") { store.setProfitGoal(deger > 0 ? deger : nil, for: month) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    if kayitli > 0 {
                        Button("Hedefi kaldır") {
                            deger = 0
                            store.setProfitGoal(nil, for: month)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Palette.zarar)
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            guard !yuklendi else { return }
            yuklendi = true
            deger = kayitli
        }
    }
}
