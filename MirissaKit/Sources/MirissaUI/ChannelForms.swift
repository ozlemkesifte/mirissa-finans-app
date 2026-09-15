import SwiftUI
import MirissaCore

/// Kanalın oran ayarları — bir kez girilir, her ay otomatik hesaplanır.
struct ChannelForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var channelId: Id
    @State private var draft: Channel?
    @State private var showDelete = false

    var body: some View {
        FormShell(title: draft?.name ?? "Kanal", canSave: draft != nil, onSave: save) {
            if let d = Binding($draft) {
                Section {
                    TextField("Kanal adı", text: d.name)
                }

                Section {
                    PercentField("Komisyon oranı", value: d.commissionPct)
                    PercentField("Ödeme komisyonu", value: d.paymentPct)
                } header: {
                    Text("Yüzdeler")
                } footer: {
                    Text("Net satış üzerinden otomatik hesaplanır. Ay sonunda gerçek tutarı kanal ekranından elle girip bunun üzerine yazabilirsin.")
                }

                Section {
                    MoneyField("Sipariş başı kargo", value: d.shippingPerOrder)
                    MoneyField("Sipariş başı hizmet bedeli", value: d.serviceFeePerOrder)
                } header: {
                    Text("Sipariş başına")
                } footer: {
                    Text("Sipariş sayısını satış girerken yazmazsan sistem satılan adetten tahmin eder.")
                }

                Section {
                    MoneyField("Aylık platform ücreti", value: d.platformFeeMonthly)
                    MoneyField("Aylık diğer kesinti", value: d.otherDeductionMonthly)
                    PercentField("Diğer kesinti oranı", value: d.otherDeductionPct)
                } header: {
                    Text("Aylık sabitler")
                } footer: {
                    Text("Aylık ücretler kaç ürün satıldığından bağımsız olarak ayda bir kez düşülür.")
                }

                if store.state.settings.vatEnabled {
                    Section {
                        Picker("Kesinti KDV oranı", selection: Binding(
                            get: { draft?.resolvedFeeVatRate ?? .yirmi },
                            set: { draft?.feeVatRate = $0 }
                        )) {
                            ForEach(VatRate.allCases) { r in Text(r.displayName).tag(r) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Toggle("Kesintiler KDV dahil", isOn: Binding(
                            get: { draft?.resolvedFeesIncludeVat ?? true },
                            set: { draft?.feesIncludeVat = $0 }
                        ))
                    } header: {
                        Text("Kesintilerin KDV'si")
                    } footer: {
                        Text("Komisyon ve kargo faturasındaki KDV indirilecek KDV'ye eklenir; kâr hesabına yalnızca KDV hariç kısmı girer.")
                    }
                }

                if store.state.channels.count > 1 {
                    Section {
                        Button(role: .destructive) { showDelete = true } label: {
                            Label("Kanalı sil", systemImage: "trash")
                        }
                    } footer: {
                        Text("Kanalın satış kayıtları da silinir.")
                    }
                }
            }
        }
        .onAppear { if draft == nil { draft = store.state.channel(channelId) } }
        .confirmationDialog("Kanal ve satışları silinecek.", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { store.deleteChannel(channelId); dismiss() }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func save() { if let draft { store.updateChannel(draft) } }
}

/// Ay sonunda gerçek kesintileri girmek için.
struct ChannelMonthForm: View {
    @Environment(AppStore.self) private var store

    var channelId: Id
    var month: MonthKey

    @State private var orderCount: Double?
    @State private var commission: Kurus?
    @State private var shipping: Kurus?
    @State private var serviceFee: Kurus?
    @State private var other: Kurus?
    @State private var ads: Kurus?
    @State private var note = ""
    @State private var loaded = false

    private var auto: ChannelMonthResult {
        // Elle girilenler olmadan otomatik değerleri görmek için
        var s = store.state
        s.channelMonths.removeAll { $0.month == month && $0.channelId == channelId }
        return Engine(s).channelResult(channelId: channelId, month: month)
    }

    private var live: ChannelMonthResult {
        store.engine.channelResult(channelId: channelId, month: month)
    }

    var body: some View {
        FormShell(title: "Gerçek Kesintiler", onSave: save) {
            Section {
                LabeledRow("Dönem", Dates.displayMonth(month))
                LabeledRow("Net satış", live.netSales.tl, strong: true)
            }

            Section {
                OptionalQtyField("Sipariş sayısı", suffix: "sipariş", value: $orderCount)
            } footer: {
                Text(live.ordersIsEstimate
                     ? "Şu an satılan adetten tahmin ediliyor: \(live.orders) sipariş. Gerçek sayıyı girersen kargo daha doğru hesaplanır."
                     : "Kargo ve hizmet bedeli bu sayı üzerinden hesaplanır.")
            }

            Section {
                OptionalMoneyField("Komisyon", autoValue: auto.commission.amount, value: $commission)
                OptionalMoneyField("Kargo", autoValue: auto.shipping.amount, value: $shipping)
                OptionalMoneyField("Hizmet bedeli", autoValue: auto.serviceFee.amount, value: $serviceFee)
                OptionalMoneyField("Diğer kesinti", autoValue: auto.otherDeduction.amount, value: $other)
                OptionalMoneyField("Reklam", autoValue: auto.ads.amount, value: $ads)
            } header: {
                Text("Ay sonu gerçek tutarları")
            } footer: {
                Text("Boş bıraktığın satırlar ayarlardaki oranlardan otomatik hesaplanır. Doldurduğun satırlar otomatik hesabın yerine geçer.")
            }

            Section {
                LabeledRow("Ürün maliyeti", live.productCost.tl)
                LabeledRow("Ambalaj maliyeti", live.packagingCost.tl)
                LabeledRow("KANALDA KALAN", live.kanaldaKalan.tl,
                           tone: live.kanaldaKalan < 0 ? Palette.zarar : Palette.kar, strong: true)
            } header: {
                Text("Sistem hesaplıyor")
            }

            Section {
                TextField("Not (isteğe bağlı)", text: $note)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let cm = store.state.channelMonth(month: month, channelId: channelId) else { return }
        orderCount = cm.orderCount.map(Double.init)
        commission = cm.commissionActual
        shipping = cm.shippingActual
        serviceFee = cm.serviceFeeActual
        other = cm.otherDeductionActual
        ads = cm.adsActual
        note = cm.note ?? ""
    }

    private func save() {
        let existing = store.state.channelMonth(month: month, channelId: channelId)
        store.upsertChannelMonth(ChannelMonth(
            id: existing?.id ?? Ids.make(.channelMonth),
            month: month, channelId: channelId,
            orderCount: orderCount.map { Int($0.rounded()) },
            commissionActual: commission,
            shippingActual: shipping,
            serviceFeeActual: serviceFee,
            otherDeductionActual: other,
            adsActual: ads,
            note: note.isEmpty ? nil : note
        ))
    }
}
