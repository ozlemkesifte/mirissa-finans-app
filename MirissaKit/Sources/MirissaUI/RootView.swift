import SwiftUI
import MirissaCore

public struct RootView: View {
    @State private var store: AppStore
    @State private var period = Period()
    @State private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    public init(store: AppStore? = nil) {
        _store = State(initialValue: store ?? AppStore())
    }

    public var body: some View {
        Group {
            if store.state.settings.setupCompleted {
                sekmeler
            } else {
                SetupWizard()
            }
        }
        .tint(Palette.accent)
        .environment(store)
        .environment(period)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.otomatikYedekGerekirse()
                BildirimPlanlayici.yenile(store)
                store.flush()
            }
        }
        .onAppear { store.otomatikYedekGerekirse() }
        .alert("Değişiklik yapılamadı", isPresented: Binding(
            get: { store.sonHata != nil }, set: { if !$0 { store.hatayiKapat() } })
        ) {
            Button("Tamam") { store.hatayiKapat() }
        } message: {
            Text(store.sonHata ?? "")
        }
    }

    private var sekmeler: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("Ana Sayfa", systemImage: "house.fill") }
                .tag(0)
            SalesView()
                .tabItem { Label("Satışlar", systemImage: "cart.fill") }
                .tag(1)
            ExpensesView()
                .tabItem { Label("Giderler", systemImage: "creditcard.fill") }
                .tag(2)
            StockView()
                .tabItem { Label("Ürün & Stok", systemImage: "shippingbox.fill") }
                .tag(3)
            ReportsView()
                .tabItem { Label("Raporlar", systemImage: "chart.bar.fill") }
                .tag(4)
        }
    }
}
