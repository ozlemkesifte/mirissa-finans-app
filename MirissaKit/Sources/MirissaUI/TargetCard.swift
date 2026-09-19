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
                    Divider().overlay(Palette.separator)
                    ForEach(karHedefleri) { t in
                        karHedefi(t)
                    }
                    KarHedefiGirisi(month: month)
                    notlar(p)
                    SabitGiderDokumuBolumu(plan: p)
                    katkiOzeti
                    ReklamHedefiBolumu(month: month)
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
                Text((store.engine.karHedefiBasligi(month: month) ?? "\(Money.format(t.targetProfit)) kâr için").trUpper)
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if store.engine.hedefVergiSonrasi(month) {
                    Text("Vergi öncesi karşılığı yaklaşık \(Money.format(t.targetProfit))")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                }
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

    /// Tek eksik "dağılım sorusu" ise bu bir veri eksiği değil,
    /// sorulmamış bir sorudur — kullanıcıya hata gibi gösterilmez.
    private var yalnizcaDagilimSorusu: Bool {
        plan.missing.count == 1 && plan.missing.first?.kind == .dagilim
    }

    @ViewBuilder
    private func eksikBolumu(_ p: BreakevenPlan) -> some View {
        if yalnizcaDagilimSorusu {
            VStack(alignment: .leading, spacing: 14) {
                Text("BU AY MASRAFLARI KARŞILAMAK İÇİN")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)
                Text("Tek bir soru kaldı")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text("Satışlarının hangi kanal ve üründen geldiğini söylersen "
                     + "bu ay kaç kargo çıkarman gerektiğini hesaplayabilirim. "
                     + "Bir dakika sürer, kesin olması da gerekmiyor.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                BigButton("Dağılımı gir", icon: "chart.pie") {
                    sheet = .satisDagilimi
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            eksikListesi(p)
        }
    }

    private func eksikListesi(_ p: BreakevenPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BU AY MASRAFLARI KARŞILAMAK İÇİN")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkFaint)
            Text(p.missing.isEmpty
                 ? "Hedef henüz hesaplanamıyor."
                 : "Hedefi hesaplamak için \(p.missing.count) şey gerekiyor.")
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
                        Text("Fiyattan KDV, komisyon, ödeme kesintisi, kargo, hizmet bedeli, diğer kesintiler, ürün, ambalaj ve koli maliyeti düşülmüş hali. "
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

/// Kullanıcının kendi aylık kâr hedefi. Girilmemişse hazır tutar gösterilmez.
struct KarHedefiGirisi: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @State private var sheet: AppSheet?

    var body: some View {
        let baslik = store.engine.karHedefiBasligi(month: month)
        Button { sheet = .karHedefi(month) } label: {
            Label(baslik.map { "Kâr hedefini değiştir (\($0))" } ?? "Kâr hedefi seç: bu ay ne kadar kazanmak istiyorsun?",
                  systemImage: "target")
                .font(.footnote.weight(.semibold))
        }
        .appSheets($sheet)
    }
}

/// Tek aktif kâr hedefi. Kaydetmeden önce hedefin vergi öncesi mi vergi sonrası (net) mı olduğu seçilmelidir.
struct KarHedefiFormu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Ay ("2026-09") ya da yıl ("2026")
    var anahtar: String
    var yillik: Bool

    @State private var tutar: Kurus = 0
    @State private var vergiSonrasi: Bool?
    @State private var yuklendi = false

    private var kayitli: Kurus? {
        yillik ? Int(anahtar).flatMap { store.state.settings.yearlyProfitGoal(for: $0) }
            : store.state.settings.profitGoal(for: anahtar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(yillik ? "Yıllık kâr hedefi" : "Aylık kâr hedefi", value: $tutar)
                } footer: {
                    Text(yillik ? "\(anahtar) yılı için tek bir hedef." : "\(Dates.displayMonth(anahtar)) için tek bir hedef.")
                }
                Section {
                    Button { vergiSonrasi = false } label: { secenek("Vergi öncesi kâr", secili: vergiSonrasi == false) }
                    Button { vergiSonrasi = true } label: { secenek("Vergi sonrası net kâr", secili: vergiSonrasi == true) }
                } header: {
                    Text("Bu tutar hangisi?")
                } footer: {
                    Text("Vergi sonrası seçersen gereken kargo, Ayarlar → Vergi'deki vergi türüne göre vergi öncesine çevrilerek hesaplanır (tahmini).")
                }
                if kayitli != nil {
                    Section {
                        Button("Hedefi kaldır", role: .destructive) { kaydet(nil) }
                    }
                }
            }
            .navigationTitle(yillik ? "Yıllık kâr hedefi" : "Aylık kâr hedefi")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { kaydet(tutar) }
                        .disabled(tutar <= 0 || vergiSonrasi == nil)
                }
            }
            .onAppear {
                guard !yuklendi else { return }
                yuklendi = true
                tutar = kayitli ?? 0
                // Kayıtlı hedefin türü; yeni hedefte seçim kullanıcıya bırakılır
                if kayitli != nil { vergiSonrasi = store.engine.hedefVergiSonrasi(anahtar) }
            }
        }
    }

    private func secenek(_ ad: String, secili: Bool) -> some View {
        HStack {
            Text(ad).foregroundStyle(Palette.ink)
            Spacer()
            if secili { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
        }
    }

    private func kaydet(_ t: Kurus?) {
        let v = vergiSonrasi ?? false
        if yillik, let y = Int(anahtar) {
            store.setYearlyProfitGoal(t, for: y, vergiSonrasi: v)
        } else {
            store.setProfitGoal(t, for: anahtar, vergiSonrasi: v)
        }
        dismiss()
    }
}

