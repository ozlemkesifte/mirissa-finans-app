import SwiftUI
import MirissaCore

/// "Yarım kalan işlem var" — uzun bir akış yarıda bırakıldığında
/// ana sayfada çıkan küçük kart. Cevaplar diskte durur, kaybolmaz.
struct YarimIslemKarti: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: AppSheet?

    /// "Daha sonra" denenler bu açılışta gizlenir; kayıt silinmez.
    @State private var gizlenen: Set<String> = []
    @State private var silinecek: WizardDraft?

    private var bekleyenler: [WizardDraft] {
        store.state.drafts
            .filter { !gizlenen.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        if !bekleyenler.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundStyle(Palette.uyari)
                        Text("Yarım kalan işlem var")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                    }
                    ForEach(bekleyenler) { d in
                        satir(d)
                        if d.id != bekleyenler.last?.id {
                            Divider().overlay(Palette.separator)
                        }
                    }
                }
            }
            .alert("Bu yarım kurulumu silmek istediğine emin misin?",
                   isPresented: Binding(get: { silinecek != nil },
                                        set: { if !$0 { silinecek = nil } })) {
                Button("Vazgeç", role: .cancel) { silinecek = nil }
                Button("Sil", role: .destructive) {
                    if let d = silinecek { store.clearDraft(id: d.id) }
                    silinecek = nil
                }
            } message: {
                Text(silinecek.map { "\($0.title) · \($0.progressLabel)" } ?? "")
            }
        }
    }

    private func satir(_ d: WizardDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(d.progressLabel)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button("Devam et") { sheet = hedef(d) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onFilled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Button("Daha sonra") { gizlenen.insert(d.id) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Palette.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Button("İptal et") { silinecek = d }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.zarar)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Palette.zararYumusak)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Hangi akışın açılacağı. İlk kurulum ayrı ekrandan açılır.
    private func hedef(_ d: WizardDraft) -> AppSheet? {
        switch d.kind {
        case .kanalKurulumu:
            return d.subjectId.map { AppSheet.channelWizard($0) }
        case .fiyatGuncelleme:
            return .priceUpdate(nil)
        case .stokKurulumu:
            return .countFlow
        case .yeniIslem:
            switch d.subjectId {
            case "satis": return .saleFlow
            case "alim": return .purchaseFlow
            case "gider": return .expenseFlow
            default: return .yeniIslem
            }
        case .ilkKurulum:
            store.restartSetup()
            return nil
        }
    }
}
