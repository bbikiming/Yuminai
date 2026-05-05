import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-108** — CLAUDEMdMerger: begin/end marker 기반 CLAUDE.md 안전 merge 검증.
@Suite("CLAUDEMdMerger (ADR-108)")
struct CLAUDEMdMergerTests {

    // MARK: - 상수

    let begin = CLAUDEMdMerger.beginMarker
    let end   = CLAUDEMdMerger.endMarker

    // MARK: - existing == nil (새 파일)

    @Test("existing nil + profileSection 있음 → marker + section만 출력")
    func nilExistingWithSection() {
        let result = CLAUDEMdMerger.merge(existing: nil, profileSection: "## 프로필\n- 이름: 김유민")
        #expect(result.contains(CLAUDEMdMerger.beginMarker))
        #expect(result.contains(CLAUDEMdMerger.endMarker))
        #expect(result.contains("## 프로필"))
        #expect(result.contains("김유민"))
    }

    @Test("existing nil + profileSection 비어있음 → 빈 문자열 반환")
    func nilExistingEmptySection() {
        let result = CLAUDEMdMerger.merge(existing: nil, profileSection: "")
        #expect(result.isEmpty || !result.contains(CLAUDEMdMerger.beginMarker))
    }

    // MARK: - existing 있고 marker 없음

    @Test("기존 내용 있고 marker 없음 → 끝에 append")
    func noMarkerAppendsToEnd() {
        let existing = "# 내 CLAUDE.md\n\n프로젝트 규칙이에요."
        let result = CLAUDEMdMerger.merge(existing: existing, profileSection: "## 프로필\n내용")
        // 기존 내용 보존
        #expect(result.contains("내 CLAUDE.md"))
        #expect(result.contains("프로젝트 규칙이에요."))
        // marker + section 추가
        #expect(result.contains(CLAUDEMdMerger.beginMarker))
        #expect(result.contains(CLAUDEMdMerger.endMarker))
        #expect(result.contains("## 프로필"))
        // 기존 내용이 marker 앞에 위치
        let beginIdx = result.range(of: CLAUDEMdMerger.beginMarker)!.lowerBound
        let existingIdx = result.range(of: "내 CLAUDE.md")!.lowerBound
        #expect(existingIdx < beginIdx)
    }

    @Test("기존 내용이 빈 문자열이고 marker 없음 → marker만 출력")
    func emptyExistingNoMarker() {
        let result = CLAUDEMdMerger.merge(existing: "", profileSection: "내용")
        #expect(result.contains(CLAUDEMdMerger.beginMarker))
        #expect(result.contains("내용"))
    }

    // MARK: - marker 있을 때 replace

    @Test("marker 있음 → 그 사이만 교체, 앞뒤 내용 보존")
    func existingMarkerIsReplaced() {
        let existing = """
        # 내 규칙

        첫 번째 내용

        \(CLAUDEMdMerger.beginMarker)
        ## 사용자 프로필
        - 이름: 구버전
        \(CLAUDEMdMerger.endMarker)

        마지막 내용
        """
        let result = CLAUDEMdMerger.merge(existing: existing, profileSection: "## 사용자 프로필\n- 이름: 신버전")
        // 앞뒤 내용 보존
        #expect(result.contains("내 규칙"))
        #expect(result.contains("첫 번째 내용"))
        #expect(result.contains("마지막 내용"))
        // 새 내용 반영
        #expect(result.contains("신버전"))
        // 구 내용 대체됨
        #expect(!result.contains("구버전"))
        // marker 한 쌍만 존재
        let beginCount = result.components(separatedBy: CLAUDEMdMerger.beginMarker).count - 1
        let endCount   = result.components(separatedBy: CLAUDEMdMerger.endMarker).count - 1
        #expect(beginCount == 1)
        #expect(endCount == 1)
    }

    @Test("marker 교체 후 기존 앞 내용이 marker보다 앞에 위치")
    func markerReplacementPreservesOrder() {
        let existing = """
        # 앞 내용
        \(CLAUDEMdMerger.beginMarker)
        이전 섹션
        \(CLAUDEMdMerger.endMarker)
        # 뒤 내용
        """
        let result = CLAUDEMdMerger.merge(existing: existing, profileSection: "새 섹션")
        let frontIdx  = result.range(of: "앞 내용")!.lowerBound
        let markerIdx = result.range(of: CLAUDEMdMerger.beginMarker)!.lowerBound
        let backIdx   = result.range(of: "뒤 내용")!.lowerBound
        #expect(frontIdx < markerIdx)
        #expect(markerIdx < backIdx)
    }

    // MARK: - profileSection 비어있을 때 marker 제거

    @Test("profileSection 비어있음 + marker 있음 → marker 블록 제거")
    func emptyProfileSectionRemovesMarker() {
        let existing = """
        # 앞
        \(CLAUDEMdMerger.beginMarker)
        ## 사용자 프로필
        \(CLAUDEMdMerger.endMarker)
        # 뒤
        """
        let result = CLAUDEMdMerger.merge(existing: existing, profileSection: "")
        #expect(!result.contains(CLAUDEMdMerger.beginMarker))
        #expect(!result.contains(CLAUDEMdMerger.endMarker))
        // 앞뒤 내용은 보존
        #expect(result.contains("앞"))
        #expect(result.contains("뒤"))
    }

    @Test("profileSection 공백만 있음 + marker 있음 → marker 블록 제거")
    func whitespaceOnlyProfileSectionRemovesMarker() {
        let existing = "\(CLAUDEMdMerger.beginMarker)\n내용\n\(CLAUDEMdMerger.endMarker)"
        let result = CLAUDEMdMerger.merge(existing: existing, profileSection: "   \n\t  ")
        #expect(!result.contains(CLAUDEMdMerger.beginMarker))
    }

    // MARK: - 다른 내용 보존 통합 테스트

    @Test("복잡한 기존 CLAUDE.md — 사용자 규칙과 marker 섹션 독립적으로 보존/갱신")
    func complexFilePreservesUserContent() {
        let existing = """
        # 프로젝트 규칙

        ## 코딩 스타일
        - 들여쓰기: 4 스페이스
        - 최대 줄 길이: 120

        \(CLAUDEMdMerger.beginMarker)
        ## 사용자 프로필
        - 이름: 이전 이름
        \(CLAUDEMdMerger.endMarker)

        ## 금지 사항
        - git push --force 금지
        """
        let newSection = "## 사용자 프로필\n- 이름: 새로운 이름\n- 직업: iOS 개발자"
        let result = CLAUDEMdMerger.merge(existing: existing, profileSection: newSection)

        // 사용자 규칙 보존
        #expect(result.contains("코딩 스타일"))
        #expect(result.contains("들여쓰기: 4 스페이스"))
        #expect(result.contains("금지 사항"))
        #expect(result.contains("git push --force 금지"))

        // 새 프로필 반영
        #expect(result.contains("새로운 이름"))
        #expect(result.contains("iOS 개발자"))

        // 이전 프로필 제거
        #expect(!result.contains("이전 이름"))
    }

    // MARK: - 마커 상수 확인

    @Test("beginMarker와 endMarker가 다름")
    func markersAreDifferent() {
        #expect(CLAUDEMdMerger.beginMarker != CLAUDEMdMerger.endMarker)
    }

    @Test("markers는 HTML 주석 형식")
    func markersAreHTMLComments() {
        #expect(CLAUDEMdMerger.beginMarker.hasPrefix("<!--"))
        #expect(CLAUDEMdMerger.endMarker.hasPrefix("<!--"))
    }
}
