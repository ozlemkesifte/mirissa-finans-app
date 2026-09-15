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
            Screen(name: "1-ana-sayfa", title: "Ana Sayfa", view: wrap(HomeView())),
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
                BreakevenCard(month: month, hedeflerAcik: true)
                    .padding(Metrics.pad)
            }
            .screenBackground()
            .environment(store)
            .environment(Period(month: month))
        )
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
