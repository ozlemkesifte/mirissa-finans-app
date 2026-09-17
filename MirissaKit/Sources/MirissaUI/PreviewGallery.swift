import SwiftUI
import MirissaCore

/// Ekranları tek tek dışarıya açar — Xcode önizlemeleri ve
/// Xcode'suz görsel doğrulama (PNG üretimi) için.
public enum PreviewGallery {
    public struct Screen: Identifiable {
        public var id: String { name }
        public var name: String
        public var title: String
        public var view: AnyView
    }

    @MainActor
    public static func screens(store: AppStore, period: Period) -> [Screen] {
        func wrap<V: View>(_ v: V) -> AnyView {
            AnyView(v.environment(store).environment(period))
        }
        return [
            Screen(name: "1-ana-sayfa", title: "Ana Sayfa", view: wrap(HomeView(tab: .constant(0)))),
            Screen(name: "2-satislar", title: "Satışlar", view: wrap(SalesView())),
            Screen(name: "3-giderler", title: "Giderler", view: wrap(ExpensesView())),
            Screen(name: "4-urun-stok", title: "Ürün & Stok", view: wrap(StockView())),
            Screen(name: "5-raporlar", title: "Raporlar", view: wrap(ReportsView())),
        ]
    }

    /// Sadece "BU AY NEREDEYİZ?" kartı, hedefleri açık — tasarım kontrolü için
    @MainActor
    public static func breakevenCard(store: AppStore, month: MonthKey) -> AnyView {
        AnyView(
            ScrollView {
                BreakevenCard(month: month, detayAcik: true)
                    .padding(Metrics.pad)
            }
            .screenBackground()
            .environment(store)
            .environment(Period(month: month))
        )
    }

    /// Gider formu — sınıflandırma ve fatura bölümlerini görmek için
    @MainActor
    public static func expenseForm(store: AppStore, month: MonthKey, expenseId: Id) -> AnyView {
        AnyView(
            ExpenseForm(editing: expenseId, month: month)
                .environment(store).environment(Period(month: month))
        )
    }

    /// KDV ve alacak/ödenecek kartları, açık halde
    @MainActor
    public static func vatAndBalance(store: AppStore, month: MonthKey) -> AnyView {
        AnyView(
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    VatCard(month: month, acik: true)
                    BalanceCard(month: month, sheet: .constant(nil), acik: true)
                }
                .padding(Metrics.pad)
            }
            .screenBackground()
            .environment(store)
            .environment(Period(month: month))
        )
    }

    /// Rehberli akışlar — soru ekranları
    @MainActor
    public static func guidedFlows(store: AppStore) -> [Screen] {
        func wrap<V: View>(_ v: V) -> AnyView {
            AnyView(v.environment(store).environment(Period()))
        }
        return [
            Screen(name: "f1-yeni-islem", title: "Yeni İşlem", view: wrap(YeniIslemAkisi())),
            Screen(name: "f2-satis", title: "Satış akışı", view: wrap(SaleFlow())),
            Screen(name: "f3-alim", title: "Alım akışı", view: wrap(PurchaseFlow())),
            Screen(name: "f4-gider", title: "Gider akışı", view: wrap(ExpenseFlow())),
            Screen(name: "f5-sayim", title: "Sayım akışı", view: wrap(CountFlow())),
            Screen(name: "f6-kurulum", title: "Kurulum", view: wrap(SetupWizard())),
            Screen(name: "f7-fiyat", title: "Fiyat güncelle", view: wrap(PriceUpdateFlow())),
            Screen(name: "f8-kanal-ekle", title: "Kanal ekle", view: wrap(ChannelAddFlow())),
            Screen(name: "f11-eksikler", title: "Eksikleri tamamla",
                   view: wrap(EksikleriTamamlaFlow())),
            Screen(name: "f12-dagilim", title: "Satış dağılımı",
                   view: wrap(SatisDagilimiFlow())),
            Screen(name: "f10-devam", title: "Kaldığın yerden devam",
                   view: wrap(DevamSorusu(baslik: "Trendyol kurulumu",
                                          ilerleme: "7/12 adım tamamlandı",
                                          devam: {}, bastan: {}, vazgec: {}))),
            Screen(name: "f9-kanal-kurulum", title: "Kanal kurulumu",
                   view: wrap(ChannelSetupFlow(channelId: ChannelIds.trendyol))),
        ]
    }

    /// Ana sayfanın dört senaryosu — görsel doğrulama için
    @MainActor
    public static func homeScenario(store: AppStore, month: MonthKey) -> AnyView {
        AnyView(
            HomeView(tab: .constant(0))
                .environment(store)
                .environment(Period(month: month))
        )
    }

    /// Reklam hedefi bölümü açık hali — görsel doğrulama için
    @MainActor
    public static func adTargets(store: AppStore, month: MonthKey) -> AnyView {
        AnyView(
            ScrollView {
                Card { ReklamHedefiBolumu(month: month, acik: true) }
                    .padding(16)
            }
            .background(Palette.bg)
            .environment(store)
            .environment(Period(month: month))
        )
    }

    /// Kurulumun belirli bir adımı — görsel doğrulama için
    @MainActor
    public static func setupStep(store: AppStore, _ adim: SetupPreviewStep) -> AnyView {
        AnyView(SetupWizard(baslangic: adim.iceri)
            .environment(store).environment(Period()))
    }

    public enum SetupPreviewStep: String, CaseIterable, Sendable {
        case urunSayisi, urunAdi, urunMaliyetKdv, urunMaliyetOran, setVarMi, setBilesenleri, malzemeSecimi, setAmbalaji, kanalSecimi

        var iceri: SetupWizard.Adim {
            switch self {
            case .urunSayisi: return .urunSayisi
            case .urunAdi: return .urunAdi(0)
            case .urunMaliyetKdv: return .urunMaliyetKdv(0)
            case .urunMaliyetOran: return .urunMaliyetOran(0)
            case .setVarMi: return .setVarMi
            case .setBilesenleri: return .setBilesenleri(0)
            case .malzemeSecimi: return .malzemeSecimi
            case .setAmbalaji: return .setAmbalaji(0)
            case .kanalSecimi: return .kanalSecimi
            }
        }
    }

    /// İlk kurulum sihirbazı
    @MainActor
    public static func setupWizard(store: AppStore) -> AnyView {
        AnyView(SetupWizard().environment(store).environment(Period()))
    }

    /// Ürün formu — reçete soruları açık
    @MainActor
    public static func productForm(store: AppStore, productId: Id) -> AnyView {
        AnyView(ProductForm(editing: productId).environment(store).environment(Period()))
    }

    @MainActor
    public static func detail(store: AppStore, period: Period, materialId: Id) -> AnyView {
        AnyView(
            NavigationStack { MaterialDetail(materialId: materialId) }
                .environment(store).environment(period)
        )
    }

    @MainActor
    public static func productDetail(store: AppStore, period: Period, productId: Id) -> AnyView {
        AnyView(
            NavigationStack { ProductDetail(productId: productId) }
                .environment(store).environment(period)
        )
    }
}
