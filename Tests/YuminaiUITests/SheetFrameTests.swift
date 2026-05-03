import Foundation
import Testing
@testable import YuminaiUI

@Suite("YuminaiSheetFrame (ADR-073)")
struct SheetFrameTests {
    @Test("absoluteMinWidth — 작은 모니터(960×640) 기준")
    func absoluteMinWidth() {
        // 960px 보조 모니터에서 sheet 1개 + 메인 윈도우 1개 가능해야
        #expect(YuminaiSheetFrameModifier.absoluteMinWidth <= 460)
        // 너무 작으면 컨텐츠 가독성 문제
        #expect(YuminaiSheetFrameModifier.absoluteMinWidth >= 320)
    }

    @Test("absoluteMinHeight — 짧은 노트북 화면 기준")
    func absoluteMinHeight() {
        // dock + menubar 빼고 noteobook (1280x800)에서 표시 가능
        #expect(YuminaiSheetFrameModifier.absoluteMinHeight <= 400)
        #expect(YuminaiSheetFrameModifier.absoluteMinHeight >= 200)
    }

    @Test("modifier 생성 — 큰 sheet (CreateWorkspace 580×640)")
    func largeModifierConstruction() {
        let modifier = YuminaiSheetFrameModifier(
            idealWidth: 580,
            idealHeight: 640,
            wrapInScrollView: false  // 내부에 ScrollView 있는 sheet
        )
        #expect(modifier.idealWidth == 580)
        #expect(modifier.idealHeight == 640)
        #expect(modifier.wrapInScrollView == false)
    }

    @Test("modifier 생성 — 짧은 sheet (FileNameSheet 440×220)")
    func smallModifierConstruction() {
        let modifier = YuminaiSheetFrameModifier(
            idealWidth: 440,
            idealHeight: 220,
            wrapInScrollView: false
        )
        // 짧은 sheet도 같은 absoluteMin 적용
        #expect(modifier.idealWidth == 440)
        #expect(modifier.idealHeight == 220)
    }
}
