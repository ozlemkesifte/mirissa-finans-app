import SwiftUI
import MirissaCore

struct SaleForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editingId: Id?
    @State private var month: MonthKey
    @State private var channelId: Id = ChannelIds.trendyol
    @State private var productId: Id = ""
    @State private var qty: Double = 0
    @State private var gross: Kurus = 0
    @State private var discount: Kurus = 0
    @State private var returnsAmount: Kurus = 0
    @State private var returnsQty: Double = 0
    @State private var restock = true
    @State private var showReturns = false
    @State private var vatRate: VatRate = .yirmi
    @State private var vatIncluded = true
    @State private var loaded = false

    init(month: MonthKey) {
        self.editingId = nil
        self._month = State(initialValue: month)
    }

    init(editing id: Id) {
        self.editingId = id
        self._month = State(initialValue: Dates.currentMonth())
    }

    private var net: Kurus { gross - discount - returnsAmount }
    /// Kâr hesabına giren tutar
    private var netExVat: Kurus {
        store.state.settings.vatEnabled
            ? Vat.net(net, rate: vatRate, included: vatIncluded) : net
    }
    private var canSave: Bool { !productId.isEmpty && (qty > 0 || gross > 0) }

    var body: some View {
        FormShell(
            title: editingId == nil ? "Aylık Satış Ekle" : "Satışı Düzenle",
            canSave: canSave,
            issues: { Validation.sale(taslak, state: store.state, editingId: editingId) },
            summary: { Validation.saleSummary(taslak, state: store.state) },
            onSave: save
        ) {
            Section {
                MonthRow(month: $month)
                Picker("Satış kanalı", selection: $channelId) {
                    ForEach(store.state.activeChannels) { c in Text(c.name).tag(c.id) }
                }
                Picker("Ürün", selection: $productId) {
                    Text("Seç").tag("")
                    ForEach(store.state.activeProducts) { p in Text(p.name).tag(p.id) }
                }
            }

            Section {
                QtyField("Satılan adet", suffix: "adet", value: $qty)
                MoneyField("Toplam satış", value: $gross)
            } footer: {
                Text("Ay sonunda kanalın toplam rakamını gir — her siparişi tek tek girmene gerek yok.")
            }

            Section {
                DisclosureGroup("İndirim, iade ve KDV") {
                    MoneyField("İndirim", value: $discount)
                    Toggle("İade var", isOn: $showReturns.animation())
                    if showReturns {
                        MoneyField("İade tutarı", value: $returnsAmount)
                        QtyField("İade adedi", suffix: "adet", value: $returnsQty)
                        Toggle("İade edilen ürün stoğa geri girsin", isOn: $restock)
                    }
                    VatSection(rate: $vatRate, included: $vatIncluded, amount: net,
                               label: "Satış tutarı", asSection: false)
                }
            } footer: {
                Text("Çoğu zaman bunlara dokunmana gerek yok.")
            }

            Section {
                LabeledRow("Gerçek satış", netExVat.tl, tone: Palette.accent, strong: true)
                if !productId.isEmpty, qty > 0 {
                    let b = store.engine.cost(of: productId, asOf: Dates.monthEnd(month))
                    LabeledRow("Ürün maliyeti", Money.roundHalfAwayFromZero(Double(b.intrinsic) * (qty - returnsQty)).tl)
                    LabeledRow("Ambalaj maliyeti", Money.roundHalfAwayFromZero(Double(b.packaging) * qty).tl)
                }
            } header: {
                Text("Sistem hesaplıyor")
            } footer: {
                Text("Kaydettiğinde ürün ve paketleme malzemeleri stoktan otomatik düşer.")
            }

            if let id = editingId {
                Section {
                    Button(role: .destructive) {
                        store.deleteSale(id)
                        dismiss()
                    } label: {
                        Label("Satışı sil", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = editingId, let s = store.state.sales.first(where: { $0.id == id }) {
            month = s.month; channelId = s.channelId; productId = s.productId
            qty = s.qty; gross = s.grossSales; discount = s.discount
            returnsAmount = s.returnsAmount; returnsQty = s.returnsQty; restock = s.returnsRestock
            showReturns = s.returnsAmount != 0 || s.returnsQty != 0
            vatRate = s.resolvedVatRate
            vatIncluded = s.resolvedVatIncluded
        } else {
            vatRate = store.state.settings.vatEnabled ? store.state.settings.defaultVatRate : .yok
            vatIncluded = store.state.settings.defaultVatIncluded
            productId = store.state.activeProducts.first?.id ?? ""
            channelId = store.state.activeChannels.first?.id ?? ChannelIds.trendyol
        }
    }

    /// Doğrulama ve özet için o anki form değerleri
    private var taslak: SalesEntry {
        SalesEntry(
            id: editingId ?? "taslak",
            month: month, channelId: channelId, productId: productId,
            qty: qty, grossSales: gross, discount: discount,
            returnsAmount: showReturns ? returnsAmount : 0,
            returnsQty: showReturns ? returnsQty : 0,
            returnsRestock: restock,
            vatRate: store.state.settings.vatEnabled ? vatRate : nil,
            vatIncluded: store.state.settings.vatEnabled ? vatIncluded : nil
        )
    }

    private func save() {
        var entry = SalesEntry(
            id: editingId ?? Ids.make(.sale),
            month: month, channelId: channelId, productId: productId,
            qty: qty, grossSales: gross, discount: discount,
            returnsAmount: showReturns ? returnsAmount : 0,
            returnsQty: showReturns ? returnsQty : 0,
            returnsRestock: restock,
            vatRate: store.state.settings.vatEnabled ? vatRate : nil,
            vatIncluded: store.state.settings.vatEnabled ? vatIncluded : nil
        )
        if editingId != nil {
            store.updateSale(entry)
        } else {
            entry.id = Ids.make(.sale)
            store.addSale(entry)
        }
    }
}
