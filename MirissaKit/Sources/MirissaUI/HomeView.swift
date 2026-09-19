import SwiftUI
import MirissaCore

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @Binding var tab: Int
    @State private var sheet: AppSheet?

    private var result: CompanyMonthResult { period.result(store.engine) }
    private var alerts: [StockAlert] { store.engine.stockAlerts() }   // bugünkü stok, bugünkü hız

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    PeriodPicker(period: period)
                    if let hata = store.loadError {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Verilerin açılamadı", systemImage: "exclamationmark.octagon.fill")
                                    .font(.headline)
                                    .foregroundStyle(Palette.zarar)
                                Text(hata)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Şu an gördüğün boş başlangıç verisidir. Yeni kayıt girmeden önce "
                                     + "Ayarlar → Yedekten geri yükle ile son yedeğini aç.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    AySonuKarti(sheet: $sheet)
                    YedekHatirlatmaKarti()
                    ButunlukKarti()

                    // 1) HEDEF — satış girilmemiş olsa bile çalışır.
                    //    Ana ekranın ilk sorusu: bu ay kaç kargo çıkarmalıyım?
                    if period.scope == .month {
                        HedefKarti(sheet: $sheet, month: period.month)
                    } else {
                        YearlyCard(year: period.year, sheet: $sheet)
                    }

                    // 2) GERÇEKLEŞEN — satış girildiyse rakamlar, girilmediyse tek cümle.
                    if period.scope == .month {
                        if satisGirilmedi {
                            GerceklesenKarti(sheet: $sheet, month: period.month)
                        } else {
                            // Satış girildiyse gerçekleşen kartı tüm dökümü gösterir
                            BreakevenCard(month: period.month)
                        }
                    } else {
                        headline
                    }
                    EksikBilgiNotu(uyari: result.yaklasikUyarisi)
                    EksikBilgiNotu(uyari: result.maliyetDegisimUyarisi)
                    if !satisGirilmedi || period.scope == .year {
                        VergiKarti(month: period.scope == .month ? period.month : min(period.to, Dates.currentMonth()))
                    }
                    NakitOzetKarti {
                        UserDefaults.standard.set(ReportTab.nakit.rawValue, forKey: "raporSekmesi")
                        tab = 4
                    }
                    islemler
                    YarimIslemKarti(sheet: $sheet)
                    PriceCheckCard(sheet: $sheet)
                    SiparisZamaniKarti()
                    if !alerts.isEmpty { stockAlerts }
                    TrendChart(
                        points: trendPoints,
                        title: period.scope == .month ? "Son 6 Ay" : "\(period.year) Ayları"
                    )
                    channels
                    urunlerVeStoklar
                    Color.clear.frame(height: 24)
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
                // Yıllık görünümde kart yılın toplamını gösterir; tek ayın kesinti formu açılmaz
                ChannelCard(result: c, onEdit: period.scope == .month
                            ? { sheet = .channelMonth(c.channelId, period.month) } : nil)
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

    // MARK: Tek büyük giriş

    private var islemler: some View {
        Button { sheet = .yeniIslem } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Yeni İşlem")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(Palette.onFilled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Yeni işlem ekle")
    }

    // MARK: Ürünler ve stoklar

    private struct StokSatiri: Identifiable {
        var ref: ItemRef
        var ad: String
        var miktar: String
        var durum: StockStatus
        var id: String { ref.id }
    }

    private var stokSatirlari: [StokSatiri] {
        var out: [StokSatiri] = []
        for p in store.state.activeProducts where p.tracksOwnStock {
            let r = ItemRef.product(p.id)
            out.append(StokSatiri(ref: r, ad: p.name,
                                  miktar: Units.formatQty(store.engine.qty(r), baseUnit: .adet),
                                  durum: store.engine.status(r)))
        }
        for m in store.state.activeMaterials {
            let r = ItemRef.material(m.id)
            out.append(StokSatiri(ref: r, ad: m.name,
                                  miktar: Units.formatQty(store.engine.qty(r), baseUnit: m.baseUnit),
                                  durum: store.engine.status(r)))
        }
        return out
    }

    private var urunlerVeStoklar: some View {
        let hepsi = stokSatirlari
        let gosterilen = Array(hepsi.prefix(6))
        return VStack(spacing: Metrics.gap) {
            SectionTitle("Ürünler ve Stoklar", actionLabel: hepsi.count > 6 ? "Tümü" : nil) {
                tab = 3
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(gosterilen.enumerated()), id: \.element.id) { i, r in
                        NavigationLink {
                            if r.ref.kind == .product {
                                ProductDetail(productId: r.ref.id)
                            } else {
                                MaterialDetail(materialId: r.ref.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(r.ad).font(.subheadline).foregroundStyle(Palette.ink)
                                Spacer(minLength: 8)
                                Text(r.miktar)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(r.durum == .normal ? Palette.ink
                                                     : (r.durum == .azaliyor ? Palette.uyari : Palette.zarar))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, Metrics.pad)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < gosterilen.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                    if hepsi.count > 6 {
                        Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        Button { tab = 3 } label: {
                            Text("+ \(hepsi.count - 6) kalem daha")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
                    if result.koliSayisi > 0 {
                        LabeledRow("Gönderilen koli", "\(Int(result.koliSayisi))",
                                   tone: Palette.inkSoft, badge: result.koliTahmini ? "tahmini" : nil)
                    }
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
