import SwiftUI

/// `MessageInputView`는 v3에서 `Composer`로 대체됨. Backwards-compat shim 한정 — 새 코드는 사용 금지.
///
/// 새 진입점: `Composer` (Composer.swift)
@available(*, deprecated, renamed: "Composer", message: "Composer를 사용하세요 (모델/모드/효과 picker, send/stop, git meta 통합)")
public struct MessageInputView: View {
    @Binding public var text: String
    public let isStreaming: Bool
    public let placeholder: String
    public let onSend: () -> Void
    public let onCancel: () -> Void

    public init(
        text: Binding<String>,
        isStreaming: Bool,
        placeholder: String = "메시지 입력",
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.placeholder = placeholder
        self.onSend = onSend
        self.onCancel = onCancel
    }

    public var body: some View {
        // 단순 fallback 입력 (테스트/프리뷰용)
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .padding()
    }
}
