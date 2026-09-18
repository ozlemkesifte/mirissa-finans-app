import Foundation

/// "2026-09-13" — yerel takvim günü. State içinde asla `Date` tutulmaz.
public typealias DateKey = String
/// "2026-09"
public typealias MonthKey = String

public enum Dates {
    /// Cihazın yerel takvimine göre bugün. `toISOString` benzeri UTC kaymasını engeller.
    public static func today(_ date: Date = Date(), calendar: Calendar = .current) -> DateKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return key(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    public static func currentMonth(_ date: Date = Date(), calendar: Calendar = .current) -> MonthKey {
        month(of: today(date, calendar: calendar))
    }

    public static func key(_ y: Int, _ m: Int, _ d: Int) -> DateKey {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    public static func monthKey(_ y: Int, _ m: Int) -> MonthKey {
        String(format: "%04d-%02d", y, m)
    }

    public static func month(of d: DateKey) -> MonthKey {
        String(d.prefix(7))
    }

    public static func year(of m: MonthKey) -> Int {
        Int(m.prefix(4)) ?? 0
    }

    public static func monthNumber(of m: MonthKey) -> Int {
        Int(m.dropFirst(5).prefix(2)) ?? 1
    }

    public static func day(of d: DateKey) -> Int {
        Int(d.suffix(2)) ?? 1
    }

    public static func monthStart(_ m: MonthKey) -> DateKey {
        "\(m)-01"
    }

    public static func monthEnd(_ m: MonthKey) -> DateKey {
        let y = year(of: m), mm = monthNumber(of: m)
        return key(y, mm, daysInMonth(year: y, month: mm))
    }

    public static func daysInMonth(year y: Int, month m: Int) -> Int {
        switch m {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeap(y) ? 29 : 28
        default: return 30
        }
    }

    public static func isLeap(_ y: Int) -> Bool {
        (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }

    public static func addMonths(_ m: MonthKey, _ n: Int) -> MonthKey {
        let total = year(of: m) * 12 + (monthNumber(of: m) - 1) + n
        return monthKey(total / 12, total % 12 + 1)
    }

    /// İki ay arasındaki fark (ay sayısı). addMonths(a, diff(a,b)) == b
    public static func monthsBetween(_ a: MonthKey, _ b: MonthKey) -> Int {
        (year(of: b) * 12 + monthNumber(of: b)) - (year(of: a) * 12 + monthNumber(of: a))
    }

    /// Her iki uç dahil.
    public static func monthRange(from: MonthKey, to: MonthKey) -> [MonthKey] {
        let n = monthsBetween(from, to)
        guard n >= 0 else { return [] }
        return (0...n).map { addMonths(from, $0) }
    }

    /// Aya, o ayda var olan en yakın günü uygular (31 -> 30/28).
    public static func dateIn(month m: MonthKey, dayOfMonth d: Int) -> DateKey {
        let y = year(of: m), mm = monthNumber(of: m)
        return key(y, mm, min(max(d, 1), daysInMonth(year: y, month: mm)))
    }

    public static let monthNamesTR = [
        "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
        "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
    ]

    public static let monthNamesShortTR = [
        "Oca", "Şub", "Mar", "Nis", "May", "Haz",
        "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara",
    ]

    /// "Eylül 2026"
    /// İki gün arasındaki fark (b - a). Geçersiz tarihte 0.
    public static func daysBetween(_ a: DateKey, _ b: DateKey) -> Int {
        guard let ga = gunSayisi(a), let gb = gunSayisi(b) else { return 0 }
        return gb - ga
    }

    /// Tarihe ay ekler; gün ayın son gününü aşarsa ayın sonuna çekilir (31 Ocak + 1 ay = 28/29 Şubat)
    public static func addMonthsToDate(_ d: DateKey, _ n: Int) -> DateKey {
        let ay = addMonths(month(of: d), n)
        let gun = Int(d.suffix(2)) ?? 1
        let son = Int(monthEnd(ay).suffix(2)) ?? 28
        return String(format: "%@-%02d", ay, min(gun, son))
    }

    /// Bir güne n gün ekler.
    public static func addDays(_ d: DateKey, _ n: Int) -> DateKey {
        guard let toplam = gunSayisi(d) else { return d }
        return tarihten(gun: toplam + n)
    }

    /// 1970-01-01'den bu yana geçen gün — takvim hesabı için
    private static func gunSayisi(_ d: DateKey) -> Int? {
        let p = d.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let g = Int(p[2]),
              (1...12).contains(m) else { return nil }
        var toplam = 0
        if y >= 1970 {
            for yil in 1970..<y { toplam += isLeap(yil) ? 366 : 365 }
        } else {
            for yil in y..<1970 { toplam -= isLeap(yil) ? 366 : 365 }
        }
        for ay in 1..<m { toplam += daysInMonth(year: y, month: ay) }
        return toplam + g - 1
    }

    private static func tarihten(gun: Int) -> DateKey {
        var kalan = gun
        var y = 1970
        while kalan < 0 { y -= 1; kalan += isLeap(y) ? 366 : 365 }
        while kalan >= (isLeap(y) ? 366 : 365) { kalan -= isLeap(y) ? 366 : 365; y += 1 }
        var m = 1
        while kalan >= daysInMonth(year: y, month: m) {
            kalan -= daysInMonth(year: y, month: m)
            m += 1
        }
        return key(y, m, kalan + 1)
    }

    public static func displayMonth(_ m: MonthKey) -> String {
        let i = monthNumber(of: m) - 1
        guard i >= 0 && i < 12 else { return m }
        return "\(monthNamesTR[i]) \(year(of: m))"
    }

    /// "Eyl 26"
    public static func displayMonthShort(_ m: MonthKey) -> String {
        let i = monthNumber(of: m) - 1
        guard i >= 0 && i < 12 else { return m }
        return "\(monthNamesShortTR[i]) \(String(year(of: m)).suffix(2))"
    }

    /// "13 Eylül 2026"
    public static func displayDate(_ d: DateKey) -> String {
        let i = monthNumber(of: month(of: d)) - 1
        guard i >= 0 && i < 12 else { return d }
        return "\(day(of: d)) \(monthNamesTR[i]) \(year(of: month(of: d)))"
    }

    /// "13 Eyl"
    public static func displayDateShort(_ d: DateKey) -> String {
        let i = monthNumber(of: month(of: d)) - 1
        guard i >= 0 && i < 12 else { return d }
        return "\(day(of: d)) \(monthNamesShortTR[i])"
    }
}
