import Foundation

/// Bir tutarın elle mi girildiğini yoksa otomatik mi hesaplandığını taşır.
public struct Figure: Hashable, Sendable {
    public var amount: Kurus
    public var isManual: Bool

    public init(_ amount: Kurus, manual: Bool = false) {
        self.amount = amount
        self.isManual = manual
    }

    public static let zero = Figure(0)
}

public struct ChannelMonthResult: Hashable, Sendable, Identifiable {
    public var channelId: Id
    public var channelName: String
    public var month: MonthKey

    public var grossSales: Kurus
    public var discount: Kurus
    public var returnsAmount: Kurus
    public var netSales: Kurus
    public var units: Double
    public var returnedUnits: Double
    public var orders: Int
    /// Sipariş sayısı girilmediği için adetten tahmin edildi mi
    public var ordersIsEstimate: Bool

    public var commission: Figure
    public var shipping: Figure
    public var serviceFee: Figure
    public var otherDeduction: Figure
    /// `otherDeduction` içindeki sipariş sayısından bağımsız kısım
    /// (aylık platform ücreti, aylık sabit kesinti) — başa baş hesabı için ayrılır
    public var fixedDeduction: Kurus
    public var ads: Figure
    /// Reklamın sabit sayılan kısmı — kullanıcının gider başına yaptığı seçime göre
    public var adsFixed: Kurus
    /// Bu kanala işaretlenmiş diğer giderler (influencer, sabit vb.)
    public var otherChannelExpenses: [ExpenseCategory: Kurus]
    /// Bu kanala işaretlenmiş diğer giderlerin sabit kısmı
    public var otherChannelExpensesFixed: Kurus
    public var productCost: Kurus
    public var packagingCost: Kurus

    public var id: String { "\(channelId)#\(month)" }

    public var otherChannelExpensesTotal: Kurus {
        otherChannelExpenses.values.reduce(0, +)
    }

    public var adsVariable: Kurus { max(ads.amount - adsFixed, 0) }
    public var otherChannelExpensesVariable: Kurus {
        max(otherChannelExpensesTotal - otherChannelExpensesFixed, 0)
    }

    /// Sipariş adedine bağlı giderler — bir sipariş daha gelirse artan kısım
    public var variableCost: Kurus {
        commission.amount + shipping.amount + serviceFee.amount
            + max(otherDeduction.amount - fixedDeduction, 0)
            + productCost + packagingCost
            + adsVariable + otherChannelExpensesVariable
    }

    /// Sipariş adedinden bağımsız giderler — ay boyunca sabit
    public var fixedCost: Kurus {
        min(fixedDeduction, otherDeduction.amount) + min(adsFixed, ads.amount)
            + min(otherChannelExpensesFixed, otherChannelExpensesTotal)
    }

    /// KATKI = net satış − değişken giderler. Sabit giderleri bu tutar karşılar.
    public var contribution: Kurus { netSales - variableCost }

    /// Platformun kestiği tutarlar (reklam, ürün maliyeti ve ambalaj hariç)
    public var channelFees: Kurus {
        commission.amount + shipping.amount + serviceFee.amount + otherDeduction.amount
    }

    /// Bu kanalın toplam gideri
    public var totalCost: Kurus {
        channelFees + ads.amount + otherChannelExpensesTotal + productCost + packagingCost
    }

    /// KANALDA KALAN = net satış − kesintiler − reklam − diğer − ürün maliyeti − ambalaj
    public var kanaldaKalan: Kurus { netSales - totalCost }

    public var marginPct: Double {
        netSales > 0 ? Double(kanaldaKalan) / Double(netSales) * 100 : 0
    }

    public var isEmpty: Bool {
        grossSales == 0 && units == 0 && totalCost == 0
    }

    public static func empty(channelId: Id, channelName: String, month: MonthKey) -> ChannelMonthResult {
        .init(
            channelId: channelId, channelName: channelName, month: month,
            grossSales: 0, discount: 0, returnsAmount: 0, netSales: 0,
            units: 0, returnedUnits: 0, orders: 0, ordersIsEstimate: true,
            commission: .zero, shipping: .zero, serviceFee: .zero,
            otherDeduction: .zero, fixedDeduction: 0, ads: .zero, adsFixed: 0,
            otherChannelExpenses: [:], otherChannelExpensesFixed: 0,
            productCost: 0, packagingCost: 0
        )
    }
}

public struct CompanyMonthResult: Hashable, Sendable, Identifiable {
    public var month: MonthKey
    public var channels: [ChannelMonthResult]
    /// Hiçbir kanala ait olmayan şirket giderleri (kâra etki eden)
    public var ortakGider: Kurus
    /// Ortak giderlerin satışa bağlı kısmı
    public var ortakGiderDegisken: Kurus
    /// Stoğa giren alımlar — kasadan çıktı ama kâra satıldıkça yansır
    public var stokAlimi: Kurus
    /// Kasadan bu ay çıkan toplam
    public var nakitCikisi: Kurus
    public var expenseBreakdown: [ExpenseCategory: Kurus]

    public var id: String { month }

    /// GERÇEK CİRO = net satışlar (indirim ve iade düşülmüş)
    public var gercekCiro: Kurus { channels.reduce(0) { $0 + $1.netSales } }
    public var grossSales: Kurus { channels.reduce(0) { $0 + $1.grossSales } }
    public var units: Double { channels.reduce(0) { $0 + $1.units } }
    public var orders: Int { channels.reduce(0) { $0 + $1.orders } }
    public var toplamKanaldaKalan: Kurus { channels.reduce(0) { $0 + $1.kanaldaKalan } }

