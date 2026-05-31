# @unchecked Sendable の使用箇所と改善方針

## 概要

`KanaKanjiConverter` を `actor` 化する過程で、`actor` 間または actor から非同期コンテキストへの値の受け渡し（`sending` parameter / cross-actor call）が必要になりました。

これらの型は実際には **シングルスレッド・シングル actor 内でのみ使われている** か、または **内部 mutable 状態を持たない** ので安全ですが、コンパイラの自動 `Sendable` 判定を通らなかったため `@unchecked Sendable` を付与しています。

---

## 各箇所の詳細

### 1. `EfficientNGram`

**ファイル**: `Sources/EfficientNGram/Inference.swift`

```swift
public struct EfficientNGram: @unchecked Sendable {
```

#### 現状
- `struct` だが内部に `Marisa` 型（C++ ラッパーのクラスインスタンス）を保持
- `Marisa` は `Sendable` でないため、コンパイラが自動的に `Sendable` と判定しない
- 実際の使用: `Zenz.candidateEvaluate(..., personalizationMode: (base: EfficientNGram, personal: EfficientNGram)?, ...)` で `Zenz` actor 内に渡される

#### なぜ @unchecked か
- `Marisa`（C++ trie ライブラリの Swift ラッパー）は `class` だが読み込み後 immutable
- `EfficientNGram` は actor 境界を越えて **read-only で使われる**（`bulkPredict()` のみ呼ばれる）
- `Zenz` actor 内で base/personal モデルを同時に保持して使うだけで、他の actor へは渡されない

#### 改善方法と影響度
| 方法 | 影響度 | 備考 |
|---|---|---|
| `Marisa` ラッパーに `@unchecked Sendable` を付与し、`EfficientNGram` の `@unchecked` を削除 | **小** | `Marisa` が読み込み後 immutable なことを保証すれば正しい方法 |
| `Zenz.candidateEvaluate` の `personalizationMode` を `sending` ではなく `borrowing` に変更 | **小** | actor 内でのみ使うので共有参照で十分 |
| `EfficientNGram` を `actor` にする | **中** | `bulkPredict()` を async にする必要があるが、呼び出し元も async 化済み |

**推奨**: `Marisa` ラッパーに `@unchecked Sendable` を移動し、`EfficientNGram` は `Sendable` 自動判定に委ねる。

---

### 2. `Kana2Kanji`

**ファイル**: `Sources/KanaKanjiConverterModule/ConversionAlgorithms/Kana2Kanji.swift`

```swift
struct Kana2Kanji: @unchecked Sendable {
```

#### 現状
- `struct` だが内部に `var dicdataStore: DicdataStore`（`final class`）を保持
- `DicdataStore` は `Sendable` でないため、コンパイラが自動 `Sendable` を拒否
- `KanaKanjiConverter` actor 内で `let converter: Kana2Kanji` として保持
- `convertToLattice`（async）で `self.converter.all_zenzai(...)` を呼ぶ際に `self.converter` を `sending` 渡す必要がある

#### なぜ @unchecked か
- `Kana2Kanji` は `KanaKanjiConverter` actor 内でのみ使われる
- `dicdataStore` は初期化時に1回だけセットされ、その後 read-only（検索メソッドは値を返すだけ）
- `all_zenzai` は `self`（`Kana2Kanji`）を渡すが、これは actor 内の同期的なメソッド呼び出し

#### 改善方法と影響度
| 方法 | 影響度 | 備考 |
|---|---|---|
| `DicdataStore` に `@unchecked Sendable` を付与 | **小〜中** | 辞書データは読み込み後 immutable なので正しい。ただし `loudses` / `loudstxts` は初期化後に mutable な箇所もある |
| `Kana2Kanji` を `actor` にしないまま `@unchecked Sendable` を維持 | **なし** | 現状維持。実際には安全 |
| `Kana2Kanji.all_zenzai` の `self` 渡しを `sending` ではなく actor 内参照に変更 | **小** | `all_zenzai` のシグネチャを `sending self` から変更する必要がある |

**推奨**: `DicdataStore` の `Sendable` 化を検討し、`Kana2Kanji` の `@unchecked Sendable` を削除する。

---

### 3. `ZenzaiCache`

**ファイル**: `Sources/KanaKanjiConverterModule/ConversionAlgorithms/Zenzai/zenzai.swift`

```swift
struct ZenzaiCache: @unchecked Sendable {
```

#### 現状
- `struct` だが内部に `var` プロパティ（`prefixConstraint`, `satisfyingCandidate`, `inputData`, `cachedLattice`）を持つ
- `Lattice` は `Sequence` プロトコルに準拠した `struct` だが、`LatticeNode`（`final class`）を含む
- `ZenzaiCache` は `KanaKanjiConverter` actor 内で `sessions` 辞書に保持され、`all_zenzai` の結果として返される

#### なぜ @unchecked か
- `ZenzaiCache` は `KanaKanjiConverter` actor 内でのみ作成・使用される
- `Lattice` は actor 内でのみ触られる（`cachedLattice` は `getPreprocessedLattice` で read されるだけ）
- `LatticeNode` が `final class` なので、コンパイラが自動 `Sendable` を拒否

#### 改善方法と影響度
| 方法 | 影響度 | 備考 |
|---|---|---|
| `LatticeNode` を `struct` 化 | **大** | 再帰的な `prevs: [RegisteredNode]` を含むツリー構造。大規模リファクタリングが必要 |
| `ZenzaiCache` を actor 内のみで使われることを明示し `@unchecked Sendable` を維持 | **なし** | 現状維持。実際には安全 |
| `ZenzaiCache` の `cachedLattice` を `Lattice?` ではなく lattice の immutable snapshot に変更 | **中** | 実装の変更が必要 |

