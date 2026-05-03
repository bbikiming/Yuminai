import Foundation

/// **ADR-088** — OpenAI Codex CLI에서 호출 가능한 모델 enum.
///
/// Codex CLI는 `-m <MODEL>` 옵션으로 모델을 받으며, 자체 model_provider 매핑을 통해
/// OpenAI API 또는 OSS provider로 라우팅한다. 사용자 `~/.codex/config.toml`의
/// `model = "..."` 키와 동일한 string identifier를 사용한다.
///
/// **참조**: `codex --help` 예시 `-c model="o3"` + 사용자 config의 `model = "gpt-5.4"`.
///
/// **OpenAI 모델 식별자는 빠르게 바뀌므로** 이 enum은 자주 쓰이는 7개를 cover하고,
/// 그 외는 `.custom(String)`으로 받는다. 기본값은 `.gpt5` — 가장 신형 + 일반 목적.
public enum CodexModel: Sendable, Codable, Hashable {
    /// GPT-5 (general purpose, default).
    case gpt5
    /// GPT-5 Codex 변형 — 코딩 특화 reasoning.
    case gpt5Codex
    /// o3 — OpenAI 추론 모델 (deep thinking).
    case o3
    /// o3-mini — o3의 빠른 변형.
    case o3Mini
    /// o4-mini — 차세대 추론 (빠름).
    case o4Mini
    /// GPT-4o — multimodal 4세대.
    case gpt4o
    /// GPT-4.1 — 4o의 일반화 변형.
    case gpt41
    /// 사용자 정의 raw string (config.toml에 있거나 신모델이 출시되었을 때).
    /// 예: `.custom("gpt-5.4")`.
    case custom(String)

    /// Codex CLI에 전달할 raw model identifier.
    public var rawIdentifier: String {
        switch self {
        case .gpt5: return "gpt-5"
        case .gpt5Codex: return "gpt-5-codex"
        case .o3: return "o3"
        case .o3Mini: return "o3-mini"
        case .o4Mini: return "o4-mini"
        case .gpt4o: return "gpt-4o"
        case .gpt41: return "gpt-4.1"
        case .custom(let id): return id
        }
    }

    public var displayName: String {
        switch self {
        case .gpt5: return "GPT-5"
        case .gpt5Codex: return "GPT-5 Codex"
        case .o3: return "o3"
        case .o3Mini: return "o3-mini"
        case .o4Mini: return "o4-mini"
        case .gpt4o: return "GPT-4o"
        case .gpt41: return "GPT-4.1"
        case .custom(let id): return id
        }
    }

    public var subtitle: String {
        switch self {
        case .gpt5: return "범용 · 균형 (default)"
        case .gpt5Codex: return "코딩 특화 reasoning"
        case .o3: return "깊은 추론 · 느림"
        case .o3Mini: return "빠른 추론"
        case .o4Mini: return "차세대 reasoning · 빠름"
        case .gpt4o: return "멀티모달 · 안정"
        case .gpt41: return "4o 일반화 변형"
        case .custom: return "사용자 정의"
        }
    }

    /// 1M tokens당 input price (USD, 대략 — 가격은 자주 바뀌므로 참조용).
    public var inputPricePerMillion: Double {
        switch self {
        case .gpt5: return 1.25
        case .gpt5Codex: return 1.25
        case .o3: return 10.0
        case .o3Mini: return 1.10
        case .o4Mini: return 1.10
        case .gpt4o: return 2.50
        case .gpt41: return 2.00
        case .custom: return 0  // 알 수 없음
        }
    }

    public var outputPricePerMillion: Double {
        switch self {
        case .gpt5: return 10.0
        case .gpt5Codex: return 10.0
        case .o3: return 40.0
        case .o3Mini: return 4.40
        case .o4Mini: return 4.40
        case .gpt4o: return 10.0
        case .gpt41: return 8.0
        case .custom: return 0
        }
    }

    /// 대략적인 컨텍스트 윈도우 (token).
    public var contextWindowTokens: Int {
        switch self {
        case .gpt5, .gpt5Codex: return 400_000
        case .o3, .o3Mini, .o4Mini: return 200_000
        case .gpt4o, .gpt41: return 128_000
        case .custom: return 128_000  // 보수적 default
        }
    }

    /// 잘 알려진 모델 목록 (UI picker default 표시용).
    /// `.custom`은 별도 메뉴 항목으로 처리.
    public static let knownCases: [CodexModel] = [
        .gpt5, .gpt5Codex, .o4Mini, .o3, .o3Mini, .gpt4o, .gpt41
    ]

    public static let `default`: CodexModel = .gpt5

    // MARK: - Codable (custom case 보존)

    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    private enum Kind: String, Codable {
        case gpt5, gpt5Codex, o3, o3Mini, o4Mini, gpt4o, gpt41, custom
    }

    public init(from decoder: Decoder) throws {
        // 두 형식 지원:
        // 1. 신규: { "kind": "gpt5" } 또는 { "kind": "custom", "value": "gpt-5.4" }
        // 2. 옛/string: 직접 string ("gpt-5", "o3", "gpt-5.4" 등) → 매칭되면 known case, 아니면 .custom
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            self = CodexModel.fromRawIdentifier(single)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .gpt5: self = .gpt5
        case .gpt5Codex: self = .gpt5Codex
        case .o3: self = .o3
        case .o3Mini: self = .o3Mini
        case .o4Mini: self = .o4Mini
        case .gpt4o: self = .gpt4o
        case .gpt41: self = .gpt41
        case .custom:
            let v = try c.decode(String.self, forKey: .value)
            self = .custom(v)
        }
    }

    public func encode(to encoder: Encoder) throws {
        // 단순 string으로 인코딩 — config 호환성 + 가독성
        var c = encoder.singleValueContainer()
        try c.encode(rawIdentifier)
    }

    /// raw identifier로부터 enum 복원. 매칭 안 되면 `.custom(raw)`.
    public static func fromRawIdentifier(_ raw: String) -> CodexModel {
        for known in knownCases where known.rawIdentifier == raw {
            return known
        }
        return .custom(raw)
    }
}
