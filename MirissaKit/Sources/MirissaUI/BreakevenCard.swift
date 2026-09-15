import SwiftUI
import MirissaCore

/// Ay başında hedef, ay sonunda gerçekleşen sonuç.
/// Kullanıcıdan günlük satış girişi beklenmez.
struct BreakevenCard: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    /// Önizleme ve ekran görüntüsü için detayları açık göstermeye yarar
    var detayAcik = false

    private var plan: BreakevenPlan { store.engine.plan(month: month) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                let p = plan
                header(p)
                if p.mode == .gerceklesen {
                    sonuc(p)
                    if p.issues.contains(.ayHenuzBitmedi) { gelismis(p) }
                } else if let engel = p.blocking {
                    Text(engel.message)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if engel == .referansYok { BeklenenProfilForm() }
                } else {
                    hedefler(p)
                    araDurumOzeti(p)
                    dayanak(p)
                    gelismis(p)
                }
                notlar(p)
            }
        }
    }

    // MARK: Başlık

    private func header(_ p: BreakevenPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Aylık sonuç".trUpper)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkFaint)
            Spacer()
            if p.mode == .hedef && p.isApproximate && p.canCompute {
                Pill("yaklaşık")
            }
        }
    }

    /// Bu ay için kaydedilmiş gider (henüz satış girilmediğinde gösterilir)
    private var kaydedilmisGider: Kurus {
        store.engine.companyMonth(month).toplamGider
    }

    // MARK: Hedef modu

    @ViewBuilder
    private func hedefler(_ p: BreakevenPlan) -> some View {
        // Sadece gider girilmiş olması "zarar" değildir: satış ay sonunda girilir.
        if !p.hasProgress {
            VStack(alignment: .leading, spacing: 9) {
                Text("Satış verisi henüz girilmedi")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                LabeledRow("Kaydedilmiş gider", kaydedilmisGider.tl, tone: Palette.gider)
                if let basaBas = p.targets.first(where: { $0.isBreakeven }) {
                    LabeledRow("Başa baş hedefi", "yaklaşık \(basaBas.orders) sipariş")
                    LabeledRow("Günlük ortalama hedef", "\(basaBas.dailyOrders) sipariş",
                               tone: Palette.uyari, strong: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let basaBas = p.targets.first(where: { $0.isBreakeven }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BAŞA BAŞ HEDEFİ")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.uyari)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(basaBas.orders) sipariş")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    Text("günde ~\(basaBas.dailyOrders)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.uyari)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Palette.uyariYumusak)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if !p.targets.filter({ !$0.isBreakeven }).isEmpty {
            Divider().overlay(Palette.separator)
            VStack(spacing: 10) {
                ForEach(p.targets.filter { !$0.isBreakeven }) { t in
                    TargetRow(target: t)
                }
            }
        }
    }

    // MARK: Ara dönem özeti (yalnızca işaretliyken görünür)

    @ViewBuilder
    private func araDurumOzeti(_ p: BreakevenPlan) -> some View {
        if p.hasProgress, let tarih = p.progressAsOf, let girilen = p.progressOrders,
           let kalanGun = p.remainingDays {
            Divider().overlay(Palette.separator)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Dates.displayDateShort(tarih))'e kadar \(girilen) sipariş girildi · \(kalanGun) gün kaldı")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                if let basaBas = p.targets.first(where: { $0.isBreakeven }),
                   let kalan = basaBas.remainingOrders {
                    if kalan == 0 {
                        Text("Başa baş hedefi tamamlandı.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.kar)
                    } else {
                        Text("Başa baş için kalan \(kalan) sipariş"
                             + (basaBas.remainingDailyOrders.map { " · günde ~\($0)" } ?? ""))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.uyari)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Gelişmiş (açılır) — ara dönem verisi

    private func gelismis(_ p: BreakevenPlan) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.separator).padding(.bottom, 12)
            Disclosure {
                HStack {
                    Text("Gelişmiş · Ara dönem verisi")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkFaint)
                    Spacer(minLength: 8)
                }
            } content: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Satışları ay sonunda tek seferde girmen yeterli — normal kullanım budur. Ay bitmeden ara toplam girdiysen bunu işaretleyebilirsin; sistem o zaman kalan günü ve kalan sipariş hedefini hesaplar.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if p.hasProgress {
                        Button("Ara dönem işaretini kaldır") {
                            store.setProgressAsOf(nil, for: month)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.zarar)
                    } else {
                        Button("Girilenleri ara toplam say") {
                            store.setProgressAsOf(Dates.today(), for: month)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Dayanak (açılır)

    private func dayanak(_ p: BreakevenPlan) -> some View {
        Disclosure(open: detayAcik) {
            HStack {
                Text("Bu hesap neye dayanıyor?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
            }
        } content: {
            VStack(spacing: 10) {
                Text(p.basis.explanation)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LabeledRow("Sipariş başına ortalama katkı",
                           Money.roundHalfAwayFromZero(p.contributionPerOrder).tl,
                           tone: Palette.accent)
                LabeledRow("Bu ayın sabit giderleri", p.fixedCosts.tl)
                if p.unitsPerOrder > 1.01 {
                    LabeledRow("Sipariş başına ürün",
                               String(format: "%.1f", p.unitsPerOrder).replacingOccurrences(of: ".", with: ","))
                }
                CustomGoalRow(month: month)
            }
        }
    }

    // MARK: Gerçekleşen modu

    private func sonuc(_ p: BreakevenPlan) -> some View {
        let a = p.actual ?? .bos
        return VStack(spacing: 9) {
            if let be = a.breakevenOrders {
                LabeledRow("Başa baş hedefi", "\(be) sipariş")
            }
            LabeledRow("Gerçekleşen sipariş", "\(a.orders) sipariş", strong: true)
            Divider().overlay(Palette.separator)
            LabeledRow("Gerçek ciro", a.revenue.tl)
            LabeledRow("Gerçek gider", a.expenses.tl, tone: Palette.gider)
            HStack(alignment: .firstTextBaseline) {
                Text(a.profit < 0 ? "GERÇEK ZARAR" : "GERÇEK KÂR")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(a.profit.tl)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(a.profit < 0 ? Palette.zarar : Palette.kar)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            LabeledRow("Kâr marjı", Money.formatPercent(a.marginPct),
                       tone: a.profit < 0 ? Palette.zarar : Palette.kar)
            if a.cashOut != a.expenses {
                LabeledRow("Bu ay ödenen (nakit çıkışı)", a.cashOut.tl, tone: Palette.inkSoft)
            }
            if let cumle = a.breakevenSentence {
                Text(cumle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(a.reachedBreakeven ? Palette.kar : Palette.zarar)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Notlar

    @ViewBuilder
    private func notlar(_ p: BreakevenPlan) -> some View {
        let gosterilecek = p.notes.filter { $0 != .araDurumIsaretli }
        if !gosterilecek.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(gosterilecek) { n in
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
}

// MARK: - Hedef satırı

private struct TargetRow: View {
    var target: MonthlyTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(target.label)
                    .font(.subheadline.weight(target.isCustom ? .semibold : .regular))
                    .foregroundStyle(target.isCustom ? Palette.ink : Palette.inkSoft)
                if target.isCustom { Pill("hedefim", tone: Palette.accent, background: Palette.karYumusak) }
                Spacer(minLength: 8)
                Text("\(target.orders) sipariş")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text(altSatir)
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
        }
    }

    private var altSatir: String {
        var parcalar = ["günlük ortalama \(target.dailyOrders) sipariş"]
        if let kalan = target.remainingOrders {
            parcalar = ["kalan \(kalan) sipariş"]
            if let g = target.remainingDailyOrders { parcalar.append("günde ~\(g)") }
        }
        if target.products > Double(target.orders) + 0.5 {
            parcalar.append("~\(Int(target.products.rounded())) ürün")
        }
        parcalar.append("~\(target.revenue.tl) ciro")
        return parcalar.joined(separator: " · ")
    }
}

// MARK: - Kendi hedefin

private struct CustomGoalRow: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

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

// MARK: - İlk ay: beklenen sipariş profili

private struct BeklenenProfilForm: View {
    @Environment(AppStore.self) private var store

    @State private var channelId: Id = ""
    @State private var productId: Id = ""
    @State private var ortalamaTutar: Kurus = 0
    @State private var yuklendi = false

    private var gecerli: Bool { !channelId.isEmpty && !productId.isEmpty && ortalamaTutar > 0 }

    var body: some View {
        VStack(spacing: 10) {
            Divider().overlay(Palette.separator)
            Text("Beklenen sipariş profili")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Ağırlıklı kanal", selection: $channelId) {
                Text("Seç").tag("")
                ForEach(store.state.activeChannels) { c in Text(c.name).tag(c.id) }
            }
            Picker("Ağırlıklı ürün", selection: $productId) {
                Text("Seç").tag("")
                ForEach(store.state.activeProducts) { p in Text(p.name).tag(p.id) }
            }
            MoneyField("Ortalama sipariş tutarı", placeholder: "örn. 700", value: $ortalamaTutar)

            Button("Hedefi hesapla") {
                store.setExpectedMix(ExpectedMix(
                    channelId: channelId, productId: productId,
                    averageOrderValue: ortalamaTutar
                ))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(gecerli ? Palette.accent : Palette.inkFaint)
            .disabled(!gecerli)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Bu sadece bir varsayım. İlk gerçek ayın tamamlanınca hedef kendiliğinden senin gerçek verinle hesaplanır.")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            guard !yuklendi else { return }
            yuklendi = true
            if let m = store.state.settings.expectedMix {
                channelId = m.channelId
                productId = m.productId
                ortalamaTutar = m.averageOrderValue
            } else {
                channelId = store.state.activeChannels.first?.id ?? ""
                productId = store.state.activeProducts.first?.id ?? ""
            }
        }
    }
}