**推奨**: `LatticeNode` の struct 化は影響が大きいため、当面は `@unchecked Sendable` を維持する。

---

### 4. `ZenzaiTypoGenerationCache`

**ファイル**: `Sources/KanaKanjiConverterModule/ConversionAlgorithms/Zenzai/Zenz/ZenzaiTypoCandidateGenerator.swift`

```swift
final class ZenzaiTypoGenerationCache: @unchecked Sendable {
```

#### 現状
- `final class` で内部に mutable な `var` プロパティ多数
- `KanaKanjiConverter` actor 内の `ConversionSessionState` に保持される
- `Zenz.generateTypoCandidates(..., cache: ZenzaiTypoGenerationCache)` で `Zenz` actor に渡される

#### なぜ @unchecked か
- `ZenzaiTypoGenerationCache` は `KanaKanjiConverter` actor 内の `var` として保持される
- `Zenz` actor に `sending` で渡されるが、実際には `Zenz` actor 内で read/write される
- 2つの actor（`KanaKanjiConverter` と `Zenz`）間で共有されるが、**排他アクセスは各 actor の serial 実行キューで保証される**
- ただし、コンパイラは「2つの actor が同じ class インスタンスにアクセスする」ことを安全と判定できない

#### 改善方法と影響度
| 方法 | 影響度 | 備考 |
|---|---|---|
| `ZenzaiTypoGenerationCache` を `struct` 化 | **中** | `Zenz.generateTypoCandidates` の `cache` パラメータを `inout` にする必要がある。呼び出し元も変更が必要 |
| `ZenzaiTypoGenerationCache` を `Zenz` actor に移動し、キー（session ID）で管理 | **中** | キャッシュのライフタイム管理が複雑になる |
| `@unchecked Sendable` を維持 | **なし** | 現状維持。`KanaKanjiConverter` actor から `Zenz` actor へ `await` で渡されるため実際には安全 |

**推奨**: `struct` 化は可能だが呼び出しチェーンの変更が必要。当面は `@unchecked Sendable` を維持する。

---

### 5. `DicdataStoreState`

**ファイル**: `Sources/KanaKanjiConverterModule/DictionaryManagement/DicdataStoreState.swift`

```swift
package final class DicdataStoreState: @unchecked Sendable {
```

#### 現状
- `final class` で内部に mutable な `var` プロパティ多数（`keyboardLanguage`, `dynamicUserDictionary`, `learningMemoryManager` など）
- `KanaKanjiConverter` actor 内で `let dicdataStoreState: DicdataStoreState` として保持
- `convertToLattice`（async）で `self.converter.all_zenzai(..., dicdataStoreState: self.dicdataStoreState)` に渡される

#### なぜ @unchecked か
- `DicdataStoreState` は `KanaKanjiConverter` actor 内でのみ作成・使用される
- ただし `Kana2Kanji`（`struct`）のメソッドに渡されるため、`sending` parameter として扱われる必要がある
- `final class` + mutable 状態のため、コンパイラは自動 `Sendable` を拒否
- 実際には `KanaKanjiConverter` actor の serial 実行キュー内でしかアクセスされない

#### 改善方法と影響度
| 方法 | 影響度 | 備考 |
|---|---|---|
| `DicdataStoreState` を `actor` にする | **大** | これが元の計画 Phase 4。ただし `DicdataStore` 内から大量の同期呼び出しがあるため、`DicdataStore` も actor 化が必要 |
| `DicdataStoreState` を `struct` 化 | **中〜大** | `LearningManager`（`final class`）の扱いが問題。参照共有が必要 |
| `@unchecked Sendable` を維持 | **なし** | 現状維持。実際には `KanaKanjiConverter` actor 内でしかアクセスされない |

**推奨**: `DicdataStoreState` の actor 化は `DicdataStore` の actor 化とセットで実施する必要がある。当面は `@unchecked Sendable` を維持する。

---

## まとめ

| 型 | 現状の安全根拠 | 理想の改善策 | 優先度 |
|---|---|---|---|
| `EfficientNGram` | read-only, actor 内使用 | `Marisa` ラッパーの `Sendable` 化 | 高 |
| `Kana2Kanji` | actor 内使用, `DicdataStore` は read-mostly | `DicdataStore` の `Sendable` 化 | 中 |
| `ZenzaiCache` | actor 内使用, `LatticeNode` が class | `LatticeNode` の struct 化（大規模） | 低（影響大） |
| `ZenzaiTypoGenerationCache` | 2 actor 間で await 渡し | struct 化 | 中 |
| `DicdataStoreState` | actor 内使用 | `DicdataStore` + `DicdataStoreState` の actor 化 | 低（影響大） |

### リスク評価

現状の `@unchecked Sendable` は **実際には安全** ですが、将来的な変更で以下のリスクがあります：

1. **他の開発者が `@unchecked Sendable` 型を actor 外で使い始める** → データ競合の可能性
2. **コンパイラの strict concurrency チェックがさらに厳しくなる** → `@unchecked Sendable` が拒否される可能性

### 推奨事項

1. **短期的**: 各 `@unchecked Sendable` の上に「この型は actor 内でしか使われない」ことを示すコメントを残す
2. **中期的**: `EfficientNGram` → `Kana2Kanji` → `ZenzaiTypoGenerationCache` の順で `Sendable` 化を検討
3. **長期的**: `DicdataStore` / `DicdataStoreState` の actor 化を検討（ただし影響が大きい）
