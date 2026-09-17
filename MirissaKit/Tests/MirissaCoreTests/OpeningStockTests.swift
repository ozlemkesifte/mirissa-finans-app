import Testing
import Foundation
@testable import MirissaCore

/// "Şu anda 740 şampuanım var" — geçmişte alınmış stok.
/// Stoğa eklenmeli, maliyete girmeli; ama bu ayın gideri, nakit çıkışı
/// veya KDV kaydı OLMAMALI.
@Suite("Başlangıç stoğu")
struct OpeningStockTests {

    private func kurulum() -> AppState {
        var s = SeedData.initialState()
        let ay = Dates.monthStart("2026-09")

        // 740 şampuan, birim maliyeti 141 TL
        if let i = s.products.firstIndex(where: { $0.id == SeedData.P.sampuan }) {
            s.products[i].openingQty = 740
            s.products[i].openingUnitCost = tl(141)
            s.products[i].openingDate = ay
            s.products[i].costLines = [CostLine(id: "c", label: "Birim maliyet", amount: tl(141))]
        }
        // 380 koli, adedi 11 TL
        if let i = s.materials.firstIndex(where: { $0.id == SeedData.M.koli }) {
            s.materials[i].openingQty = 380
            s.materials[i].openingUnitCost = tl(11)
            s.materials[i].openingDate = ay
        }
        return s
    }

    @Test func stogaEklenir() {
        let e = Engine(kurulum())
        #expect(e.qty(.product(SeedData.P.sampuan)) == 740)
        #expect(e.qty(.material(SeedData.M.koli)) == 380)
    }

    @Test func maliyetHesabindaKullanilir() {
        let e = Engine(kurulum())
        // Stok değeri başlangıç maliyetinden hesaplanır
        #expect(approx(e.unitCost(.product(SeedData.P.sampuan)), Double(tl(141))))
        #expect(e.balance(.product(SeedData.P.sampuan)).value == tl(141) * 740)
        #expect(approx(e.unitCost(.material(SeedData.M.koli)), Double(tl(11))))
        #expect(e.balance(.material(SeedData.M.koli)).value == tl(11) * 380)
        // Paketleme maliyeti başlangıç stoğunun birim maliyetini kullanır
        let b = e.cost(of: SeedData.P.sampuan)
        #expect(b.packaging + b.orderPackaging > 0)
        #expect(b.orderPackaging == Money.roundHalfAwayFromZero(e.unitCost(.material(SeedData.M.koli))))
    }

    @Test func buAyinGideriOlarakYAZILMAZ() {
        let r = Engine(kurulum()).companyMonth("2026-09")
        #expect(r.toplamGider == 0)
        #expect(r.ortakGider == 0)
        #expect(r.stokAlimi == 0)
        #expect(r.gercekKar == 0)
    }

    @Test func nakitCikisiOlarakYAZILMAZ() {
        let r = Engine(kurulum()).companyMonth("2026-09")
        #expect(r.nakitCikisi == 0)
        // Giderler listesinde hiç satır oluşturmaz
        #expect(Engine(kurulum()).expenseInstances(month: "2026-09").isEmpty)
    }

    @Test func kdvKaydiOLUSTURMAZ() {
        let e = Engine(kurulum())
        let kdv = e.vatStatus("2026-09")
        #expect(kdv.hesaplanan == 0)
        #expect(kdv.indirilecek == 0)
        #expect(kdv.odenecek == 0)
        #expect(!kdv.hasData)
    }

    /// Başlangıç stoğu üzerine yapılan alım ortalama maliyeti doğru harmanlar
    @Test func sonrakiAlimlaHarmanlanir() {
        var s = kurulum()
        // 380 koli 11 TL'den elde; 620 koli daha 13 TL'den alınıyor (KDV hariç)
        s.purchases.append(StockPurchase(
            id: "pur", date: "2026-09-10", item: .material(SeedData.M.koli),
            qty: 620, unit: .adet, totalPaid: tl(8060), vatRate: .yok
        ))
        let e = Engine(s)
        #expect(e.qty(.material(SeedData.M.koli)) == 1000)
        // (380×11 + 620×13) / 1000 = 12,24
        #expect(approx(e.unitCost(.material(SeedData.M.koli)), Double(tl(12.24)), 1))
        // Sonraki alım normal şekilde gider ve nakit çıkışı oluşturur
        let r = e.companyMonth("2026-09")
        #expect(r.stokAlimi == tl(8060))
        #expect(r.nakitCikisi == tl(8060))
    }