    /// TOPLAM GİDER = kanal giderleri + ortak şirket giderleri
    public var toplamGider: Kurus {
        channels.reduce(0) { $0 + $1.totalCost } + ortakGider
    }

    /// GERÇEK KÂR = toplam kanalda kalan − ortak şirket giderleri
    public var gercekKar: Kurus { toplamKanaldaKalan - ortakGider }
    public var isLoss: Bool { gercekKar < 0 }

    public var karMarjiPct: Double {
        gercekCiro > 0 ? Double(gercekKar) / Double(gercekCiro) * 100 : 0
    }

    public var urunVeAmbalajMaliyeti: Kurus {
        channels.reduce(0) { $0 + $1.productCost + $1.packagingCost }
    }

    public var ortakGiderSabit: Kurus { max(ortakGider - ortakGiderDegisken, 0) }

    /// Bütün kanalların katkısı — sabit giderleri karşılayan tutar
    public var toplamKatki: Kurus {
        channels.reduce(0) { $0 + $1.contribution } - ortakGiderDegisken
    }

    /// Sipariş adedinden bağımsız bütün giderler (kanal sabitleri + ortak sabit giderler)
    public var toplamSabitGider: Kurus {
        channels.reduce(0) { $0 + $1.fixedCost } + ortakGiderSabit
    }

    public var hasData: Bool { gercekCiro != 0 || toplamGider != 0 || nakitCikisi != 0 }

    public static func empty(_ m: MonthKey) -> CompanyMonthResult {
        .init(month: m, channels: [], ortakGider: 0, ortakGiderDegisken: 0,
              stokAlimi: 0, nakitCikisi: 0, expenseBreakdown: [:])
    }
}

public struct TrendPoint: Hashable, Sendable, Identifiable {
    public var month: MonthKey
    public var gelir: Kurus
    public var gider: Kurus
    public var kar: Kurus
    public var id: String { month }
}

public struct YearResult: Hashable, Sendable {
    public var year: Int
    public var months: [CompanyMonthResult]

    public var gercekCiro: Kurus { months.reduce(0) { $0 + $1.gercekCiro } }
    public var toplamGider: Kurus { months.reduce(0) { $0 + $1.toplamGider } }
    public var gercekKar: Kurus { months.reduce(0) { $0 + $1.gercekKar } }
    public var units: Double { months.reduce(0) { $0 + $1.units } }
    public var isLoss: Bool { gercekKar < 0 }

    public var karMarjiPct: Double {
        gercekCiro > 0 ? Double(gercekKar) / Double(gercekCiro) * 100 : 0
    }

    public var expenseBreakdown: [ExpenseCategory: Kurus] {
        var out: [ExpenseCategory: Kurus] = [:]
        for m in months { for (k, v) in m.expenseBreakdown { out[k, default: 0] += v } }
        return out
    }

    public var trend: [TrendPoint] {
        months.map { TrendPoint(month: $0.month, gelir: $0.gercekCiro, gider: $0.toplamGider, kar: $0.gercekKar) }
    }

    /// Kanal bazında yıllık toplamlar
    public func channelTotals() -> [Id: [ChannelMonthResult]] {
        var out: [Id: [ChannelMonthResult]] = [:]
        for m in months { for c in m.channels { out[c.channelId, default: []].append(c) } }
        return out
    }
}

public extension Array where Element == ChannelMonthResult {
    /// Aynı kanalın birden çok ayını tek sonuçta toplar
    func aggregated(channelId: Id, channelName: String, label: MonthKey) -> ChannelMonthResult {
        var r = ChannelMonthResult.empty(channelId: channelId, channelName: channelName, month: label)
        var manualCommission = false, manualShipping = false, manualService = false
        var manualOther = false, manualAds = false
        for c in self {
            r.grossSales += c.grossSales
            r.discount += c.discount
            r.returnsAmount += c.returnsAmount
            r.netSales += c.netSales
            r.units += c.units
            r.returnedUnits += c.returnedUnits
            r.orders += c.orders
            r.ordersIsEstimate = r.ordersIsEstimate && c.ordersIsEstimate
            r.commission.amount += c.commission.amount; manualCommission = manualCommission || c.commission.isManual
            r.shipping.amount += c.shipping.amount; manualShipping = manualShipping || c.shipping.isManual
            r.serviceFee.amount += c.serviceFee.amount; manualService = manualService || c.serviceFee.isManual
            r.otherDeduction.amount += c.otherDeduction.amount; manualOther = manualOther || c.otherDeduction.isManual
            r.fixedDeduction += c.fixedDeduction
            r.ads.amount += c.ads.amount; manualAds = manualAds || c.ads.isManual
            r.adsFixed += c.adsFixed
            r.otherChannelExpensesFixed += c.otherChannelExpensesFixed
            r.productCost += c.productCost
            r.packagingCost += c.packagingCost
            for (k, v) in c.otherChannelExpenses { r.otherChannelExpenses[k, default: 0] += v }
        }
        r.commission.isManual = manualCommission
        r.shipping.isManual = manualShipping
        r.serviceFee.isManual = manualService
        r.otherDeduction.isManual = manualOther
        r.ads.isManual = manualAds
        return r
    }
}
