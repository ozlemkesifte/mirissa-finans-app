import SwiftUI
import MirissaCore

/// İlk açılışta çıkan zorunlu kurulum.
/// Tek ekranda tek soru; cevaba göre sonraki soru değişir.
/// Geçmişte alınmış stoklar "başlangıç stoğu" olarak girilir:
/// stoğa ve maliyete girer, bu ayın gideri veya nakit çıkışı sayılmaz.
public struct SetupWizard: View {
    @Environment(AppStore.self) private var store

    enum Adim: Hashable {
        case karsilama
        case urunSayisi
        case urunAdi(Int)
        case urunStok(Int)
        case urunMaliyet(Int)
        case ambalajDahil(Int)
        case malzemeSecimi
        case malzemeDetay(Int)
        case giderVarMi
        case giderler
        case kanalKullanim(Int)
        case kanalDetay(Int)
        case ozet
    }

    @State private var adim: Adim = .karsilama
    @State private var gecmis: [Adim] = []
    @State private var urunler: [UrunTaslak] = []
    @State private var malzemeler: [MalzemeTaslak] = []
    @State private var giderler: [GiderTaslak] = []
    @State private var kanallar: [KanalTaslak] = []
    @State private var yuklendi = false

    public init() {}

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
        icerik
            .background(Palette.bg)
            .onAppear(perform: yukle)
    }

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case .karsilama: karsilama
        case let .urunSayisi: urunSayisiAdimi
        case let .urunAdi(i): urunAdiAdimi(i)
        case let .urunStok(i): urunStokAdimi(i)
        case let .urunMaliyet(i): urunMaliyetAdimi(i)
        case let .ambalajDahil(i): ambalajDahilAdimi(i)
        case .malzemeSecimi: malzemeSecimAdimi
        case let .malzemeDetay(i): malzemeDetayAdimi(i)
        case .giderVarMi: giderVarMiAdimi
        case .giderler: giderAdimi
        case let .kanalKullanim(i): kanalKullanimAdimi(i)
        case let .kanalDetay(i): kanalDetayAdimi(i)
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
            soru: "Kaç ürün satıyorsun?",
            aciklama: "Set gibi birden çok üründen oluşanları saymana gerek yok, "
                + "onları sonra ekleyebilirsin.",
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
        SoruAdimi(
            soru: "\(i + 1). ürünün adı ne?",
            adim: i + 1, toplam: urunler.count,
            ileriAktif: !urunTaslak(i).ad.trimmingCharacters(in: .whitespaces).isEmpty,
            geri: geriGit,
            ileri: { ileri(.urunStok(i)) }
        ) {
            Card {
                TextField("Ürün adı", text: urunBinding(i).ad)
                    .font(.title3)
                    .foregroundStyle(Palette.ink)
            }
            if urunler.count > 1 {
                SecenekButonu(baslik: "Bu ürünü eklemeyeceğim",
                              ikon: "minus.circle", renk: Palette.inkSoft) {
                    urunler.remove(at: i)
                    ileri(sonrakiUrunAdimi(i))
                }
            }
        }
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
            ileri: { ileri(.ambalajDahil(i)) }
        ) {
            BuyukParaAlani(baslik: "1 adet \(urunAdi(i))", deger: urunBinding(i).maliyet)
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
        i + 1 < urunler.count ? .urunAdi(i + 1) : .malzemeSecimi
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
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array($malzemeler.enumerated()), id: \.element.id) { i, $m in
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
                malzemeler.append(MalzemeTaslak(ad: "", birim: .adet, secili: true, yeni: true))
            }
        }
    }

    // MARK: 7 — Malzeme detayı

    private func malzemeDetayAdimi(_ sira: Int) -> some View {
        let indisler = seciliIndisler
        let i = indisler.indices.contains(sira) ? indisler[sira] : indisler.last ?? 0
        let m = malzemeTaslak(i)
        let birim = m.birim.displayName
        return SoruAdimi(
            soru: m.ad.isEmpty ? "Bu malzemeyi anlat" : "\(m.ad)",
            aciklama: "Elindeki miktarı, birim maliyetini ve bir siparişte kaç tane "
                + "kullandığını yaz. Bilmiyorsan boş bırak.",
            adim: sira + 1, toplam: indisler.count,
            geri: geriGit,
            ileri: { ileri(sonrakiMalzemeAdimi(sira)) }
        ) {
            if m.yeni {
                Card {
                    TextField("Malzeme adı", text: malzemeBinding(i).ad)
                        .font(.title3)
                        .foregroundStyle(Palette.ink)
                }
            }
            BuyukSayiAlani(baslik: "Şu anda elinde", birim: birim, deger: malzemeBinding(i).stok)
            BuyukParaAlani(baslik: "1 \(birim) maliyeti", deger: malzemeBinding(i).maliyet)
            BuyukSayiAlani(baslik: "Bir siparişte kullandığın",
                           birim: birim, deger: malzemeBinding(i).siparisBasi)
        }
    }

    private func sonrakiMalzemeAdimi(_ sira: Int) -> Adim {
        sira + 1 < seciliIndisler.count ? .malzemeDetay(sira + 1) : .giderVarMi
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
                    ileri(ilkKanalAdimi)
                }
            }
        }
    }

    private var giderAdimi: some View {
        SoruAdimi(
            soru: "Bu giderler neler?",
            aciklama: "Adını ve aylık tutarını yaz.",
            geri: geriGit,
            ileri: { ileri(ilkKanalAdimi) }
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
                        MoneyField("Aylık tutar", value: $g.tutar)
                    }
                }
            }
            BigButton("Bir tane daha ekle", icon: "plus", tone: Palette.gider) {
                giderler.append(GiderTaslak(ad: "", tutar: 0))
            }
        }
    }

    // MARK: 9 — Kanallar

    private var ilkKanalAdimi: Adim { kanallar.isEmpty ? .ozet : .kanalKullanim(0) }

    private func kanalKullanimAdimi(_ i: Int) -> some View {
        SoruAdimi(
            soru: "\(kanalTaslak(i).ad) üzerinden satış yapıyor musun?",
            adim: i + 1, toplam: kanallar.count,
            geri: geriGit
        ) {
            EvetHayirSorusu(
                evet: "Evet",
                hayir: "Hayır",
                secim: kanalTaslak(i).acik
            ) { secim in
                if kanallar.indices.contains(i) { kanallar[i].acik = secim }
                ileri(secim ? .kanalDetay(i) : sonrakiKanalAdimi(i))
            }
        }
    }

    private func kanalDetayAdimi(_ i: Int) -> some View {
        SoruAdimi(
            soru: "\(kanalTaslak(i).ad) senden ne kesiyor?",
            aciklama: "Komisyon oranını ve sipariş başına ödediğin kargo tutarını girersen "
                + "kârlılık doğru hesaplanır. Her ay gerçek tutarı da yazabilirsin.",
            adim: i + 1, toplam: kanallar.count,
            geri: geriGit,
            ileri: { ileri(sonrakiKanalAdimi(i)) }
        ) {
            Card {
                VStack(spacing: 12) {
                    PercentField("Komisyon oranı", value: kanalBinding(i).komisyon)
                    MoneyField("Sipariş başı kargo", value: kanalBinding(i).kargo)
                }
            }
        }
    }

    private func sonrakiKanalAdimi(_ i: Int) -> Adim {
        i + 1 < kanallar.count ? .kanalKullanim(i + 1) : .ozet
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
                + "KDV kaydı oluşturmaz. Hepsini sonradan değiştirebilirsin."
        )
    }

    // MARK: Gezinme

    private func ileri(_ hedef: Adim) {
        gecmis.append(adim)
        withAnimation(.snappy(duration: 0.2)) { adim = hedef }
    }

    private func geriGit() {
        guard let onceki = gecmis.popLast() else { return }
        withAnimation(.snappy(duration: 0.2)) { adim = onceki }
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

    // MARK: Veri

    private func yukle() {
        guard !yuklendi else { return }
        yuklendi = true
        let s = store.state
        urunler = s.products.filter { !$0.isBundle }.map { p in
            UrunTaslak(id: p.id, ad: p.name,
                       stok: p.openingQty ?? 0,
                       maliyet: p.costLines.reduce(0) { $0 + $1.amount },
                       ambalajDahil: p.recipe.isEmpty ? nil
                        : p.recipe.allSatisfy { !$0.resolvedAddsCost })
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
                    p.openingQty = t.stok > 0 ? t.stok : nil
                    p.openingUnitCost = t.maliyet > 0 ? t.maliyet : nil
                    p.openingDate = ay
                    p.costLines = t.maliyet > 0
                        ? [CostLine(id: p.costLines.first?.id ?? Ids.make(.costLine),
                                    label: "Birim maliyet", amount: t.maliyet)]
                        : p.costLines
                    yeniUrunler.append(p)
                } else {
                    yeniUrunler.append(Product(
                        id: t.id, name: t.ad,
                        costLines: t.maliyet > 0
                            ? [CostLine(label: "Birim maliyet", amount: t.maliyet)] : [],
                        openingQty: t.stok > 0 ? t.stok : nil,
                        openingUnitCost: t.maliyet > 0 ? t.maliyet : nil,
                        openingDate: ay
                    ))
                }
            }
            // Setleri koru
            yeniUrunler += s.products.filter { p in
                p.isBundle && !yeniUrunler.contains { $0.id == p.id }
            }
            s.products = yeniUrunler

            // --- Malzemeler ---
            var yeniMalzemeler: [StockMaterial] = []
            for t in malzemeler where !t.ad.trimmingCharacters(in: .whitespaces).isEmpty {
                if var m = s.materials.first(where: { $0.id == t.id }) {
                    m.name = t.ad
                    m.archived = !t.secili
                    m.openingQty = t.secili && t.stok > 0 ? t.stok : nil
                    m.openingUnitCost = t.secili && t.maliyet > 0 ? t.maliyet : nil
                    m.openingDate = ay
                    yeniMalzemeler.append(m)
                } else if t.secili {
                    yeniMalzemeler.append(StockMaterial(
                        id: t.id, name: t.ad, baseUnit: t.birim,
                        openingQty: t.stok > 0 ? t.stok : nil,
                        openingUnitCost: t.maliyet > 0 ? t.maliyet : nil,
                        openingDate: ay
                    ))
                }
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
            let sade = Set(s.products.filter { !$0.isBundle }.map(\.id))
            for t in malzemeler where t.secili && t.siparisBasi > 0 && aktif.contains(t.id) {
                let gecenler = s.products.filter { p in
                    p.recipe.contains { $0.materialId == t.id }
                }.map(\.id)
                // Malzeme hiçbir reçetede yoksa tüm sade ürünlere eklenir,
                // varsa yalnızca zaten kullandığı ürünlerin miktarı güncellenir.
                let hedefler = gecenler.isEmpty ? Array(sade) : gecenler
                for i in s.products.indices where hedefler.contains(s.products[i].id) {
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
                for i in s.products.indices {
                    s.products[i].recipe.removeAll { sifirlanan.contains($0.materialId) }
                }
            }

            // --- "Ambalaj üretim fiyatına dahil" cevabı ---
            // Evet → malzeme stoktan düşer ama maliyete ikinci kez eklenmez.
            for t in urunler {
                guard let dahil = t.ambalajDahil,
                      let i = s.products.firstIndex(where: { $0.id == t.id }) else { continue }
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
                        category: .sabit, recurrence: .aylik,
                        vatRate: s.settings.vatEnabled ? s.settings.defaultVatRate : nil,
                        vatIncluded: s.settings.defaultVatIncluded
                    ))
                }
            }

            // --- Kanallar ---
            for t in kanallar {
                guard let i = s.channels.firstIndex(where: { $0.id == t.id }) else { continue }
                s.channels[i].archived = !t.acik
                if t.acik {
                    if s.channels[i].kind == .ownStore {
                        s.channels[i].paymentPct = t.komisyon
                        s.channels[i].commissionPct = 0
                    } else {
                        s.channels[i].commissionPct = t.komisyon
                    }
                    s.channels[i].shippingPerOrder = t.kargo
                }
            }

            s.settings.setupCompleted = true
        }
    }
}

// MARK: - Taslak modeller

struct UrunTaslak: Identifiable {
    var id: Id = Ids.make(.product)
    var ad: String
    var stok: Double = 0
    var maliyet: Kurus = 0
    /// Şişe/kapak/etiket üretim fiyatına dahil mi? nil = henüz sorulmadı
    var ambalajDahil: Bool?
}

struct MalzemeTaslak: Identifiable {
    var id: Id = Ids.make(.material)
    var ad: String
    var birim: UnitCode
    var secili: Bool
    var stok: Double = 0
    var maliyet: Kurus = 0
    /// Bir siparişte kullanılan miktar (reçete)
    var siparisBasi: Double = 0
    /// Kuruluma girerken reçetede yazan miktar; sıfırlanırsa satır kaldırılır
    var ilkSiparisBasi: Double = 0
    var yeni: Bool = false
}

struct GiderTaslak: Identifiable {
    var id: Id = Ids.make(.expense)
    var ad: String
    var tutar: Kurus
}

struct KanalTaslak: Identifiable {
    var id: Id
    var ad: String
    var acik: Bool
    var komisyon: Double
    var kargo: Kurus
}
