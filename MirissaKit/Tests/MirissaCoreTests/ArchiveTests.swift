import Testing
import Foundation
@testable import MirissaCore

@Suite("Satıştan kaldırma (arşiv)")
@MainActor
struct ArchiveTests {
    @Test func arsivlenenUrununGecmisiVeRaporlariKalir() {
        let st = AppStore.inMemory(Golden.senaryo())
        let urun = st.state.products[0].id
        let once = st.engine.companyMonth("2026-09")
        let satisSayisi = st.state.sales.count
        st.setProductArchived(urun, true)
        #expect(st.state.sales.count == satisSayisi)
        #expect(st.engine.companyMonth("2026-09").gercekKar == once.gercekKar)
        #expect(!st.state.activeProducts.contains { $0.id == urun })
        st.setProductArchived(urun, false)
        #expect(st.state.activeProducts.contains { $0.id == urun })
    }

    @Test func kapatilanKanalinGecmisiKalir() {
        let st = AppStore.inMemory(Golden.senaryo())
        let kanal = st.state.channels[0].id
        let once = st.engine.companyMonth("2026-09").gercekKar
        st.setChannelArchived(kanal, true)
        #expect(st.engine.companyMonth("2026-09").gercekKar == once)
        #expect(!st.state.activeChannels.contains { $0.id == kanal })
    }
}
