# ADR-135: AutoRun Log Viewer Sheet

**날짜**: 2026-05-08  
**상태**: Accepted  
**연관**: ADR-132 (AutoRun 모드), ADR-134 (CommandPolicy Wire-up)

---

## 1. 배경

AutoRun이 완료된 뒤 사용자가 어떤 LLM 응답이 오고, 어떤 명령이 감지되고, 어떤 경고가 발생했는지 볼 방법이 없었다. `.harness/auto-run-log/<run-id>.jsonl` 파일이 생성되지만 UI가 없었다.

---

## 2. 결정

`AutoRunLogViewerSheet`를 신설한다.

### 레이아웃

```
┌─ 실행 목록 (240pt) ──────┬─ 턴 로그 상세 ────────────────────┐
│ Run #1  3턴  종료        │  [Turn 1] 2026-05-08 21:10:03      │
│ Run #2  7턴  실행 중     │  Prompt: <initial prompt>          │
│ ...                     │  Response: <first 200 chars>...    │
│                         │  Commands: git status              │
│                         │  Warnings: -                       │
└─────────────────────────┴────────────────────────────────────┘
                          [재현]  [닫기]
```

### 데이터 소스

- 현재 선택된 workspace의 `.harness/auto-run-log/` 디렉토리 탐색
- 각 `.jsonl` 파일 → `AutoRunTurnLog` 배열로 파싱 (JSONDecoder)
- 최신 20개 run만 표시

### 재현 기능

"재현" 버튼: 해당 run의 `initialPrompt`로 `AppModel.startAutoRun()` 재호출.

---

## 3. 진입점

`AutoRunControlSheet` 푸터에 "로그 이력" 버튼 추가 → `AppModel.showAutoRunLogViewerSheet = true`.

---

## 4. 영향 파일

| 파일 | 변경 |
|------|------|
| `Sources/YuminaiApp/AutoRunLogViewerSheet.swift` | 신규 |
| `Sources/YuminaiApp/AppModel.swift` | `showAutoRunLogViewerSheet` 추가 |
| `Sources/YuminaiApp/AutoRunControlSheet.swift` | "로그 이력" 버튼 추가 |
| `Sources/YuminaiApp/RootView.swift` | sheet 등록 |
