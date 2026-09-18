import SwiftUI
import MirissaCore

/// İlk açılışta çıkan zorunlu kurulum.
/// Tek ekranda tek soru; cevaba göre sonraki soru değişir.
/// Geçmişte alınmış stoklar "başlangıç stoğu" olarak girilir:
/// stoğa ve maliyete girer, bu ayın gideri veya nakit çıkışı sayılmaz.
public struct SetupWizard: View {
    @Environment(AppStore.self) private var store

    public enum Adim: Hashable, Codable {
        case karsilama
        case urunSayisi
        case urunAdi(Int)
        case urunStok(Int)
        case urunMaliyet(Int)
        case urunMaliyetKdv(Int)
        case urunMaliyetOran(Int)
        case ambalajDahil(Int)
        case setVarMi
        case setSayisi
        case setAdi(Int)
        case setBilesenleri(Int)
        case malzemeSecimi
        case malzemeAdi
        case malzemeDetay(Int)
        case setAmbalaji(Int)
        case kanalSecimi
        case kanalAdi
        case kanalKurulum(Int)
        case giderVarMi
        case giderler
        case ozet
    }

    @State private var adim: Adim = .karsilama
    @State private var gecmis: [Adim] = []
    @State private var urunler: [UrunTaslak] = []
    @State private var malzemeler: [MalzemeTaslak] = []
    @State private var setler: [SetTaslak] = []
    @State private var giderler: [GiderTaslak] = []
    @State private var kanallar: [KanalTaslak] = []
    @State private var seciliKanallar: Set<Id> = []
    @State private var kurulacakKanallar: [Id] = []
    @State private var ekKanallar: [ChannelPreset] = []
    @State private var malzemeArama = ""
    @State private var yuklendi = false
    @State private var devamSorusu: WizardDraft?
    @State private var taslakOkundu = false

    /// Kurulumun diske yazılan hâli
    private struct Taslak: Codable {
        var adim: Adim
        var gecmis: [Adim]
        var urunler: [UrunTaslak]
        var setler: [SetTaslak]
        var malzemeler: [MalzemeTaslak]
        var giderler: [GiderTaslak]
        var seciliKanallar: [Id]
        var kurulacakKanallar: [Id]
    }

    private var taslakKaydi: TaslakKaydi {
        TaslakKaydi(kind: .ilkKurulum, subjectId: nil, baslik: "İlk kurulum", toplamAdim: 14)
    }

    public init() {}

    /// Yalnızca önizleme/görsel doğrulama için: belirli bir adımdan başlatır.
    init(baslangic: Adim) { _adim = State(initialValue: baslangic) }

