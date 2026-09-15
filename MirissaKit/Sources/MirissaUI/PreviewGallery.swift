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

    /// İlk kurulum sihirbazı
    @MainActor
    public static func setupWizard(store: AppStore) -> AnyView {
        AnyView(SetupWizard().environment(store).environment(Period()))
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
