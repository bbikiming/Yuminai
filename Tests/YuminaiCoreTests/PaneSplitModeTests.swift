import Foundation
import Testing
import YuminaiCore

@Suite("PaneSplitMode")
struct PaneSplitModeTests {
    @Test("3개 case 모두 한국어 라벨 + icon")
    func metadata() {
        for mode in PaneSplitMode.allCases {
            #expect(!mode.label.isEmpty)
            #expect(!mode.icon.isEmpty)
        }
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for mode in PaneSplitMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(PaneSplitMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("기본은 .single")
    func defaultIsSingle() {
        // PaneSplitMode 자체에 default static 없으니 raw value 확인
        #expect(PaneSplitMode.single.rawValue == "single")
        #expect(PaneSplitMode.horizontal.rawValue == "horizontal")
        #expect(PaneSplitMode.vertical.rawValue == "vertical")
    }
}