    /// Seçili malzemelerin `malzemeler` içindeki sıraları
    private var seciliIndisler: [Int] {
        malzemeler.indices.filter {
            malzemeler[$0].secili && !malzemeler[$0].ad.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var doluUrunler: [UrunTaslak] {
        urunler.filter { !$0.ad.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var body: some View {
        Group {
            if let d = devamSorusu {
                DevamSorusu(
                    baslik: d.title, ilerleme: d.progressLabel,
                    devam: { taslagiGeriYukle(); devamSorusu = nil },
                    bastan: { taslakKaydi.sil(store); yukle(); devamSorusu = nil }
                )
            } else {
                icerik
            }
        }
        .background(Palette.bg)
        .onAppear(perform: baslat)
    }

    private func baslat() {
        guard !taslakOkundu else { return }
        taslakOkundu = true
        if let d = taslakKaydi.mevcut(store), d.decode(Taslak.self) != nil {
            yuklendi = true       // taslak varken mevcut veriyle üzerine yazma
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
        urunler = t.urunler
        setler = t.setler
        malzemeler = t.malzemeler
        giderler = t.giderler
        seciliKanallar = Set(t.seciliKanallar)
        kurulacakKanallar = t.kurulacakKanallar
    }

    private func taslakKaydet() {
        taslakKaydi.kaydet(store, adim: gecmis.count + 1, durum: Taslak(
            adim: adim, gecmis: gecmis, urunler: urunler, setler: setler,
            malzemeler: malzemeler, giderler: giderler,
            seciliKanallar: Array(seciliKanallar).sorted(),
            kurulacakKanallar: kurulacakKanallar
        ))
    }

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case .karsilama: karsilama
        case let .urunSayisi: urunSayisiAdimi
        case let .urunAdi(i): urunAdiAdimi(i).id("urunAdi-\(i)")
        case let .urunStok(i): urunStokAdimi(i).id("urunStok-\(i)")
        case let .urunMaliyet(i): urunMaliyetAdimi(i).id("urunMaliyet-\(i)")
        case let .urunMaliyetKdv(i): urunMaliyetKdvAdimi(i).id("urunMaliyetKdv-\(i)")
        case let .urunMaliyetOran(i): urunMaliyetOranAdimi(i).id("urunMaliyetOran-\(i)")
        case let .ambalajDahil(i): ambalajDahilAdimi(i).id("ambalajDahil-\(i)")
        case .setVarMi: setVarMiAdimi
        case .setSayisi: setSayisiAdimi
        case let .setAdi(i): setAdiAdimi(i).id("setAdi-\(i)")
        case let .setBilesenleri(i): setBilesenleriAdimi(i).id("setBilesen-\(i)")
        case .malzemeSecimi: malzemeSecimAdimi
        case .malzemeAdi: malzemeAdiAdimi
        case let .malzemeDetay(i): malzemeDetayAdimi(i).id("malzemeDetay-\(i)")
        case let .setAmbalaji(i): setAmbalajiAdimi(i).id("setAmbalaj-\(i)")
        case .kanalSecimi: kanalSecimAdimi
        case .kanalAdi: kanalAdiAdimi
        case let .kanalKurulum(i): kanalKurulumAdimi(i).id("kanalKurulum-\(i)")
        case .giderVarMi: giderVarMiAdimi
        case .giderler: giderAdimi
        case .ozet: ozetAdimi
        }
    }

    // MARK: 0 — Karşılama

    private var karsilama: some View {
        SoruAdimi(
            soru: "Başlamadan önce birkaç soru soracağım",
            aciklama: "Her ekranda tek soru olacak. Bilmediğin bir şey olursa boş bırak, "
                + "sonra da değiştirebilirsin.",
            ileriBaslik: "Başla",
            ileri: { ileri(.urunSayisi) }
        ) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    madde("cube.box", "Ürünlerin ve elindeki stok")
                    madde("shippingbox", "Ambalaj ve sarf malzemelerin")
                    madde("repeat", "Her ay ödediğin sabit giderler")
                    madde("storefront", "Satış kanalların ve komisyonları")
                    Divider().overlay(Palette.separator)
                    Text("Sonrasında tek bir buton olacak: Yeni İşlem.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func madde(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Palette.accent)
                .frame(width: 26)
            Text(text).font(.subheadline).foregroundStyle(Palette.ink)
            Spacer()
        }
    }

    // MARK: 1 — Kaç ürün

    private var urunSayisiAdimi: some View {
        SoruAdimi(
            soru: "Kaç temel fiziksel ürünün var?",
            aciklama: "Sadece gerçekten stoğunu tuttuğun ürünleri say — şampuan, serum gibi. "
                + "Set ve çoklu paketleri sayma, onları birazdan ayrıca soracağım.",
            geri: geriGit
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { n in
                    SecenekButonu(baslik: n == 5 ? "5 veya daha fazla" : "\(n) ürün",
                                  secili: urunler.count == n) {
                        urunSayisiniAyarla(n)
                        ileri(.urunAdi(0))
                    }
                }
            }
        }
    }

    private func urunSayisiniAyarla(_ n: Int) {
        if urunler.count > n { urunler.removeLast(urunler.count - n) }
        while urunler.count < n { urunler.append(UrunTaslak(ad: "")) }
    }

    // MARK: 2 — Ürün adı

    private func urunAdiAdimi(_ i: Int) -> some View {
        AdSorusu(
            soru: "\(i + 1). ürünün adı ne?",
            placeholder: "Örneğin: Şampuan",
            baslangic: urunTaslak(i).ad,
            adim: i + 1, toplam: urunler.count,
            mevcutAdlar: urunler.enumerated()
                .filter { $0.offset != i }.map { $0.element.ad }
                + setler.map(\.ad),
            geri: geriGit,
            ekSecenek: urunler.count > 1
                ? ("Bu ürünü eklemeyeceğim", "minus.circle", {
                    urunler.remove(at: i)
                    ileri(sonrakiUrunAdimi(i))
                })
                : nil,
            onDevam: { ad in
                if urunler.indices.contains(i) { urunler[i].ad = ad }
                ileri(.urunStok(i))
            }
        )
    }

    // MARK: 3 — Ürün stoğu

    private func urunStokAdimi(_ i: Int) -> some View {
        SoruAdimi(
            soru: "\(urunAdi(i)) — şu anda kaç adet var?",
            aciklama: "Depodaki mevcut miktar. Bu, bu ayın gideri sayılmaz; "
                + "sadece stok ve maliyet hesabına girer.",
            adim: i + 1, toplam: urunler.count,
            geri: geriGit,
            ileri: { ileri(.urunMaliyet(i)) }
        ) {
            BuyukSayiAlani(baslik: urunAdi(i), birim: "adet", deger: urunBinding(i).stok)
        }
    }

    // MARK: 4 — Ürün maliyeti

    private func urunMaliyetAdimi(_ i: Int) -> some View {
        SoruAdimi(
            soru: "\(urunAdi(i)) — bir adedi sana kaça mal oluyor?",
            aciklama: "Üretim, fason ve hammadde dahil. Bilmiyorsan boş bırak, sonra girebilirsin.",
            adim: i + 1, toplam: urunler.count,
            geri: geriGit,
            ileri: {
                // Tutar girildiyse KDV'si sorulmadan kaydedilmez.
                ileri(urunTaslak(i).maliyet > 0 ? .urunMaliyetKdv(i) : .ambalajDahil(i))
            }
        ) {
            BuyukParaAlani(baslik: "1 adet \(urunAdi(i))", deger: urunBinding(i).maliyet)
        }
    }

    /// "Yazdığın tutar KDV dahil mi?"
    private func urunMaliyetKdvAdimi(_ i: Int) -> some View {
        KdvDahilSorusu(
            tutar: urunTaslak(i).maliyet,
            oran: urunTaslak(i).maliyetKdvOrani,
            secim: urunTaslak(i).maliyetKdvDahil,
            adim: i + 1, toplam: urunler.count,
            geri: geriGit
        ) { secim in
            if urunler.indices.contains(i) { urunler[i].maliyetKdvDahil = secim }
            ileri(.urunMaliyetOran(i))
        }
    }

    /// "KDV oranı nedir?" — seçim yapılmadan geçilmez
    private func urunMaliyetOranAdimi(_ i: Int) -> some View {
        let t = urunTaslak(i)
        return KdvOraniSorusu(
            tutar: t.maliyet,
            dahil: t.maliyetKdvDahil ?? true,
            secim: t.maliyetKdvOranSecildi ? t.maliyetKdvOrani : nil,
            adim: i + 1, toplam: urunler.count,
            geri: geriGit
        ) { oran in
            if urunler.indices.contains(i) {
                urunler[i].maliyetKdvOrani = oran
                urunler[i].maliyetKdvOranSecildi = true
            }
            ileri(.ambalajDahil(i))
        }
    }

    // MARK: 5 — Ambalaj dahil mi

    private func ambalajDahilAdimi(_ i: Int) -> some View {
        SoruAdimi(
            soru: "Bu maliyete şişe, kapak ve etiket dahil mi?",
            aciklama: "Fason üretici sana kutulanmış, etiketlenmiş halde teslim ediyorsa "
                + "\"Evet\" de. O zaman bu malzemeleri maliyete ikinci kez eklemem.",
            adim: i + 1, toplam: urunler.count,
            geri: geriGit
        ) {
            if urunTaslak(i).maliyet > 0 {
                KdvOnizlemeKarti(
                    baslik: "NET ÜRÜN MALİYETİ",
                    tutar: urunTaslak(i).maliyet,
                    oran: urunTaslak(i).maliyetKdvOrani,
                    dahil: urunTaslak(i).maliyetKdvDahil ?? true
                )
            }
            EvetHayirSorusu(
                evet: "Evet, fiyata dahil",
                hayir: "Hayır, ayrıca alıyorum",
                evetAciklama: "Stoktan düşerim ama maliyete tekrar eklemem",
                hayirAciklama: "Ambalaj maliyetini malzemelerden hesaplarım",
                secim: urunTaslak(i).ambalajDahil
            ) { secim in
                if urunler.indices.contains(i) { urunler[i].ambalajDahil = secim }
                ileri(sonrakiUrunAdimi(i))
            }
        }
    }

    private func sonrakiUrunAdimi(_ i: Int) -> Adim {
        i + 1 < urunler.count ? .urunAdi(i + 1) : .setVarMi
    }

    // MARK: 5b — Set ve çoklu paketler

    private var setVarMiAdimi: some View {
        SoruAdimi(
            soru: "Set veya çoklu paket satıyor musun?",
            aciklama: "\"Şampuan + Serum Seti\" ya da \"2'li Şampuan Paketi\" gibi. "
                + "Bunların ayrı stoğunu tutmam; satıldığında içindeki ürünleri düşerim.",
            geri: geriGit
        ) {
            EvetHayirSorusu(
                evet: "Evet, satıyorum",
                hayir: "Hayır, sadece tekil ürün",
                evetAciklama: "Her paket için içinde ne olduğunu soracağım",
                secim: setler.isEmpty ? nil : true
            ) { secim in
                if secim {
                    if setler.isEmpty { setler = [SetTaslak(ad: "")] }
                    ileri(.setSayisi)
                } else {
                    setler = []
                    ileri(.malzemeSecimi)
                }
            }
        }
    }

    private var setSayisiAdimi: some View {
        SoruAdimi(
            soru: "Kaç farklı set veya paket satıyorsun?",
            aciklama: "Aynı ürünlerden oluşan her farklı satış seçeneği ayrı sayılır.",
            geri: geriGit
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { n in
                    SecenekButonu(baslik: n == 5 ? "5 veya daha fazla" : "\(n) tane",
                                  secili: setler.count == n) {
                        if setler.count > n { setler.removeLast(setler.count - n) }
                        while setler.count < n { setler.append(SetTaslak(ad: "")) }
                        ileri(.setAdi(0))
                    }
                }
            }
        }
    }

    private func setAdiAdimi(_ i: Int) -> some View {
        AdSorusu(
            soru: "\(i + 1). paketin adı ne?",
            aciklama: "Müşterinin gördüğü isim: \"Saç Derisi Bakım Seti\", \"2'li Şampuan Paketi\".",
            placeholder: "Örneğin: Saç Derisi Bakım Seti",
            baslangic: setTaslak(i).ad,
            adim: i + 1, toplam: setler.count,
            mevcutAdlar: doluUrunler.map(\.ad)
                + setler.enumerated().filter { $0.offset != i }.map { $0.element.ad },
            geri: geriGit,
            onDevam: { ad in
                if setler.indices.contains(i) { setler[i].ad = ad }
                ileri(.setBilesenleri(i))
            }
        )
    }

    private func setBilesenleriAdimi(_ i: Int) -> some View {
        let t = setTaslak(i)
        return SoruAdimi(
            soru: "\(t.ad.isEmpty ? "Bu pakette" : t.ad) — içinde ne var?",
            aciklama: "Bir adet satıldığında stoktan düşecek ürünler.",
            adim: i + 1, toplam: setler.count,
            ileriAktif: t.bilesenler.values.contains { $0 > 0 },
            geri: geriGit,
            ileri: { ileri(sonrakiSetAdimi(i)) }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(doluUrunler) { u in
                    Card {
                        HStack(spacing: 12) {
                            Text(u.ad)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            SayiSayaci(deger: bilesenBinding(i, u.id))
                        }
                    }
                }
            }
            setOzetKarti(i)
        }
    }

