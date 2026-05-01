# Security (Yuminai)

> 본인 1인 사용 / unsigned. 그래도 보안 위생은 동일하게 적용.

## 시크릿 저장: Keychain Only

```swift
import Security

public struct KeychainStore: Sendable {
    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yuminai",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)  // upsert
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw YuminaiError.keychainWriteFailed(status: status) }
    }
    
    public func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yuminai",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw YuminaiError.keychainReadFailed(status: status)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
```

저장 키 규칙:
- `anthropic_api_key`
- `telegram_bot_token`
- `obsidian_vault_path` (경로는 시크릿이 아니지만 location protection 위해)
- `mcp_server_*_token`

## 절대 금지

- `UserDefaults`에 시크릿
- `Info.plist`에 API key
- `.env` 파일 (Yuminai는 .env 사용 안 함)
- 코드에 하드코딩
- 로그/에러 메시지에 시크릿 노출
- 시크릿을 일반 Sendable struct에 평문으로 보관 (메모리 덤프 위험)

## 입력 검증 (시스템 경계)

| 경계 | 검증 |
|------|------|
| 사용자 입력 (채팅창) | 길이 제한 (예: 1MB), 기본 sanitize는 Claude에 위임 |
| Vault 파일 경로 | symlink resolve 후 root 외부 차단 |
| Telegram bot 명령 | 화이트리스트(allowed user IDs)만 응답 |
| MCP 서버 응답 | JSON schema validation |
| 외부 URL | scheme 화이트리스트 (`https`, `obsidian://`, `claude://`) |

## Path Traversal 방어

```swift
public func resolveSafePath(_ relative: String, in root: URL) throws -> URL {
    let resolved = root.appending(path: relative).standardized.resolvingSymlinksInPath()
    guard resolved.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)) else {
        throw YuminaiError.pathTraversalAttempted(relative: relative)
    }
    return resolved
}
```

## Process Spawning 보안

- `Process.executableURL`만 사용 (shell 호출 금지)
- 사용자 입력을 인자에 직접 넣지 말 것 (경로 escape는 OK, 명령 합성 X)
- stdin으로 보내는 텍스트는 그대로 OK (Claude가 처리)

## 외부 통신

- HTTPS only (ATS 강제)
- 인증서 핀닝은 MVP에선 생략 (Telegram/Anthropic 신뢰)
- 모든 응답은 길이 제한 (예: 10MB) — DoS 방어

## 로깅

```swift
import os

let log = Logger(subsystem: "com.yuminai", category: "claude-adapter")

// GOOD
log.info("Claude spawned for workspace \(workspace.id, privacy: .public)")

// BAD - 시크릿 노출
log.info("API key: \(apiKey)")  // ABSOLUTELY NOT
```

`Logger`의 `privacy` 라벨 활용. 기본은 `.private` (Console.app에서 마스킹됨).

## 의존성 보안

- 외부 의존성 추가 시:
  - GitHub stars / 활동 / 최근 커밋 확인
  - License 호환성 (MIT, Apache 2.0 OK)
  - SPM `Package.resolved` 커밋
- `swift package show-dependencies`로 트랜시티브 검토

## App Sandbox 결정

| 옵션 | 장점 | 단점 |
|------|------|------|
| Sandbox OFF | Process spawn 자유로움, 단순 | OS 보호 약함 |
| Sandbox ON + 임시 예외 | OS 보호 유지 | 복잡, 일부 케이스 실패 |

**결정**: 본인 사용 + Process spawn 핵심이므로 **Sandbox OFF**. Hardened Runtime은 켜되 일부 entitlement 허용:
- `com.apple.security.cs.allow-jit` (필요 시)
- `com.apple.security.cs.disable-library-validation` (SwiftTerm 등 동적 로딩)
- `com.apple.security.cs.allow-unsigned-executable-memory` (피해야 함)

## 정기 점검 체크리스트

월 1회 / 의존성 업데이트 시:
- [ ] Keychain 항목 정리 (사용 안 하는 키 삭제)
- [ ] `Package.resolved` 변경 검토
- [ ] log 출력에서 시크릿 노출 grep (`grep -r "api_key\|token\|password" .build/`)
- [ ] entitlements 변경 검토
