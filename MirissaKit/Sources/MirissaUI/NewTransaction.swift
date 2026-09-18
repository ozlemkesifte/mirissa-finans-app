import SwiftUI
import MirissaCore

/// "+ Yeni İşlem" — önce ne yapmak istediğini sorar, sonra o akışı açar.
struct YeniIslemAkisi: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Islem: String, Identifiable, CaseIterable {
        case satis, rapor, alim, gider, sayim, baslangic
        var id: String { rawValue }

        var baslik: String {
            switch self {
            case .satis: return "Satış gireceğim"
            case .rapor: return "Satışları rapordan aktaracağım"
            case .alim: return "Bir şey satın aldım"
            case .gider: return "Gider / fatura ödedim"
            case .sayim: return "Stok sayımı yaptım"
            case .baslangic: return "Başlangıç bilgisini değiştireceğim"
            }
        }

        var aciklama: String {
            switch self {
            case .satis: return "Ayın toplam satışını kanal kanal gir"
            case .rapor: return "Trendyol / Shopify sipariş raporu (CSV): satış, sipariş ve koli kendiliğinden"
            case .alim: return "Kutu, koli, şişe, ürün — stoğa giren her şey"
            case .gider: return "Reklam, kargo, muhasebeci, abonelik"
            case .sayim: return "Depoda saydığın gerçek miktarı yaz"
            case .baslangic: return "Ürün, malzeme ve kanal bilgilerini yeniden gözden geçir"
            }
        }

        var ikon: String {
            switch self {
            case .satis: return "cart.fill"
            case .rapor: return "doc.text.fill"
            case .alim: return "shippingbox.fill"
            case .gider: return "creditcard.fill"
            case .sayim: return "checklist"
            case .baslangic: return "slider.horizontal.3"
            }
        }

        var renk: Color {
            switch self {
            case .satis: return Palette.accent
            case .rapor: return Palette.accent
            case .alim: return Palette.uyari
            case .gider: return Palette.gider
            case .sayim: return Palette.accent
            case .baslangic: return Palette.inkSoft
            }
        }
    }

    @State private var secim: Islem?
    @State private var kurulumOnayi = false

    var body: some View {
        switch secim {
        case .satis: SaleFlow()
        case .rapor: RaporIceAktarmaAkisi()
        case .alim: PurchaseFlow()
        case .gider: ExpenseFlow()
        case .sayim: CountFlow()
        case .baslangic, .none: menu
        }
    }

    private var menu: some View {
        SoruAdimi(
            soru: "Ne yapmak istiyorsun?",
            aciklama: "Birini seç, gerisini adım adım soracağım.",
            vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(Islem.allCases) { i in
                    if i == .baslangic {
                        Divider().overlay(Palette.separator).padding(.vertical, 4)
                    }
                    SecenekButonu(baslik: i.baslik, aciklama: i.aciklama,
                                  ikon: i.ikon, renk: i.renk) {
                        if i == .baslangic { kurulumOnayi = true } else { secim = i }
                    }
                }
            }
        }
        .alert("Başlangıç bilgilerini düzenle", isPresented: $kurulumOnayi) {
            Button("Vazgeç", role: .cancel) {}
            Button("Devam et") {
                store.restartSetup()
                dismiss()
            }
        } message: {
            Text("Kurulum soruları yeniden açılır. Girdiğin satış, gider ve stok "
                 + "kayıtlarının hiçbiri silinmez.")
        }
    }
}
