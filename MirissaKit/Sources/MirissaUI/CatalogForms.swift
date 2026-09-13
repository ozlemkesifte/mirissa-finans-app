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
    @State private var packSizes: [String: Double] = [:]
    @State private var showPack = false
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
                OptionalQtyField("Stok azalıyor uyarısı", suffix: baseUnit.displayName, value: $minQty)
                OptionalQtyField("Kritik stok uyarısı", suffix: baseUnit.displayName, value: $criticalQty)
            } header: {
                Text("Uyarı seviyeleri")
            } footer: {
                Text("Stok bu seviyelerin altına düştüğünde ana sayfada uyarı çıkar. Boş bırakırsan uyarı verilmez.")
            }

            if let id = editingId {
                Section {
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Malzemeyi sil", systemImage: "trash")
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
        packSizes = m.packSizesRaw
        showPack = !m.packSizesRaw.isEmpty
    }

    private func save() {
        let clean = showPack ? packSizes.filter { $0.value > 0 } : [:]
        if let id = editingId, var m = store.state.material(id) {
            m.name = name; m.category = category; m.baseUnit = baseUnit
            m.minQty = minQty; m.criticalQty = criticalQty; m.packSizesRaw = clean
            store.updateMaterial(m)
        } else {
            store.addMaterial(StockMaterial(
                name: name, category: category, baseUnit: baseUnit,
                packSizesRaw: clean, minQty: minQty, criticalQty: criticalQty
            ))
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
                        Button(m.name) {
                            recipe.append(RecipeLine(materialId: m.id, qty: 1, unit: m.baseUnit))
                        }
                    }
                } label: {
                    Label("Malzeme ekle", systemImage: "plus.circle")
                }
                .foregroundStyle(Palette.accent)
            } header: {
                Text("Paketleme reçetesi")
            } footer: {
                Text("1 adet satıldığında kullanılan malzemeler. Satış girdiğinde bunlar otomatik olarak stoktan düşülür.")
            }

            Section("Uyarı seviyeleri") {
                OptionalQtyField("Stok azalıyor uyarısı", suffix: "adet", value: $minQty)
                OptionalQtyField("Kritik stok uyarısı", suffix: "adet", value: $criticalQty)
            }

            if editingId != nil {
                Section {
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Ürünü sil", systemImage: "trash")
                    }
                } footer: {
                    Text("Ürünün satış kayıtları ve stok geçmişi de silinir.")
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Ürün, satışları ve stok geçmişiyle birlikte silinecek.",
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
        costLines = p.costLines; recipe = p.recipe
        minQty = p.minQty; criticalQty = p.criticalQty
    }

    private func save() {
        let cleanCost = costLines.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty || $0.amount != 0 }
        if let id = editingId, var p = store.state.product(id) {
            p.name = name; p.isBundle = isBundle
            p.components = isBundle ? components : []
            p.costLines = cleanCost; p.recipe = recipe
            p.minQty = minQty; p.criticalQty = criticalQty
            store.updateProduct(p)
        } else {
            store.addProduct(Product(
                name: name, isBundle: isBundle,
                components: isBundle ? components : [],
                costLines: cleanCost, recipe: recipe,
                minQty: minQty, criticalQty: criticalQty
            ))
        }
    }
}

private struct RecipeLineRow: View {
    @Binding var line: RecipeLine
    @Environment(AppStore.self) private var store

    private var material: StockMaterial? { store.state.material(line.materialId) }

    var body: some View {
        HStack {
            Text(material?.name ?? "Silinmiş malzeme")
                .lineLimit(1)
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
    }
}
