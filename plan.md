# 計画: KanaKanjiConverter Main API async 化 (B案)

## 目標

`KanaKanjiConverter` の主要 public API を async 化し、バックグラウンドスレッドで安全に動作させる。

## 方針

1. **不必要に非同期にしない** — 同期で十分な箇所は async にしない
2. **状態を持たないものは struct Sendable** — 既存の値型はそのまま活かす
3. **状態を持つものは actor にする** — 排他が必要な中心クラスを actor 化
4. **final class はやめる** — struct または actor に移行
5. **必要な箇所のみ MainActor.run を使う** — `UITextChecker` アクセスだけを MainActor に局所化

---

## 変更対象 (Phase 別)

### Phase 1: SpellChecker actor 化

`SpellChecker` は `final class` → **`actor SpellChecker`** に変更。

- iOS / tvOS / visionOS:
  - `UITextChecker` の `@MainActor` プロパティを `actor SpellChecker` 内に保持。
  - `completions(...)` メソッドは内部で `await MainActor.run { ... }` で `UITextChecker` にアクセス。
  - メインスレッドでない場合は非ブロッキング hop、メインスレッドならすぐ実行。
- macOS:
  - `NSSpellChecker` は `MainActor` 不要なのでそのまま。

**ファイル**: `Sources/KanaKanjiConverterModule/ConverterAPI/SpellChecker.swift`

### Phase 2: KanaKanjiConverter async 化

`KanaKanjiConverter` は `final class` → **`actor KanaKanjiConverter`** に変更。

すべての mutable 状態を actor 隔離下に移行:
- `sessions`, `activeSessionID`, `lastData`
- `zenz`, `zenzaiPersonalization`
- `checker` (`actor SpellChecker`)
- `dicdataStoreState`

**async 化する public API**:
- `requestCandidates(_:options:) async -> ConversionResult`
- `predictNextInputText(...) async -> ...`
- `experimentalRequestTypoCorrection(...) async -> [ZenzaiTypoCandidate]`
- `getModel(...) async -> Zenz?`
- `setKeyboardLanguage(_:)` — actor 内では同期呼び出し可能
- `importDynamicUserDictionary(_:shortcuts:)` — 同上
- `updateUserDictionaryURL(_:forceReload:)` — 同上
- `updateLearningConfig(_:)` — 同上
- `setCompletedData(_:)` — 同上
- `updateLearningData(_:)` / `updateLearningData(_:with:)` — 同上
- `commitUpdateLearningData()` — 同上
- `forgetMemory(_:)` — 同上
- `resetMemory()` — 同上
- `stopComposition()` — 同上
- `mergeCandidates(_:_:)` — 同上

**async 化する package API**:
- `requestPostCompositionPredictionCandidates(...)` — 内部で `requestCandidates` を呼ぶ可能性があるため async

**private / internal メソッド**:
- `getForeignPredictionCandidate(...)` → `async` (SpellChecker actor を呼ぶため)
- `getTopLevelAdditionalCandidate(...)` → `async` (上記を呼ぶため)
- `getPredictionCandidate(...)` → `async` (内部で `predictNextInputText` を呼ぶため)
- `processResult(...)` → `async`
- `convertToLattice(...)` → `async` (内部で `getModel` → Zenz actor を呼ぶため)
- `getZenzaiPersonalization(...)` → 同期のまま (actor 内で mutable 状態を触るだけ)
- `withScratchSession(...)` → 同期のまま (actor 内でのみ使う)

**ファイル**: `Sources/KanaKanjiConverterModule/ConverterAPI/KanaKanjiConverter.swift`

### Phase 3: Zenz async 化

`Zenz` は `final class` → **`actor Zenz`** に変更。

- `ZenzContext`（llama.cpp のラッパー、mutable final class）は `actor Zenz` 内に隠蔽。
- async 化メソッド:
  - `candidateEvaluate(...)` → `async -> CandidateEvaluationResult`
  - `predictNextInputText(...)` → `async -> String`
  - `generateTypoCandidates(...)` → `async -> [ZenzaiTypoCandidate]`
  - `endSession()` → 同期のまま (actor 内で mutable 状態をクリアするだけ)

**ファイル**: `Sources/KanaKanjiConverterModule/ConversionAlgorithms/Zenzai/Zenz/Zenz.swift`

