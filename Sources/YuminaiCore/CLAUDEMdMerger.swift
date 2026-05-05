import Foundation

/// **ADR-108** — `CLAUDE.md` 파일의 Yuminai 프로필 섹션을 안전하게 merge한다.
///
/// Claude Code는 `<workspace>/CLAUDE.md`를 자동으로 읽는다 (Anthropic 공식 동작).
/// Yuminai는 이 파일의 begin/end marker 사이만 관리하고, 나머지는 사용자가 자유롭게 편집할 수 있다.
///
/// 정책:
/// - 파일이 없으면 marker + section만 새로 작성
/// - 파일에 marker가 없으면 끝에 append
/// - 파일에 marker가 있으면 그 사이만 replace (나머지 내용 보존)
/// - profileSection이 비어있으면 marker 자체를 제거 (프로필 삭제 시)
public enum CLAUDEMdMerger {

    public static let beginMarker = "<!-- BEGIN YUMINAI USER PROFILE -->"
    public static let endMarker   = "<!-- END YUMINAI USER PROFILE -->"

    /// 기존 CLAUDE.md 내용에서 Yuminai marker 사이만 replace.
    /// - Parameters:
    ///   - existing: 기존 파일 내용 (nil이면 새 파일).
    ///   - profileSection: marker 안에 들어갈 본문 (`renderForCLAUDEMd()` 결과).
    ///                     빈 문자열이면 marker 자체를 제거한다.
    /// - Returns: 병합된 최종 문자열.
    public static func merge(existing: String?, profileSection: String) -> String {
        let current = existing ?? ""
        let trimmed = profileSection.trimmingCharacters(in: .whitespacesAndNewlines)

        // profileSection이 비어있으면 marker 블록 제거
        if trimmed.isEmpty {
            return removeMarkerBlock(from: current)
        }

        let block = buildBlock(profileSection: trimmed)

        // marker가 이미 있으면 그 사이만 교체
        if let range = markerRange(in: current) {
            var result = current
            result.replaceSubrange(range, with: block)
            return result
        }

        // marker 없으면 끝에 append
        if current.isEmpty {
            return block
        }
        // 앞 내용이 있으면 빈 줄 하나 추가 후 append
        let separator = current.hasSuffix("\n\n") ? "" : current.hasSuffix("\n") ? "\n" : "\n\n"
        return current + separator + block
    }

    // MARK: - Private

    /// begin ~ end marker를 포함한 문자열 범위. 없으면 nil.
    private static func markerRange(in text: String) -> Range<String.Index>? {
        guard let beginRange = text.range(of: beginMarker),
              let endRange   = text.range(of: endMarker),
              beginRange.lowerBound < endRange.lowerBound
        else { return nil }
        return beginRange.lowerBound..<endRange.upperBound
    }

    /// marker 블록 제거. marker 바로 앞뒤 공백 정리.
    private static func removeMarkerBlock(from text: String) -> String {
        guard let range = markerRange(in: text) else { return text }

        var result = text
        // marker 블록 삭제
        result.removeSubrange(range)

        // 앞뒤 공백/개행 정리 (marker 삭제 후 남은 연속 빈 줄 최대 1개로)
        var cleaned = result
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// profileSection을 begin/end marker로 감싼 완성 블록 생성.
    private static func buildBlock(profileSection: String) -> String {
        return """
        \(beginMarker)
        \(profileSection)
        \(endMarker)
        """
    }
}
