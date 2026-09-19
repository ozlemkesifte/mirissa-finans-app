import Testing
@testable import MirissaUI
@testable import MirissaCore
import MirissaTestSupport

@Suite("Sayı okuma")
struct NumberParseTests {
    @Test func miktarVeYuzdeTekNoktaOndaliktir() {
        #expect(NumberInput.parse("0.125") == 0.125)
        #expect(NumberInput.parse("2.500") == 2.5)
        #expect(NumberInput.parse("12,5") == 12.5)
        #expect(NumberInput.parse("0,125") == 0.125)
        #expect(NumberInput.parse("1.234.567") == 1_234_567)
        #expect(NumberInput.parse("1.234,5") == 1_234.5)
    }

    @Test func paradaNoktaBinliktir() {
        #expect(NumberInput.kurus("5.000") == tl(5_000))
        #expect(NumberInput.kurus("5.000,50") == 500_050)
        #expect(NumberInput.kurus("0.50") == 50)
        #expect(NumberInput.kurus("12,50") == 1_250)
        #expect(NumberInput.kurus("1.250") == tl(1_250))
    }
}