    /// Başlangıç stoğundan satış yapılabilir, stok doğru düşer
    @Test func baslangicStogundanSatisYapilir() {
        var s = kurulum()
        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 80, gross: tl(55_920))
        let e = Engine(s)
        #expect(e.qty(.product(SeedData.P.sampuan)) == 660)
        #expect(e.qty(.material(SeedData.M.koli)) == 300)
        // Satılan malın maliyeti kâra girer
        let r = e.companyMonth("2026-09")
        #expect(r.channels.first { $0.channelId == ChannelIds.trendyol }?.productCost == tl(141) * 80)
    }

    /// Hareket geçmişinde tek satır olarak görünür
    @Test func gecmisteTekSatirGorunur() {
        let e = Engine(kurulum())
        let gecmis = e.history(.product(SeedData.P.sampuan))
        #expect(gecmis.count == 1)
        #expect(gecmis.first?.kind == .opening)
        #expect(gecmis.first?.delta == 740)
    }
}

@Suite("İlk kurulum")
struct SetupFlagTests {

    /// Yeni kurulumda sihirbaz çıkar
    @Test func yeniKurulumdaSihirbazCikar() {
        #expect(SeedData.initialState().settings.setupCompleted == false)
        #expect(AppSettings().setupCompleted == false)
    }

    /// Kayıtlı dosyası olan kullanıcı sihirbazı tekrar görmez
    @Test func mevcutKullaniciSihirbaziGormez() throws {
        // setupCompleted alanı olmayan eski bir yedek
        let json = """
        {"schemaVersion":1,"savedAt":"2026-09-01T00:00:00Z","state":{
          "materials":[],"products":[],"channels":[],"channelMonths":[],
          "sales":[],"expenses":[],"purchases":[],"adjustments":[],"counts":[],
          "settings":{"consumptionWindowMonths":3,"capitalizePurchases":true,"companyName":"Mirissa Lab"}
        }}
        """
        let geri = try Persistence.decode(Data(json.utf8))
        #expect(geri.settings.setupCompleted == true)
    }

    /// Kurulumu bitirince bayrak kalıcı olur
    @Test func kurulumBayragiKalici() throws {
        var s = SeedData.initialState()
        s.settings.setupCompleted = true
        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri.settings.setupCompleted == true)
    }

    /// Sihirbazın yazdığı başlangıç stoğu gider veya KDV oluşturmaz
    @Test func sihirbazVerisiGiderOlusturmaz() {
        var s = SeedData.initialState()
        let ay = Dates.monthStart(Dates.currentMonth())
        for i in s.products.indices where !s.products[i].isBundle {
            s.products[i].openingQty = 100
            s.products[i].openingUnitCost = tl(140)
            s.products[i].openingDate = ay
            s.products[i].costLines = [CostLine(label: "Birim maliyet", amount: tl(140))]
        }
        for i in s.materials.indices {
            s.materials[i].openingQty = 300
            s.materials[i].openingUnitCost = tl(5)
            s.materials[i].openingDate = ay
        }
        s.settings.setupCompleted = true

        let e = Engine(s)
        let r = e.companyMonth(Dates.currentMonth())
        #expect(r.toplamGider == 0)
        #expect(r.nakitCikisi == 0)
        #expect(r.stokAlimi == 0)
        #expect(e.vatStatus(Dates.currentMonth()).hasData == false)
        // Ama stok ve stok değeri oluştu
        #expect(e.qty(.product(SeedData.P.sampuan)) == 100)
        #expect(e.totalStockValue > 0)
    }
}

@Suite("Yedek uyumluluğu")
struct BackupCompatTests {

    /// Yeni alan eklemek eski yedekleri okunamaz hale getirmemeli —
    /// aksi halde uygulama güncellemesi veri kaybına yol açar.
    @Test func eksikAlanliYedekOkunur() throws {
        // En eski biçim: balances, settings alanlarının hiçbiri yok
        let json = """
        {"schemaVersion":1,"savedAt":"2026-01-01T00:00:00Z","state":{
          "materials":[],"products":[],"channels":[],"sales":[]
        }}
        """
        let geri = try Persistence.decode(Data(json.utf8))
        #expect(geri.balances.isEmpty)
        #expect(geri.expenses.isEmpty)
        #expect(geri.counts.isEmpty)
        #expect(geri.settings.companyName == "Mirissa Lab")
        #expect(geri.settings.setupCompleted == true)
    }

    /// Tam dolu bir durum yazılıp okunduğunda hiçbir şey kaybolmaz
    @Test func tamDurumKayipsizDoner() throws {
        var s = SeedData.initialState()
        s.settings.setupCompleted = true
        s.products[0].openingQty = 740
        s.products[0].openingUnitCost = tl(141)
        s.materials[0].openingQty = 380
        s.balances = [BalanceItem(kind: .alacak, name: "Trendyol", amount: tl(45_000))]
        s.addSale("sal", "2026-09", channel: ChannelIds.trendyol,
                  product: SeedData.P.sampuan, qty: 10, gross: tl(7000))
        s.expenses.append(Expense(date: "2026-09-01", name: "Ajans", amount: tl(20_000),
                                  category: .sabit, recurrence: .aylik,
                                  vatRate: .yirmi, vatIncluded: true))

        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri == s)
    }
}
