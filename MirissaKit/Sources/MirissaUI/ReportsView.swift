import SwiftUI
import MirissaCore

/// Finans & Vergiler sekmesinin bölümleri. Ham değerler eski "raporSekmesi" kayıtlarıyla uyumludur.
enum ReportTab: String, CaseIterable, Identifiable, Sendable {
    case aylik, kanallar, kdv, vergiler, hakedis, giderler, urunler, nakit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aylik: return "Kâr & Zarar"
        case .kanallar: return "Satış Kanalları"
        case .kdv: return "KDV"
        case .vergiler: return "Vergiler"
        case .hakedis: return "Hakediş & Mutabakat"
        case .giderler: return "Giderler"
        case .urunler: return "Ürünler"
        case .nakit: return "Nakit"
        }
    }
}

/// Finans & Vergiler: bütün ayrıntılı finansal analiz burada, ana ekranda değil.
struct ReportsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    /// Seçili bölüm hatırlanır; ana sayfadaki "Nasıl hesaplandı?" doğrudan ilgili bölümü açar
    @AppStorage("raporSekmesi") private var tab: ReportTab = .aylik
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    bolumSecici
                    switch tab {
                    case .aylik: KarZararBolumu(sheet: $sheet)
                    case .kanallar: ChannelReport(onEdit: { id in sheet = .channelMonth(id, period.month) })
                    case .kdv: KdvBolumu()
                    case .vergiler: VergilerBolumu()
                    case .hakedis: HakedisBolumu(onEdit: { id in sheet = .channelMonth(id, period.month) })
                    case .giderler: GiderlerBolumu()
                    case .urunler: UrunRaporu()
                    case .nakit:
                        NakitRaporu()
                        BalanceCard(month: min(period.month, Dates.currentMonth()), sheet: $sheet)
                        TedarikciBorclariKarti()
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 4)
            }
            .screenBackground()
            .navigationTitle("Finans & Vergiler")
            .largeTitleMode()
            .appSheets($sheet)
        }
    }

    /// Yatay kaydırılan bölüm düğmeleri
    private var bolumSecici: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReportTab.allCases) { t in
                    Button { tab = t } label: {
                        Text(t.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(tab == t ? Palette.onFilled : Palette.ink)
                            .background(tab == t ? Palette.accent : Palette.card)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Kâr & Zarar

struct KarZararBolumu: View {
    @Environment(Period.self) private var period
    @Binding var sheet: AppSheet?

    var body: some View {
        VStack(spacing: Metrics.gap) {
            Picker("", selection: Bindable(period).scope) {
                Text("Ay").tag(PeriodScope.month)
                Text("Yıl").tag(PeriodScope.year)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if period.scope == .month { MonthlyReport(sheet: $sheet) } else { YearlyReport() }
        }
    }
}

// MARK: - Aylık

struct MonthlyReport: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @Binding var sheet: AppSheet?

    private var result: CompanyMonthResult { store.engine.companyMonth(period.month) }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            MonthStepper(month: Bindable(period).month)
            if store.engine.satisGirilmedi(month: period.month) {
                Card(background: Palette.inset) {
                    Text("Bu ayın satışları henüz girilmedi. Aşağıdaki kâr/zarar yalnızca kaydedilmiş giderleri gösterir.")
                        .font(.footnote).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ResultSummary(
                title: Dates.displayMonth(period.month),
                ciro: result.gercekCiro,
                gider: result.toplamGider,
                kar: result.gercekKar,
                marj: result.karMarjiPct
            )
            EksikBilgiNotu(uyari: result.yaklasikUyarisi)
            EksikBilgiNotu(uyari: result.maliyetDegisimUyarisi)
            TrendChart(points: store.engine.trend(endingAt: period.month, months: 6), title: "Son 6 Ay")
            if result.units > 0 {
                Card {
                    VStack(spacing: 9) {
                        LabeledRow("Satılan ürün", "\(Int(result.units)) adet")
                        if result.orders > 0 { LabeledRow("Sipariş", "\(result.orders)") }
                        if result.units > 0 {
                            LabeledRow("Ürün başına kalan",
                                       Money.roundHalfAwayFromZero(Double(result.gercekKar) / result.units).tl,
                                       tone: result.gercekKar < 0 ? Palette.zarar : Palette.kar)
                        }
                        if result.nakitCikisi != result.toplamGider {
                            LabeledRow("Kasa çıkışı (kâr değil)", result.nakitCikisi.tl, tone: Palette.inkSoft)
                        }
                        if result.stokAlimiNakit != 0 {
                            LabeledRow("Stok alımı (nakit)", result.stokAlimiNakit.tl, tone: Palette.inkSoft)
                        }
                    }
                }
            }
            Card(background: Palette.inset) {
                Text("Bu sayfadaki kâr vergi öncesidir. Vergi sonrası tahmini net kâr için Vergiler bölümüne bak.")
                    .font(.footnote).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - KDV

struct KdvBolumu: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period

    var body: some View {
        VStack(spacing: Metrics.gap) {
            MonthStepper(month: Bindable(period).month)
            if store.state.settings.vatEnabled {
                VatCard(month: period.month, acik: true)
                KdvKayitlariKarti(month: period.month)
            } else {
                Card(background: Palette.inset) {
                    Text("KDV hesabı kapalı (Ayarlar). Kapalıyken tutarlar KDV'siz kabul edilir.")
                        .font(.footnote).foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }
}

// MARK: - Vergiler

struct VergilerBolumu: View {
    @Environment(Period.self) private var period

    var body: some View {
        VStack(spacing: Metrics.gap) {
            MonthStepper(month: Bindable(period).month)
            VergiKarti(month: min(period.month, Dates.currentMonth()))
        }
    }
}

// MARK: - Giderler

struct GiderlerBolumu: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period

    var body: some View {
        let r = period.result(store.engine)
        VStack(spacing: Metrics.gap) {
            PeriodPicker(period: period)
            ExpenseBreakdownCard(breakdown: r.expenseBreakdown, total: r.toplamGider)
            GiderAyrimiKarti()
        }
    }
}

// MARK: - Hakediş & Mutabakat

struct HakedisBolumu: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    var onEdit: (Id) -> Void

    var body: some View {
        let e = store.engine
        let ay = period.month
        VStack(spacing: Metrics.gap) {
            MonthStepper(month: Bindable(period).month)
            ForEach(e.companyMonth(ay).channels.filter { !$0.isEmpty }) { c in
                let beklenen = e.beklenenHakedis(month: ay, channelId: c.channelId)
                let h = e.hakedis(month: ay, channelId: c.channelId)
                Card {
                    VStack(spacing: 9) {
                        Text(c.channelName.trUpper)
                            .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LabeledRow("Müşterinin ödediği (KDV dahil)", c.netSalesIncVat.tl)
                        let abonelik = store.state.channel(c.channelId)?.kind == .ownStore ? c.sabitKesintiBrut : 0
                        LabeledRow("Kanal kesintileri (KDV dahil)", "-" + (c.channelFees + c.feeVat - abonelik).tl)
                        if abonelik != 0 {
                            LabeledRow("Aylık abonelik (ayrıca faturalanır, hakedişten kesilmez)", abonelik.tl, tone: Palette.inkFaint)
                        }
                        if c.stopaj != 0 { LabeledRow("E-ticaret stopajı (vergiden mahsup)", "-" + c.stopaj.tl) }
                        Divider().overlay(Palette.separator)
                        LabeledRow("Beklenen hakediş", beklenen.tl, strong: true)
                        if let h {
                            LabeledRow("Gerçek hesaba yatan", h.yatan.tl)
                            LabeledRow("Fark (beklenen − yatan)", h.fark.tl,
                                       tone: h.fark == 0 ? Palette.inkSoft : Palette.uyari, strong: true)
                        } else {
                            LabeledRow("Gerçek hesaba yatan", "girilmedi", tone: Palette.inkFaint)
                        }
                        Button { onEdit(c.channelId) } label: {
                            Label("Yatan tutarı / gerçek kesintileri gir", systemImage: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Palette.inset)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
            Card(background: Palette.inset) {
                Text("Fark, kesintilerin tahminden farklı olduğunu gösterir (kampanya/kupon katkısı, desi farkı, iade kargosu, ceza…). "
                     + "Uygulama farkı kendiliğinden bir kaleme yazmaz.")
                    .font(.footnote).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Yıllık

struct YearlyReport: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var openMonth: MonthKey?

    private var year: Int { period.year }
    private var result: YearResult { store.engine.year(year) }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            HStack {
                Button { period.month = Dates.addMonths(period.month, -12) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.bold))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
                Spacer()
                Text("\(year)").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Button { period.month = Dates.addMonths(period.month, 12) } label: {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 12)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

            ResultSummary(
                title: "\(year) Toplamı",
                ciro: result.gercekCiro,
                gider: result.toplamGider,
                kar: result.gercekKar,
                marj: result.karMarjiPct
            )

            TrendChart(points: result.trend, title: "Ocak – Aralık")

            SectionTitle("Aylar")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(result.months.enumerated()), id: \.element.id) { i, m in
                        MonthRowView(result: m, open: openMonth == m.month) {
                            withAnimation(.snappy(duration: 0.2)) {
                                openMonth = openMonth == m.month ? nil : m.month
                            }
                        }
                        if i < result.months.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }

            ExpenseBreakdownCard(breakdown: result.expenseBreakdown, total: result.toplamGider)
        }
    }
}

private struct MonthRowView: View {
    @Environment(AppStore.self) private var store
    var result: CompanyMonthResult
    private var satisGirilmedi: Bool { store.engine.satisGirilmedi(month: result.month) }
    var open: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(Dates.displayMonth(result.month))
                        .font(.subheadline)
                        .foregroundStyle(result.hasData ? Palette.ink : Palette.inkFaint)
                    if satisGirilmedi {
                        Text("satış girilmedi").font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.uyari)
                    }
                    Spacer(minLength: 8)
                    Text(result.gercekKar.tlCompact)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.gercekKar < 0 ? Palette.zarar
                                         : (result.hasData ? Palette.kar : Palette.inkFaint))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 8) {
                    LabeledRow("Gerçek ciro", result.gercekCiro.tl)
                    LabeledRow("Toplam gider", result.toplamGider.tl)
                    LabeledRow("Kâr marjı", Money.formatPercent(result.karMarjiPct))
                    ForEach(result.channels.filter { !$0.isEmpty }) { c in
                        LabeledRow(c.channelName, c.kanaldaKalan.tl,
                                   tone: c.kanaldaKalan < 0 ? Palette.zarar : Palette.kar)
                    }
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Kanallar

struct ChannelReport: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    var onEdit: (Id) -> Void

    /// Dönemin kanal toplamları, her kanal için bir kez. Arşivlenmiş kanal da dönemde satışı ya da
    /// gideri varsa görünür (toplamlar ana sayfayı tutsun)
    private var kanallar: [(Channel, ChannelMonthResult)] {
        store.state.channels.compactMap { ch in
            let r = store.engine.channelTotals(from: period.from, to: min(period.to, Dates.currentMonth()),
                                               channelId: ch.id)
            return !ch.archived || r.totalCost != 0 || r.netSales != 0 ? (ch, r) : nil
        }
    }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            PeriodPicker(period: period)
            ForEach(kanallar, id: \.0.id) { ch, r in
                Card {
                    VStack(spacing: 10) {
                        HStack {
                            Text(ch.name.trUpper)
                                .font(.caption.weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.inkFaint)
                            Spacer()
                            if r.netSales > 0 {
                                Pill(Money.formatPercent(r.marginPct),
                                     tone: r.kanaldaKalan < 0 ? Palette.zarar : Palette.kar,
                                     background: r.kanaldaKalan < 0 ? Palette.zararYumusak : Palette.karYumusak)
                            }
                        }
                        Divider().overlay(Palette.separator)
                        LabeledRow("Brüt satış (KDV hariç)", r.grossSales.tl)
                        if r.discount != 0 { LabeledRow("İndirim", "-" + r.discount.tl) }
                        if r.returnsAmount != 0 { LabeledRow("İade", "-" + r.returnsAmount.tl) }
                        LabeledRow("Net satış (KDV hariç)", r.netSales.tl, strong: true)
                        LabeledRow("Satılan ürün", "\(Int(r.units)) adet")
                        if r.commission.amount != 0 { LabeledRow("Komisyon", "-" + r.commission.amount.tl) }
                        if r.shipping.amount != 0 { LabeledRow("Kargo", "-" + r.shipping.amount.tl) }
                        if r.serviceFee.amount != 0 { LabeledRow("Hizmet bedeli", "-" + r.serviceFee.amount.tl) }
                        if r.otherDeduction.amount != 0 {
                            LabeledRow("Diğer kesintiler (ödeme/POS, ek kesintiler, aylık ücret)", "-" + r.otherDeduction.amount.tl)
                        }
                        if r.ads.amount != 0 { LabeledRow("Reklam", "-" + r.ads.amount.tl) }
                        ForEach(r.otherChannelExpenses.sorted { $0.key.rawValue < $1.key.rawValue }, id: \.key) { k, v in
                            LabeledRow(k.displayName, "-" + v.tl)
                        }
                        if r.productCost != 0 { LabeledRow("Ürün maliyeti", "-" + r.productCost.tl) }
                        if r.packagingCost != 0 { LabeledRow("Ambalaj", "-" + r.packagingCost.tl) }
                        Divider().overlay(Palette.separator)
                        LabeledRow("KANALDA KALAN", r.kanaldaKalan.tl,
                                   tone: r.kanaldaKalan < 0 ? Palette.zarar : Palette.kar, strong: true)
                        if r.netSales > 0 {
                            LabeledRow("Kanal kâr marjı", Money.formatPercent(r.marginPct), tone: Palette.inkSoft)
                        }
                        if r.feeVat != 0 {
                            LabeledRow("Kesintilerin KDV'si (indirilecek KDV, gider değil)", r.feeVat.tl, tone: Palette.inkSoft)
                        }
                        if r.stopaj != 0 {
                            LabeledRow("E-ticaret stopajı (gider değil, vergiden mahsup)", r.stopaj.tl, tone: Palette.inkSoft)
                        }
                        if period.scope == .month {
                            LabeledRow("Beklenen hakediş", store.engine.beklenenHakedis(month: period.month, channelId: ch.id).tl,
                                       tone: Palette.inkSoft)
                            if let h = store.engine.hakedis(month: period.month, channelId: ch.id) {
                                LabeledRow("Gerçek hesaba yatan", h.yatan.tl, tone: Palette.inkSoft)
                                LabeledRow("Fark (beklenen − yatan)", h.fark.tl,
                                           tone: h.fark == 0 ? Palette.inkSoft : Palette.uyari)
                            } else {
                                LabeledRow("Gerçek hesaba yatan", "girilmedi", tone: Palette.inkFaint)
                            }
                        }
                        if period.scope == .month {
                            Button { onEdit(ch.id) } label: {
                                Label("Gerçek kesintileri gir", systemImage: "pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Palette.inset)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
            Card(background: Palette.inset) {
                Text("Kanalda kalan, şirket net kârı değildir. Ortak şirket giderleri ayrıca bu tutardan düşülür. "
                     + "Kampanya/kupon katkısı, işlem bedeli ve POS kesintisi ayrı alan olarak girilmiyorsa "
                     + "kanal ayarındaki ek kesintiler ya da diğer kesintiler içindedir.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }
}

// MARK: - Ortak parçalar

struct MonthStepper: View {
    @Binding var month: MonthKey

    var body: some View {
        HStack {
            Button { month = Dates.addMonths(month, -1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.bold))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
            Spacer()
            Text(Dates.displayMonth(month)).font(.headline).foregroundStyle(Palette.ink)
            Spacer()
            Button { month = Dates.addMonths(month, 1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.vertical, 12)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

struct ResultSummary: View {
    var title: String
    var ciro: Kurus
    var gider: Kurus
    var kar: Kurus
    var marj: Double

    var body: some View {
        Card {
            VStack(spacing: 11) {
                Text(title.trUpper)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LabeledRow("Gerçek ciro", ciro.tl)
                LabeledRow("Toplam gider", gider.tl, tone: Palette.gider)
                Divider().overlay(Palette.separator)
                HStack(alignment: .firstTextBaseline) {
                    Text(kar < 0 ? "GERÇEK ZARAR" : "GERÇEK KÂR (VERGİ ÖNCESİ)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(kar.tl)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(kar < 0 ? Palette.zarar : Palette.kar)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                LabeledRow("Kâr marjı", Money.formatPercent(marj),
                           tone: kar < 0 ? Palette.zarar : Palette.kar)
            }
        }
    }
}

struct ExpenseBreakdownCard: View {
    var breakdown: [ExpenseCategory: Kurus]
    var total: Kurus

    private var rows: [(ExpenseCategory, Kurus)] {
        breakdown.filter { $0.value != 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            SectionTitle("Gider Dağılımı")
            Card {
                if rows.isEmpty {
                    Text("Bu dönemde gider yok.")
                        .font(.footnote).foregroundStyle(Palette.inkFaint)
                } else {
                    VStack(spacing: 12) {
                        ForEach(rows, id: \.0) { cat, amount in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(cat.displayName).font(.subheadline).foregroundStyle(Palette.inkSoft)
                                    Spacer()
                                    Text(amount.tl).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Palette.inset)
                                        Capsule().fill(Palette.gider.opacity(0.75))
                                            .frame(width: geo.size.width * share(amount))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                }
            }
        }
    }

    private func share(_ a: Kurus) -> CGFloat {
        total > 0 ? min(max(CGFloat(a) / CGFloat(total), 0), 1) : 0
    }
}
