# ADR-147: SwiftUI Theme Lint Script

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-137 (Color Token Migration)

---

## 1. 배경

ADR-137에서 Color 리터럴을 Theme 토큰으로 교체했지만, 미래에 새 코드가 다시 `Color.orange` 등 하드코딩 색상을 사용할 위험이 있다. 이를 CI에서 자동으로 감지하는 lint가 필요하다.

---

## 2. 결정

`scripts/lint-theme.sh`를 신설한다.

### 감지 대상

**1. Color literal** — 허용 목록 외 직접 색상 사용:

- 차단: `Color.orange`, `Color.red`, `Color.green`, `Color.blue`, `Color.yellow`, `Color.purple`, `Color.pink`, `Color.teal`
- 허용: `Color.clear`, `Color.white`, `Color.black`, `Color.primary`, `Color.secondary`, `Color.accentColor`
- SwiftUI 단축형 `.orange` (불완전 표기)는 감지 안 함 — `Color.orange` 형태만 차단

**2. 하드코딩 .cornerRadius(<숫자>)** — `Theme.Radius.*` 토큰 미사용

**3. 하드코딩 .padding(<큰 숫자>)** — 10 이상 숫자, 0/1/2/0.5/1.5는 미세 조정값으로 허용

### 예외 파일 (정의처)

```
Theme.swift, SharedComponents.swift, PolishedComponents.swift,
FlatComponents.swift, SheetFrame.swift, CategoryColors.swift,
AutoRunCommandExtractor.swift
```

### 실행 모드

```bash
./scripts/lint-theme.sh         # 위반 시 exit 1 (CI 차단)
./scripts/lint-theme.sh --warn  # 위반 시 exit 0 (경고만, 현재 CI 모드)
```

---

## 3. CI 통합

`release.yml`의 Build 단계 직전에 실행:

```yaml
- name: Theme lint (ADR-147)
  run: |
    chmod +x scripts/lint-theme.sh
    bash scripts/lint-theme.sh --warn
```

현재는 `--warn` 모드. 미래에 `--warn` 제거로 gate 강화 가능.

---

## 4. 초기 실행 결과

- ADR-137 마이그레이션 완료 후: 0 violations
- Radius: 0, Padding: 0

---

## 5. 영향 파일

| 파일 | 변경 |
|------|------|
| `scripts/lint-theme.sh` | 신규 (실행 권한 포함) |
| `.github/workflows/release.yml` | Theme lint step 추가 |
