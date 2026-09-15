import SwiftUI
import MirissaCore

/// İlk açılışta çıkan zorunlu kurulum. Tek ekranda tek soru.
/// Geçmişte alınmış stoklar "başlangıç stoğu" olarak girilir:
/// stoğa ve maliyete girer, bu ayın gideri veya nakit çıkışı sayılmaz.
public struct SetupWizard: View {
    @Environment(AppStore.self) private var store

    @State private var adim = 0
    @State private var urunler: [UrunTaslak] = []
    @State private var malzemeler: [MalzemeTaslak] = []
    @State private var giderler: [GiderTaslak] = []
    @State private var kanallar: [KanalTaslak] = []
    @State private var yuklendi = false

    public init() {}

    private let sonAdim = 7

    public var body: some View {
        VStack(spacing: 0) {
            ilerleme
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.gap) {
                    baslik
                    icerik
                    Color.clear.frame(height: 12)
                }
                .padding(Metrics.pad)
            }
            .screenBackground()
            altButonlar
        }
        .background(Palette.bg)
        .onAppear(perform: yukle)
    }

    // MARK: Üst çubuk

    private var ilerleme: some View {
        VStack(spacing: 8) {
            HStack {
                Text(adim == 0 ? "İlk kurulum" : "Adım \(adim) / \(sonAdim)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.inset)
                    Capsule().fill(Palette.accent)
                        .frame(width: geo.size.width * CGFloat(adim) / CGFloat(sonAdim))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Palette.card)
    }

    private var baslik: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(soru)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !aciklama.isEmpty {
                Text(aciklama)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var soru: String {
        switch adim {
        case 0: return "Hoş geldin"
        case 1: return "Hangi ürünleri satıyorsun?"
        case 2: return "Şu anda elinde kaç adet var?"
        case 3: return "Bir adedi sana kaça mal oluyor?"
        case 4: return "Hangi ambalaj ve sarf malzemelerini kullanıyorsun?"
        case 5: return "Bu malzemelerden şu anda ne kadar var?"
        case 6: return "Her ay ödediğin sabit giderler neler?"
        default: return "Nerelerde satış yapıyorsun?"
        }
    }

    private var aciklama: String {
        switch adim {
        case 0:
            return "Yedi kısa adımda uygulamayı kendi işine göre kuracağız. Bilmediğin bir şey olursa boş bırak, sonradan değiştirebilirsin."
        case 1: return "Set gibi birden çok üründen oluşanları sonra ekleyebilirsin."
        case 2:
            return "Depodaki mevcut adet. Bunlar geçmişte alındığı için bu ayın gideri veya nakit çıkışı olarak yazılmaz — sadece stoğuna eklenir."
        case 3: return "Üretim, fason, hammadde dahil; ambalaj hariç. Ambalajı sistem reçeteden hesaplayacak."
        case 4: return "Kullanmadıklarının işaretini kaldır. Sonradan ekleyip çıkarabilirsin."
        case 5: return "Elindeki mevcut miktar ve birim maliyeti. Bunlar da bu ayın gideri sayılmaz."
        case 6: return "Muhasebeci, ajans, abonelikler… Bir kez gir, her ay otomatik eklensin."
        case 7: return "Komisyon oranını ve sipariş başına kargo tutarını girersen kârlılık doğru hesaplanır."
        default: return ""
        }
    }

    // MARK: İçerik

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case 0: karsilama
        case 1: urunAdimi
        case 2: urunStokAdimi
        case 3: urunMaliyetAdimi
        case 4: malzemeSecimAdimi
        case 5: malzemeStokAdimi
        case 6: giderAdimi
        default: kanalAdimi
        }
    }

    private var karsilama: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                madde("cube.box", "Ürünlerin ve elindeki stok")
                madde("shippingbox", "Ambalaj ve sarf malzemelerin")
                madde("repeat", "Her ay ödediğin sabit giderler")
                madde("storefront", "Satış kanalların ve komisyonları")
                Divider().overlay(Palette.separator)
                Text("Sonrasında günlük kullanım üç şeyden ibaret: satış gir, gider gir, stok alımı gir.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
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

    // 1 — Ürünler
    private var urunAdimi: some View {
        VStack(spacing: Metrics.gap) {
            ForEach($urunler) { $u in
                Card {
                    HStack(spacing: 10) {
                        TextField("Ürün adı", text: $u.ad)
                            .foregroundStyle(Palette.ink)
                        Button {
                            urunler.removeAll { $0.id == u.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            BigButton("Ürün ekle", icon: "plus", tone: Palette.gider) {
                urunler.append(UrunTaslak(ad: ""))
            }
        }
    }

    // 2 — Ürün stokları
    private var urunStokAdimi: some View {
        VStack(spacing: Metrics.gap) {
            ForEach($urunler) { $u in
                if !u.ad.isEmpty {
                    Card {
                        QtyField(u.ad, suffix: "adet", value: $u.stok)
                    }
                }
            }
            if urunler.allSatisfy({ $0.ad.isEmpty }) { bosUyari("Önce ürün eklemelisin.") }
        }
    }

    // 3 — Ürün maliyetleri
    private var urunMaliyetAdimi: some View {
        VStack(spacing: Metrics.gap) {
            ForEach($urunler) { $u in
                if !u.ad.isEmpty {
                    Card { MoneyField(u.ad, value: $u.maliyet) }
                }
            }
            if urunler.allSatisfy({ $0.ad.isEmpty }) { bosUyari("Önce ürün eklemelisin.") }
        }
    }

    // 4 — Malzeme seçimi
    private var malzemeSecimAdimi: some View {
        VStack(spacing: Metrics.gap) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array($malzemeler.enumerated()), id: \.element.id) { i, $m in
                        Button {
                            m.secili.toggle()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.secili ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(m.secili ? Palette.accent : Palette.inkFaint)
                                Text(m.ad).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(m.birim.displayName)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, Metrics.pad)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < malzemeler.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }
            BigButton("Başka malzeme ekle", icon: "plus", tone: Palette.gider) {
                malzemeler.append(MalzemeTaslak(ad: "", birim: .adet, secili: true, yeni: true))
            }
        }
    }

    // 5 — Malzeme stokları
    private var malzemeStokAdimi: some View {
        VStack(spacing: Metrics.gap) {
            ForEach($malzemeler) { $m in
                if m.secili && !m.ad.isEmpty {
                    Card {
                        VStack(spacing: 10) {
                            Text(m.ad)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            QtyField("Mevcut miktar", suffix: m.birim.displayName, value: $m.stok)
                            MoneyField("1 \(m.birim.displayName) maliyeti", value: $m.maliyet)
                        }
                    }
                }
            }
        }
    }

    // 6 — Sabit giderler
    private var giderAdimi: some View {
        VStack(spacing: Metrics.gap) {
            ForEach($giderler) { $g in
                Card {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Gider adı", text: $g.ad).foregroundStyle(Palette.ink)
                            Button { giderler.removeAll { $0.id == g.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Palette.inkFaint)
                            }
                            .buttonStyle(.plain)
                        }
                        MoneyField("Aylık tutar", value: $g.tutar)
                    }
                }
            }
            BigButton("Sabit gider ekle", icon: "plus", tone: Palette.gider) {
                giderler.append(GiderTaslak(ad: "", tutar: 0))
            }
            if giderler.isEmpty { bosUyari("Sabit giderin yoksa bu adımı atlayabilirsin.") }
        }
    }

    // 7 — Kanallar
    private var kanalAdimi: some View {
        VStack(spacing: Metrics.gap) {
            ForEach($kanallar) { $k in
                Card {
                    VStack(spacing: 10) {
                        Toggle(isOn: $k.acik) {
                            Text(k.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        }
                        if k.acik {
                            Divider().overlay(Palette.separator)
                            PercentField("Komisyon oranı", value: $k.komisyon)
                            MoneyField("Sipariş başı kargo", value: $k.kargo)
                        }
                    }
                }
            }
        }
    }

    private func bosUyari(_ t: String) -> some View {
        Card(background: Palette.inset) {
            Text(t).font(.footnote).foregroundStyle(Palette.inkSoft)
        }
    }

    // MARK: Alt butonlar

    private var altButonlar: some View {
        HStack(spacing: Metrics.gap) {
            if adim > 0 {
                Button("Geri") { withAnimation { adim -= 1 } }
                    .font(.headline)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: 90)
            }
            BigButton(adim == sonAdim ? "Kurulumu bitir" : (adim == 0 ? "Başla" : "Devam"),
                      icon: adim == sonAdim ? "checkmark" : nil) {
                if adim == sonAdim { bitir() } else { withAnimation { adim += 1 } }
            }
        }
        .padding(Metrics.pad)
        .background(Palette.card)
    }

    // MARK: Veri

    private func yukle() {
        guard !yuklendi else { return }
        yuklendi = true
        let s = store.state
        urunler = s.products.filter { !$0.isBundle }.map {
            UrunTaslak(id: $0.id, ad: $0.name,
                       stok: $0.openingQty ?? 0,
                       maliyet: $0.costLines.reduce(0) { $0 + $1.amount })
        }
        if urunler.isEmpty { urunler = [UrunTaslak(ad: "")] }
        malzemeler = s.materials.map {
            MalzemeTaslak(id: $0.id, ad: $0.name, birim: $0.baseUnit,
                          secili: !$0.archived,
                          stok: $0.openingQty ?? 0,
                          maliyet: $0.openingUnitCost ?? 0)
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
}

struct MalzemeTaslak: Identifiable {
    var id: Id = Ids.make(.material)
    var ad: String
    var birim: UnitCode
    var secili: Bool
    var stok: Double = 0
    var maliyet: Kurus = 0
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