/// Başa baş hedefini oluşturan sabit giderler, tek tek.
/// Hedef yüksek görünüyorsa sebebi buradan görülür ve yerinde düzeltilir.
struct SabitGiderDokumuBolumu: View {
    @Environment(AppStore.self) private var store
    var plan: BreakevenPlan
    @State private var acik = false
    @State private var yillikSoru: SabitGiderSatiri?

    /// Başa baş hesabında kullanılan sabit gider
    private var planSabit: Kurus { plan.fixedCosts }
    /// Hedef kurulum verisinden (satış yok) mi: o zaman satışa bağlı giderler de aylık sayılır
    private var satisaBagliDahil: Bool { plan.basis == .beklenenDagilim }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Palette.separator)
            Button {
                withAnimation(.snappy(duration: 0.2)) { acik.toggle() }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bu hedefi hangi giderler oluşturuyor?")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("Bu ayın sabit giderleri: \(planSabit.tl)")
                            .font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: acik ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold)).foregroundStyle(Palette.inkFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if acik {
                // Döküm yalnızca açılınca hesaplanır. Ayın gerçekleşen sonucu gösteriliyorsa henüz
                // satışı olmayan kanalın ücreti eklenmez (başlıktaki toplamla aynı temel)
                let d = store.engine.sabitGiderDokumu(month: plan.month, planli: plan.basis != .ayinKendisi)
                if d.satirlar.isEmpty && planSabit == 0 {
                    Text("Bu ay sabit gider yok.").font(.caption).foregroundStyle(Palette.inkFaint)
                }
                ForEach(d.satirlar) { s in satir(s) }
                // Hedef kurulum verisinden hesaplanıyorsa satışa bağlı giderler de aylık sayılır (açıklanan fark);
                // bunun dışında kalan her fark hesap tutarsızlığıdır, bir kaleme yazılmaz
                let satisaBagli = satisaBagliDahil ? planSabit - (d.toplam + d.tutarsizlik) : 0
                let tutarsiz = planSabit - d.toplam - satisaBagli
                if satisaBagli != 0 {
                    LabeledRow("Satışa bağlı aylık giderler", satisaBagli.tl, tone: Palette.inkSoft)
                    Text("Henüz satış olmadığı için satışa bağlı giderler de aylık tutar olarak karşılanıyor.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if tutarsiz != 0 { TutarsizlikUyarisi(tutar: tutarsiz) }
                Text("Yılda bir ödediğin bir gideri \"Her ay\" girdiysen \"Yılda bir ödüyorum\"a dokun: "
                     + "kâra her ay 1/12'si yazılır. Birkaç ay işine yarayan büyük bir harcamayı aylara bölebilirsin. "
                     + "Para ve KDV yine ödediğin ayda çıkar.")
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(yillikSoru.map { "\($0.ad) yılda bir mi ödeniyor?" } ?? "",
                            isPresented: Binding(get: { yillikSoru != nil }, set: { if !$0 { yillikSoru = nil } }),
                            titleVisibility: .visible) {
            Button("Evet, yılda bir ödüyorum") {
                if let id = yillikSoru?.expenseId { store.giderYillikYap(id) }
                yillikSoru = nil
            }
            Button("Vazgeç", role: .cancel) { yillikSoru = nil }
        } message: {
            if let s = yillikSoru, let e = s.expenseId.flatMap({ id in store.state.expenses.first { $0.id == id } }) {
                Text("Girdiğin \(e.amount.tl) yılda bir ödenen tutar sayılacak; kâra her ay \(Expenses.aylikKarPayi(e.amount, rate: e.resolvedVatRate, included: e.resolvedVatIncluded, aySayisi: 12).tl)\(e.resolvedVatRate != .yok ? " (KDV hariç)" : "") yazılacak. "
                     + "Bu giderin geçmiş ayları da buna göre düzelir.")
            }
        }
    }

    private func satir(_ s: SabitGiderSatiri) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.ad).font(.footnote).foregroundStyle(Palette.ink)
                Text(s.aciklama).font(.caption2)
                    .foregroundStyle(s.tur == .tekSeferlik ? Palette.uyari : Palette.inkFaint)
                if let id = s.expenseId {
                    if s.tur == .herAy {
                        Button("Yılda bir ödüyorum") { yillikSoru = s }
                            .font(.caption2.weight(.semibold)).buttonStyle(.plain)
                            .foregroundStyle(Palette.accent)
                    } else if s.tur == .tekSeferlik || s.tur == .yayilmis {
                        Menu(s.tur == .tekSeferlik ? "Aylara böl" : "Bölmeyi değiştir") {
                            ForEach([3, 6, 12, 24], id: \.self) { n in
                                Button("\(n) aya böl") { store.giderAylaraBol(id, ay: n) }
                            }
                            if s.tur == .yayilmis {
                                Button("Tamamı ödendiği ay") { store.giderAylaraBol(id, ay: 1) }
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(s.tutar.tl).font(.footnote.weight(.medium)).foregroundStyle(Palette.ink)
        }
    }
}
