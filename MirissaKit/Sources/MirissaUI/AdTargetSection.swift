import SwiftUI
import MirissaCore

/// Hedef kartının altında açılan "Reklam hedefim ne olmalı?" bölümü.
/// Her rakamı düz bir cümleyle söyler; yeni menü açmaz.
struct ReklamHedefiBolumu: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey

    @State private var acik: Bool
    @State private var baskaTutar = false
    @State private var elleTutar: Kurus = 0
    @State private var butce: Kurus = 0

    init(month: MonthKey, acik: Bool = false) {
        self.month = month
        _acik = State(initialValue: acik)
    }

    private var birak: Kurus? { store.state.settings.adKeepPerOrder }
    private static let hazirTutarlar: [Kurus] = [0, 100, 150, 200].map { Money.fromTL(Double($0)) }
    private var ozelTutarSecili: Bool {
        guard let birak else { return false }
        return !Self.hazirTutarlar.contains(birak)
    }

    var body: some View {
        let e = store.engine
        let liste = e.adTargets(keepPerOrder: birak)
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider().overlay(Palette.separator)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { acik.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "megaphone")
                            .foregroundStyle(Palette.accent)
                        Text("Reklam hedefim ne olmalı?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        Image(systemName: acik ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if acik {
                    icerik(e, liste: liste)
                }
            }
        }
    }

    // MARK: İçerik

    @ViewBuilder
    private func icerik(_ e: Engine, liste: [AdTarget]) -> some View {
        let karisik = e.blendedAdTarget(month: month, keepPerOrder: birak)
        let eksik = e.missingForTarget(month: month)
            .filter { [.fiyat, .urunMaliyeti, .kanalKesintisi].contains($0.kind) }

        let maliyetsiz = Array(Set(liste.flatMap(\.missingCostProducts) + (karisik?.missingCostProducts ?? []))).sorted()
        let kesintisiz = Array(Set(liste.flatMap { t in t.missingFees.map { "\(t.channelName) \($0)" } })).sorted()

        VStack(alignment: .leading, spacing: 14) {
            if !maliyetsiz.isEmpty {
                uyari("Maliyeti girilmemiş: \(maliyetsiz.joined(separator: ", ")). Bu ürünlerin reklam hedefi "
                      + "hesaplanamaz; maliyet sıfır sayılsaydı hedef olduğundan kolay görünürdü. Önce maliyeti gir.",
                      renk: Palette.zarar, zemin: Palette.zararYumusak)
            }
            if !kesintisiz.isEmpty {
                uyari("Bilinmeyen kesinti: \(kesintisiz.joined(separator: ", ")). Bu kanalların hedefi yaklaşıktır; "
                      + "gerçek kesinti eklenince hedef zorlaşabilir.",
                      renk: Palette.uyari, zemin: Palette.uyariYumusak)
            } else if !eksik.isEmpty, maliyetsiz.isEmpty {
                uyari("Bazı fiyat bilgileri eksik. Fiyatı olmayan ürünler ortak hedefe katılmadı.",
                      renk: Palette.uyari, zemin: Palette.uyariYumusak)
            }

            birakSorusu

            if let k = karisik ?? (liste.count == 1 ? liste.first : nil) {
                if k.missingCostProducts.isEmpty {
                    anaHedef(k, tek: karisik == nil)
                    butceBolumu(e, hedef: k)
                    gerceklesen(e, hedef: k)
                } else {
                    cumle("Ortak hedef, maliyeti girilmemiş ürünler yüzünden şu an hesaplanamıyor.")
                }
            } else {
                Text("Hangi üründen ne kadar sattığın belli olmadığı için tek bir ortak hedef çıkaramıyorum. "
                     + "Aşağıda her ürünün kendi hedefi var.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            urunBazinda(liste)

            Text("Nasıl hesaplandı: Sipariş değeri müşterinin ödediği KDV dahil tutardır (reklam panelleri böyle raporlar). "
                 + "Siparişte birden çok ürün varsa hepsi sayılır; kargo ve hizmet bedeli siparişte bir kez düşülür. "
                 + "Bundan KDV, komisyon, kargo, hizmet bedeli, ürün ve ambalaj maliyeti düşülünce reklama kalan tutar bulunur. "
                 + "ROAS = sipariş değeri ÷ bir siparişe harcanan reklam. Reklam harcaması KDV hariç alınır. "
                 + "Sabit giderler (kira, maaş) burada yok; onlar yukarıdaki kargo hedefinde.")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Siparişte ne kalsın

    private var birakSorusu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reklam parası çıktıktan sonra her siparişte en az ne kalsın?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bu para sabit giderlerini ve kârını karşılar. Emin değilsen 150 TL iyi bir başlangıç.")
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach([0, 100, 150, 200], id: \.self) { t in
                    let k = Money.fromTL(Double(t))
                    secenek(t == 0 ? "Sadece zarar etmeyeyim" : "\(t) TL",
                            secili: birak == k && !baskaTutar) {
                        baskaTutar = false
                        store.setAdKeepPerOrder(k)
                    }
                }
            }
            HStack(spacing: 8) {
                secenek(ozelTutarSecili ? "Başka tutar: \(Money.format(birak ?? 0))" : "Başka tutar",
                        secili: baskaTutar || ozelTutarSecili) {
                    baskaTutar = true
                    elleTutar = birak ?? 0
                }
                if baskaTutar {
                    paraAlani($elleTutar)
                    Button("Kaydet") {
                        store.setAdKeepPerOrder(max(elleTutar, 0))
                        baskaTutar = false
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                }
            }
        }
    }

    // MARK: Ana hedef

    @ViewBuilder
    private func anaHedef(_ k: AdTarget, tek: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tek ? "\(k.channelName) \(k.productName) için" : "Satış karışımına göre ortalama bir sipariş için")
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(Palette.inkFaint)

            if k.reklamsizZarar {
                uyari("Bir sipariş ortalama \(Money.format(k.orderValue)). Reklam olmadan bile her siparişte "
                      + "\(Money.format(-k.beforeAds)) zarar ediliyor. Bu durumda reklam zararı büyütür. "
                      + "Önce fiyatı ya da maliyetleri düzeltmek gerekir.",
                      renk: Palette.zarar, zemin: Palette.zararYumusak)
            } else if let bb = k.breakevenROAS {
                cumle("Bir sipariş ortalama \(Money.format(k.orderValue)) (KDV dahil). Kesintiler, KDV ve maliyetler "
                      + "düşünce reklama \(Money.format(k.beforeAds)) kalıyor.")
                cumle(adetCumlesi(k))

                buyukSatir("Zarar sınırı", "ROAS \(RoasFormat.format(bb))", renk: Palette.zarar)
                cumle("\(panel(k, tek: tek)) ROAS \(RoasFormat.format(bb)) altına düşerse reklamla gelen her satış zarar ettirir. "
                      + "Bir siparişe \(Money.format(k.beforeAds)) üstünde reklam harcanırsa zarar başlar.")

                if let birak, birak > 0 {
                    if let hedef = k.targetROAS {
                        buyukSatir("Hedef", "ROAS \(RoasFormat.format(hedef))", renk: Palette.kar)
                        buyukSatir("Sipariş başı en fazla", Money.format(k.maxCPA), renk: Palette.kar)
                        cumle("Her siparişte \(Money.format(birak)) kalması için \(panel(k, tek: tek)) ROAS en az "
                              + "\(RoasFormat.format(hedef)) olmalı. Başka bir deyişle sipariş (satın alma) başına "
                              + "reklam maliyeti \(Money.format(k.maxCPA)) tutarını geçmemeli.")
                    } else {
                        uyari("Seçtiğin \(Money.format(birak)) bu siparişlerde kalamaz: reklamdan önce "
                              + "zaten \(Money.format(k.beforeAds)) kalıyor. Daha düşük bir tutar seç "
                              + "ya da fiyatı gözden geçir.",
                              renk: Palette.uyari, zemin: Palette.uyariYumusak)
                    }
                } else if birak == 0 {
                    cumle("Sadece zarar etmemeyi seçtin. ROAS \(RoasFormat.format(bb)) olursa reklamdan ne kâr ne zarar "
                          + "edersin; sabit giderler için hiçbir şey kalmaz. Gerçek hedef bunun üstünde olmalı.")
                } else {
                    cumle("Hedef ROAS için yukarıdan her siparişte ne kalmasını istediğini seç.")
                }
            }
        }
    }

    // MARK: Bütçe

    @ViewBuilder
    private func butceBolumu(_ e: Engine, hedef k: AdTarget) -> some View {
        if !k.reklamsizZarar, k.maxCPA > 0 {
            let harcanan = e.adPerformance(month: month).adSpend
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(Palette.separator)
                Text("Bütçe hesabı")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    Text("Bu ay reklama")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                    paraAlani($butce)
                    Text("harcarsam")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                }
                if butce > 0, let adet = e.ordersForBudget(butce, target: k) {
                    let sinir = birak.map { $0 > 0 } ?? false
                    cumle("\(Money.format(butce)) harcarsan reklamdan en az \(adet) sipariş gelmeli"
                          + (sinir ? " ki her siparişte \(Money.format(birak ?? 0)) kalsın." : ", yoksa zarar edersin.")
                          + " Bu, en az \(Money.format(k.orderValue * adet)) satış demek.")
                } else if harcanan == 0 {
                    Text("Bir tutar yaz; kaç sipariş gelmesi gerektiğini söyleyeyim.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .onAppear { if butce == 0 { butce = harcanan } }
        }
    }

    // MARK: Gerçekleşen

    @ViewBuilder
    private func gerceklesen(_ e: Engine, hedef k: AdTarget) -> some View {
        let p = e.adPerformance(month: month)
        if p.adSpend > 0, p.revenue <= 0 {
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(Palette.separator)
                Text("Bu ay ne oldu?")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                cumle("Bu ay reklama \(Money.format(p.adSpend)) girdin ama henüz satış girmedin. "
                      + "Satışları girince reklamın hedefin üstünde mi altında mı olduğunu söyleyeceğim.")
            }
        } else if let mer = p.mer {
            let hukum = e.adVerdict(p, target: k)
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(Palette.separator)
                Text("Bu ay ne oldu?")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                cumle("Girdiğin kayıtlara göre reklama \(Money.format(p.adSpend)) harcadın, toplam satışın "
                      + "\(Money.format(p.revenue)). Her 1 TL reklama \(RoasFormat.format(mer)) TL satış geldi.")
                switch hukum {
                case .zarar:
                    uyari("Bu, zarar sınırı olan \(RoasFormat.format(k.breakevenROAS ?? 0))'in altında. "
                          + "Şu anki haliyle reklam para kaybettiriyor.",
                          renk: Palette.zarar, zemin: Palette.zararYumusak)
                case .basaBasUstu:
                    if let h = k.targetROAS {
                        uyari("Zarar sınırının üstündesin ama hedef olan \(RoasFormat.format(h))'e ulaşmadın. "
                              + "Reklam zarar ettirmiyor, ama istediğin kadar da bırakmıyor.",
                              renk: Palette.uyari, zemin: Palette.uyariYumusak)
                    } else {
                        uyari("Zarar sınırının üstündesin. Hedef seçersen hedefe göre de söylerim.",
                              renk: Palette.kar, zemin: Palette.karYumusak)
                    }
                case .hedefUstu:
                    uyari("Hedefin üstündesin. Reklam istediğin kadar bırakıyor.",
                          renk: Palette.kar, zemin: Palette.karYumusak)
                case .veriYok:
                    EmptyView()
                }
                if let cpa = p.cpa {
                    cumle("Sipariş başına ortalama \(Money.format(cpa)) reklam düştü (tüm siparişler dahil).")
                }
                Text("Bu oran tüm satışlara ve tüm reklam giderlerine bakar. Reklam panellerinin kendi gösterdiği ROAS "
                     + "genelde daha yüksektir çünkü reklamsız gelecek satışları da kendine yazar. Kararı bu orana göre "
                     + "vermek daha güvenli."
                     + (pazaryeriSatisiVar(e) ? " Pazaryeri satışları da dahil olduğu için panelde gördüğünle birebir aynı olmaz." : ""))
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Ürün bazında

    @ViewBuilder
    private func urunBazinda(_ liste: [AdTarget]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Palette.separator)
            Text("Ürün ve kanal bazında")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
            ForEach(liste) { t in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(t.channelName) · \(t.productName)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text(satirMetni(t))
                        .font(.caption)
                        .foregroundStyle(t.reklamsizZarar ? Palette.zarar
                                         : (t.hedefiKaldirmiyor ? Palette.uyari : Palette.inkSoft))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func satirMetni(_ t: AdTarget) -> String {
        if !t.missingCostProducts.isEmpty {
            return "Maliyeti girilmediği için hesaplanamıyor: \(t.missingCostProducts.joined(separator: ", "))"
        }
        guard let bb = t.breakevenROAS else {
            return "Reklamsız bile siparişte \(Money.format(-t.beforeAds)) zarar. Reklam verme."
        }
        var s = "Sipariş \(Money.format(t.orderValue))"
        if t.unitsPerOrder > 1.001 { s += " (ort. \(adetMetni(t.unitsPerOrder)) ürün)" }
        s += " · zarar sınırı ROAS \(RoasFormat.format(bb))"
        if let h = t.targetROAS, let birak, birak > 0 {
            s += " · hedef ROAS \(RoasFormat.format(h)) · siparişe en fazla \(Money.format(t.maxCPA)) reklam"
        } else if t.hedefiKaldirmiyor {
            s += " · seçtiğin tutarı bırakamaz, en fazla \(Money.format(t.beforeAds)) kalıyor"
        } else {
            s += " · siparişe en fazla \(Money.format(t.beforeAds)) reklam"
        }
        return s
    }

    // MARK: Parçalar

    /// Hangi reklam panelinden söz edildiği: pazaryeri kendi panelidir, Meta değil.
    private func panel(_ k: AdTarget, tek: Bool) -> String {
        if tek { return k.isMarketplace ? "\(k.channelName) reklamlarında" : "Meta / Google reklamlarında" }
        return k.isMarketplace ? "Pazaryeri reklamlarında" : "Reklam panelinde (Meta vb.)"
    }

    private func adetMetni(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.decimalSeparator = ","
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "1"
    }

    private func adetCumlesi(_ k: AdTarget) -> String {
        if k.unitsPerOrderKnown {
            return "Girdiğin sipariş sayılarına göre bir siparişte ortalama \(adetMetni(k.unitsPerOrder)) ürün var; "
                + "hesap buna göre yapıldı."
        }
        return "Sipariş sayısı girilmediği için her siparişte 1 ürün olduğu kabul edildi. "
            + "Satış girerken sipariş sayısını da yazarsan hesap gerçek sepete göre yapılır."
    }

    private func pazaryeriSatisiVar(_ e: Engine) -> Bool {
        e.companyMonth(month).channels.contains { c in
            c.netSales > 0 && store.state.channel(c.channelId)?.kind == .marketplace
        }
    }

    private func cumle(_ s: String) -> some View {
        Text(s)
            .font(.footnote)
            .foregroundStyle(Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buyukSatir(_ etiket: String, _ deger: String, renk: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(etiket).font(.footnote).foregroundStyle(Palette.inkFaint)
            Spacer(minLength: 8)
            Text(deger)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(renk)
        }
    }

    private func uyari(_ s: String, renk: Color, zemin: Color) -> some View {
        Text(s)
            .font(.footnote.weight(.medium))
            .foregroundStyle(renk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(zemin, in: RoundedRectangle(cornerRadius: 10))
    }

    private func secenek(_ baslik: String, secili: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(baslik)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(secili ? Palette.onFilled : Palette.ink)
                .background(secili ? Palette.accent : Palette.inset,
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func paraAlani(_ deger: Binding<Kurus>) -> some View {
        KucukParaAlani(deger: deger)
    }
}

/// Satır içi küçük para girişi; yazılan metin değerle eşit tutulur.
private struct KucukParaAlani: View {
    @Binding var deger: Kurus
    @State private var metin = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $metin)
                .font(.footnote.weight(.semibold))
                .numericKeyboard()
                .frame(minWidth: 60, maxWidth: 110)
            Text("TL").font(.caption).foregroundStyle(Palette.inkFaint)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { metin = deger == 0 ? "" : NumberInput.display(deger) }
        .onChange(of: metin) { _, yeni in deger = NumberInput.kurus(yeni) ?? 0 }
        .onChange(of: deger) { _, yeni in
            if let taze = NumberInput.senkron(metin: metin, kurus: yeni) { metin = taze }
        }
    }
}
