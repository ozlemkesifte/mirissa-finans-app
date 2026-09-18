import Foundation

/// Sonradan eklenen ayarlar. Hepsi isteğe bağlıdır; boşken hiçbir hesap değişmez.
public struct EkAyarlar: Codable, Hashable, Sendable {
    // Yedek
    /// Yedeğin telefon dışına en son kaydedildiği (paylaşıldığı) gün
    public var sonYedekPaylasim: DateKey?
    /// Otomatik yedeğin en son alındığı gün
    public var sonOtomatikYedek: DateKey?

    // Vergi karşılığı
    /// "sahis" (gelir vergisi) ya da "sirket" (kurumlar vergisi)
    public var vergiTuru: String?
    /// Muhasebecinin söylediği yaklaşık oran (%). Girilmemişse vergi tahmini yapılmaz.
    public var vergiOrani: Double?

    // Nakit
    /// Kasa + banka bakiyesi ve girildiği gün
    public var kasaBakiye: Kurus?
    public var kasaTarih: DateKey?
    /// Kanal → satıştan kaç gün sonra para hesaba geçiyor (hakediş gecikmesi)
    public var hakedisGecikmesi: [Id: Int]?

    // Kilit
    /// KDV beyanı verilip kilitlenen aylar: bu aylara ait kayıt değiştirilemez
    public var kilitliAylar: [MonthKey]?

    // Hatırlatma
    public var hatirlatmalarAcik: Bool?

    public init() {}

    public var kilitli: Set<MonthKey> { Set(kilitliAylar ?? []) }
    public func gecikme(_ kanal: Id) -> Int { hakedisGecikmesi?[kanal] ?? 0 }
}

/// Değişiklik günlüğü satırı
public struct ChangeLogEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Tur: String, Codable, Sendable { case eklendi, degisti, silindi, geriYuklendi }
    public var id: Id
    public var zaman: String
    public var tur: Tur
    public var alan: String
    public var aciklama: String

    public init(id: Id = UUID().uuidString, zaman: String, tur: Tur, alan: String, aciklama: String) {
        self.id = id
        self.zaman = zaman
        self.tur = tur
        self.alan = alan
        self.aciklama = aciklama
    }
}
