import SwiftUI
import MirissaCore

/// Bir satış kanalını baştan sona kuran soru-cevap akışı.
/// Kanal bağımsızdır: Trendyol da, Hepsiburada da, kullanıcının
/// kendi eklediği bir kanal da aynı motordan geçer.
struct ChannelSetupFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var channelId: Id
    /// Kurulum sihirbazının içinden çağrıldığında sıradaki kanala geçmek için
    var onBitti: (() -> Void)?

    private enum Adim: Hashable, Codable {
        case urunler
        case fiyat(Int)
        case komisyonVarMi
        case komisyonNasil
        case komisyonDeger
        case kargoVarMi
        case kargoNasil
        case kargoDeger
        case ekKalem(Int)       // bilinen kesinti türleri sırayla
        case ekKalemDeger(Int)
        case baskaVarMi
        case yeniKalemAdi
        case yeniKalemNasil
        case yeniKalemDeger
        case ozet
    }

    /// Kanal kurulumunda sırayla sorulan bilinen kesintiler
    private static let bilinenKalemler: [(ad: String, aciklama: String)] = [
        ("Hizmet bedeli", "Pazaryerinin sipariş başına aldığı sabit bedel"),
        ("İşlem bedeli", "Sipariş işleme / fatura bedeli"),
        ("Kampanya katkısı", "Pazaryeri kampanyalarına senin koyduğun pay"),
        ("Kupon katkısı", "Müşteriye verilen kupon indiriminin sana düşen kısmı"),
        ("Ödeme / POS komisyonu", "Kredi kartı veya ödeme altyapısı kesintisi"),
        ("Kanal reklam gideri", "Bu kanalda verdiğin reklamlar"),
        ("Aylık sabit kanal ücreti", "Mağaza aboneliği gibi aylık sabit tutar"),
    ]

    @State private var adim: Adim = .urunler
    @State private var gecmis: [Adim] = []

    @State private var seciliUrunler: Set<Id> = []
    @State private var fiyatlar: [Id: Kurus] = [:]

    @State private var komisyonVar: Bool?
    @State private var komisyonBasis: FeeBasis = .yuzde
    @State private var komisyonDeger: Double = 0
    @State private var komisyonBilinmiyor = false

    @State private var kargoVar: Bool?
    @State private var kargoBasis: FeeBasis = .siparisBasi
    @State private var kargoDeger: Double = 0
    @State private var kargoBilinmiyor = false

    @State private var ekler: [ChannelExtraFee] = []
    @State private var taslakKalem = ChannelExtraFee(label: "", basis: .yuzde)
    @State private var yuklendi = false
    @State private var devamSorusu: WizardDraft?
    @State private var taslakOkundu = false

    /// Akışın diske yazılan durumu — uygulama kapansa bile kaybolmaz
    private struct Taslak: Codable {
        var adim: Adim
        var gecmis: [Adim]
        var seciliUrunler: [Id]
        var fiyatlar: [Id: Kurus]
        var komisyonVar: Bool?
        var komisyonBasis: FeeBasis
        var komisyonDeger: Double
        var komisyonBilinmiyor: Bool
        var kargoVar: Bool?
        var kargoBasis: FeeBasis
        var kargoDeger: Double
        var kargoBilinmiyor: Bool
        var ekler: [ChannelExtraFee]
    }

    private var taslakKaydi: TaslakKaydi {
        TaslakKaydi(kind: .kanalKurulumu, subjectId: channelId,
                    baslik: "\(kanalAdi) kurulumu", toplamAdim: 12)
    }

    private var kanal: Channel? { store.state.channel(channelId) }
    private var kanalAdi: String { kanal?.name ?? "Kanal" }
    private var bugun: DateKey { Dates.today() }

    private var satilanUrunler: [Product] {
        store.state.activeProducts.filter { seciliUrunler.contains($0.id) }
    }

    var body: some View {
        Group {
            if let d = devamSorusu {
                DevamSorusu(
                    baslik: d.title,
                    ilerleme: d.progressLabel,
                    devam: {
                        taslagiGeriYukle()
                        devamSorusu = nil
                    },
                    bastan: {
                        taslakKaydi.sil(store)
                        devamSorusu = nil
                    },
                    vazgec: { dismiss() }
                )
            } else {
                icerik
            }
        }
        .onAppear(perform: baslat)
    }

    private func baslat() {
        guard !taslakOkundu else { return }
        taslakOkundu = true
        if let d = taslakKaydi.mevcut(store), d.decode(Taslak.self) != nil {
            devamSorusu = d
            return
        }
        yukle()
    }

    private func taslagiGeriYukle() {
        guard let t = taslakKaydi.oku(store, Taslak.self) else { yukle(); return }
        yuklendi = true
        adim = t.adim
        gecmis = t.gecmis
        seciliUrunler = Set(t.seciliUrunler)
        fiyatlar = t.fiyatlar
        komisyonVar = t.komisyonVar
        komisyonBasis = t.komisyonBasis
        komisyonDeger = t.komisyonDeger
        komisyonBilinmiyor = t.komisyonBilinmiyor
        kargoVar = t.kargoVar
        kargoBasis = t.kargoBasis
        kargoDeger = t.kargoDeger
        kargoBilinmiyor = t.kargoBilinmiyor
        ekler = t.ekler
    }

    private func taslakKaydet() {
        taslakKaydi.kaydet(store, adim: gecmis.count + 1, durum: Taslak(
            adim: adim, gecmis: gecmis,
            seciliUrunler: Array(seciliUrunler).sorted(), fiyatlar: fiyatlar,
            komisyonVar: komisyonVar, komisyonBasis: komisyonBasis,
            komisyonDeger: komisyonDeger, komisyonBilinmiyor: komisyonBilinmiyor,
            kargoVar: kargoVar, kargoBasis: kargoBasis,
            kargoDeger: kargoDeger, kargoBilinmiyor: kargoBilinmiyor,
            ekler: ekler
        ))
    }

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case .urunler: urunlerAdimi
        case let .fiyat(i): fiyatAdimi(i)
        case .komisyonVarMi: komisyonVarMiAdimi
        case .komisyonNasil: komisyonNasilAdimi
        case .komisyonDeger: komisyonDegerAdimi
        case .kargoVarMi: kargoVarMiAdimi
        case .kargoNasil: kargoNasilAdimi
        case .kargoDeger: kargoDegerAdimi
        case let .ekKalem(i): ekKalemAdimi(i)
        case let .ekKalemDeger(i): ekKalemDegerAdimi(i)
        case .baskaVarMi: baskaVarMiAdimi
        case .yeniKalemAdi: yeniKalemAdiAdimi
        case .yeniKalemNasil: yeniKalemNasilAdimi
        case .yeniKalemDeger: yeniKalemDegerAdimi
        case .ozet: ozetAdimi
        }
    }

    // MARK: 1 — Bu kanalda hangi ürünler satılıyor

    private var urunlerAdimi: some View {
        SoruAdimi(
            soru: "\(kanalAdi) üzerinden hangileri satılıyor?",
            aciklama: "Set ve çoklu paketler de ayrı birer satış seçeneğidir.",
            ileriAktif: !seciliUrunler.isEmpty,
            vazgec: { dismiss() },
            ileri: { ileri(.fiyat(0)) }
        ) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(store.state.activeProducts.enumerated()), id: \.element.id) { i, p in
                        Button {
                            if seciliUrunler.contains(p.id) { seciliUrunler.remove(p.id) }
                            else { seciliUrunler.insert(p.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: seciliUrunler.contains(p.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(seciliUrunler.contains(p.id)
                                                     ? Palette.accent : Palette.inkFaint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).foregroundStyle(Palette.ink)
                                    if p.isBundle {
                                        Text("Set / paket")
                                            .font(.caption).foregroundStyle(Palette.inkFaint)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Metrics.pad)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < store.state.activeProducts.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }
        }
    }

    // MARK: 2 — Her ürünün bu kanaldaki fiyatı

    private func fiyatAdimi(_ i: Int) -> some View {
        let liste = satilanUrunler
        let p = liste.indices.contains(i) ? liste[i] : nil
        return SoruAdimi(
            soru: p.map { "\($0.name) — \(kanalAdi) fiyatı ne?" } ?? "",
            aciklama: "Aynı ürünün fiyatı kanala göre değişebilir. "
                + "Müşterinin \(kanalAdi)'da gördüğü fiyatı yaz.",
            adim: i + 1, toplam: liste.count,
            geri: geriGit, vazgec: { dismiss() },
            ileri: {
                ileri(i + 1 < liste.count ? .fiyat(i + 1) : .komisyonVarMi)
            }
        ) {
            if let p {
                BuyukParaAlani(baslik: "\(p.name) · \(kanalAdi)", deger: Binding(
                    get: { fiyatlar[p.id] ?? 0 },
                    set: { fiyatlar[p.id] = $0 }
                ))
                if let baska = digerKanalFiyatlari(p), !baska.isEmpty {
                    Card(background: Palette.inset) {
                        VStack(spacing: 8) {
                            ForEach(baska, id: \.0) { ad, tutar in
                                LabeledRow(ad, Money.format(tutar))
                            }
                        }
                    }
                }
            }
        }
    }

    private func digerKanalFiyatlari(_ p: Product) -> [(String, Kurus)]? {
        let out = store.state.activeChannels
            .filter { $0.id != channelId }
            .compactMap { c -> (String, Kurus)? in
                p.price(for: c.id, on: bugun).map { (c.name, $0) }
            }
        return out.isEmpty ? nil : out
    }

    // MARK: 3 — Komisyon

    private var komisyonVarMiAdimi: some View {
        SoruAdimi(
            soru: "\(kanalAdi) komisyon kesiyor mu?",
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Evet", ikon: "percent") {
                    komisyonVar = true
                    komisyonBilinmiyor = false
                    ileri(.komisyonNasil)
                }
                SecenekButonu(baslik: "Hayır", renk: Palette.gider) {
                    komisyonVar = false
                    komisyonBilinmiyor = false
                    komisyonDeger = 0
                    ileri(.kargoVarMi)
                }
                SecenekButonu(baslik: "Şimdilik bilmiyorum",
                              aciklama: "Sonra girersin; sonuçlar \"yaklaşık\" yazar",
                              ikon: "questionmark.circle", renk: Palette.inkSoft) {
                    komisyonVar = true
                    komisyonBilinmiyor = true
                    ileri(.kargoVarMi)
                }
            }
        }
    }

    private var komisyonNasilAdimi: some View {
        SoruAdimi(
            soru: "Komisyon nasıl hesaplanıyor?",
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Satışın yüzdesi", aciklama: "Örneğin %4",
                              ikon: "percent") {
                    komisyonBasis = .yuzde
                    ileri(.komisyonDeger)
                }
                SecenekButonu(baslik: "Sipariş başına sabit TL", ikon: "turkishlirasign.circle") {
                    komisyonBasis = .siparisBasi
                    ileri(.komisyonDeger)
                }
                SecenekButonu(baslik: "Aylık gerçek toplamı ben gireceğim",
                              aciklama: "Her ay o kanalın ekranından okuyup yazarsın",
                              ikon: "square.and.pencil", renk: Palette.gider) {
                    komisyonBasis = .elleAylik
                    komisyonDeger = 0
                    ileri(.kargoVarMi)
                }
            }
        }
    }

    private var komisyonDegerAdimi: some View {
        SoruAdimi(
            soru: komisyonBasis == .yuzde ? "Komisyon oranı kaç?" : "Sipariş başına kaç TL?",
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.kargoVarMi) }
        ) {
            if komisyonBasis == .yuzde {
                Card { PercentField("Komisyon oranı", value: $komisyonDeger) }
            } else {
                BuyukParaAlani(baslik: "Sipariş başına komisyon", deger: Binding(
                    get: { Kurus(komisyonDeger) },
                    set: { komisyonDeger = Double($0) }
                ))
            }
        }
    }

    // MARK: 4 — Kargo

    private var kargoVarMiAdimi: some View {
        SoruAdimi(
            soru: "Kargo gideri var mı?",
            aciklama: "Kargoyu sen ödüyorsan evet. Müşteri ödüyorsa hayır.",
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Evet", ikon: "shippingbox") {
                    kargoVar = true
                    kargoBilinmiyor = false
                    ileri(.kargoNasil)
                }
                SecenekButonu(baslik: "Hayır", renk: Palette.gider) {
                    kargoVar = false
                    kargoBilinmiyor = false
                    kargoDeger = 0
                    ileri(.ekKalem(0))
                }
                SecenekButonu(baslik: "Şimdilik bilmiyorum",
                              ikon: "questionmark.circle", renk: Palette.inkSoft) {
                    kargoVar = true
                    kargoBilinmiyor = true
                    ileri(.ekKalem(0))
                }
            }
        }
    }

    private var kargoNasilAdimi: some View {
        SoruAdimi(
            soru: "Kargoyu nasıl hesaplayalım?",
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Sipariş başına sabit tutar",
                              aciklama: "Örneğin 107 TL", ikon: "shippingbox") {
                    kargoBasis = .siparisBasi
                    ileri(.kargoDeger)
                }
                SecenekButonu(baslik: "Değişken — ortalama bir tutar yazayım",
                              aciklama: "Desi ve mesafeye göre değişiyorsa ortalamasını yaz",
                              ikon: "arrow.up.arrow.down") {
                    kargoBasis = .siparisBasi
                    ileri(.kargoDeger)
                }
                SecenekButonu(baslik: "Aylık toplamı ben gireceğim",
                              ikon: "square.and.pencil", renk: Palette.gider) {
                    kargoBasis = .elleAylik
                    kargoDeger = 0
                    ileri(.ekKalem(0))
                }
            }
        }
    }

    private var kargoDegerAdimi: some View {
        SoruAdimi(
            soru: "Sipariş başına ortalama kargo ne kadar?",
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.ekKalem(0)) }
        ) {
            BuyukParaAlani(baslik: "Sipariş başına kargo", deger: Binding(
                get: { Kurus(kargoDeger) },
                set: { kargoDeger = Double($0) }
            ))
        }
    }

    // MARK: 5 — Bilinen diğer kesintiler, tek tek

    private func ekKalemAdimi(_ i: Int) -> some View {
        let k = Self.bilinenKalemler[min(i, Self.bilinenKalemler.count - 1)]
        return SoruAdimi(
            soru: "\(k.ad) var mı?",
            aciklama: k.aciklama,
            adim: i + 1, toplam: Self.bilenSayisi,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Evet") {
                    taslakKalem = ChannelExtraFee(
                        label: k.ad,
                        basis: k.ad == "Aylık sabit kanal ücreti" ? .aylikSabit : .yuzde
                    )
                    ileri(.ekKalemDeger(i))
                }
                SecenekButonu(baslik: "Hayır", renk: Palette.gider) {
                    ileri(sonrakiEkKalem(i))
                }
                SecenekButonu(baslik: "Şimdilik bilmiyorum",
                              ikon: "questionmark.circle", renk: Palette.inkSoft) {
                    ekler.append(ChannelExtraFee(label: k.ad, basis: .yuzde, unknown: true))
                    ileri(sonrakiEkKalem(i))
                }
            }
        }
    }

    private static var bilenSayisi: Int { bilinenKalemler.count }

    private func sonrakiEkKalem(_ i: Int) -> Adim {
        i + 1 < Self.bilinenKalemler.count ? .ekKalem(i + 1) : .baskaVarMi
    }

    private func ekKalemDegerAdimi(_ i: Int) -> some View {
        SoruAdimi(
            soru: "\(taslakKalem.label) nasıl hesaplanıyor?",
            adim: i + 1, toplam: Self.bilenSayisi,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            kalemDegerAlani { ileri(sonrakiEkKalem(i)) }
        }
    }

    // MARK: 6 — Açık uçlu: başka kesinti

    private var baskaVarMiAdimi: some View {
        SoruAdimi(
            soru: "Başka bir gider veya kesinti var mı?",
            aciklama: "Listede olmayan bir kesinti varsa kendi adıyla ekleyebilirsin.",
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Hayır, hepsi bu", ikon: "checkmark.circle") {
                    ileri(.ozet)
                }
                SecenekButonu(baslik: "Başka gider / kesinti ekle",
                              ikon: "plus.circle", renk: Palette.gider) {
                    taslakKalem = ChannelExtraFee(label: "", basis: .yuzde)
                    ileri(.yeniKalemAdi)
                }
            }
            if !ekler.isEmpty {
                Card {
                    VStack(spacing: 9) {
                        ForEach(ekler) { f in
                            LabeledRow(f.label, kalemMetni(f))
                        }
                    }
                }
            }
        }
    }

    private var yeniKalemAdiAdimi: some View {
        SoruAdimi(
            soru: "Bu kesintinin adı ne?",
            ileriAktif: !taslakKalem.label.trimmingCharacters(in: .whitespaces).isEmpty,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.yeniKalemNasil) }
        ) {
            Card {
                TextField("Örneğin: Depo hizmet bedeli", text: $taslakKalem.label)
                    .font(.title3)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private var yeniKalemNasilAdimi: some View {
        SoruAdimi(
            soru: "\(taslakKalem.label) nasıl hesaplanıyor?",
            geri: geriGit, vazgec: { dismiss() }
        ) {
            kalemDegerAlani { ileri(.baskaVarMi) }
        }
    }

    private var yeniKalemDegerAdimi: some View { yeniKalemNasilAdimi }

    /// Kesinti türü + tutar aynı ekranda: tür seçilince alan değişir
    @ViewBuilder
    private func kalemDegerAlani(_ bitir: @escaping () -> Void) -> some View {
        VStack(spacing: Metrics.gap) {
            ForEach(FeeBasis.allCases) { b in
                SecenekButonu(baslik: b.displayName, secili: taslakKalem.basis == b) {
                    taslakKalem.basis = b
                    if b == .elleAylik { taslakKalem.value = 0 }
                }
            }
        }
        if taslakKalem.basis == .yuzde {
            Card {
                PercentField("Oran", value: Binding(
                    get: { taslakKalem.value },
                    set: { taslakKalem.value = $0 }
                ))
            }
        } else if taslakKalem.basis != .elleAylik {
            BuyukParaAlani(
                baslik: taslakKalem.basis == .siparisBasi ? "Sipariş başına" : "Ayda bir",
                deger: Binding(
                    get: { Kurus(taslakKalem.value) },
                    set: { taslakKalem.value = Double($0) }
                )
            )
        }
        BigButton(taslakKalem.basis == .elleAylik ? "Tamam" : "Ekle") {
            ekler.removeAll { $0.label == taslakKalem.label }
            ekler.append(taslakKalem)
            bitir()
        }
    }

    private func kalemMetni(_ f: ChannelExtraFee) -> String {
        if f.unknown { return "bilinmiyor" }
        switch f.basis {
        case .yuzde: return Money.formatPercent(f.value)
        case .siparisBasi: return "\(Money.format(Kurus(f.value))) / sipariş"
        case .aylikSabit: return "\(Money.format(Kurus(f.value))) / ay"
        case .elleAylik: return "aylık girilecek"
        }
    }

    // MARK: 7 — Özet

    private var ozetAdimi: some View {
        OzetAdimi(
            ozet: ozet,
            sorunlar: [],
            kaydetBaslik: "Onayla",
            geri: geriGit,
            vazgec: { dismiss() },
            kaydet: kaydet
        )
    }

    private var ozet: SaveSummary {
        var satirlar: [String] = [kanalAdi.trUpper]
        for p in satilanUrunler {
            let f = fiyatlar[p.id] ?? 0
            satirlar.append("\(p.name): \(f > 0 ? Money.format(f) : "fiyat girilmedi")")
        }
        satirlar.append(komisyonOzeti)
        satirlar.append(kargoOzeti)
        for f in ekler { satirlar.append("\(f.label): \(kalemMetni(f))") }
        if let (once, sonra) = hedefOnizleme() {
            let yon = sonra < once ? "düşecek" : "yükselecek"
            satirlar.append("Bu ayarlarla aylık başa baş hedefin yaklaşık "
                + "\(once) kargodan \(sonra) kargoya \(yon)")
        }
        let eksik = eksikListesi
        if !eksik.isEmpty {
            satirlar.append("Girilmeyenler: \(eksik.joined(separator: ", ")) — "
                + "bu kalemler hesaba katılmaz, sonuçlar \"yaklaşık\" yazar")
        }
        return SaveSummary(
            lines: satirlar,
            note: "Bu bilgilerle hesaplama yapılacak. Fiyat veya komisyon sonradan "
                + "değişirse eski dönemler olduğu gibi kalır."
        )
    }

    private var komisyonOzeti: String {
        if komisyonBilinmiyor { return "Komisyon: bilinmiyor" }
        guard komisyonVar == true else { return "Komisyon: yok" }
        switch komisyonBasis {
        case .yuzde: return "Komisyon: \(Money.formatPercent(komisyonDeger))"
        case .elleAylik: return "Komisyon: aylık gerçek tutar girilecek"
        default: return "Komisyon: \(Money.format(Kurus(komisyonDeger))) / sipariş"
        }
    }

    private var kargoOzeti: String {
        if kargoBilinmiyor { return "Kargo: bilinmiyor" }
        guard kargoVar == true else { return "Kargo: yok" }
        return kargoBasis == .elleAylik
            ? "Kargo: aylık toplam girilecek"
            : "Ortalama kargo: \(Money.format(Kurus(kargoDeger))) / sipariş"
    }

    private var eksikListesi: [String] {
        var out: [String] = []
        if komisyonBilinmiyor { out.append("komisyon") }
        if kargoBilinmiyor { out.append("kargo gideri") }
        out += ekler.filter(\.unknown).map(\.label)
        return out
    }

    /// "Başa baş hedefin 84 kargodan 92 kargoya yükselecek" — teknik formül yok.
    /// Geçmiş raporlar değişmez; yalnızca bu ay ve sonrası yeniden hesaplanır.
    private func hedefOnizleme() -> (Int, Int)? {
        let ay = Dates.month(of: bugun)
        let once = store.engine.plan(month: ay, today: bugun)
        guard let oncekiHedef = once.targets.first(where: { $0.isBreakeven })?.orders,
              var kopya = kanal.map({ _ in store.state }) else { return nil }
        guard let i = kopya.channels.firstIndex(where: { $0.id == channelId }) else { return nil }
        var c = kopya.channels[i]
        c.setRates(taslakRates)
        kopya.channels[i] = c
        for p in satilanUrunler {
            guard let tutar = fiyatlar[p.id], tutar > 0,
                  let j = kopya.products.firstIndex(where: { $0.id == p.id }) else { continue }
            kopya.products[j].applyCurrentPrice(tutar, channelId: channelId, today: bugun)
        }
        let sonra = Engine(kopya).plan(month: ay, today: bugun)
        guard let yeniHedef = sonra.targets.first(where: { $0.isBreakeven })?.orders,
              yeniHedef != oncekiHedef else { return nil }
        return (oncekiHedef, yeniHedef)
    }

    // MARK: Kayıt

    private func kaydet() {
        store.applyChannelRates(channelId, taslakRates)

        // Bu kanaldaki fiyatlar geçmişi bozmadan yazılır.
        let bugunku = bugun
        for p in satilanUrunler {
            guard let tutar = fiyatlar[p.id], tutar > 0,
                  var urun = store.state.product(p.id) else { continue }
            urun.applyCurrentPrice(tutar, channelId: channelId, today: bugunku)
            store.updateProduct(urun)
        }

        // Akış tamamlandı: yarım kayıt silinir
        taslakKaydi.sil(store)
        if let onBitti { onBitti() } else { dismiss() }
    }

    /// Kullanıcının verdiği cevaplardan oluşan kesinti seti
    private var taslakRates: ChannelRates {
        var extras = ekler
        if komisyonBasis == .elleAylik, komisyonVar == true, !komisyonBilinmiyor {
            extras.append(ChannelExtraFee(label: "Komisyon", basis: .elleAylik))
        }
        if kargoBasis == .elleAylik, kargoVar == true, !kargoBilinmiyor {
            extras.append(ChannelExtraFee(label: "Kargo", basis: .elleAylik))
        }
        var bilinmeyen: [String] = []
        if komisyonBilinmiyor { bilinmeyen.append("komisyon") }
        if kargoBilinmiyor { bilinmeyen.append("kargo gideri") }

        let kendiSitesi = kanal?.kind == .ownStore
        let yuzde = (komisyonVar == true && !komisyonBilinmiyor && komisyonBasis == .yuzde)
            ? komisyonDeger : 0
        let siparisBasiKomisyon = (komisyonVar == true && !komisyonBilinmiyor
                                   && komisyonBasis == .siparisBasi) ? komisyonDeger : 0
        if siparisBasiKomisyon > 0 {
            extras.append(ChannelExtraFee(label: "Komisyon", basis: .siparisBasi,
                                          value: siparisBasiKomisyon))
        }

        // Yeni oranlar bugünden geçerli: geçmiş aylar eski oranlarla kalır.
        return ChannelRates(
            from: baslangicTarihi,
            commissionPct: kendiSitesi ? 0 : yuzde,
            paymentPct: kendiSitesi ? yuzde : 0,
            shippingPerOrder: (kargoVar == true && !kargoBilinmiyor && kargoBasis != .elleAylik)
                ? Kurus(kargoDeger) : 0,
            extras: extras,
            unknownFields: bilinmeyen
        )
    }

    /// Kanal ilk kez kuruluyorsa oranlar baştan geçerli sayılır;
    /// sonradan değiştiriliyorsa bugünden başlar.
    private var baslangicTarihi: DateKey {
        (kanal?.rateHistory ?? []).isEmpty ? "1970-01-01" : bugun
    }

    // MARK: Gezinme ve yükleme

    private func yukle() {
        guard !yuklendi, let c = kanal else { return }
        yuklendi = true
        let r = c.rates(on: bugun)
        seciliUrunler = Set(store.state.activeProducts
            .filter { $0.price(for: channelId, on: bugun) != nil }
            .map(\.id))
        if seciliUrunler.isEmpty {
            seciliUrunler = Set(store.state.activeProducts.map(\.id))
        }
        for p in store.state.activeProducts {
            if let f = p.price(for: channelId, on: bugun) { fiyatlar[p.id] = f }
        }
        let oran = r.commissionPct + r.paymentPct
        if oran > 0 {
            komisyonVar = true
            komisyonBasis = .yuzde
            komisyonDeger = oran
        }
        if r.shippingPerOrder > 0 {
            kargoVar = true
            kargoBasis = .siparisBasi
            kargoDeger = Double(r.shippingPerOrder)
        }
        ekler = r.extras.filter { $0.label != "Komisyon" && $0.label != "Kargo" }
    }

    private func ileri(_ hedef: Adim) {
        gecmis.append(adim)
        withAnimation(.snappy(duration: 0.2)) { adim = hedef }
        taslakKaydet()
    }

    private func geriGit() {
        guard let onceki = gecmis.popLast() else { return }
        withAnimation(.snappy(duration: 0.2)) { adim = onceki }
        taslakKaydet()
    }
}

/// "Satış kanalı ekle" — önce hangi kanal, sonra o kanalın kendi kurulumu.
struct ChannelAddFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var secilen: Id?
    @State private var adYaziliyor = false
    @State private var yeniAd = ""

    var body: some View {
        if let secilen {
            ChannelSetupFlow(channelId: secilen) { dismiss() }
        } else if adYaziliyor {
            adAdimi
        } else {
            secimAdimi
        }
    }

    private var mevcutIdler: Set<Id> {
        Set(store.state.channels.filter { !$0.archived }.map(\.id))
    }

    private var secimAdimi: some View {
        SoruAdimi(
            soru: "Hangi satış kanalını eklemek istersin?",
            vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(ChannelPreset.hazir.filter { !mevcutIdler.contains($0.id) }) { k in
                    SecenekButonu(baslik: k.name, ikon: "storefront") {
                        ekle(id: k.id, ad: k.name, kind: k.kind)
                    }
                }
                SecenekButonu(baslik: "Listede yok — kendim yazayım",
                              ikon: "plus.circle", renk: Palette.gider) {
                    withAnimation { adYaziliyor = true }
                }
            }
        }
    }

    private var adAdimi: some View {
        SoruAdimi(
            soru: "Kanalın adı ne?",
            ileriAktif: !yeniAd.trimmingCharacters(in: .whitespaces).isEmpty,
            geri: { withAnimation { adYaziliyor = false } },
            vazgec: { dismiss() },
            ileri: {
                let ad = yeniAd.trimmingCharacters(in: .whitespaces)
                ekle(id: "kanal_" + ad.lowercased().replacingOccurrences(of: " ", with: "_"),
                     ad: ad, kind: .other)
            }
        ) {
            Card {
                TextField("Kanal adı", text: $yeniAd)
                    .font(.title3)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private func ekle(id: Id, ad: String, kind: ChannelKind) {
        if store.state.channel(id) == nil {
            store.upsertChannel(Channel(id: id, name: ad, kind: kind,
                                        feeVatRate: .yirmi, feesIncludeVat: true,
                                        setupCompleted: false))
        } else {
            var c = store.state.channel(id)!
            c.archived = false
            store.upsertChannel(c)
        }
        secilen = id
    }
}
