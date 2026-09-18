import SwiftUI
import UniformTypeIdentifiers
import MirissaCore

/// Yedek dosyası: bütün kayıtlar + fatura ekleri
struct YedekBelgesi: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var veri: Data
    init(veri: Data) { self.veri = veri }
    init(configuration: ReadConfiguration) throws {
        veri = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: veri)
    }
}

/// Ana sayfa: telefon dışına yedek alınmadıysa açıkça söyler
struct YedekHatirlatmaKarti: View {
    @Environment(AppStore.self) private var store
    @State private var belge: YedekBelgesi?
    @State private var disaKaydet = false

    private var gun: Int? { Backup.yedeksizGun(store.state.settings) }
    private var veriVar: Bool { !store.state.sales.isEmpty || !store.state.expenses.isEmpty
        || !store.state.purchases.isEmpty }
    private var gerekli: Bool { veriVar && (gun.map { $0 >= 7 } ?? true) }

    var body: some View {
        if gerekli {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label(gun.map { "Son yedek \($0) gün önce" } ?? "Verilerinin telefon dışında yedeği yok",
                          systemImage: "externaldrive.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.uyari)
                    Text("Telefon kaybolursa ya da uygulama silinirse bütün kayıtlar gider. "
                         + "Yedeği iCloud Drive'a ya da e-postana kaydet; fatura ekleri de içinde.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let v = try? store.yedekPaketi() {
                            belge = YedekBelgesi(veri: v)
                            disaKaydet = true
                        }
                    } label: {
                        Label("Şimdi yedekle", systemImage: "icloud.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fileExporter(isPresented: $disaKaydet, document: belge, contentType: .json,
                          defaultFilename: "mirissa-yedek-\(Dates.today())") { sonuc in
                if case .success = sonuc { store.yedekPaylasildi() }
            }
        }
    }
}

/// Ayarlar → Yedekleme bölümü
struct YedeklemeBolumu: View {
    @Environment(AppStore.self) private var store
    @State private var belge: YedekBelgesi?
    @State private var disaKaydet = false
    @State private var iceAl = false
    @State private var onizleme: BackupPreview?
    @State private var mesaj: String?

    var body: some View {
        Section {
            Button {
                if let v = try? store.yedekPaketi() {
                    belge = YedekBelgesi(veri: v)
                    disaKaydet = true
                }
            } label: {
                Label("Yedeği kaydet (iCloud Drive, Dosyalar…)", systemImage: "icloud.and.arrow.up")
            }
            if let u = store.otomatikYedekler.first {
                ShareLink(item: u) {
                    Label("Son otomatik yedeği paylaş", systemImage: "square.and.arrow.up")
                }
                .foregroundStyle(Palette.accent)
            }
            Button { iceAl = true } label: {
                Label("Yedekten geri yükle", systemImage: "arrow.uturn.backward.circle")
            }
            if let mesaj { Text(mesaj).font(.footnote).foregroundStyle(Palette.accent) }
        } header: {
            Text("Yedekleme")
        } footer: {
            Text(aciklama)
        }
        .fileExporter(isPresented: $disaKaydet, document: belge, contentType: .json,
                      defaultFilename: "mirissa-yedek-\(Dates.today())") { sonuc in
            switch sonuc {
            case .success: store.yedekPaylasildi(); mesaj = "Yedek kaydedildi."
            case .failure(let e): mesaj = "Yedek kaydedilemedi: \(e.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $iceAl, allowedContentTypes: [.json]) { sonuc in
            guard case let .success(url) = sonuc else { return }
            let erisim = url.startAccessingSecurityScopedResource()
            defer { if erisim { url.stopAccessingSecurityScopedResource() } }
            do {
                onizleme = try store.yedegiOku(try Data(contentsOf: url))
            } catch {
                mesaj = "Bu dosya okunamadı: \(error)"
            }
        }
        .sheet(isPresented: Binding(get: { onizleme != nil }, set: { if !$0 { onizleme = nil } })) {
            if let o = onizleme {
                GeriYuklemeOnizleme(onizleme: o) {
                    do {
                        try store.geriYukle(o)
                        mesaj = "Yedek geri yüklendi. Önceki verin 'Yedekler' klasörüne kopyalandı."
                    } catch {
                        mesaj = "Geri yüklenemedi: \(error)"
                    }
                    onizleme = nil
                } vazgec: { onizleme = nil }
            }
        }
    }

    private var aciklama: String {
        var s = "Uygulama her gün kendi kendine bir yedek alır (son 14 gün). Dosyalar uygulamasında "
            + "\"iPhone'umda › Mirissa Finans › Yedekler\" klasöründe durur. Telefon kaybına karşı "
            + "haftada bir yedeği iCloud Drive'a kaydet; fatura ekleri de içindedir."
        if let g = store.state.settings.ek.sonYedekPaylasim {
            s += " Son dışarı kaydedilen yedek: \(Dates.displayDateShort(g))."
        }
        return s
    }
}

/// Geri yüklemeden önce ne olacağını gösterir; onay olmadan hiçbir şey değişmez
struct GeriYuklemeOnizleme: View {
    @Environment(AppStore.self) private var store
    var onizleme: BackupPreview
    var onayla: () -> Void
    var vazgec: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let g = onizleme.gun { LabeledRow("Yedeğin tarihi", Dates.displayDateShort(g)) }
                    LabeledRow("Ürün", "\(onizleme.urun)")
                    LabeledRow("Malzeme", "\(onizleme.malzeme)")
                    LabeledRow("Satış kaydı", "\(onizleme.satis)")
                    LabeledRow("Gider kaydı", "\(onizleme.gider)")
                    LabeledRow("Alım", "\(onizleme.alim)")
                    LabeledRow("Fatura eki", "\(onizleme.fatura)")
                } header: { Text("Yedekte olanlar") }

                Section {
                    LabeledRow("Satış kaydı", "\(store.state.sales.count)")
                    LabeledRow("Gider kaydı", "\(store.state.expenses.count)")
                } header: { Text("Şu an telefonda olanlar") } footer: {
                    Text("Geri yükleyince şu anki veriler yedektekilerle değişir. Değişmeden önce şu anki "
                         + "verinin bir kopyası 'Yedekler' klasörüne alınır; istersen ona geri dönebilirsin.")
                }

                if !onizleme.atlanan.isEmpty {
                    Section {
                        ForEach(onizleme.atlanan, id: \.self) { Text($0) }
                    } header: { Text("Atlanacak bozuk satırlar") } footer: {
                        Text("Bu satırlar silinmiş bir ürüne, kanala ya da malzemeye ait olduğu için hesaba katılamaz.")
                    }
                }

                Section {
                    Button("Geri yükle", role: .destructive, action: onayla)
                    Button("Vazgeç", role: .cancel, action: vazgec)
                }
            }
            .navigationTitle("Yedeği geri yükle")
            .inlineTitle()
        }
    }
}
