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

                if store.state.settings.vatEnabled {
                    Section {
                        Toggle("Komisyon KDV hariç fiyattan", isOn: Binding(
                            get: { draft?.komisyonKdvHaric ?? false },
                            set: { draft?.komisyonKdvHaric = $0 }
                        ))
                    } header: {
                        Text("Komisyon neyin yüzdesi?")
                    } footer: {
                        Text("Trendyol komisyonu KDV hariç satış fiyatından hesaplar, faturada üstüne KDV ekler. "
                             + "Ürünün KDV'si ile kesinti KDV'si aynıysa (ikisi de %20) iki seçenek aynı sonucu verir; "
                             + "%10 veya %1 KDV'li ürün satıyorsan bunu açık tut. Değişiklik bugünden başlar, geçmiş aylar değişmez.")
                    }
                }

                Section {
                    Toggle("Bu kanal e-ticaret stopajı kesiyor", isOn: Binding(
                        get: { draft?.stopajAcik ?? false },
                        set: { acik in
                            if acik {
                                // Açınca (yeniden açınca da) bu aydan başlar: geçmiş aylar değişmez,
                                // kapalı kaldığı aylar kesilmiş sayılmaz
                                draft?.stopajBitis = nil
                                if (draft?.stopajPct ?? 0) <= 0 { draft?.stopajPct = 1 }
                                draft?.stopajBaslangic = Dates.monthStart(Dates.currentMonth())
                            } else if (draft?.stopajPct ?? 0) > 0 {
                                // Kapatmak geçmişi silmez: geçen aya kadar kesilmiş sayılır
                                draft?.stopajBitis = Dates.addMonths(Dates.currentMonth(), -1)
                            }
                        }
                    ))
                    if draft?.stopajAcik == true {
                        PercentField("Stopaj oranı", value: Binding(
                            get: { draft?.stopajPct ?? 0 },
                            set: { draft?.stopajPct = $0 }
                        ))
                        DateRow(label: "Kesilmeye başladığı gün", dateKey: Binding(
                            get: { draft?.stopajBaslangic ?? "2025-01-01" },
                            set: { draft?.stopajBaslangic = $0 }
                        ))
                    }
                } header: {
                    Text("E-ticaret stopajı")
                } footer: {
                    Text("1 Ocak 2025'ten beri pazaryerleri KDV hariç satış tutarının %1'ini keserek vergi dairesine yatırır "
                         + "(komisyon ve kargo düşülmeden). Bu bir gider değildir: hesabına yatan parayı azaltır ama "
                         + "yıllık gelir/kurumlar vergisinden ve geçici vergiden düşülür. Kârın değişmez; vergi karşılığın azalır. "
                         + "Kendi siten (Shopify) kesmez; bunu kapalı bırak. Oranı hesap özetinden kontrol et. "
                         + "Başlangıç günü bu ay gelir; geçmiş aylarda da kesildiyse (2025'ten beri) tarihi geriye al — "
                         + "o ayların hakediş farkını daha önce \"diğer kesinti\"ye yazdıysan geriye alma, iki kez sayılır.")
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
    /// Otomatik değerler yalnızca sipariş sayıları değişince yeniden hesaplanır (her tuşta motor kurulmasın)
    @State private var otomatik: ChannelMonthResult?

    private var auto: ChannelMonthResult { otomatik ?? otomatikHesapla() }

    private func otomatikHesapla() -> ChannelMonthResult {
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
        store.engine.kesintiBrut(net, channelId: channelId, month: month)
    }

    /// Bu ay için beklenen hakediş (formdaki kesintilerle, KDV dahil)
    private var beklenen: Kurus {
        let giderler = [commission ?? brut(auto.commission.amount), shipping ?? brut(auto.shipping.amount),
                        serviceFee ?? brut(auto.serviceFee.amount), other ?? brut(auto.otherDeduction.amount)]
        // Stopaj pazaryerince kesilir: hesaba yatan paradan düşer (kârdan değil)
        return live.netSalesIncVat - giderler.reduce(0, +) - live.stopaj
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
                if live.stopaj > 0 {
                    LabeledRow("Kesilen stopaj (vergiden düşülür)", live.stopaj.tl, tone: Palette.inkSoft)
                }
                if let p = payout {
                    let fark = beklenen - p
                    LabeledRow("Uygulamanın beklediği", beklenen.tl)
                    LabeledRow(fark > 0 ? "Beklenenden az yattı" : (fark < 0 ? "Beklenenden fazla yattı" : "Fark yok"),
                               abs(fark).tl, tone: abs(fark) > 10_000 ? Palette.uyari : Palette.inkSoft)
                    if abs(fark) > 10_000 {
                        Button("Farkı \"diğer kesinti\" olarak ekle") {
                            other = max((other ?? brut(auto.otherDeduction.amount))
                                        + store.engine.kesintiGirisi(brutFark: fark, channelId: channelId, month: month), 0)
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
        .onAppear {
            load()
            otomatik = otomatikHesapla()
        }
        .onChange(of: orderCount) { _, _ in otomatik = otomatikHesapla() }
        .onChange(of: bigOrderCount) { _, _ in otomatik = otomatikHesapla() }
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
        // Mevcut kayıttan başlanır: formda olmayan alanlar (içe aktarılan sipariş listesi gibi) korunur
        var cm = store.state.channelMonth(month: month, channelId: channelId)
            ?? ChannelMonth(month: month, channelId: channelId)
        cm.orderCount = orderCount.map { Int($0.rounded()) }
        cm.commissionActual = commission
        cm.shippingActual = shipping
        cm.serviceFeeActual = serviceFee
        cm.otherDeductionActual = other
        cm.adsActual = ads
        cm.note = note.isEmpty ? nil : note
        cm.bigOrderCount = bigOrderCount.map { Int($0.rounded()) }
        cm.payoutActual = payout
        store.upsertChannelMonth(cm)
    }
}
