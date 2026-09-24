import SwiftUI
import MirissaCore

/// Ana ekran: şirket sahibinin karar paneli. Yalnızca beş sorunun cevabı:
/// bu ay ne sattım, kâr/zarar ne, başa baş için kaç kargo, seçili kâr hedefi için kaç kargo,
/// bu yıl ne durumdayım. Vergi, KDV, kanal kesintileri, gider ve stok maliyeti ayrıntıları
/// "Finans & Vergiler" sekmesindedir; ana ekrana taşınmaz.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @Binding var tab: Int
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    MonthStepper(month: Bindable(period).month)
                    if let hata = store.loadError { yuklemeHatasi(hata) }
                    ButunlukKarti()
                    BuAyKarti(month: period.month, sheet: $sheet) { finansaGit(.aylik) }
                    BuAyHedefKarti(month: period.month, sheet: $sheet)
                    BuYilKarti(year: period.year, sheet: $sheet)
                    islemler
                    NavigationLink {
                        HatirlatmalarEkrani()
                    } label: {
                        HStack {
                            Label("Hatırlatmalar ve yapılacaklar", systemImage: "checklist")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(Metrics.pad)
                        .background(Palette.card)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
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

    /// "Nasıl hesaplandı?" — Finans & Vergiler sekmesinin ilgili bölümünü açar
    private func finansaGit(_ bolum: ReportTab) {
        UserDefaults.standard.set(bolum.rawValue, forKey: "raporSekmesi")
        period.scope = .month
        tab = 4
    }

    private func yuklemeHatasi(_ hata: String) -> some View {
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
}

// MARK: - Ana ekran kartları

/// Kart başlığı ve sağında "Nasıl hesaplandı?" bağlantısı
private struct KartBasligi<Hedef: View>: View {
    var baslik: String
    var yaklasik = false
    @ViewBuilder var detay: () -> Hedef

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(baslik)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkFaint)
            if yaklasik { Pill("yaklaşık") }
            Spacer(minLength: 8)
            detay()
        }
    }
}

/// "Nasıl hesaplandı?" bağlantı yazısı
struct NasilHesaplandi: View {
    var body: some View {
        Text("Nasıl hesaplandı?")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.accent)
    }
}

