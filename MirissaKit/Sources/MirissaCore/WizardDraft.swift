import Foundation

/// Uzun soru-cevap akışları yarıda kalabilir. Verilen cevaplar yalnızca
/// bellekte tutulmaz: her adımda diske yazılır, uygulama kapansa ve telefon
/// yeniden başlasa bile kaldığı yerden devam edilir.
public enum WizardKind: String, Codable, CaseIterable, Sendable, Hashable {
    case ilkKurulum
    case kanalKurulumu
    case fiyatGuncelleme
    case yeniIslem
    case stokKurulumu

    public var displayName: String {
        switch self {
        case .ilkKurulum: return "İlk kurulum"
        case .kanalKurulumu: return "Satış kanalı kurulumu"
        case .fiyatGuncelleme: return "Fiyat güncelleme"
        case .yeniIslem: return "Yeni işlem"
        case .stokKurulumu: return "Stok kurulumu"
        }
    }
}

/// Yarım kalmış bir akışın kaydı.
/// `payload` akışın kendi durumunun JSON'u — her akış kendi alanlarını saklar.
public struct WizardDraft: Codable, Identifiable, Hashable, Sendable {
    public var kind: WizardKind
    /// Hangi kanal / hangi ürün / hangi işlem türü. Akışlar birbirini ezmesin diye.
    public var subjectId: Id?
    /// "Trendyol kurulumu" gibi kullanıcıya gösterilecek ad
    public var title: String
    /// Tamamlanan adım sırası (1'den başlar)
    public var step: Int
    public var totalSteps: Int
    public var updatedAt: DateKey
    public var payload: Data

    public var id: String { "\(kind.rawValue)#\(subjectId ?? "-")" }

    public var progressLabel: String {
        totalSteps > 0 ? "\(step)/\(totalSteps) adım tamamlandı" : "\(step). adımda kaldı"
    }

    public init(kind: WizardKind, subjectId: Id? = nil, title: String,
                step: Int, totalSteps: Int,
                updatedAt: DateKey = Dates.today(), payload: Data) {
        self.kind = kind
        self.subjectId = subjectId
        self.title = title
        self.step = step
        self.totalSteps = totalSteps
        self.updatedAt = updatedAt
        self.payload = payload
    }

    /// Akışın kendi durumunu taslağa yazar.
    public static func make<T: Encodable>(
        kind: WizardKind, subjectId: Id? = nil, title: String,
        step: Int, totalSteps: Int, updatedAt: DateKey = Dates.today(), state: T
    ) -> WizardDraft? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return WizardDraft(kind: kind, subjectId: subjectId, title: title,
                           step: step, totalSteps: totalSteps,
                           updatedAt: updatedAt, payload: data)
    }

    /// Taslaktaki cevapları geri okur. Akışın alanları değiştiyse `nil` döner
    /// ve akış baştan başlar — bozuk veriyle açılmaz.
    public func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: payload)
    }
}
