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

    var body: some View {
        NavigationStack {
            Form {
                Section("Satış kanalları") {
                    ForEach(store.state.channels) { c in
                        Button { sheet = .channelSetup(c.id) } label: {
                            HStack {
                                Text(c.name).foregroundStyle(Palette.ink)
                                Spacer()
                                if c.commissionPct > 0 || c.paymentPct > 0 {
                                    Text(Money.formatPercent(c.commissionPct + c.paymentPct))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }
                    Button {
                        let c = Channel(id: Ids.make(.channelMonth), name: "Yeni kanal")
                        store.addChannel(c)
                        sheet = .channelSetup(c.id)
                    } label: {
                        Label("Kanal ekle", systemImage: "plus.circle")
                    }
                    .foregroundStyle(Palette.accent)
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

                Section {
                    Button {
                        backupURL = (try? store.exportJSON()).flatMap(ExportService.writeBackup)
                    } label: {
                        Label("Yedek dosyası oluştur", systemImage: "arrow.down.doc")
                    }
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Yedeği paylaş / kaydet", systemImage: "square.and.arrow.up")
                        }
                        .foregroundStyle(Palette.accent)
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Yedekten geri yükle", systemImage: "arrow.up.doc")
                    }
                } header: {
                    Text("Yedekleme")
                } footer: {
                    Text("Yedek dosyası bütün verilerini içerir. iCloud Drive'a veya kendine e-posta ile gönderip saklayabilirsin.")
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
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case let .success(url):
                    let needsStop = url.startAccessingSecurityScopedResource()
                    defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try store.importJSON(try Data(contentsOf: url))
                        message = "Yedek geri yüklendi."
                    } catch {
                        message = "Yedek okunamadı: \(error)"
                    }
                case let .failure(e):
                    message = "Dosya seçilemedi: \(e.localizedDescription)"
                }
            }
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