/// BU AY: gerçek ciro, kâr/zarar, kâr marjı. Satış girilmediyse 0 TL yerine tek cümle.
struct BuAyKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @Binding var sheet: AppSheet?
    var detay: () -> Void

    var body: some View {
        let e = store.engine
        let r = e.companyMonth(month)
        let durum = e.satisDurumu(month)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                KartBasligi(baslik: "BU AY", yaklasik: r.yaklasikUyarisi != nil || r.maliyetDegisimUyarisi != nil) {
                    if durum != .girilmedi {
                        Button(action: detay) { NasilHesaplandi() }.buttonStyle(.plain)
                    }
                }
                if durum == .girilmedi {
                    Text("Bu ayın satışları henüz girilmedi.")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Button("Satış gir") { sheet = .saleFlow }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                } else {
                    if durum == .sifirSatis {
                        Text("Bu ay satış olmadı olarak işaretlendi.")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSoft)
                    }
                    SadeSatir("Ciro", r.gercekCiro.tl)
                    SadeSatir(r.isLoss ? "Zarar (vergi öncesi)" : "Kâr (vergi öncesi)",
                              (r.gercekKar > 0 ? "+" : "") + r.gercekKar.tl
                                + (r.gercekCiro > 0 ? " · " + Money.formatPercent(r.karMarjiPct) : ""),
                              tone: r.isLoss ? Palette.zarar : Palette.kar)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// BU AY HEDEF: başa baş kargo, günlük ortalama ve seçili tek kâr hedefi.
struct BuAyHedefKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @Binding var sheet: AppSheet?

    var body: some View {
        let e = store.engine
        let p = e.plan(month: month)
        let basaBas = p.targets.first { $0.isBreakeven }
        let secili = p.targets.first { !$0.isBreakeven }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                KartBasligi(baslik: "HEDEF", yaklasik: p.isApproximate && p.canCompute) {
                    NavigationLink { HedefDetayEkrani(month: month) } label: { NasilHesaplandi() }
                        .buttonStyle(.plain)
                }
                if let be = basaBas {
                    SadeSatir("Başa baş", "\(be.orders) kargo", buyuk: true)
                    Text("≈ günde \(be.dailyOrders) kargo")
                        .font(.subheadline)
                        .foregroundStyle(Palette.uyari)
                    if let t = secili {
                        SadeSatir(e.karHedefiBasligi(month: month) ?? "Seçili kâr hedefi", "\(t.orders) kargo")
                    } else if let neden = e.karHedefiHesaplanamadi(month: month) {
                        Text(neden).font(.caption).foregroundStyle(Palette.uyari)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Aylık kâr hedefi her zaman buradan seçilir / değiştirilir
                    Button { sheet = .karHedefi(month) } label: {
                        Label(store.state.settings.profitGoal(for: month) == nil ? "Aylık kâr hedefi seç" : "Aylık kâr hedefini değiştir",
                              systemImage: "target")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                    StokYetersizUyarisi(gereken: secili?.orders ?? be.orders, month: month)
                    ReklamOzetSatiri(month: month)
                } else {
                    Text(p.missing.isEmpty ? (p.blocking?.message ?? "Hedef henüz hesaplanamıyor.")
                         : "Hedefi hesaplamak için \(p.missing.count) bilgi gerekiyor.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if !p.missing.isEmpty {
                        Button("Eksikleri tamamla") { sheet = .eksikleriTamamla }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Ana ekranda reklamın tek satırı: zarar sınırı ROAS ve (seçildiyse) hedef ROAS.
/// Dokununca reklam hedefi ekranı açılır (siparişte ne kalsın, bütçe, ürün bazında).
struct ReklamOzetSatiri: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    var body: some View {
        let e = store.engine
        let birak = store.state.settings.adKeepPerOrder
        let liste = e.adTargets(keepPerOrder: birak)
        let k = e.blendedAdTarget(month: month, keepPerOrder: birak) ?? (liste.count == 1 ? liste.first : nil)
        if !liste.isEmpty {
            NavigationLink { ReklamHedefiEkrani(month: month) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "megaphone").foregroundStyle(Palette.accent)
                    Text(ozet(k)).font(.subheadline).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.inkFaint)
                }
                .padding(.top, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func ozet(_ k: AdTarget?) -> String {
        guard let k else { return "Reklam: ürün bazında hedefler" }
        if k.gerceklesmeOlagandisi { return "Reklam: hedef hesaplanamadı (olağandışı oran)" }
        guard let bb = k.breakevenROAS else { return "Reklam: reklamsız bile zarar" }
        var s = "Reklam: zarar sınırı ROAS \(RoasFormat.format(bb))"
        if let h = k.targetROAS { s += " · hedef ROAS \(RoasFormat.format(h))" }
        else if k.hedefiKaldirmiyor { s += " · seçilen tutar mümkün değil" }
        return s
    }
}

/// Reklam hedefi ekranı (ana ekrandaki reklam satırından açılır)
struct ReklamHedefiEkrani: View {
    var month: MonthKey

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.gap) {
                ReklamRaporu(month: month)
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 4)
        }
        .screenBackground()
        .navigationTitle("Reklam hedefi")
    }
}

/// Stok yalnızca yetersizse kısa bir satırla söylenir; hedefin kendisini değiştirmez.
struct StokYetersizUyarisi: View {
    @Environment(AppStore.self) private var store
    var gereken: Int
    var month: MonthKey

    var body: some View {
        // Bu ay: zaten gönderilen siparişler stoktan düşmüştür; yalnızca kalan hedef karşılaştırılır
        let kalan = month == Dates.currentMonth() ? max(gereken - store.engine.companyMonth(month).orders, 0) : gereken
        if month >= Dates.currentMonth(), let k = store.engine.stokKapasitesi(), k.kargo < kalan {
            Label("Stok yetersiz: mevcut stokla yaklaşık \(k.kargo) kargo hazırlanabilir (\(k.darbogaz)).",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.zarar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// BU YIL: yıllık ciro, kâr/zarar, marj, yıllık başa baş ve yıl geneli ortalamalar, seçili yıllık hedef.
struct BuYilKarti: View {
    @Environment(AppStore.self) private var store
    var year: Int
    @Binding var sheet: AppSheet?

    var body: some View {
        let e = store.engine
        let yp = e.yearlyPlan(year: year)
        let satisVar = yp.actualRevenue != 0 || yp.actualOrders > 0
        let basaBas = yp.targets.first { $0.isBreakeven }
        let secili = yp.targets.first { !$0.isBreakeven }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                KartBasligi(baslik: "BU YIL · \(year)", yaklasik: yp.isApproximate && yp.canCompute) {
                    NavigationLink { YillikDetayEkrani(year: year) } label: { NasilHesaplandi() }
                        .buttonStyle(.plain)
                }
                if satisVar {
                    SadeSatir("Ciro", yp.actualRevenue.tl)
                    SadeSatir(yp.actualProfit < 0 ? "Zarar (vergi öncesi)" : "Kâr (vergi öncesi)",
                              (yp.actualProfit > 0 ? "+" : "") + yp.actualProfit.tl
                                + (yp.actualRevenue > 0 ? " · " + Money.formatPercent(yp.actualMarginPct) : ""),
                              tone: yp.actualProfit < 0 ? Palette.zarar : Palette.kar)
                } else {
                    Text("Bu yılın satışları henüz girilmedi.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                }
                if let be = basaBas {
                    Divider().overlay(Palette.separator)
                    SadeSatir("Başa baş", "\(be.ordersPerYear) kargo / yıl")
                    Text("≈ \(be.ordersPerMonth) / ay · \(be.ordersPerDay) / gün (yıl geneli ortalama)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.uyari)
                    if let t = secili {
                        SadeSatir(e.yillikKarHedefiBasligi(year: year) ?? "Seçili yıllık hedef",
                                  "\(t.ordersPerYear) kargo")
                    } else if let neden = e.yillikKarHedefiHesaplanamadi(year: year) {
                        Text(neden).font(.caption).foregroundStyle(Palette.uyari)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { sheet = .yillikKarHedefi(year) } label: {
                        Label(store.state.settings.yearlyProfitGoal(for: year) == nil ? "Yıllık kâr hedefi seç" : "Yıllık kâr hedefini değiştir",
                              systemImage: "target")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                } else if let engel = yp.blocking {
                    Text(engel.message)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Ana ekranın sade satırı: solda etiket, sağda büyük rakam
struct SadeSatir: View {
    var etiket: String
    var deger: String
    var tone: Color = Palette.ink
    var buyuk = false

    init(_ etiket: String, _ deger: String, tone: Color = Palette.ink, buyuk: Bool = false) {
        self.etiket = etiket; self.deger = deger; self.tone = tone; self.buyuk = buyuk
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(etiket)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(deger)
                .font(.system(buyuk ? .title2 : .title3, design: .rounded).weight(.semibold))
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Detay ekranları (ana ekrandan "Nasıl hesaplandı?" ile açılır)

/// Aylık hedefin bütün hesabı: sabit giderler, sipariş başı katkı, reklam hedefi, stok.
struct HedefDetayEkrani: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @State private var sheet: AppSheet?

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.gap) {
                HedefKarti(sheet: $sheet, month: month)
                StokKapasitesiKarti(month: month)
                if store.engine.satisDurumu(month) != .girilmedi {
                    BreakevenCard(month: month)
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 4)
        }
        .screenBackground()
        .navigationTitle("\(Dates.displayMonth(month)) hedefi")
        .appSheets($sheet)
    }
}

/// Hedef için gereken kargo ile mevcut stokla hazırlanabilecek kargo (bilgi; hedefi değiştirmez)
struct StokKapasitesiKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    var body: some View {
        let e = store.engine
        let p = e.plan(month: month)
        if month >= Dates.currentMonth(),
           let t = p.targets.first(where: { !$0.isBreakeven }) ?? p.targets.first, let k = e.stokKapasitesi() {
            let gonderilen = month == Dates.currentMonth() ? e.companyMonth(month).orders : 0
            let kalan = max(t.orders - gonderilen, 0)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STOK")
                        .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Palette.inkFaint)
                    Text("Bu hedef için \(t.orders) kargo gerekiyor"
                         + (gonderilen > 0 ? " (\(gonderilen) gönderildi, \(kalan) kaldı)" : "")
                         + ". Mevcut stokla yaklaşık \(k.kargo) kargo hazırlanabilir.")
                        .font(.subheadline)
                        .foregroundStyle(k.kargo < kalan ? Palette.zarar : Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("İlk bitecek kalem: \(k.darbogaz). Hesap, son ayların sipariş başına gerçek tüketiminden gelir; hedefin kendisini değiştirmez.")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Yıllık hedefin ayrıntısı: aktif ay ortalaması, en yoğun ay, hedef düzenleme
struct YillikDetayEkrani: View {
    var year: Int
    @State private var sheet: AppSheet?

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.gap) {
                YearlyCard(year: year, sheet: $sheet)
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 4)
        }
        .screenBackground()
        .navigationTitle("\(year) hedefi")
        .appSheets($sheet)
    }
}

/// Ana ekrandan kaldırılan hatırlatma ve iş kartları
struct HatirlatmalarEkrani: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: AppSheet?

    var body: some View {
        let uyarilar = store.engine.stockAlerts()
        ScrollView {
            VStack(spacing: Metrics.gap) {
                AySonuKarti(sheet: $sheet)
                YedekHatirlatmaKarti()
                YarimIslemKarti(sheet: $sheet)
                PriceCheckCard(sheet: $sheet)
                SiparisZamaniKarti()
                if !uyarilar.isEmpty {
                    SectionTitle("Stok Uyarıları")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(uyarilar.enumerated()), id: \.element.id) { i, a in
                                StockAlertRow(alert: a)
                                    .padding(.horizontal, Metrics.pad)
                                    .padding(.vertical, 12)
                                if i < uyarilar.count - 1 {
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
        .navigationTitle("Yapılacaklar")
        .appSheets($sheet)
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
