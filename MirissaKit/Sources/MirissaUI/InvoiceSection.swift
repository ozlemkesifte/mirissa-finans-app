import SwiftUI
import UniformTypeIdentifiers
import MirissaCore
#if os(iOS)
import PhotosUI
#endif

struct PickedFile: Equatable {
    var data: Data
    var ext: String
}

/// Fatura / fiş eki. Yeni kayıtta dosya bellekte tutulur, kaydedilince bağlanır.
struct InvoiceSection: View {
    /// Kayıtta hâlihazırda duran dosya adı
    var current: String?
    @Binding var picked: PickedFile?
    @Binding var removed: Bool

    @State private var showFileImporter = false
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif

    private var gosterilecek: String? { removed ? nil : current }
    private var varMi: Bool { picked != nil || gosterilecek != nil }

    var body: some View {
        Section {
            if varMi {
                onizleme
                Button(role: .destructive) {
                    picked = nil
                    if current != nil { removed = true }
                    #if os(iOS)
                    photo = nil
                    #endif
                } label: {
                    Label("Faturayı kaldır", systemImage: "trash")
                }
            } else {
                #if os(iOS)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Fotoğraf çek / seç", systemImage: "camera")
                }
                #endif
                Button {
                    showFileImporter = true
                } label: {
                    Label("Dosyadan seç (PDF / görsel)", systemImage: "doc")
                }
            }
        } header: {
            Text("Fatura / fiş")
        } footer: {
            Text(varMi
                 ? "Fatura bu kayda bağlı. Uygulama içinde saklanır, internete gönderilmez."
                 : "İstersen faturanın fotoğrafını veya PDF'ini bu kayda ekleyebilirsin.")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .pdf]) { result in
            guard case let .success(url) = result else { return }
            let stop = url.startAccessingSecurityScopedResource()
            defer { if stop { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                picked = PickedFile(data: data, ext: url.pathExtension)
                removed = false
            }
        }
        #if os(iOS)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    picked = PickedFile(data: data, ext: "jpg")
                    removed = false
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var onizleme: some View {
        if let p = picked {
            HStack(spacing: 12) {
                kucukGorsel(data: p.data, pdf: p.ext.lowercased() == "pdf")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yeni fatura seçildi").font(.subheadline).foregroundStyle(Palette.ink)
                    Text("Kaydedince eklenecek").font(.caption).foregroundStyle(Palette.inkFaint)
                }
                Spacer()
            }
        } else if let name = gosterilecek, AttachmentStore.exists(name) {
            HStack(spacing: 12) {
                kucukGorsel(url: AttachmentStore.url(name), pdf: AttachmentStore.isPDF(name))
                VStack(alignment: .leading, spacing: 2) {
                    Text(AttachmentStore.isPDF(name) ? "PDF fatura" : "Fatura fotoğrafı")
                        .font(.subheadline).foregroundStyle(Palette.ink)
                    Text("Açmak için paylaş").font(.caption).foregroundStyle(Palette.inkFaint)
                }
                Spacer()
                ShareLink(item: AttachmentStore.url(name)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .foregroundStyle(Palette.accent)
            }
        } else if gosterilecek != nil {
            Text("Fatura dosyası bulunamadı.")
                .font(.footnote)
                .foregroundStyle(Palette.uyari)
        }
    }

    @ViewBuilder
    private func kucukGorsel(data: Data? = nil, url: URL? = nil, pdf: Bool) -> some View {
        if pdf {
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundStyle(Palette.gider)
                .frame(width: 52, height: 52)
                .background(Palette.inset)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let img = PlatformImage.load(data: data, url: url) {
            img.resizable().scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(Palette.inkFaint)
                .frame(width: 52, height: 52)
                .background(Palette.inset)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

enum PlatformImage {
    static func load(data: Data? = nil, url: URL? = nil) -> Image? {
        let bytes = data ?? url.flatMap { try? Data(contentsOf: $0) }
        guard let bytes else { return nil }
        #if os(iOS)
        return UIImage(data: bytes).map { Image(uiImage: $0) }
        #else
        return NSImage(data: bytes).map { Image(nsImage: $0) }
        #endif
    }
}
