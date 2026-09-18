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
        FormShell(title: draft?.name ?? "Kanal", canSave: draft != nil,
                  issues: { draft.map { Validation.channel($0) } ?? [] },
                  onSave: save) {
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
                            get: { draft?.resolvedFeeVatRate ?? .yok },
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
                        Text("Komisyon ve kargo faturasındaki KDV indirilecek KDV'ye eklenir; kâr hesabına yalnızca KDV hariç kısmı girer. Oran bu kanala özeldir, istediğin zaman değiştirebilirsin.")
                    }
                }

                if store.state.channels.count > 1 {
                    Section {
                        Button {
                            store.setChannelArchived(channelId, true)
                            dismiss()
                        } label: {
                            Label("Kanalı kapat (arşivle)", systemImage: "archivebox")
                        }
                    } footer: {
                        Text("Kanal yeni girişlerde ve hedeflerde görünmez; geçmiş satışları ve raporlar kalır. "
                             + "Ürün & Stok → Arşiv'den geri açabilirsin.")
                    }
                    Section {
                        Button(role: .destructive) { showDelete = true } label: {
                            Label("Kalıcı olarak sil", systemImage: "trash")
                        }
                    } footer: {
                        Text("Kanalın bütün satış kayıtları da silinir; geçmiş raporlar değişir.")
                    }
                }
            }
        }
        .onAppear { if draft == nil { draft = store.state.channel(channelId) } }
        .confirmationDialog("Kanal ve bütün satışları kalıcı olarak silinecek. Geçmiş ayların kârı değişecek.", isPresented: $showDelete, titleVisibility: .visible) {
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
    @State private var bigOrderCount: Double?
    @State private var commission: Kurus?
    @State private var shipping: Kurus?
    @State private var serviceFee: Kurus?
    @State private var other: Kurus?
    @State private var ads: Kurus?
    @State private var payout: Kurus?
    @State private var note = ""
    @State private var loaded = false

    private var auto: ChannelMonthResult {
        // Elle girilen TUTARLAR olmadan otomatik değerler; sipariş sayısı korunur,
        // yoksa kargo ve koli önerisi adetten tahmin edilir ve yanlış çıkar.
        var s = store.state
        let mevcut = s.channelMonth(month: month, channelId: channelId)
        s.channelMonths.removeAll { $0.month == month && $0.channelId == channelId }
        let siparis = orderCount.map { Int($0.rounded()) } ?? mevcut?.orderCount
        let buyuk = bigOrderCount.map { Int($0.rounded()) } ?? mevcut?.bigOrderCount
        if siparis != nil || buyuk != nil {
            s.channelMonths.append(ChannelMonth(id: mevcut?.id ?? "auto", month: month,
                                                channelId: channelId, orderCount: siparis,
                                                bigOrderCount: buyuk))
        }
        return Engine(s).channelResult(channelId: channelId, month: month)
    }

    /// Kesinti alanlarına faturadaki tutar yazılır: kanal ayarı "KDV dahil" ise
    /// otomatik öneri de KDV dahil gösterilir, yoksa kullanıcı KDV hariç sanır.
    private func brut(_ net: Kurus) -> Kurus {
        store.engine.kesintiBrut(net, channelId: channelId)
    }

    /// Bu ay için beklenen hakediş (formdaki kesintilerle, KDV dahil)
    private var beklenen: Kurus {
        let giderler = [commission ?? brut(auto.commission.amount), shipping ?? brut(auto.shipping.amount),
                        serviceFee ?? brut(auto.serviceFee.amount), other ?? brut(auto.otherDeduction.amount)]
        return live.netSalesIncVat - giderler.reduce(0, +)
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
                OptionalQtyField("3+ ürünlü sipariş (2 koli)", suffix: "sipariş", value: $bigOrderCount)
            } footer: {
                Text((live.ordersIsEstimate
                     ? "Şu an satılan adetten tahmin ediliyor: \(live.orders) sipariş. Gerçek sayıyı girersen kargo daha doğru hesaplanır."
                     : "Kargo ve hizmet bedeli bu sayı üzerinden hesaplanır.")
                     + " Koli: 1–2 ürünlük sipariş 1, 3 ve üzeri 2 koli. "
                     + (live.koliSayisi > 0
                        ? "Bu ay \(Int(live.koliSayisi)) koli sayıldı\(live.koliTahmini ? " (tahmini)" : "")."
                        : ""))
            }

            Section {
                OptionalMoneyField("Komisyon", autoValue: brut(auto.commission.amount), value: $commission)
                OptionalMoneyField("Kargo", autoValue: brut(auto.shipping.amount), value: $shipping)
                OptionalMoneyField("Hizmet bedeli", autoValue: brut(auto.serviceFee.amount), value: $serviceFee)
                OptionalMoneyField("Diğer kesinti", autoValue: brut(auto.otherDeduction.amount), value: $other)
                OptionalMoneyField("Reklam (KDV hariç)", autoValue: auto.ads.amount, value: $ads)
            } header: {
                Text("Ay sonu gerçek tutarları")
            } footer: {
                Text("Boş bıraktığın satırlar ayarlardaki oranlardan otomatik hesaplanır. "
                     + "Doldurduğun satırlar otomatik hesabın yerine geçer. "
                     + "Kesintilere hakediş raporundaki tutarı yaz"
                     + (brut(100) != 100 ? " (KDV dahil)" : "") + "; reklamı KDV hariç yaz.")
            }

            Section {
                OptionalMoneyField("Hesabına yatan hakediş", autoValue: beklenen, value: $payout)
                if let p = payout {
                    let fark = beklenen - p
                    LabeledRow("Uygulamanın beklediği", beklenen.tl)
                    LabeledRow(fark > 0 ? "Beklenenden az yattı" : (fark < 0 ? "Beklenenden fazla yattı" : "Fark yok"),
                               abs(fark).tl, tone: abs(fark) > 10_000 ? Palette.uyari : Palette.inkSoft)
                    if abs(fark) > 10_000 {
                        Button("Farkı \"diğer kesinti\" olarak ekle") {
                            other = max((other ?? brut(auto.otherDeduction.amount)) + fark, 0)
                        }
                    }
                }
            } header: {
                Text("Hakediş kontrolü")
            } footer: {
                Text("Pazaryerinin bu ayın satışları için yatırdığı toplamı yaz. Az yattıysa kesintiler tahminden "
                     + "fazladır (kampanya katkısı, desi farkı, iade kargosu, ceza). Farkı eklersen kâr gerçeğe yaklaşır; "
                     + "eklemek senin kararın, uygulama kendiliğinden değiştirmez.")
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
        bigOrderCount = cm.bigOrderCount.map(Double.init)
        commission = cm.commissionActual
        shipping = cm.shippingActual
        serviceFee = cm.serviceFeeActual
        other = cm.otherDeductionActual
        ads = cm.adsActual
        payout = cm.payoutActual
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
            note: note.isEmpty ? nil : note,
            bigOrderCount: bigOrderCount.map { Int($0.rounded()) },
            payoutActual: payout
        ))
    }
}
