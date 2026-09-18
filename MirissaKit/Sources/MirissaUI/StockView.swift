import SwiftUI
import MirissaCore

enum StockTab: String, CaseIterable, Identifiable {
    case urunler, malzemeler, sayim
    var id: String { rawValue }
    var label: String {
        switch self {
        case .urunler: return "Ürünler"
        case .malzemeler: return "Ambalaj & Sarf"
        case .sayim: return "Stok Sayımı"
        }
    }
}

struct StockView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: StockTab = .urunler
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    Picker("", selection: $tab) {
                        ForEach(StockTab.allCases) { t in Text(t.label).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.bottom, 2)

                    switch tab {
                    case .urunler: products
                    case .malzemeler: materials
                    case .sayim: counting
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 4)
            }
            .screenBackground()
            .navigationTitle("Ürün & Stok")
            .largeTitleMode()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .purchaseFlow } label: {
                        Image(systemName: "shippingbox")
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
            .appSheets($sheet)
        }
    }

    // MARK: Ürünler

    private var products: some View {
        VStack(spacing: Metrics.gap) {
            ForEach(store.state.activeProducts) { p in
                NavigationLink { ProductDetail(productId: p.id) } label: {
                    ItemCard(
                        name: p.name,
                        badge: p.isBundle ? "set" : nil,
                        qtyText: p.tracksOwnStock
                            ? Units.formatQty(store.engine.qty(.product(p.id)), baseUnit: .adet)
                            : "—",
                        subtitle: p.tracksOwnStock
                            ? "Maliyet: \(store.engine.cost(of: p.id).total.tl)"
                            : "Maliyet: \(store.engine.cost(of: p.id).total.tl) · stok bileşenlerden düşer",
                        status: p.tracksOwnStock ? store.engine.status(.product(p.id)) : .normal
                    )
                }
                .buttonStyle(.plain)
            }
            BigButton("Fiyat Güncelle", icon: "tag") { sheet = .priceUpdate(nil) }
            BigButton("Ürün Ekle", icon: "plus", tone: Palette.gider) { sheet = .addProduct }
        }
    }

    // MARK: Ambalaj & sarf

    private var materials: some View {
        VStack(spacing: Metrics.gap) {
            ForEach(store.state.activeMaterials) { m in
                let ref = ItemRef.material(m.id)
                NavigationLink { MaterialDetail(materialId: m.id) } label: {
                    ItemCard(
                        name: m.name,
                        badge: nil,
                        qtyText: Units.formatQty(store.engine.qty(ref), baseUnit: m.baseUnit),
                        subtitle: subtitle(for: ref),
                        status: store.engine.status(ref)
                    )
                }
                .buttonStyle(.plain)
            }
            BigButton("Stok Malzemesi Ekle", icon: "plus", tone: Palette.gider) { sheet = .addMaterial }
        }
    }

    private func subtitle(for ref: ItemRef) -> String {
        if let n = store.engine.ordersLeft(ref) { return "Yaklaşık \(n) siparişlik" }
        let ham = store.engine.unitCost(ref)
        guard ham > 0 else { return "Maliyet girilmedi" }
        // Gram / ml / cm başına maliyet kuruşun altında kalabilir: 1.000 birimlik fiyat gösterilir
        if ref.kind == .material, let m = store.state.material(ref.id),
           [UnitCode.gram, .ml, .cm].contains(m.baseUnit), ham < 50 {
            let buyuk: String = m.baseUnit == .gram ? "kg" : (m.baseUnit == .ml ? "litre" : "10 metre")
            return "Birim maliyet: \(Money.roundHalfAwayFromZero(ham * 1_000).tl) / \(buyuk)"
        }
        return "Birim maliyet: \(Money.roundHalfAwayFromZero(ham).tl)"
    }

    // MARK: Stok sayımı

    private var counting: some View {
        VStack(spacing: Metrics.gap) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Depodakini say, sisteme yaz")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Sistemdeki miktarla gerçek sayım arasındaki farkı hesaplar ve stoğu senin saydığın gerçek miktara sabitler.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            BigButton("Stok Sayımı Yap", icon: "checklist") { sheet = .countFlow }

            SectionTitle("Sisteme göre mevcut")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    let rows = countRows
                    ForEach(Array(rows.enumerated()), id: \.element.0.id) { i, row in
                        Button { sheet = .countStock(row.0) } label: {
                            HStack {
                                Text(row.1).font(.subheadline).foregroundStyle(Palette.ink)
                                Spacer(minLength: 8)
                                Text(row.2)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, Metrics.pad)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < rows.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }
        }
    }

    private var countRows: [(ItemRef, String, String)] {
        var out: [(ItemRef, String, String)] = []
        for p in store.state.activeProducts where p.tracksOwnStock {
            let r = ItemRef.product(p.id)
            out.append((r, p.name, Units.formatQty(store.engine.qty(r), baseUnit: .adet)))
        }
        for m in store.state.activeMaterials {
            let r = ItemRef.material(m.id)
            out.append((r, m.name, Units.formatQty(store.engine.qty(r), baseUnit: m.baseUnit)))
        }
        return out
    }
}

