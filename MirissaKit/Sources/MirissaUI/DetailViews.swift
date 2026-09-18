import SwiftUI
import MirissaCore

// MARK: - Ürün detayı

struct ProductDetail: View {
    @Environment(AppStore.self) private var store
    var productId: Id
    @State private var sheet: AppSheet?

    private var product: Product? { store.state.product(productId) }
    private var ref: ItemRef { .product(productId) }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.gap) {
                if let p = product {
                    if store.engine.hasCycle(productId) {
                        Card(background: Palette.zararYumusak) {
                            Text("Bu setin içeriği kendini içeriyor. Maliyet hesaplanamıyor — set içeriğini düzelt.")
                                .font(.footnote)
                                .foregroundStyle(Palette.zarar)
                        }
                    }

                    summary(p)
                    fiyatKarti(p)
                    costCard(p)
                    SatisHakedisKarti(productId: productId)

                    if p.isBundle { componentsCard(p) }
                    recipeCard(p)

                    if p.tracksOwnStock {
                        actions
                        MovementHistory(item: ref)
                    }
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 4)
        }
        .screenBackground()
        .navigationTitle(product?.name ?? "Ürün")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Düzenle") { sheet = .editProduct(productId) }
                    .foregroundStyle(Palette.accent)
            }
        }
        .appSheets($sheet)
    }

    private func summary(_ p: Product) -> some View {
        let b = store.engine.balance(ref)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: Metrics.gap),
                                   GridItem(.flexible(), spacing: Metrics.gap)], spacing: Metrics.gap) {
            BigStat(
                title: "Stok",
                value: p.tracksOwnStock ? Units.formatQty(b.qty, baseUnit: .adet) : "—",
                tone: b.qty < 0 ? Palette.zarar : Palette.ink,
                caption: p.tracksOwnStock ? nil : "Set: bileşenlerden düşer"
            )
            BigStat(
                title: "Birim Maliyet",
                value: store.engine.cost(of: productId).total.tl,
                tone: Palette.ink
            )
        }
    }

    private func costCard(_ p: Product) -> some View {
        VStack(spacing: Metrics.gap) {
            SectionTitle("Bir satışın maliyeti", actionLabel: "Düzenle") { sheet = .editProduct(productId) }
            Card {
                if let d = store.engine.birimMaliyetDokumu(productId: productId) {
                    BirimMaliyetListesi(dokum: d)
                }
            }
            if p.recipe.isEmpty && !p.isBundle {
                Text("Ambalaj reçetesi yok: koli, patpat, dolgu gibi malzemeler bu ürünün maliyetine eklenmiyor.")
                    .font(.caption).foregroundStyle(Palette.uyari)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fiyatKarti(_ p: Product) -> some View {
        let bugun = Dates.today()
        let etiket = p.price(on: bugun)
        return VStack(spacing: Metrics.gap) {
            SectionTitle("Satış Fiyatı")
            Card {
                VStack(spacing: 9) {
                    if let etiket {
                        LabeledRow("Etiket", Money.format(etiket), strong: true)
                        ForEach(store.state.activeChannels) { c in
                            if let f = p.price(for: c.id, on: bugun), f != etiket {
                                LabeledRow(c.name, Money.format(f))
                            }
                        }
                        if let sonra = sonrakiFiyat(p, bugun) {
                            Divider().overlay(Palette.separator)
                            LabeledRow("\(Dates.displayDate(sonra.from)) tarihinden itibaren",
                                       Money.format(sonra.amount), tone: Palette.accent)
                        }
                    } else {
                        Text("Fiyat girilmemiş.")
                            .font(.footnote).foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    BigButton("Fiyatı Güncelle", icon: "tag", tone: Palette.gider) {
                        sheet = .priceUpdate(p.id)
                    }
                }
            }
        }
    }

    /// İleri tarihli bir fiyat tanımlıysa onu gösterir
    private func sonrakiFiyat(_ p: Product, _ bugun: DateKey) -> PricePoint? {
        (p.priceHistory ?? [])
            .filter { $0.from > bugun }
            .min { $0.from < $1.from }
    }

    private func componentsCard(_ p: Product) -> some View {
        let hazir = store.engine.buildable(p.id)
        let darBogaz = store.engine.buildableBottleneck(p.id)
        return VStack(spacing: Metrics.gap) {
            SectionTitle("Setin İçindekiler")
            Card {
                VStack(spacing: 9) {
                    ForEach(p.components) { c in
                        LabeledRow(
                            store.state.product(c.productId)?.name ?? "—",
                            "\(NumberInput.display(c.qty).isEmpty ? "0" : NumberInput.display(c.qty)) adet"
                        )
                    }
                    if let hazir {
                        Divider().overlay(Palette.separator)
                        LabeledRow("Eldeki stokla hazırlanabilir", "\(hazir) adet",
                                   tone: hazir == 0 ? Palette.zarar : Palette.ink, strong: true)
                        if hazir > 0, let darBogaz,
                           let ad = store.state.product(darBogaz.productId)?.name {
                            Text("Sınırlayan: \(ad)")
                                .font(.caption)
                                .foregroundStyle(Palette.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text("Setin ayrı stoğu tutulmaz. Satıldığında içindeki ürünler düşer, "
                         + "maliyeti de onlardan hesaplanır.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func recipeCard(_ p: Product) -> some View {
        VStack(spacing: Metrics.gap) {
            SectionTitle("Paketleme Reçetesi")
            Card {
                if p.recipe.isEmpty {
                    Text("Reçete tanımlanmadı. Kutu, koli, etiket gibi malzemeleri eklersen satışta otomatik düşer.")
                        .font(.footnote).foregroundStyle(Palette.inkFaint)
                } else {
                    VStack(spacing: 9) {
                        ForEach(p.recipe) { line in
                            let m = store.state.material(line.materialId)
                            LabeledRow(
                                m?.name ?? "Silinmiş malzeme",
                                "\(NumberInput.display(line.qty).isEmpty ? "0" : NumberInput.display(line.qty)) \(line.unit.displayName)"
                            )
                        }
                        Divider().overlay(Palette.separator)
                        Text("1 adet satıldığında bu malzemeler stoktan düşer.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Metrics.gap) {
            BigButton("Stok Al", icon: "shippingbox") { sheet = .addPurchase(ref) }
            BigButton("Düzelt", icon: "slider.horizontal.3", tone: Palette.gider) { sheet = .adjustStock(ref) }
        }
    }
}

// MARK: - Malzeme detayı

struct MaterialDetail: View {
    @Environment(AppStore.self) private var store
    var materialId: Id
    @State private var sheet: AppSheet?

    private var material: StockMaterial? { store.state.material(materialId) }
    private var ref: ItemRef { .material(materialId) }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.gap) {
                if let m = material {
                    summary(m)
                    detail(m)
                    actions
                    MovementHistory(item: ref)
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 4)
        }
        .screenBackground()
        .navigationTitle(material?.name ?? "Malzeme")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Düzenle") { sheet = .editMaterial(materialId) }
                    .foregroundStyle(Palette.accent)
            }
        }
        .appSheets($sheet)
    }

    private func summary(_ m: StockMaterial) -> some View {
        let b = store.engine.balance(ref)
        let status = store.engine.status(ref)
        return VStack(spacing: Metrics.gap) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Metrics.gap),
                                GridItem(.flexible(), spacing: Metrics.gap)], spacing: Metrics.gap) {
                BigStat(
                    title: "Mevcut Stok",
                    value: Units.formatQty(b.qty, baseUnit: m.baseUnit),
                    tone: status == .normal ? Palette.ink : (status == .azaliyor ? Palette.uyari : Palette.zarar),
                    caption: store.engine.ordersLeft(ref).map { "yaklaşık \($0) siparişlik" }
                )
                BigStat(title: "Stok Değeri", value: b.value.tl, tone: Palette.ink)
            }
            if status != .normal {
                Card(background: status == .azaliyor ? Palette.uyariYumusak : Palette.zararYumusak) {
                    Text(status.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(status == .azaliyor ? Palette.uyari : Palette.zarar)
                }
            }
        }
    }

    private func detail(_ m: StockMaterial) -> some View {
        let b = store.engine.balance(ref)
        let rate = store.engine.consumptionRate(ref)
        return Card {
            VStack(spacing: 9) {
                LabeledRow("Birim maliyet",
                           Money.roundHalfAwayFromZero(b.unitCost).tl + " / " + m.baseUnit.displayName)
                if m.baseUnit == .gram, b.unitCost > 0 {
                    LabeledRow("Kilogram maliyeti", Money.roundHalfAwayFromZero(b.unitCost * 1000).tl)
                }
                if rate.hasData {
                    LabeledRow("Sipariş başına kullanım",
                               Units.formatQty(rate.perOrder, baseUnit: m.baseUnit, forceBase: true))
                }
                if let min = m.minQty {
                    LabeledRow("Azalıyor eşiği", Units.formatQty(min, baseUnit: m.baseUnit))
                }
                if let crit = m.criticalQty {
                    LabeledRow("Kritik eşik", Units.formatQty(crit, baseUnit: m.baseUnit))
                }
                if m.minQty == nil && m.criticalQty == nil {
                    Text("Uyarı seviyesi tanımlı değil. Düzenle'den min. ve kritik stok girersen bitmek üzereyken haber verir.")
                        .font(.caption).foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Metrics.gap) {
            HStack(spacing: Metrics.gap) {
                BigButton("Stok Al", icon: "shippingbox") { sheet = .addPurchase(ref) }
                BigButton("Düzelt", icon: "slider.horizontal.3", tone: Palette.gider) { sheet = .adjustStock(ref) }
            }
            BigButton("Stok Sayımı Yap", icon: "checklist", tone: Palette.gider) { sheet = .countStock(ref) }
        }
    }
}
