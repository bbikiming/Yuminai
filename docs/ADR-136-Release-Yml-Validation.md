# ADR-136: release.yml CI Validation 강화

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-123 (Release Distribution), ADR-147 (Theme Lint)

---

## 1. 배경

`release.yml`에서 `swift test`가 실패해도 artifact가 만들어지는 구조적 문제가 있었다. `continue-on-error` 옵션이 build 단계에만 적용되고 test 단계에는 없었지만, 실패 시나리오 테스트가 부족했다.

---

## 2. 결정

### 단계 순서 명확화

```yaml
1. Checkout
2. Setup Swift
3. Cache SPM
4. Theme lint (ADR-147) --warn 모드
5. Build (universal, continue-on-error)
6. Build (arm64 fallback, if universal fails)
7. swift test --parallel   ← 반드시 artifact 전
8. Extract version
9. Build app bundle + DMG
10. Verify DMG
11. Generate release notes
12. Create GitHub Release
```

### Theme lint 추가

ADR-147 lint script를 `--warn` 모드로 실행한다. 위반이 있어도 CI는 계속되지만 Summary에 경고가 기록된다. 미래에 `--warn` 제거로 gate 강화 가능.

---

## 3. 비고

테스트 실패 시 DMG 빌드로 진행되지 않도록 단계 순서로 강제한다. GitHub Actions는 기본적으로 이전 step 실패 시 이후 step을 건너뛴다.

---

## 4. 영향 파일

| 파일 | 변경 |
|------|------|
| `.github/workflows/release.yml` | Theme lint step 추가, 단계 순서 문서화 |