### Phase 4: DicdataStore 非同期対応

`DicdataStore` は現状 `final class` で `prepareState()` が同期。内部辞書データは主に不変（読み込み後）。

- `DicdataStore` は actor にしない。内部 mutable 状態（`loudses`, `loudstxts` など）は主に初期化時にしか変化しない。
- `prepareState()` は同期のまま。
- `KanaKanjiConverter` (actor) 内で `let dicdataStore: DicdataStore` として保持。
- `DicdataStore` の検索メソッドは値を返すだけなので同期でよい。ただし actor 内から呼ばれるため actor-isolated で問題なし。
- `DicdataStoreState` は `final class` → **`actor DicdataStoreState`** に変更。
  - `KanaKanjiConverter` (actor) 内で `let dicdataStoreState: DicdataStoreState` として保持。
  - 学習データ更新・辞書再読み込みなどの mutable 操作を actor 隔離下に。

**ファイル**: `Sources/KanaKanjiConverterModule/DictionaryManagement/DicdataStoreState.swift`

### Phase 5: AncoSession async 化

`AncoSession` は `struct` のまま（immutable ではないが、actor 化するほどの mutable 状態ではない）。

- `execute(...)` → `async throws -> ExecutionResult`
- `experimentalRequestTypoCorrection(...)` → `async -> TypoCorrectionResult`
- `converter` (`actor KanaKanjiConverter`) を保持するため、`AncoSession` は `Sendable struct` にはならない（が問題ない）。

**ファイル**: `Sources/KanaKanjiConverterModule/ConverterAPI/Session/AncoSession.swift`

### Phase 6: CliTool / テスト対応

- `RunCommand`, `SessionCommand` の `@MainActor` を削除。
- 各 `run()` 内で `await` を追加。

**テスト**:
- `KanaKanjiConverterModuleTests`, `KanaKanjiConverterModuleWithDefaultDictionaryTests`
- `requestCandidates` 呼び出しに `await` を追加。
- `@MainActor` 属性を削除。

### Phase 7: final class 整理 (最小限)

変更対象外だが、`final class` はやめる方針に従い、以下を struct 化:
- `ZenzaiTypoGenerationCache` → `struct` (actor 内の `var` として保持)
- `NGramCache` → `struct` (同上)

変更しない（影響が大きいため）:
- `LatticeNode` — `final class` のまま。actor 内で使用されるので安全。
- `InputStyleManager` — シングルトン。別途検討。

---

## 依存関係図 (変更後)

```
actor KanaKanjiConverter
  ├── let converter: Kana2Kanji (struct, Sendable)
  ├── var sessions: [SessionID: ConversionSessionState] (actor 隔離)
  ├── var zenz: actor Zenz?
  ├── var checker: actor SpellChecker
  ├── let dicdataStore: DicdataStore (class, 読み込み後ほぼ immutable)
  └── let dicdataStoreState: actor DicdataStoreState

actor SpellChecker
  └── await MainActor.run { UITextChecker.completions(...) }

actor Zenz
  └── let zenzContext: ZenzContext (class, actor 内に隠蔽)

actor DicdataStoreState
  └── var learningMemoryManager: LearningManager

AncoSession (struct)
  └── let converter: actor KanaKanjiConverter
```

---

## 既存クライアントへの影響

- `requestCandidates(...)` → `await requestCandidates(...)` に変更が必要
- `predictNextInputText(...)` → `await` 化
- その他 public API も同様
- `ConversionResult` は既に `Sendable struct` のため影響なし

---

## リスク

1. **パフォーマンス**: async/await のオーバーヘッド。ただし actor 内でのみ実行される処理は同期的であり hop は少ない。
2. **大規模変更**: テスト・CliTool・ドキュメントの更新が必要。
3. **破壊的変更**: 既存ライブラリ利用者に `await` の追加が必要。

---

## チェックリスト

- [ ] Phase 1: SpellChecker actor 化
- [ ] Phase 2: KanaKanjiConverter async 化
- [ ] Phase 3: Zenz async 化
- [ ] Phase 4: DicdataStoreState actor 化
- [ ] Phase 5: AncoSession async 化
- [ ] Phase 6: CliTool / テスト対応
- [ ] Phase 7: final class 整理 (最小限)
- [ ] ビルド通過確認
- [ ] テスト通過確認