    @ViewBuilder
    private func setOzetKarti(_ i: Int) -> some View {
        let t = setTaslak(i)
        let maliyet = setMaliyeti(t)
        let hazir = hazirlanabilir(t)
        if maliyet > 0 || hazir != nil {
            Card(background: Palette.inset) {
                VStack(spacing: 10) {
                    if maliyet > 0 {
                        LabeledRow("İçindekilerin maliyeti", Money.format(maliyet), strong: true)
                    }
                    if let hazir {
                        LabeledRow("Eldeki stokla hazırlanabilir", "\(hazir) adet")
                    }
                    Text("Bu maliyeti ayrıca girmene gerek yok; içindeki ürünlerden "
                         + "kendim hesaplıyorum.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Bileşenlerin taslak maliyetlerinden hesaplanır — elle girilmez.
    private func setMaliyeti(_ t: SetTaslak) -> Kurus {
        doluUrunler.reduce(0) { acc, u in
            let adet = t.bilesenler[u.id] ?? 0
            return acc + Money.roundHalfAwayFromZero(Double(u.maliyet) * adet)
        }
    }

    /// 500 şampuan + 300 serum → en fazla 300 set.
    /// Ürün kayıtlıysa gerçek stok, yeni giriliyorsa az önce yazılan miktar kullanılır.
    private func hazirlanabilir(_ t: SetTaslak) -> Int? {
        var en: Int?
        var stokBilgisiVar = false
        for u in doluUrunler {
            let adet = t.bilesenler[u.id] ?? 0
            guard adet > 0 else { continue }
            let mevcut = store.state.product(u.id) != nil
                ? store.engine.qty(.product(u.id))
                : u.stok
            if mevcut > 0 { stokBilgisiVar = true }
            let kac = Int((mevcut / adet).rounded(.down))
            en = min(en ?? kac, kac)
        }
        return stokBilgisiVar ? en : nil
    }

    private func sonrakiSetAdimi(_ i: Int) -> Adim {
        i + 1 < setler.count ? .setAdi(i + 1) : .malzemeSecimi
    }

    // MARK: 7b — Sete özel ambalaj

    private func setAmbalajiAdimi(_ i: Int) -> some View {
        let t = setTaslak(i)
        return SoruAdimi(
            soru: "\(t.ad) paketlenirken ne kullanılıyor?",
            aciklama: "Bu paket satıldığında gerçekte ne kullanılıyorsa onu yaz. "
                + "Hem set kutusu hem ürünlerin kendi kutuları kullanılıyorsa ikisini de "
                + "yaz; kullanılmayanı sıfır bırak.",
            adim: i + 1, toplam: setler.count,
            geri: geriGit,
            ileri: { ileri(sonrakiSetAmbalajAdimi(i)) }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(seciliIndisler, id: \.self) { mi in
                    let m = malzemeTaslak(mi)
                    Card {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.ad).font(.headline).foregroundStyle(Palette.ink)
                                Text(m.birim.displayName)
                                    .font(.caption).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            SayiSayaci(deger: setAmbalajBinding(i, m.id))
                        }
                    }
                }
            }
        }
    }

    /// Ambalajı hiç girilmemiş setler için tekil siparişteki kullanımı öneri olarak doldurur.
    private func setAmbalajlariniHazirla() {
        let standart = seciliIndisler
            .map { malzemeler[$0] }
            .filter { $0.siparisBasi > 0 }
        guard !standart.isEmpty else { return }
        for i in setler.indices where setler[i].ambalaj.isEmpty {
            for m in standart { setler[i].ambalaj[m.id] = m.siparisBasi }
        }
    }

    private func sonrakiSetAmbalajAdimi(_ i: Int) -> Adim {
        i + 1 < setler.count ? .setAmbalaji(i + 1) : .kanalSecimi
    }

    // MARK: 6 — Malzeme seçimi

    private var malzemeSecimAdimi: some View {
        SoruAdimi(
            soru: "Bir siparişte hangi malzemeleri kullanıyorsun?",
            aciklama: "Kullanmadıklarının işaretini kaldır. Sonradan ekleyip çıkarabilirsin.",
            ileriAktif: !seciliIndisler.isEmpty,
            geri: geriGit,
            ileri: { ileri(.malzemeDetay(0)) }
        ) {
            AramaAlani(placeholder: "Malzeme ara", metin: $malzemeArama,
                       toplam: malzemeler.count)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array($malzemeler.enumerated()).filter { çift in
                        let ad = malzemeler.indices.contains(çift.offset)
                            ? malzemeler[çift.offset].ad : ""
                        return araSuz([ad], malzemeArama) { $0 }.isEmpty == false
                    }, id: \.element.id) { i, $m in
                        Button { m.secili.toggle() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.secili ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(m.secili ? Palette.accent : Palette.inkFaint)
                                Text(m.ad).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(m.birim.displayName)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, Metrics.pad)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < malzemeler.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }
            BigButton("Listede olmayan malzeme ekle", icon: "plus", tone: Palette.gider) {
                ileri(.malzemeAdi)
            }
        }
    }

    private var malzemeAdiAdimi: some View {
        AdSorusu(
            soru: "Eklemek istediğin malzemenin adı ne?",
            aciklama: "Kutu, koli, etiket, poşet gibi satışta kullandığın her şey.",
            placeholder: "Örneğin: Altın yaldızlı kurdele",
            ileriBaslik: "Ekle",
            mevcutAdlar: malzemeler.map(\.ad),
            geri: geriGit,
            onDevam: { ad in
                malzemeler.append(MalzemeTaslak(ad: ad, birim: .adet, secili: true, yeni: true))
                geriGit()
            }
        )
    }

    // MARK: 7 — Malzeme detayı

    private func malzemeDetayAdimi(_ sira: Int) -> some View {
        let indisler = seciliIndisler
        // Sıra geçerli değilse başka bir malzemeye yazmak yerine hiçbir şey yapma.
        let i = indisler.indices.contains(sira) ? indisler[sira] : -1
        let m = malzemeTaslak(i)
        let birim = m.birim.displayName
        return SoruAdimi(
            soru: m.ad.isEmpty ? "Bu malzemeyi anlat" : "\(m.ad)",
            aciklama: "Elindeki miktarı, birim maliyetini ve tek ürünlük bir siparişte kaç tane "
                + "kullandığını yaz. Sadece sette kullanıyorsan sıfır bırak — "
                + "setin ambalajını birazdan ayrıca soracağım.",
            adim: sira + 1, toplam: indisler.count,
            ileriAktif: m.maliyet == 0 || m.maliyetKdvDahil != nil,
            geri: geriGit,
            ileri: { ileri(sonrakiMalzemeAdimi(sira)) }
        ) {
            BuyukSayiAlani(baslik: "Şu anda elinde", birim: birim, deger: malzemeBinding(i).stok)
            BuyukParaAlani(baslik: "1 \(birim) maliyeti", deger: malzemeBinding(i).maliyet)
            if m.maliyet > 0 {
                // Tutarın KDV'si sorulmadan maliyet kaydedilmez.
                VStack(alignment: .leading, spacing: Metrics.gap) {
                    Text("Bu tutar KDV dahil mi?".trUpper)
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    EvetHayirSorusu(
                        evet: "Evet, KDV dahil",
                        hayir: "Hayır, KDV hariç",
                        secim: m.maliyetKdvDahil
                    ) { secim in
                        if malzemeler.indices.contains(i) {
                            malzemeler[i].maliyetKdvDahil = secim
                        }
                    }
                    if m.maliyetKdvDahil != nil {
                        Text("KDV oranı".trUpper)
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.inkFaint)
                        ForEach(VatRate.allCases.reversed()) { r in
                            SecenekButonu(baslik: r == .yok ? "KDV yok" : r.displayName,
                                          secili: m.maliyetKdvOrani == r) {
                                if malzemeler.indices.contains(i) {
                                    malzemeler[i].maliyetKdvOrani = r
                                }
                            }
                        }
                        KdvOnizlemeKarti(
                            baslik: "NET BİRİM MALİYET",
                            tutar: m.maliyet,
                            oran: m.maliyetKdvOrani,
                            dahil: m.maliyetKdvDahil ?? true
                        )
                    }
                }
            }
            BuyukSayiAlani(baslik: "Bir siparişte kullandığın",
                           birim: birim, deger: malzemeBinding(i).siparisBasi)
        }
    }

