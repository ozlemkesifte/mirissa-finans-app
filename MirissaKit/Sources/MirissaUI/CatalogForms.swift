import SwiftUI
import MirissaCore

// MARK: - Malzeme

struct MaterialForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editingId: Id?
    @State private var name = ""
    @State private var category: MaterialCategory = .ambalaj
    @State private var baseUnit: UnitCode = .adet
    @State private var minQty: Double?
    @State private var criticalQty: Double?
    @State private var tedarikGun: Double?
    @State private var minSiparis: Double?
    @State private var packSizes: [String: Double] = [:]
    @State private var showPack = false
    @State private var siparisBasi: Bool?
    @State private var loaded = false
    @State private var showDelete = false

    init() { self.editingId = nil }
    init(editing id: Id) { self.editingId = id }

    private let baseChoices: [(UnitCode, String)] = [
        (.adet, "Adet ile sayılır"),
        (.gram, "Ağırlık (gram / kg)"),
        (.ml, "Hacim (ml / litre)"),
        (.cm, "Uzunluk (cm / metre)"),
    ]

    private let containerUnits: [UnitCode] = [.paket, .kutu, .koli, .rulo]

    var body: some View {
        FormShell(
            title: editingId == nil ? "Stok Malzemesi Ekle" : "Malzemeyi Düzenle",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            onSave: save
        ) {
            Section {
                TextField("Malzeme adı", text: $name)
                Picker("Kategori", selection: $category) {
                    ForEach(MaterialCategory.allCases) { c in Text(c.displayName).tag(c) }
                }
            }

            Section {
                Picker("Nasıl ölçülüyor?", selection: $baseUnit) {
                    ForEach(baseChoices, id: \.0) { u, label in Text(label).tag(u) }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            } header: {
                Text("Ölçü birimi")
            } footer: {
                Text(baseUnit == .gram
                     ? "Kilogramla alıp gramla kullanabilirsin; sistem çevirir."
                     : "Bu malzeme \(baseUnit.displayName) cinsinden takip edilir.")
            }

            Section {
                Toggle("Paket / kutu / koli ile de alıyorum", isOn: $showPack.animation())
                if showPack {
                    ForEach(containerUnits) { u in
                        OptionalQtyField(
                            "1 \(u.displayName) kaç \(baseUnit.displayName)?",
                            value: Binding(
                                get: { packSizes[u.rawValue] },
                                set: { packSizes[u.rawValue] = $0 }
                            )
                        )
                    }
                }
            } footer: {
                if showPack { Text("Boş bıraktığın birimler seçeneklerde görünmez.") }
            }

            Section {
                Toggle("Sipariş başına kullanılıyor (koli gibi)", isOn: Binding(
                    get: { siparisBasi ?? StockMaterial.koliMi(name) },
                    set: { siparisBasi = $0 }
                ))
            } header: {
                Text("Nasıl harcanıyor?")
            } footer: {
                Text((siparisBasi ?? StockMaterial.koliMi(name))
                     ? "Gönderilen koli sayısına göre düşer: 1–2 ürünlük sipariş 1 adet, 3 ve üzeri ürünlü sipariş 2 adet."
                     : "Satılan her ürün için reçetedeki miktar kadar düşer (patpat, kutu, dolgu gibi).")
            }

            Section {
                OptionalQtyField("Stok azalıyor uyarısı", suffix: baseUnit.displayName, value: $minQty)
                OptionalQtyField("Kritik stok uyarısı", suffix: baseUnit.displayName, value: $criticalQty)
                OptionalQtyField("Tedarik süresi", suffix: "gün", value: $tedarikGun)
                OptionalQtyField("En az sipariş", suffix: baseUnit.displayName, value: $minSiparis)
            } header: {
                Text("Uyarı seviyeleri")
            } footer: {
                Text("Stok bu seviyelerin altına düştüğünde ana sayfada uyarı çıkar. Boş bırakırsan uyarı verilmez.")
            }

            if let id = editingId {
                Section {
                    Button {
                        store.setMaterialArchived(id, true)
                        dismiss()
                    } label: {
                        Label("Kullanmıyorum, arşivle", systemImage: "archivebox")
                    }
                } footer: {
                    Text("Malzeme listelerde görünmez; stok geçmişi ve raporlar kalır. Geri alınabilir.")
                }
                Section {
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Kalıcı olarak sil", systemImage: "trash")
                    }
                } footer: {
                    let used = store.state.products.filter { p in p.recipe.contains { $0.materialId == id } }
                    if !used.isEmpty {
                        Text("Bu malzeme şu ürünlerin reçetesinde kullanılıyor: \(used.map(\.name).joined(separator: ", ")). Silersen o satırlar da kaldırılır.")
                    }
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Malzeme, reçetelerdeki satırları ve stok geçmişiyle birlikte silinecek.",
                            isPresented: $showDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { store.deleteMaterial(editingId!); dismiss() }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = editingId, let m = store.state.material(id) else { return }
        name = m.name; category = m.category; baseUnit = m.baseUnit
        minQty = m.minQty; criticalQty = m.criticalQty
        tedarikGun = m.tedarikSuresiGun.map(Double.init); minSiparis = m.minSiparis
        packSizes = m.packSizesRaw
        showPack = !m.packSizesRaw.isEmpty
        siparisBasi = m.perOrder
    }

    private func save() {
        let clean = showPack ? packSizes.filter { $0.value > 0 } : [:]
        if let id = editingId, var m = store.state.material(id) {
            m.name = name; m.category = category; m.baseUnit = baseUnit
            m.minQty = minQty; m.criticalQty = criticalQty; m.packSizesRaw = clean
            m.perOrder = siparisBasi ?? m.perOrder
            m.tedarikSuresiGun = tedarikGun.map { Int($0.rounded()) }; m.minSiparis = minSiparis
            store.updateMaterial(m)
        } else {
            var yeni = StockMaterial(
                name: name, category: category, baseUnit: baseUnit,
                packSizesRaw: clean, minQty: minQty, criticalQty: criticalQty,
                perOrder: siparisBasi
            )
            yeni.tedarikSuresiGun = tedarikGun.map { Int($0.rounded()) }
            yeni.minSiparis = minSiparis
            store.addMaterial(yeni)
        }
    }
}

// MARK: - Ürün

struct ProductForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editingId: Id?
    @State private var name = ""
    @State private var isBundle = false
    @State private var components: [BundleComponent] = []
    @State private var costLines: [CostLine] = []
    @State private var recipe: [RecipeLine] = []

    @State private var minQty: Double?
    @State private var criticalQty: Double?
    @State private var tedarikGun: Double?
    @State private var minSiparis: Double?
    @State private var listeFiyat: Kurus = 0
    /// nil = ayarlardaki varsayılan KDV
    @State private var kdvOrani: VatRate?
    @State private var kanalFiyat: [Id: Kurus] = [:]
    @State private var loaded = false
    @State private var showDelete = false

    init() { self.editingId = nil }
    init(editing id: Id) { self.editingId = id }

    private var otherProducts: [Product] {
        store.state.activeProducts.filter { $0.id != editingId && !$0.isBundle }
    }

    var body: some View {
        FormShell(
            title: editingId == nil ? "Ürün Ekle" : "Ürünü Düzenle",
            canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            issues: { Validation.product(taslak, state: store.state) },
            onSave: save
        ) {
            Section {
                TextField("Ürün adı", text: $name)
                Toggle("Bu bir set", isOn: $isBundle.animation())
            } footer: {
                Text(isBundle
                     ? "Set satıldığında içindeki ürünler ve setin kendi paketleme malzemeleri stoktan düşer."
                     : "Tek ürün. Kendi stoğu takip edilir.")
            }

            if isBundle {
                Section("Setin içindekiler") {
                    ForEach($components, id: \.productId) { $c in
                        HStack {
                            Text(store.state.product(c.productId)?.name ?? "—")
                            Spacer()
                            QtyField("", suffix: "adet", value: $c.qty).frame(maxWidth: 150)
                        }
                    }
                    .onDelete { components.remove(atOffsets: $0) }

                    Menu("Ürün ekle") {
                        ForEach(otherProducts.filter { p in !components.contains { $0.productId == p.id } }) { p in
                            Button(p.name) { components.append(BundleComponent(productId: p.id, qty: 1)) }
                        }
                    }
                    .foregroundStyle(Palette.accent)
                }
            }

            Section {
                MoneyField("Etiket fiyatı", value: $listeFiyat)
                ForEach(store.state.activeChannels) { c in
                    MoneyField("\(c.name) fiyatı", value: Binding(
                        get: { kanalFiyat[c.id] ?? 0 },
                        set: { kanalFiyat[c.id] = $0 > 0 ? $0 : nil }
                    ))
                }
            } header: {
                Text("Satış fiyatları")
            } footer: {
                Text("Kâr her zaman girdiğin gerçek satış tutarından hesaplanır. "
                     + "Buradaki fiyat satış girişinde tutarı önden doldurur. "
                     + "Boş bıraktığın kanalda etiket fiyatı geçerli olur.")
            }

            if store.state.settings.vatEnabled {
                Section {
                    Picker("Satış KDV oranı", selection: Binding(
                        get: { kdvOrani ?? store.state.settings.defaultVatRate },
                        set: { kdvOrani = $0 == store.state.settings.defaultVatRate ? nil : $0 }
                    )) {
                        ForEach(VatRate.allCases) { r in Text(r.displayName).tag(r) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Bu ürünün KDV'si")
                } footer: {
                    Text("Fiyatın içindeki KDV devlete gider; kâr KDV hariç tutardan hesaplanır. "
                         + "Kozmetikte genellikle %20'dir; farklıysa muhasebecine sorup seç. "
                         + "Yeni satış girişleri bu oranla açılır; geçmiş satışlar kendi oranıyla kalır.")
                }
            }

            Section {
                ForEach($costLines) { $line in
                    HStack {
                        TextField("Kalem adı", text: $line.label)
                        Spacer(minLength: 8)
                        MoneyField("", value: $line.amount).frame(maxWidth: 190)
                    }
                }
                .onDelete { costLines.remove(atOffsets: $0) }

                Button {
                    costLines.append(CostLine(label: "", amount: 0))
                } label: {
                    Label("Maliyet kalemi ekle", systemImage: "plus.circle")
                }
                .foregroundStyle(Palette.accent)

                LabeledRow("Kalemler toplamı", costLines.reduce(0) { $0 + $1.amount }.tl, strong: true)
            } header: {
                Text(isBundle ? "Setin kendi maliyet kalemleri" : "Ürün maliyet kalemleri")
            } footer: {
                Text("Üretim, fason, hammadde gibi kalemler. Kutu ve etiket gibi paketleme malzemelerini aşağıdaki reçeteye yaz — böylece stoktan da düşer.")
            }

            Section {
                ForEach($recipe) { $line in
                    RecipeLineRow(line: $line)
                }
                .onDelete { recipe.remove(atOffsets: $0) }

                Menu {
                    ForEach(store.state.activeMaterials) { m in
                        Button(m.name) { receteyeEkle(m) }
                    }
                } label: {
                    Label("Malzeme ekle", systemImage: "plus.circle")
                }
                .foregroundStyle(Palette.accent)
            } header: {
                Text("Paketleme reçetesi")
            } footer: {
                Text("1 adet satıldığında kullanılan malzemeler. Her malzemeye dokunup iki soruyu cevapla: stoktan düşsün mü, maliyeti üretim fiyatında zaten var mı?")
            }

            Section("Uyarı seviyeleri") {
                OptionalQtyField("Stok azalıyor uyarısı", suffix: "adet", value: $minQty)
                OptionalQtyField("Kritik stok uyarısı", suffix: "adet", value: $criticalQty)
                OptionalQtyField("Üretim / tedarik süresi", suffix: "gün", value: $tedarikGun)
                OptionalQtyField("En az üretim adedi", suffix: "adet", value: $minSiparis)
            }

            if let id = editingId {
                Section {
                    Button {
                        store.setProductArchived(id, true)
                        dismiss()
                    } label: {
                        Label("Satıştan kaldır", systemImage: "archivebox")
                    }
                } footer: {
                    Text("Ürün listelerde, hedeflerde ve yeni satış girişinde görünmez. Geçmiş satışları, "
                         + "stok geçmişi ve raporlar olduğu gibi kalır. Ürün & Stok → Arşiv'den geri alabilirsin.")
                }
                Section {
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Kalıcı olarak sil", systemImage: "trash")
                    }
                } footer: {
                    Text("Ürünün bütün satış kayıtları ve stok geçmişi de silinir; geçmiş raporlar değişir. "
                         + "Genelde \"Satıştan kaldır\" daha doğrudur.")
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Ürün, bütün satışları ve stok geçmişiyle birlikte kalıcı olarak silinecek. Geçmiş ayların kârı değişecek.",
                            isPresented: $showDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { store.deleteProduct(editingId!); dismiss() }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = editingId, let p = store.state.product(id) else { return }
        name = p.name; isBundle = p.isBundle; components = p.components
        let bugun = Dates.today()
        listeFiyat = p.price(on: bugun) ?? 0
        kanalFiyat = Dictionary(uniqueKeysWithValues: store.state.activeChannels.compactMap { c in
            p.price(for: c.id, on: bugun).map { (c.id, $0) }
        })
        costLines = p.costLines(on: nil); recipe = p.recipe
        minQty = p.minQty; criticalQty = p.criticalQty
        tedarikGun = p.tedarikSuresiGun.map(Double.init); minSiparis = p.minSiparis
        kdvOrani = p.kdvOrani
    }

    private var taslak: Product {
        Product(
            id: editingId ?? "taslak", name: name, isBundle: isBundle,
            components: isBundle ? components : [],
            costLines: costLines, recipe: recipe,
            minQty: minQty, criticalQty: criticalQty
        )
    }

    /// Yeni üründe girilen fiyatlar "baştan beri geçerli" sayılır.
    private func yeniFiyatGecmisi() -> [PricePoint]? {
        var out: [PricePoint] = []
        if listeFiyat > 0 {
            out.append(PricePoint(amount: listeFiyat, from: "1970-01-01"))
        }
        for (kanal, tutar) in kanalFiyat.sorted(by: { $0.key < $1.key }) where tutar > 0 {
            out.append(PricePoint(channelId: kanal, amount: tutar, from: "1970-01-01"))
        }
        return out.isEmpty ? nil : out
    }

    private func receteyeEkle(_ m: StockMaterial) {
        recipe.append(RecipeLine(materialId: m.id, qty: 1, unit: m.baseUnit))
    }

    private func save() {
        let cleanCost = costLines.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty || $0.amount != 0 }
        if let id = editingId, var p = store.state.product(id) {
            p.name = name; p.isBundle = isBundle
            p.components = isBundle ? components : []
            p.applyCostLines(cleanCost, today: Dates.today())
            p.recipe = recipe
            p.minQty = minQty; p.criticalQty = criticalQty
            p.tedarikSuresiGun = tedarikGun.map { Int($0.rounded()) }; p.minSiparis = minSiparis
            p.kdvOrani = kdvOrani
            let bugun = Dates.today()
            p.applyCurrentPrice(listeFiyat, channelId: nil, today: bugun)
            for (kanal, tutar) in kanalFiyat.sorted(by: { $0.key < $1.key }) {
                p.applyCurrentPrice(tutar, channelId: kanal, today: bugun)
            }
            store.updateProduct(p)
        } else {
            var yeni = Product(
                name: name, isBundle: isBundle,
                components: isBundle ? components : [],
                costLines: cleanCost, recipe: recipe,
                minQty: minQty, criticalQty: criticalQty,
                priceHistory: yeniFiyatGecmisi()
            )
            yeni.tedarikSuresiGun = tedarikGun.map { Int($0.rounded()) }
            yeni.minSiparis = minSiparis
            yeni.kdvOrani = kdvOrani
            store.addProduct(yeni)
        }
    }
}

private struct RecipeLineRow: View {
    @Binding var line: RecipeLine
    @Environment(AppStore.self) private var store

    private var material: StockMaterial? { store.state.material(line.materialId) }
    private var ad: String { material?.name ?? "Silinmiş malzeme" }

    /// Bu satırın bir satışta ne yapacağını düz Türkçe anlatır
    private var sonuc: String {
        var parcalar: [String] = []
        if line.resolvedConsumesStock, let m = material {
            let base = Units.toBaseOrNil(qty: line.qty, unit: line.unit,
                                         baseUnit: m.baseUnit, packSizes: m.packSizes) ?? 0
            parcalar.append("\(Units.formatQty(base, baseUnit: m.baseUnit)) stoktan düşer")
        } else {
            parcalar.append("stoktan düşmez")
        }
        if line.resolvedAddsCost, let m = material {
            let base = Units.toBaseOrNil(qty: line.qty, unit: line.unit,
                                         baseUnit: m.baseUnit, packSizes: m.packSizes) ?? 0
            let tutar = Money.roundHalfAwayFromZero(
                base * store.engine.unitCost(.material(m.id)))
            parcalar.append(tutar > 0
                            ? "ürün maliyetine \(Money.format(tutar)) ekler"
                            : "ürün maliyetine mevcut birim maliyetiyle eklenir")
        } else {
            parcalar.append("ürün maliyetine eklenmez")
        }
        return "Her satışta: " + parcalar.joined(separator: " · ")
    }

    var body: some View {
        DisclosureGroup {
            HStack {
                Text("Miktar").foregroundStyle(Palette.inkSoft)
                Spacer(minLength: 8)
                QtyField("", value: $line.qty).frame(maxWidth: 90)
                if let m = material {
                    Picker("", selection: $line.unit) {
                        ForEach(Units.allowedUnits(baseUnit: m.baseUnit, packSizes: m.packSizes)) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 96)
                }
            }
            Text("Bu malzeme stoktan düşsün mü?")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: Binding(
                get: { line.resolvedConsumesStock },
                set: { line.consumesStock = $0 }
            )) {
                Text("Evet").tag(true)
                Text("Hayır").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Bu malzemeyi ayrı stok olarak takip ediyorsan ve her satışta kullanılıyorsa Evet seç.")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            Text("Maliyeti ürünün üretim fiyatında zaten var mı?")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: Binding(
                get: { line.costAlreadyInProductionPrice },
                set: { line.addsCost = !$0 }
            )) {
                Text("Evet").tag(true)
                Text("Hayır").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("\(ad) parasını üreticiye ödediğin ürün fiyatının içinde zaten ödüyorsan Evet seç. Böylece ikinci kez maliyete eklenmez.")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Palette.separator)
            Text(sonuc)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            HStack(spacing: 6) {
                Text(ad).foregroundStyle(Palette.ink).lineLimit(1)
                if let not = line.noteLabel { Pill(not) }
                Spacer(minLength: 8)
                Text("\(NumberInput.display(line.qty).isEmpty ? "0" : NumberInput.display(line.qty)) \(line.unit.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }
}
