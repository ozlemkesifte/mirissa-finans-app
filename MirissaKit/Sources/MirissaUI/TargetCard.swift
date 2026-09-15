import SwiftUI
import MirissaCore

/// Ana sayfanın ilk ve en büyük kartı.
/// Tek soruya cevap verir: "Masrafları karşılamak için bu ay kaç kargo çıkarmalıyım?"
/// Satış verisi girilmemiş olsa bile çalışır.
struct HedefKarti: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: AppSheet?
    var month: MonthKey

    @State private var katkilarAcik = false

    private var plan: BreakevenPlan { store.engine.plan(month: month) }
    private var basaBas: MonthlyTarget? { plan.targets.first { $0.isBreakeven } }
    private var karHedefleri: [MonthlyTarget] { plan.targets.filter { !$0.isBreakeven } }

    var body: some View {
        let p = plan
        Card {
            VStack(alignment: .leading, spacing: 16) {
                if let be = basaBas {
                    basaBasBolumu(be, plan: p)
                    if !karHedefleri.isEmpty {
                        Divider().overlay(Palette.separator)
                        ForEach(karHedefleri) { t in
                            karHedefi(t)
                        }
                    }
                    notlar(p)
                    katkiOzeti
                } else {
                    eksikBolumu(p)
                }
            }
        }
    }

    // MARK: Başa baş

    private func basaBasBolumu(_ t: MonthlyTarget, plan p: BreakevenPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BU AY MASRAFLARI KARŞILAMAK İÇİN")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Text("Yaklaşık \(t.orders) kargo")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 14) {
                Label("Ayda \(t.orders)", systemImage: "calendar")
                Label("Günde ~\(t.dailyOrders)", systemImage: "sun.max")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.uyari)
            if let kalan = t.remainingOrders, let gunluk = t.remainingDailyOrders {
                Text("Girdiğin ara toplama göre kalan: \(kalan) kargo · günde ~\(gunluk)")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func karHedefi(_ t: MonthlyTarget) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Money.format(t.targetProfit)) KÂR İÇİN")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.inkFaint)
                Text("\(t.orders) kargo / ay")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            Text("≈ günde \(t.dailyOrders)")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Eksik bilgi

    private func eksikBolumu(_ p: BreakevenPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BU AY MASRAFLARI KARŞILAMAK İÇİN")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkFaint)
            Text(p.missing.isEmpty
                 ? "Hedef henüz hesaplanamıyor."
                 : "Başa baş hedefini hesaplamak için \(p.missing.count) bilgi eksik.")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !p.missing.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(p.missing.prefix(6)) { m in
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
                    if p.missing.count > 6 {
                        Text("… ve \(p.missing.count - 6) bilgi daha")
                            .font(.caption)
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                BigButton("Eksikleri Tamamla", icon: "checklist") {
                    sheet = .eksikleriTamamla
                }
            } else if let engel = p.blocking {
                Text(engel.message)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Notlar

    @ViewBuilder
    private func notlar(_ p: BreakevenPlan) -> some View {
        // Gerçekleşen kartında da görünen notlar burada tekrar edilmez
        let gosterilecek = p.notes.filter {
            $0 != .araDurumIsaretli && $0 != .ayHenuzBitmedi
        }
        VStack(alignment: .leading, spacing: 6) {
            if p.isApproximate {
                Text(p.basis.label)
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
            ForEach(gosterilecek) { n in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                    Text(n.message)
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !p.missing.isEmpty {
                Button("\(p.missing.count) bilgi eksik · Tamamla") {
                    sheet = .eksikleriTamamla
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bir satış ortalama ne bırakıyor

    @ViewBuilder
    private var katkiOzeti: some View {
        let liste = store.engine.unitContributions()
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(Palette.separator)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { katkilarAcik.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Bir satış ortalama ne bırakıyor?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        Image(systemName: katkilarAcik ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if katkilarAcik {
                    VStack(spacing: 8) {
                        ForEach(liste) { u in
                            LabeledRow("\(u.channelName) \(u.productName)",
                                       "yaklaşık \(Money.format(u.contribution))",
                                       tone: u.contribution < 0 ? Palette.zarar : Palette.ink)
                        }
                        Text("Fiyattan komisyon, kargo, ürün ve ambalaj maliyeti düşülmüş hali. "
                             + "Sabit giderler bu tutarlardan karşılanır.")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// "BU AY GERÇEKLEŞEN" — ana mesaj değil, ikinci bölüm.
struct GerceklesenKarti: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: AppSheet?
    var month: MonthKey

    private var r: CompanyMonthResult { store.engine.companyMonth(month) }
    private var satisVar: Bool { r.orders > 0 || r.gercekCiro != 0 }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("BU AY GERÇEKLEŞEN")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)

                if satisVar {
                    VStack(spacing: 9) {
                        LabeledRow("Gerçek ciro", r.gercekCiro.tl)
                        LabeledRow("Toplam gider", r.toplamGider.tl, tone: Palette.gider)
                        LabeledRow(r.isLoss ? "Gerçek zarar" : "Gerçek kâr",
                                   (r.isLoss ? -r.gercekKar : r.gercekKar).tl,
                                   tone: r.isLoss ? Palette.zarar : Palette.kar, strong: true)
                        LabeledRow("Kâr marjı", Money.formatPercent(r.karMarjiPct),
                                   tone: r.isLoss ? Palette.zarar : Palette.kar)
                    }
                } else {
                    Text("Bu ayın satışlarını henüz girmedin.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if r.toplamGider != 0 {
                        LabeledRow("Kaydedilmiş gider", r.toplamGider.tl, tone: Palette.gider)
                    }
                    Button("Satış gir") { sheet = .saleFlow }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                }
            }
        }
    }
}
