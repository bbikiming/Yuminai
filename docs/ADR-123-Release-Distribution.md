# ADR-123 — DMG 배포 + GitHub Releases 자동화

- **날짜**: 2026-05-05 (Tuesday)
- **상태**: Accepted (구현 완료)
- **선행 ADR**: ADR-068/069 (build_app_bundle.sh)

---

## 배경

Yuminai를 다른 사용자에게 배포하기 위한 표준 흐름이 없었음:
- DMG는 build_app_bundle.sh로 만들 수 있으나 수동
- GitHub Releases와 연결되지 않음
- 버전 번호 관리 (semantic versioning) 없음
- 사용자 안내문 (Gatekeeper 우회 방법 등) 없음

## 결정

3가지 산출물:

1. **`.github/workflows/release.yml`** — GitHub Actions로 tag push 시 자동 빌드 + Release 생성
2. **`App/release.sh`** — 로컬 release helper (인터랙티브 + 자동화)
3. **사용자 설치 안내** — release notes 자동 생성에 포함

## 1. GitHub Actions Workflow

`.github/workflows/release.yml`:

**트리거:**
- `v*.*.*` 형식 태그 push (예: `git tag v1.0.0 && git push origin v1.0.0`)
- 또는 GitHub UI에서 manual trigger (workflow_dispatch)

**단계:**
1. `actions/checkout@v4` (full history)
2. `swift-actions/setup-swift@v2` (Swift 6.0)
3. SPM 캐시 (`actions/cache@v4`)
4. **Universal binary 시도** — `swift build --arch arm64 --arch x86_64`
5. 실패 시 native arch fallback (Metal toolchain 누락 등)
6. `swift test --parallel` (회귀 0 검증)
7. tag에서 버전 추출 → `App/build_app_bundle.sh`의 APP_VERSION 갱신
8. `./App/build_app_bundle.sh --universal --dmg` → 실패 시 `--dmg`만
9. tag 메시지를 release notes로 사용 (없으면 최근 5 커밋 자동)
10. `softprops/action-gh-release@v2`로 Release 생성 + DMG 업로드

**자동 release notes 포함:**
- 설치 방법 (Gatekeeper 우회 안내)
- 의존 도구 (Claude Code 필수, Codex/cokacdir 선택)

## 2. 로컬 release.sh

**`./App/release.sh [버전] [노트]`**:

**Pre-flight:**
- git 저장소 확인
- working tree clean (아니면 사용자 확인)
- 버전 입력 + semantic version 검증
- 중복 태그 체크

**Build + Test:**
- `swift build -c release`
- `swift test --parallel`

**DMG:**
- `App/build_app_bundle.sh`의 APP_VERSION 갱신
- `--dmg` 빌드
- 결과 검증 (`dist/Yuminai-<version>.dmg`)

**Release Notes:**
- 인자로 받거나, 없으면 마지막 태그 이후 git log 자동 추출

**Tag + Push:**
- annotated tag (`-a`) — release notes 포함
- 사용자 선택:
  - `[1]` git push → GitHub Actions가 자동 release
  - `[2]` gh CLI로 직접 release 생성 + DMG 업로드 (로컬 즉시)
  - `[3]` 종료 (수동 처리)

## 3. 사용자 설치 안내 (release notes 자동 포함)

```
## 설치 방법
1. Yuminai-<version>.dmg 다운로드
2. DMG 더블클릭 → Yuminai.app을 Applications 폴더로 드래그
3. 첫 실행 시 우클릭 → 열기 → 열기 (Gatekeeper 우회)
   또는 시스템 설정 → 개인 정보 보호 및 보안 → "차단됨" → 그래도 열기
4. Setup Wizard가 Claude Code / Codex CLI 설치를 안내

## 의존 도구
- Claude Code (필수): curl -fsSL https://claude.ai/install.sh | bash
- Codex CLI (선택): npm i -g @openai/codex
- cokacdir (선택): 텔레그램 봇 빠른 시작
```

## 한계 + 후속

### Universal binary 한계
macOS Sequoia + Xcode 16+ 환경에서 **Metal Toolchain 누락**으로 일부 dependency (SwiftTerm 등) universal 빌드 실패. 해결:
- `xcodebuild -downloadComponent MetalToolchain` (~3GB) 사전 설치
- 또는 GitHub Actions runner에서만 universal 시도 (성공 시)
- 현재는 arm64 only DMG (Apple Silicon 90%+ 시장)

### Code Signing
현재 ad-hoc 서명만 → Gatekeeper 경고. 공식 배포 (App Store / 광범위 배포) 시:
- Apple Developer Program 가입 ($99/년)
- Developer ID Application 인증서로 재서명
- `xcrun notarytool`로 Notarization
- `xcrun stapler`로 staple

이 단계는 별도 ADR (ADR-124 후보)로 분리.

### Auto-update
사용자가 수동 다운로드 → 새 DMG 설치하는 방식. 자동 업데이트는 Sparkle framework 등 통합이 필요. 별도 ADR.

## 즉시 실행 가능한 명령

```bash
# 로컬 즉시 release (인터랙티브)
./App/release.sh

# 또는 직접 버전 지정
./App/release.sh 1.0.0 "초기 릴리스"

# GitHub Actions로 release
git tag -a v1.0.0 -m "초기 릴리스"
git push origin v1.0.0
# → .github/workflows/release.yml 자동 트리거
```

## 검증

- DMG 생성 확인: `dist/Yuminai-1.0.0.dmg` (11MB, arm64)
- release.sh 실행 권한: `chmod +x App/release.sh`
- workflow file: `.github/workflows/release.yml` (validated YAML)