    private func sonrakiMalzemeAdimi(_ sira: Int) -> Adim {
        if sira + 1 < seciliIndisler.count { return .malzemeDetay(sira + 1) }
        guard !setler.isEmpty else { return .kanalSecimi }
        setAmbalajlariniHazirla()
        return .setAmbalaji(0)
    }

    // MARK: 8 — Sabit gider var mı

    private var giderVarMiAdimi: some View {
        SoruAdimi(
            soru: "Her ay düzenli ödediğin bir gider var mı?",
            aciklama: "Muhasebeci, ajans, abonelik gibi. Bir kez gir, her ay otomatik eklensin.",
            geri: geriGit
        ) {
            EvetHayirSorusu(
                evet: "Evet, var",
                hayir: "Hayır, yok",
                hayirAciklama: "Bu adımı atla"
            ) { secim in
                if secim {
                    if giderler.isEmpty { giderler = [GiderTaslak(ad: "", tutar: 0)] }
                    ileri(.giderler)
                } else {
                    giderler = []
                    ileri(.ozet)
                }
            }
        }
    }

    private var giderAdimi: some View {
        SoruAdimi(
            soru: "Bu giderler neler?",
            aciklama: "Adını, tutarını ve ayda mı yılda mı ödediğini yaz.",
            geri: geriGit,
            ileri: { ileri(.ozet) }
        ) {
            ForEach($giderler) { $g in
                Card {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Gider adı", text: $g.ad).foregroundStyle(Palette.ink)
                            Button { giderler.removeAll { $0.id == g.id } } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .buttonStyle(.plain)
                        }
                        Picker("", selection: Binding(get: { g.yillik ?? false }, set: { g.yillik = $0 })) {
                            Text("Ayda bir").tag(false)
                            Text("Yılda bir").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        MoneyField(g.yillik == true ? "Yıllık tutar" : "Aylık tutar", value: $g.tutar)
                        if g.yillik == true, g.tutar > 0 {
                            Text("Kâra her ay 1/12'si yazılır: ayda \(Money.roundHalfAwayFromZero(Double(g.tutar) / 12).tl)")
                                .font(.caption).foregroundStyle(Palette.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            BigButton("Bir tane daha ekle", icon: "plus", tone: Palette.gider) {
                giderler.append(GiderTaslak(ad: "", tutar: 0))
            }
        }
    }


    // MARK: 9 — Satış kanalları

    private var kanalSecimAdimi: some View {
        SoruAdimi(
            soru: "Hangi satış kanallarında varsın?",
            aciklama: "Birden fazla seçebilirsin. Her biri için fiyatlarını ve "
                + "kesintilerini ayrı ayrı soracağım.",
            ileriAktif: !seciliKanallar.isEmpty,
            geri: geriGit,
            ileri: { kanallariKurVeBasla() }
        ) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(kanalSecenekleri.enumerated()), id: \.element.id) { i, k in
                        Button { kanalSec(k.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: seciliKanallar.contains(k.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(seciliKanallar.contains(k.id)
                                                     ? Palette.accent : Palette.inkFaint)
                                Text(k.name).foregroundStyle(Palette.ink)
                                Spacer()
                            }
                            .padding(.horizontal, Metrics.pad)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < kanalSecenekleri.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }
            BigButton("Listede yok — kendim yazayım", icon: "plus", tone: Palette.gider) {
                ileri(.kanalAdi)
            }
        }
    }

    private var kanalAdiAdimi: some View {
        AdSorusu(
            soru: "Kanalın adı ne?",
            aciklama: "Örneğin bir pazaryeri, bir mağaza ya da toptan müşteri.",
            placeholder: "Örneğin: Toptan müşteri",
            ileriBaslik: "Ekle",
            mevcutAdlar: kanalSecenekleri.map(\.name),
            geri: geriGit,
            onDevam: { ad in
                ekKanallar.append(ChannelPreset(id: Ids.make(.channel), name: ad, kind: .other))
                seciliKanallar.insert(ekKanallar.last!.id)
                geriGit()
            }
        )
    }

    /// Seçilen kanalı tek tek kuran soru-cevap. Kanal bağımsızdır:
    /// hangi kanal olursa olsun aynı akış çalışır.
    private func kanalKurulumAdimi(_ i: Int) -> some View {
        let sirali = kurulacakKanallar
        // Yanlış kanalı kurmaktansa hiçbirini kurma.
        let id = sirali.indices.contains(i) ? sirali[i] : ""
        return ChannelSetupFlow(channelId: id) {
            if i + 1 < sirali.count {
                ileri(.kanalKurulum(i + 1))
            } else {
                ileri(.giderVarMi)
            }
        }
    }

    private var kanalSecenekleri: [ChannelPreset] {
        var out = ChannelPreset.hazir
        // Kayıtlı ama hazır listede olmayan kanallar da görünsün
        for c in store.state.channels where !out.contains(where: { $0.id == c.id }) {
            out.append(ChannelPreset(id: c.id, name: c.name, kind: c.kind))
        }
        out += ekKanallar.filter { k in !out.contains { $0.id == k.id } }
        return out
    }

    private func kanalSec(_ id: Id) {
        if seciliKanallar.contains(id) { seciliKanallar.remove(id) }
        else { seciliKanallar.insert(id) }
    }

    /// Seçilenleri kaydeder, seçilmeyenleri arşivler, ilk kanalın kurulumunu açar.
    private func kanallariKurVeBasla() {
        let secilenler = kanalSecenekleri.filter { seciliKanallar.contains($0.id) }
        kurulacakKanallar = secilenler.map(\.id)
        store.mutate { s in
            for k in secilenler {
                if let i = s.channels.firstIndex(where: { $0.id == k.id }) {
                    s.channels[i].archived = false
                    s.channels[i].name = k.name
                } else {
                    s.channels.append(Channel(id: k.id, name: k.name, kind: k.kind,
                                              feeVatRate: .yirmi, feesIncludeVat: true,
                                              setupCompleted: false))
                }
            }
            for i in s.channels.indices where !self.seciliKanallar.contains(s.channels[i].id) {
                s.channels[i].archived = true
            }
        }
        ileri(kurulacakKanallar.isEmpty ? .giderVarMi : .kanalKurulum(0))
    }

    // MARK: 10 — Özet

    private var ozetAdimi: some View {
        OzetAdimi(
            ozet: kurulumOzeti,
            sorunlar: [],
            kaydetBaslik: "Kurulumu bitir",
            geri: geriGit,
            kaydet: bitir
        )
    }

    private var kurulumOzeti: SaveSummary {
        var satirlar: [String] = []
        let u = doluUrunler
        satirlar.append("\(u.count) ürün kaydedilecek"
            + (u.isEmpty ? "" : ": " + u.map(\.ad).joined(separator: ", ")))
        let stoklu = u.filter { $0.stok > 0 }
        if !stoklu.isEmpty {
            satirlar.append("Başlangıç stoğu girilen ürün: \(stoklu.count)")
        }
        // Maliyetler her zaman KDV hariç net tutarla kaydedilir
        for t in u where t.maliyet > 0 {
            let dahil = t.maliyetKdvDahil ?? true
            satirlar.append("\(t.ad) birim maliyeti: \(Money.format(t.maliyet)) KDV "
                + (dahil ? "dahil" : "hariç")
                + " → net \(Money.format(t.netMaliyet))")
        }
        let gecerliSetler = setler.filter {
            !$0.ad.trimmingCharacters(in: .whitespaces).isEmpty
                && $0.bilesenler.values.contains { $0 > 0 }
        }
        if !gecerliSetler.isEmpty {
            satirlar.append("\(gecerliSetler.count) set/paket: "
                + gecerliSetler.map(\.ad).joined(separator: ", "))
            satirlar.append("Setlerin ayrı stoğu tutulmaz; satıldıkça içindeki ürünler düşer")
            for t in gecerliSetler where setMaliyeti(t) > 0 {
                satirlar.append("\(t.ad) maliyeti içindekilerden hesaplanacak: "
                    + Money.format(setMaliyeti(t)))
            }
            for t in gecerliSetler {
                if let hazir = hazirlanabilir(t) {
                    satirlar.append("\(t.ad) — eldeki stokla \(hazir) adet hazırlanabilir")
                }
            }
        }
        let sec = seciliIndisler
        satirlar.append("\(sec.count) ambalaj/sarf malzemesi takip edilecek")
        let recete = sec.filter { malzemeler[$0].siparisBasi > 0 }
        if !recete.isEmpty {
            satirlar.append("\(recete.count) malzeme her satışta otomatik stoktan düşecek")
        }
        let dahil = u.filter { $0.ambalajDahil == true }
        if !dahil.isEmpty {
            satirlar.append("\(dahil.count) üründe ambalaj maliyeti üretim fiyatına dahil "
                + "sayılacak, ikinci kez eklenmeyecek")
        }
        let g = giderler.filter { !$0.ad.trimmingCharacters(in: .whitespaces).isEmpty && $0.tutar > 0 }
        if !g.isEmpty {
            satirlar.append("\(g.count) sabit gider her ay otomatik eklenecek "
                + "(toplam \(Money.format(g.reduce(0) { $0 + $1.tutar })))")
        }
        let k = kanallar.filter(\.acik)
        if !k.isEmpty {
            satirlar.append("Açık satış kanalı: " + k.map(\.ad).joined(separator: ", "))
        }
        return SaveSummary(
            lines: satirlar,
            note: "Başlangıç stoğu bu ayın gideri veya nakit çıkışı sayılmaz, "
                + "indirilecek KDV oluşturmaz — KDV bilgisi yalnızca net maliyeti "
                + "bulmak için kullanılır. Set maliyetini elle girmene gerek yok; "
                + "içindeki ürünlerden hesaplanır. Hepsini sonradan değiştirebilirsin."
        )
    }

    // MARK: Gezinme

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

    // MARK: Binding yardımcıları

    private func urunAdi(_ i: Int) -> String {
        let ad = urunTaslak(i).ad.trimmingCharacters(in: .whitespaces)
        return ad.isEmpty ? "Ürün" : ad
    }

    private func urunTaslak(_ i: Int) -> UrunTaslak {
        urunler.indices.contains(i) ? urunler[i] : UrunTaslak(ad: "")
    }

    private func malzemeTaslak(_ i: Int) -> MalzemeTaslak {
        malzemeler.indices.contains(i) ? malzemeler[i]
            : MalzemeTaslak(ad: "", birim: .adet, secili: false)
    }

    private func setTaslak(_ i: Int) -> SetTaslak {
        setler.indices.contains(i) ? setler[i] : SetTaslak(ad: "")
    }

    private func setBinding(_ i: Int) -> Binding<SetTaslak> {
        Binding(
            get: { setler.indices.contains(i) ? setler[i] : SetTaslak(ad: "") },
            set: { if setler.indices.contains(i) { setler[i] = $0 } }
        )
    }

    private func bilesenBinding(_ i: Int, _ urunId: Id) -> Binding<Double> {
        Binding(
            get: { setler.indices.contains(i) ? (setler[i].bilesenler[urunId] ?? 0) : 0 },
            set: { yeni in
                guard setler.indices.contains(i) else { return }
                var t = setler[i]
                if yeni <= 0 { t.bilesenler[urunId] = nil } else { t.bilesenler[urunId] = yeni }
                setler[i] = t
            }
        )
    }

    private func setAmbalajBinding(_ i: Int, _ malzemeId: Id) -> Binding<Double> {
        Binding(
            get: { setler.indices.contains(i) ? (setler[i].ambalaj[malzemeId] ?? 0) : 0 },
            set: { yeni in
                guard setler.indices.contains(i) else { return }
                var t = setler[i]
                if yeni <= 0 { t.ambalaj[malzemeId] = nil } else { t.ambalaj[malzemeId] = yeni }
                setler[i] = t
            }
        )
    }

    /// kanal nil ise etiket fiyatı
    private func fiyatBinding(_ set: Bool, _ sira: Int, kanal: Id?) -> Binding<Kurus> {
        Binding(
            get: {
                if set {
                    guard setler.indices.contains(sira) else { return 0 }
                    return kanal.map { setler[sira].kanalFiyat[$0] ?? 0 } ?? setler[sira].listeFiyat
                }
                let dolu = doluUrunler
                guard dolu.indices.contains(sira),
                      let i = urunler.firstIndex(where: { $0.id == dolu[sira].id })
                else { return 0 }
                return kanal.map { urunler[i].kanalFiyat[$0] ?? 0 } ?? urunler[i].listeFiyat
            },
            set: { yeni in
                if set {
                    guard setler.indices.contains(sira) else { return }
                    var t = setler[sira]
                    if let kanal { t.kanalFiyat[kanal] = yeni > 0 ? yeni : nil }
                    else { t.listeFiyat = yeni }
                    setler[sira] = t
                    return
                }
                let dolu = doluUrunler
                guard dolu.indices.contains(sira),
                      let i = urunler.firstIndex(where: { $0.id == dolu[sira].id })
                else { return }
                var t = urunler[i]
                if let kanal { t.kanalFiyat[kanal] = yeni > 0 ? yeni : nil }
                else { t.listeFiyat = yeni }
                urunler[i] = t
            }
        )
    }

    private func kanalTaslak(_ i: Int) -> KanalTaslak {
        kanallar.indices.contains(i) ? kanallar[i]
            : KanalTaslak(id: "", ad: "", acik: false, komisyon: 0, kargo: 0)
    }

    private func urunBinding(_ i: Int) -> Binding<UrunTaslak> {
        Binding(
            get: { urunler.indices.contains(i) ? urunler[i] : UrunTaslak(ad: "") },
            set: { if urunler.indices.contains(i) { urunler[i] = $0 } }
        )
    }

    private func malzemeBinding(_ i: Int) -> Binding<MalzemeTaslak> {
        Binding(
            get: {
                malzemeler.indices.contains(i) ? malzemeler[i]
                    : MalzemeTaslak(ad: "", birim: .adet, secili: false)
            },
            set: { if malzemeler.indices.contains(i) { malzemeler[i] = $0 } }
        )
    }

    private func kanalBinding(_ i: Int) -> Binding<KanalTaslak> {
        Binding(
            get: {
                kanallar.indices.contains(i) ? kanallar[i]
                    : KanalTaslak(id: "", ad: "", acik: false, komisyon: 0, kargo: 0)
            },
            set: { if kanallar.indices.contains(i) { kanallar[i] = $0 } }
        )
    }

    /// Kurulumda girilen fiyatlar geçmişi silmez: ilk kez giriliyorsa
    /// baştan geçerli, değiştiriliyorsa bugünden geçerli kaydedilir.
    private static func fiyatlariUygula(_ p: inout Product, liste: Kurus, kanal: [Id: Kurus]) {
        let bugun = Dates.today()
        p.applyCurrentPrice(liste, channelId: nil, today: bugun)
        for (kanalId, tutar) in kanal.sorted(by: { $0.key < $1.key }) {
            p.applyCurrentPrice(tutar, channelId: kanalId, today: bugun)
        }
    }

    // MARK: Veri

    private func yukle() {
        guard !yuklendi else { return }
        yuklendi = true
        let s = store.state
        let bugun = Dates.today()
        urunler = s.products.filter { !$0.isBundle }.map { p in
            UrunTaslak(id: p.id, ad: p.name,
                       stok: p.openingQty ?? 0,
                       // Yalnızca bugün geçerli kalemler; kapanmış eski
                       // maliyetler toplanırsa maliyet iki kez sayılırdı.
                       maliyet: p.costLines(on: nil).reduce(0) { $0 + $1.amount },
                       ambalajDahil: p.recipe.isEmpty ? nil
                        : p.recipe.allSatisfy { !$0.resolvedAddsCost },
                       listeFiyat: p.price(on: bugun) ?? 0,
                       kanalFiyat: Dictionary(uniqueKeysWithValues:
                        s.channels.compactMap { c in
                            p.price(for: c.id, on: bugun).map { (c.id, $0) }
                        }))
        }
        if urunler.isEmpty { urunler = [UrunTaslak(ad: "")] }
        let receteler = s.products.flatMap(\.recipe)
        malzemeler = s.materials.map { m in
            MalzemeTaslak(id: m.id, ad: m.name, birim: m.baseUnit,
                          secili: !m.archived,
                          stok: m.openingQty ?? 0,
                          maliyet: m.openingUnitCost ?? 0,
                          siparisBasi: receteler
                            .filter { $0.materialId == m.id }
                            .map(\.qty).max() ?? 0,
                          ilkSiparisBasi: receteler
                            .filter { $0.materialId == m.id }
                            .map(\.qty).max() ?? 0)
        }
        setler = s.products.filter { $0.isBundle && !$0.archived }.map { p in
            SetTaslak(
                id: p.id, ad: p.name,
                bilesenler: Dictionary(p.components.map { ($0.productId, $0.qty) },
                                       uniquingKeysWith: { a, _ in a }),
                ambalaj: Dictionary(p.recipe.map { ($0.materialId, $0.qty) },
                                    uniquingKeysWith: { a, _ in a }),
                listeFiyat: p.price(on: bugun) ?? 0,
                kanalFiyat: Dictionary(uniqueKeysWithValues:
                    s.channels.compactMap { c in
                        p.price(for: c.id, on: bugun).map { (c.id, $0) }
                    })
            )
        }
        kanallar = s.channels.map {
            KanalTaslak(id: $0.id, ad: $0.name, acik: !$0.archived,
                        komisyon: $0.commissionPct + $0.paymentPct,
                        kargo: $0.shippingPerOrder)
        }
    }

    private func bitir() {
        let ay = Dates.monthStart(Dates.currentMonth())
        store.mutate { s in
            // --- Ürünler ---
            var yeniUrunler: [Product] = []
            for t in urunler where !t.ad.trimmingCharacters(in: .whitespaces).isEmpty {
                if var p = s.products.first(where: { $0.id == t.id }) {
                    p.name = t.ad
                    Self.fiyatlariUygula(&p, liste: t.listeFiyat, kanal: t.kanalFiyat)
                    p.openingQty = t.stok > 0 ? t.stok : nil
                    p.openingUnitCost = t.maliyet > 0 ? t.netMaliyet : nil
                    // Var olan kaydın açılış tarihi korunur: yoksa geçmiş aylar kayar
                    p.openingDate = p.openingDate ?? ay
                    // Maliyet değişikliği geçmiş raporları bozmaz:
                    // eski kalem kapatılır, yenisi bugünden başlar.
                    if t.maliyet > 0 {
                        let mevcut = p.costLines(on: nil).first
                        p.applyCostLines(
                            [CostLine(id: mevcut?.id ?? Ids.make(.costLine),
                                      label: "Birim maliyet", amount: t.netMaliyet)],
                            today: Dates.today()
                        )
                    }
                    yeniUrunler.append(p)
                } else {
                    var yeni = Product(
                        id: t.id, name: t.ad,
                        costLines: t.maliyet > 0
                            ? [CostLine(label: "Birim maliyet", amount: t.netMaliyet)] : [],
                        openingQty: t.stok > 0 ? t.stok : nil,
                        openingUnitCost: t.maliyet > 0 ? t.netMaliyet : nil,
                        openingDate: ay
                    )
                    Self.fiyatlariUygula(&yeni, liste: t.listeFiyat, kanal: t.kanalFiyat)
                    yeniUrunler.append(yeni)
                }
            }
            // --- Setler / çoklu paketler ---
            // Kendi stokları tutulmaz, kendi maliyet kalemleri yazılmaz:
            // maliyet bileşenlerden hesaplanır, aksi halde çift sayılır.
            let sadeIdler = Set(yeniUrunler.map(\.id))
            for t in setler {
                let ad = t.ad.trimmingCharacters(in: .whitespaces)
                let bilesenler = t.bilesenler
                    .filter { sadeIdler.contains($0.key) && $0.value > 0 }
                    .map { BundleComponent(productId: $0.key, qty: $0.value) }
                    .sorted { $0.productId < $1.productId }
                guard !ad.isEmpty, !bilesenler.isEmpty else { continue }
                let recete = t.ambalaj
                    .filter { $0.value > 0 }
                    .sorted { $0.key < $1.key }
                    .map { pair -> RecipeLine in
                        let birim = s.materials.first { $0.id == pair.key }?.baseUnit ?? .adet
                        return RecipeLine(id: "rcp_\(t.id)_\(pair.key)",
                                          materialId: pair.key, qty: pair.value, unit: birim)
                    }
                if var p = s.products.first(where: { $0.id == t.id }) {
                    p.name = ad
                    p.isBundle = true
                    p.components = bilesenler
                    p.recipe = recete
                    // Bileşen maliyeti ikinci kez yazılmaz. Geçmiş kalemler
                    // silinmez, bugünden itibaren geçersiz kılınır: eski aylar bozulmaz.
                    p.applyCostLines([], today: Dates.today())
                    p.openingQty = nil        // setin kendi stoğu yok
                    p.openingUnitCost = nil
                    p.archived = false
                    Self.fiyatlariUygula(&p, liste: t.listeFiyat, kanal: t.kanalFiyat)
                    yeniUrunler.append(p)
                } else {
                    var yeni = Product(
                        id: t.id, name: ad, isBundle: true,
                        components: bilesenler, costLines: [], recipe: recete
                    )
                    Self.fiyatlariUygula(&yeni, liste: t.listeFiyat, kanal: t.kanalFiyat)
                    yeniUrunler.append(yeni)
                }
            }
            // Kuruluma girmeyen eski setler olduğu gibi kalır
            yeniUrunler += s.products.filter { p in
                p.isBundle && !yeniUrunler.contains { $0.id == p.id }
            }
            // Kurulumda çıkarılan eski ürünler silinmez, arşivlenir: geçmiş satışları ve raporlar korunur
            for var p in s.products where !yeniUrunler.contains(where: { $0.id == p.id }) {
                p.archived = true
                yeniUrunler.append(p)
            }
            s.products = yeniUrunler

            // --- Malzemeler ---
            var yeniMalzemeler: [StockMaterial] = []
            for t in malzemeler where !t.ad.trimmingCharacters(in: .whitespaces).isEmpty {
                if var m = s.materials.first(where: { $0.id == t.id }) {
                    m.name = t.ad
                    m.archived = !t.secili
                    m.openingQty = t.secili && t.stok > 0 ? t.stok : nil
                    m.openingUnitCost = t.secili && t.maliyet > 0 ? t.netMaliyet : nil
                    m.openingDate = m.openingDate ?? ay
                    yeniMalzemeler.append(m)
                } else if t.secili {
                    yeniMalzemeler.append(StockMaterial(
                        id: t.id, name: t.ad, baseUnit: t.birim,
                        openingQty: t.stok > 0 ? t.stok : nil,
                        openingUnitCost: t.maliyet > 0 ? t.netMaliyet : nil,
                        openingDate: ay
                    ))
                }
            }
            // Listeden çıkarılan eski malzemeler de silinmez, arşivlenir (alım ve stok geçmişi korunur)
            for var m in s.materials where !yeniMalzemeler.contains(where: { $0.id == m.id }) {
                m.archived = true
                yeniMalzemeler.append(m)
            }
            s.materials = yeniMalzemeler

            // Kullanılmayan malzemelerin reçete satırlarını temizle
            let aktif = Set(s.materials.filter { !$0.archived }.map(\.id))
            let urunIdleri = Set(s.products.map(\.id))
            for i in s.products.indices {
                s.products[i].recipe.removeAll { !aktif.contains($0.materialId) }
                s.products[i].components.removeAll { !urunIdleri.contains($0.productId) }
            }

            // --- Sipariş başı kullanım → paketleme reçetesi ---
            // Motor değişmiyor; yalnızca reçete satırları yazılıyor.
            // Setlerin reçetesi ayrı soruldu; burada yalnızca tekil ürünler güncellenir.
            let sade = Set(s.products.filter { !$0.isBundle }.map(\.id))
            let seteOzel = Set(setler.flatMap { $0.ambalaj.filter { $0.value > 0 }.keys })
            for t in malzemeler where t.secili && t.siparisBasi > 0 && aktif.contains(t.id) {
                let gecenler = s.products.filter { p in
                    !p.isBundle && p.recipe.contains { $0.materialId == t.id }
                }.map(\.id)
                // Yalnızca sette kullanılan bir malzeme tüm ürünlere eklenmez
                if gecenler.isEmpty && seteOzel.contains(t.id) { continue }
                // Malzeme hiçbir reçetede yoksa tüm sade ürünlere eklenir,
                // varsa yalnızca zaten kullandığı ürünlerin miktarı güncellenir.
                let hedefler = gecenler.isEmpty ? Array(sade) : gecenler
                for i in s.products.indices
                where hedefler.contains(s.products[i].id) && !s.products[i].isBundle {
                    var p = s.products[i]
                    if let j = p.recipe.firstIndex(where: { $0.materialId == t.id }) {
                        p.recipe[j].qty = t.siparisBasi
                        p.recipe[j].unit = t.birim
                    } else {
                        p.recipe.append(RecipeLine(materialId: t.id,
                                                   qty: t.siparisBasi, unit: t.birim))
                    }
                    s.products[i] = p
                }
            }
            // Reçetede miktarı vardı, kullanıcı sıfırladıysa satır kaldırılır.
            // Hiç dokunulmamış (baştan sıfır) malzemeler olduğu gibi bırakılır.
            let sifirlanan = Set(malzemeler
                .filter { $0.ilkSiparisBasi > 0 && $0.siparisBasi == 0 }
                .map(\.id))
            if !sifirlanan.isEmpty {
                for i in s.products.indices where !s.products[i].isBundle {
                    s.products[i].recipe.removeAll { sifirlanan.contains($0.materialId) }
                }
            }

            // --- "Ambalaj üretim fiyatına dahil" cevabı ---
            // Evet → malzeme stoktan düşer ama maliyete ikinci kez eklenmez.
            for t in urunler {
                guard let dahil = t.ambalajDahil,
                      let i = s.products.firstIndex(where: { $0.id == t.id }),
                      !s.products[i].isBundle else { continue }
                var p = s.products[i]
                for j in p.recipe.indices {
                    p.recipe[j].consumesStock = true
                    p.recipe[j].addsCost = !dahil
                }
                s.products[i] = p
            }

            // --- Sabit giderler ---
            for t in giderler where !t.ad.trimmingCharacters(in: .whitespaces).isEmpty && t.tutar > 0 {
                if !s.expenses.contains(where: { $0.id == t.id }) {
                    s.expenses.append(Expense(
                        id: t.id, date: ay, name: t.ad, amount: t.tutar,
                        category: .sabit, recurrence: t.yillik == true ? .yillik : .aylik,
                        vatRate: s.settings.vatEnabled ? s.settings.defaultVatRate : nil,
                        vatIncluded: s.settings.defaultVatIncluded
                    ))
                }
            }

            // Kanal oranları ve kanal fiyatları kendi soru-cevap akışında
            // kaydedildi; burada tekrar yazılmaz.

            s.settings.setupCompleted = true
            s.drafts.removeAll { $0.kind == .ilkKurulum }
        }
    }
}

// MARK: - Taslak modeller

struct UrunTaslak: Identifiable, Codable {
    var id: Id = Ids.make(.product)
    var ad: String
    var stok: Double = 0
    var maliyet: Kurus = 0
    /// Girilen maliyet KDV dahil mi? nil = henüz sorulmadı
    var maliyetKdvDahil: Bool?
    var maliyetKdvOrani: VatRate = .yirmi
    var maliyetKdvOranSecildi = false
    /// Şişe/kapak/etiket üretim fiyatına dahil mi? nil = henüz sorulmadı
    var ambalajDahil: Bool?

    /// Kâr ve stok hesabında kullanılan KDV hariç maliyet
    var netMaliyet: Kurus {
        Vat.net(maliyet, rate: maliyetKdvOrani, included: maliyetKdvDahil ?? true)
    }
    var listeFiyat: Kurus = 0
    var kanalFiyat: [Id: Kurus] = [:]
}

/// Set / çoklu paket — fiziksel ürün değil, satış kombinasyonu (SKU).
/// Kendi stoğu tutulmaz, maliyeti bileşenlerinden hesaplanır.
struct SetTaslak: Identifiable, Codable {
    var id: Id = Ids.make(.product)
    var ad: String
    /// ürün id → bir pakette kaç adet
    var bilesenler: [Id: Double] = [:]
    /// malzeme id → pakete özel ambalaj miktarı
    var ambalaj: [Id: Double] = [:]
    var listeFiyat: Kurus = 0
    var kanalFiyat: [Id: Kurus] = [:]
}

struct MalzemeTaslak: Identifiable, Codable {
    var id: Id = Ids.make(.material)
    var ad: String
    var birim: UnitCode
    var secili: Bool
    var stok: Double = 0
    var maliyet: Kurus = 0
    /// Girilen birim maliyet KDV dahil mi? nil = henüz sorulmadı
    var maliyetKdvDahil: Bool?
    var maliyetKdvOrani: VatRate = .yirmi
    /// Bir siparişte kullanılan miktar (reçete)
    var siparisBasi: Double = 0
    /// Kuruluma girerken reçetede yazan miktar; sıfırlanırsa satır kaldırılır
    var ilkSiparisBasi: Double = 0

    /// KDV hariç birim maliyet
    var netMaliyet: Kurus {
        Vat.net(maliyet, rate: maliyetKdvOrani, included: maliyetKdvDahil ?? true)
    }
    var yeni: Bool = false
}

struct GiderTaslak: Identifiable, Codable {
    var id: Id = Ids.make(.expense)
    var ad: String
    var tutar: Kurus
    /// Yılda bir mi ödeniyor (nil = ayda bir)
    var yillik: Bool?
}

struct KanalTaslak: Identifiable {
    var id: Id
    var ad: String
    var acik: Bool
    var komisyon: Double
    var kargo: Kurus
}
