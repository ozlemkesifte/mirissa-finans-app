import Testing
import Foundation
@testable import MirissaCore
@testable import MirissaUI

/// Sihirbaz bir sonraki ürüne geçtiğinde SwiftUI aynı giriş alanını yeniden
/// kullanır. Alan kendi metnini koruduğu için önceki cevap ekranda kalıyordu:
/// 1. ürüne 5 TL yazınca 2. üründe de 5 TL görünüyordu.
/// Bağlı değer değiştiğinde metnin tazelenme kuralı burada test edilir.
@Suite("Giriş alanı tazeleme")
struct FieldSyncTests {

    private func tl(_ v: Double) -> Kurus { Money.fromTL(v) }

    // MARK: Sıradaki kayda geçiş

    @Test func sonrakiUruneGecincAlanBosalir() {
        // 1. ürüne 5 TL yazıldı, 2. ürünün maliyeti henüz boş (0)
        let taze = NumberInput.senkron(metin: "5", kurus: 0)
        #expect(taze == "")
    }

    @Test func geriGelincEskiCevapGeriGelir() {
        // 2. üründen 1. ürüne dönüldü: alan 5 TL'yi yeniden göstermeli
        let taze = NumberInput.senkron(metin: "", kurus: tl(5))
        #expect(taze == "5")
    }

    @Test func farkliUrunFarkliRakamGosterir() {
        // Ekranda 5 yazarken 12 TL'lik kayda geçildi
        #expect(NumberInput.senkron(metin: "5", kurus: tl(12)) == "12")
    }

    // MARK: Yazarken bozulmama

    @Test func kullaniciYazarkenMetneDokunulmaz() {
        // Yazılan metin bağlı değerle aynı sayıyı gösteriyorsa müdahale yok
        #expect(NumberInput.senkron(metin: "5", kurus: tl(5)) == nil)
        #expect(NumberInput.senkron(metin: "1.250", kurus: tl(1250)) == nil)
        #expect(NumberInput.senkron(metin: "", kurus: 0) == nil)
    }

    @Test func yarimOndalikYazimBozulmaz() {
        // "5," yazılırken alan sıfırlanmamalı
        #expect(NumberInput.senkron(metin: "5,", kurus: tl(5)) == nil)
        #expect(NumberInput.senkron(metin: "12,5", kurus: tl(12.5)) == nil)
    }

    // MARK: Miktar alanı

    @Test func miktarAlaniDaTazelenir() {
        #expect(NumberInput.senkron(metin: "500", deger: 0) == "")
        #expect(NumberInput.senkron(metin: "500", deger: 300) == "300")
        #expect(NumberInput.senkron(metin: "500", deger: 500) == nil)
    }

    // MARK: Boş bırakılabilen alanlar

    @Test func opsiyonelAlanBosaDonebilir() {
        #expect(NumberInput.senkron(metin: "120", opsiyonelKurus: nil) == "")
        #expect(NumberInput.senkron(metin: "", opsiyonelKurus: tl(120)) == "120")
        #expect(NumberInput.senkron(metin: "120", opsiyonelKurus: tl(120)) == nil)
        #expect(NumberInput.senkron(metin: "", opsiyonelKurus: nil) == nil)
    }

    @Test func opsiyonelSayiAlani() {
        #expect(NumberInput.senkron(metin: "3", opsiyonel: nil) == "")
        #expect(NumberInput.senkron(metin: "", opsiyonel: 3) == "3")
        #expect(NumberInput.senkron(metin: "3", opsiyonel: 3) == nil)
    }

    // MARK: Sıfır ile boş aynı şey değil

    @Test func sifirDegerAlaniBosBirakir() {
        // Sıfır maliyet "0" yazmak yerine boş görünür — kullanıcı yeni rakam yazar
        #expect(NumberInput.senkron(metin: "5", kurus: 0) == "")
        #expect(NumberInput.senkron(metin: "5", deger: 0) == "")
    }
}
