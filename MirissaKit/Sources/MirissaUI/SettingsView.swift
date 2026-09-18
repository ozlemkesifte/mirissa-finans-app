import SwiftUI
import UniformTypeIdentifiers
import MirissaCore

enum ExportService {
    /// CSV dosyalarını geçici klasöre yazar ve paylaşılabilir adreslerini döner.
    static func write(_ files: [ExportFile]) -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirissaDisaAktarim-\(Dates.today())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return files.compactMap { f in
            let url = dir.appendingPathComponent(f.name)
            do {
                try f.contents.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch { return nil }
        }
    }

    static func writeBackup(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirissa-yedek-\(Dates.today()).json")
        do { try data.write(to: url); return url } catch { return nil }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sheet: AppSheet?
    @State private var csvURLs: [URL] = []
    @State private var backupURL: URL?
    @State private var showImporter = false
    @State private var showEraseConfirm = false
    @State private var showResetConfirm = false
    @State private var message: String?

    private var bounds: (first: MonthKey, last: MonthKey) { store.state.dataMonthBounds }

    private var faturalar: [URL] {
        store.state.attachmentNames.sorted().map(AttachmentStore.url).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                VergiAyari()
                HatirlatmaAyari()
                Section {
                    ForEach(store.state.channels.filter { !$0.archived }) { c in
                        Button { sheet = .channelWizard(c.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).foregroundStyle(Palette.ink)
                                    if !c.currentRates.eksikler.isEmpty {
                                        Text("Eksik: "
                                             + c.currentRates.eksikler.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(Palette.uyari)
                                    }
                                }
                                Spacer()
                                if c.currentRates.commissionPct + c.currentRates.paymentPct > 0 {
                                    Text(Money.formatPercent(
                                        c.currentRates.commissionPct + c.currentRates.paymentPct))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }
                    Button { sheet = .channelAdd } label: {
                        Label("Satış kanalı ekle", systemImage: "plus.circle")
                    }
                    .foregroundStyle(Palette.accent)
                } header: {
                    Text("Satış kanalları")
                } footer: {
                    Text("Bir kanala dokununca fiyatları ve kesintileri tek tek yeniden sorulur. "
                         + "Değişen komisyon bugünden geçerli olur; geçmiş aylar eski oranla kalır.")
                }

                Section {
                    Toggle("KDV takibi", isOn: Binding(
                        get: { store.state.settings.vatEnabled },
                        set: { store.setVatEnabled($0) }
                    ))
                    if store.state.settings.vatEnabled {
                        Picker("Varsayılan oran", selection: Binding(
                            get: { store.state.settings.defaultVatRate },
                            set: { store.setVatDefaults(rate: $0, included: store.state.settings.defaultVatIncluded) }
                        )) {
                            ForEach(VatRate.allCases) { r in Text(r.displayName).tag(r) }
                        }
                        Toggle("Tutarlar KDV dahil girilir", isOn: Binding(
                            get: { store.state.settings.defaultVatIncluded },
                            set: { store.setVatDefaults(rate: store.state.settings.defaultVatRate, included: $0) }
                        ))
                    }
                } header: {
                    Text("KDV")
                } footer: {
                    Text(store.state.settings.vatEnabled
                         ? "Satış, gider ve alım formlarında KDV satırı çıkar. Kâr hesabı her zaman KDV hariç tutarlarla yapılır."
                         : "Kapalıyken hiçbir ekranda KDV görünmez.")
                }

                ButunlukBolumu()

                Section {
                    Picker("Fiyat kontrolü", selection: Binding(
                        get: { store.state.settings.priceCheckInterval },
                        set: { store.setPriceCheckInterval($0) }
                    )) {
                        ForEach(PriceCheckInterval.allCases) { i in
                            Text(i.displayName).tag(i)
                        }
                    }
                    if let son = store.state.settings.lastPriceCheck {
                        LabeledRow("Son kontrol", Dates.displayDate(son))
                    }
                } header: {
                    Text("Fiyatları ne sıklıkla kontrol etmek istersin?")
                } footer: {
                    Text(store.state.settings.priceCheckInterval == .kapali
                         ? "Hatırlatma çıkmaz. Fiyatları istediğin zaman Ürün & Stok ekranından güncelleyebilirsin."
                         : "Süre gelince ana sayfada küçük bir kontrol kartı çıkar. Fiyatı değiştirmek eski fiyatı silmez.")
                }

                Section {
                    Button {
                        csvURLs = ExportService.write(
                            CSVExport.all(store.engine, from: bounds.first, to: bounds.last)
                        )
                    } label: {
                        Label("Excel / CSV dosyaları oluştur", systemImage: "tablecells")
                    }
                    if !csvURLs.isEmpty {
                        ShareLink(items: csvURLs) {
                            Label("\(csvURLs.count) dosyayı paylaş", systemImage: "square.and.arrow.up")
                        }
                        .foregroundStyle(Palette.accent)
                    }
                } header: {
                    Text("Verileri dışa aktar")
                } footer: {
                    Text("Satışlar, giderler, ürünler, stoklar, stok hareketleri ve aylık özet ayrı dosyalar olarak çıkar. Excel'de Türkçe ayarlarla doğru açılır.")
                }

                YedeklemeBolumu()

                Section {
                    NavigationLink {
                        DegisiklikGecmisi()
                    } label: {
                        Label("Değişiklik geçmişi (\(store.state.changeLog.count))", systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text("Hangi kaydın ne zaman eklendiği, değiştiği ya da silindiği. Son 1.000 değişiklik saklanır.")
                }

                if !faturalar.isEmpty {
                    Section {
                        ShareLink(items: faturalar) {
                            Label("Fatura eklerini ayrıca paylaş (\(faturalar.count))", systemImage: "paperclip")
                        }
                        .foregroundStyle(Palette.accent)
                    }
                }

                Section {
                    LabeledRow("Ürün sayısı", "\(store.state.products.count)")
                    LabeledRow("Malzeme sayısı", "\(store.state.materials.count)")
                    LabeledRow("Satış kaydı", "\(store.state.sales.count)")
                    LabeledRow("Gider kaydı", "\(store.state.expenses.count)")
                    LabeledRow("Stok hareketi", "\(store.engine.ledger.rows.count)")
                    LabeledRow("Toplam stok değeri", store.engine.totalStockValue.tl, strong: true)
                } header: {
                    Text("Özet")
                }

                Section {
                    Button {
                        store.restartSetup()
                        dismiss()
                    } label: {
                        Label("İlk kurulumu tekrar çalıştır", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("Ürünler, stoklar, sabit giderler ve kanal ayarlarını adım adım tekrar gözden geçirirsin. Satış ve gider kayıtların silinmez.")
                }

                Section {
                    Button(role: .destructive) { showEraseConfirm = true } label: {
                        Label("Satış, gider ve stok kayıtlarını sil", systemImage: "eraser")
                    }
                    Button(role: .destructive) { showResetConfirm = true } label: {
                        Label("Her şeyi baştan başlat", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Tehlikeli bölge")
                } footer: {
                    Text("Bu işlemler geri alınamaz. Önce yedek almanı öneririm.")
                }

                if let message {
                    Section { Text(message).foregroundStyle(Palette.accent) }
                }
            }
            .navigationTitle("Ayarlar")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }.font(.body.weight(.semibold))
                }
            }
            .appSheets($sheet)
            .confirmationDialog("Satış, gider, alım ve stok hareketlerinin tamamı silinecek. Ürünler ve malzemeler kalır.",
                                isPresented: $showEraseConfirm, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { store.eraseAllData(); message = "Kayıtlar silindi." }
                Button("Vazgeç", role: .cancel) {}
            }
            .confirmationDialog("Bütün veriler silinip uygulama ilk haline döndürülecek.",
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Baştan başlat", role: .destructive) { store.resetToSeed(); message = "Uygulama sıfırlandı." }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }
}