// MARK: - Kart

struct ItemCard: View {
    var name: String
    var badge: String?
    var qtyText: String
    var subtitle: String
    var status: StockStatus

    private var tone: Color {
        switch status {
        case .kritik, .negatif: return Palette.zarar
        case .azaliyor: return Palette.uyari
        case .normal: return Palette.ink
        }
    }

    var body: some View {
        Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        if let badge { Pill(badge) }
                    }
                    Text(subtitle).font(.caption).foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(qtyText)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(tone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if status != .normal { Pill(status.shortLabel, tone: tone, background: Palette.inset) }
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }
}

// MARK: - Hareket geçmişi

struct MovementHistory: View {
    var item: ItemRef
    var limit: Int = 12
    @Environment(AppStore.self) private var store
    @State private var sheet: AppSheet?
    @State private var silinecek: LedgerRow?
    @State private var hepsi = false

    private var tumRows: [LedgerRow] { store.engine.history(item) }
    private var rows: [LedgerRow] { hepsi ? tumRows : Array(tumRows.prefix(limit)) }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            SectionTitle("Hareketler")
            Card(padding: 0) {
                if rows.isEmpty {
                    EmptyHint(icon: "clock", title: "Henüz hareket yok",
                              message: "Stok satın aldığında veya satış girdiğinde burada görünür.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                            Button { ac(r) } label: {
                                row(r)
                                    .padding(.horizontal, Metrics.pad)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(r.movement.source == .opening)
                            if i < rows.count - 1 {
                                Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                            }
                        }
                        if tumRows.count > limit {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { hepsi.toggle() }
                            } label: {
                                Text(hepsi ? "Daha az göster" : "Tümünü göster (\(tumRows.count))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .appSheets($sheet)
        .confirmationDialog(
            silinecek.map { "\($0.label) kaydı silinsin mi?" } ?? "",
            isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let r = silinecek { store.deleteMovementSource(r) }
                silinecek = nil
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        }
    }

    /// Hareketin kaynağını düzenlemeye açar — her kayıt sonradan düzeltilebilmeli.
    private func ac(_ r: LedgerRow) {
        switch r.movement.source {
        case .purchase: sheet = .editPurchase(r.movement.sourceId)
        case .adjustment: sheet = .editAdjustment(r.movement.sourceId)
        case .sales: sheet = .editSale(r.movement.sourceId)
        case .count: silinecek = r
        case .opening: break
        }
    }

    private func row(_ r: LedgerRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.subheadline).foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(Dates.displayDateShort(r.date))
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(deltaText(r))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(r.delta < 0 ? Palette.zarar : Palette.kar)
                Text("kalan \(Units.formatQty(r.balanceAfter, baseUnit: store.state.itemBaseUnit(item)))")
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
            }
            if r.movement.source != .opening {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }

    private func deltaText(_ r: LedgerRow) -> String {
        let unit = store.state.itemBaseUnit(item)
        let prefix = r.delta > 0 ? "+" : (r.delta < 0 ? "-" : "")
        return prefix + Units.formatQty(abs(r.delta), baseUnit: unit)
    }
}
