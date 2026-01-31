
---

# 🧭 作業指示書：DSIM/UVM デバッグ支援MCPサーバー構築計画

**目的**：
UVM検証のデバッグ効率を最大化するため、`fastMCP`ベースのMCPサーバーを構築し、
DSIMシミュレーションと連携してログ解析・エラー要約・再実行などを自動化する。

---

## 📘 フェーズ0：環境整備

### ✅ Task 0.1：Python環境セットアップ

* Python 3.10+ を使用
* 以下のライブラリをインストール

  ```bash
  pip install fastmcp aiofiles rich lxml
  ```
* OS依存のパス確認（Linux/WindowsでDSIM_HOMEを設定）

### ✅ Task 0.2：環境変数確認

* `DSIM_HOME` が設定されているか確認する。
* 未設定なら警告を出す初期化処理を追加する。

### ✅ Task 0.3：プロジェクト構造作成

```
dsim_uvm_mcp/
 ├─ server/
 │   ├─ __init__.py
 │   ├─ main.py
 │   ├─ tools/
 │   │   ├─ log_analysis.py
 │   │   ├─ sim_control.py
 │   │   ├─ coverage_tools.py
 │   │   └─ utils.py
 │   └─ mcp_server.py
 ├─ mcp.json
 └─ README.md
```

---

## ⚙️ フェーズ1：MCPサーバー骨格の実装

### ✅ Task 1.1：FastMCP初期化

* `fastmcp` をインポートしてサーバーを作成。
* MCPサーバー名は `"dsim-debug-server"`。

### ✅ Task 1.2：基本ループ実装

* `asyncio.run(mcp.run_stdio_transport())` で通信ループ起動。
* ログ出力に `rich.print` を利用。

### ✅ Task 1.3：テスト起動コマンド（仮実装）

```python
@mcp.tool()
async def run_uvm_test(test_name: str, seed: int = 1):
    """指定されたUVMテストをDSIMで実行"""
```

* DSIM呼び出しはモックでOK（`subprocess.run`を使う）。
* 結果をJSON形式で返す。

---

## 🔍 フェーズ2：デバッグ効率化ツール群の実装

### ✅ Task 2.1：`analyze_uvm_log(log_path)`

目的：UVMログを解析し、階層別に`INFO/ERROR/FATAL`を集計。

* 正規表現で以下を抽出：

  ```
  UVM_INFO @ <time>: <component> [id] message
  UVM_ERROR @ <time>: <component> [id] message
  UVM_FATAL ...
  ```
* JSON出力例：

  ```json
  {
    "summary": {"error": 3, "fatal": 1},
    "by_component": {
      "bridge_driver": {"error": 2, "info": 12},
      "scoreboard": {"error": 1}
    }
  }
  ```

---

### ✅ Task 2.2：`summarize_test_result(log_path)`

目的：シミュレーション結果を自動要約。

* 実行時間・エラー数・seed・test_nameを抽出。
* ChatGPTが読みやすいテキストを生成。
* 例：

  ```
  ✅ Test: bridge_seq_test
  ❌ Errors: 2
  🧩 Coverage: 84%
  ⏱ Runtime: 12.4s
  ```

---

### ✅ Task 2.3：`rerun_last_failed_test()`

目的：直前の失敗テストを再実行。

* `.last_failed.json` に最後のテスト情報を保存。
* 失敗テストがない場合はエラー応答。

---

### ✅ Task 2.4：`report_assertion_summary(log_path)`

目的：assertion結果の要約。

* DSIMログ内の以下パターンを抽出：

  ```
  **ASSERTION FAIL** <assert_name> @ <time>
  ```
* 集計してJSON返却。
* 例：

  ```json
  {"assert_failures": ["a_check_ready", "b_timing_delay"]}
  ```

---

### ✅ Task 2.5：`grep_uvm_error(pattern)`

目的：UVMログ内から任意パターンを検索。

* 正規表現でヒットした行を返す。
* 検索速度向上のため、`aiofiles` を使用して非同期I/O。

---

## 🧠 フェーズ3：AI解析連携（オプション）

### ✅ Task 3.1：`explain_failure(log_path)`

目的：ログを解析し、失敗原因を自然言語で要約。

* ChatGPT（または同MCPクライアント）に構造化情報を返す。
* 構文解析後に「原因候補」と「関連信号」を推定。

### ✅ Task 3.2：`suggest_debug_signals(test_name)`

目的：過去のログを分析し、観測信号候補を提示。

* 履歴データベース（`runs/`フォルダ）を参照。
* テストごとの失敗傾向を分析して出力。

---

## 🧾 フェーズ4：設定・統合テスト

### ✅ Task 4.1：`mcp.json` 作成

内容例：

```json
{
  "name": "DSIM Debug Server",
  "entry_point": "python server/mcp_server.py",
  "description": "DSIM/UVM Debugging Support Server",
  "tools": ["run_uvm_test", "analyze_uvm_log", "report_assertion_summary", "grep_uvm_error"]
}
```

### ✅ Task 4.2：動作検証

* ChatGPT (MCPクライアント) から `run_uvm_test("bridge_seq_test")` を呼ぶ。
* DSIMが動作していない場合、モックログを返す。

---

## 📊 フェーズ5：拡張（任意）

| 機能                             | 目的             |
| ------------------------------ | -------------- |
| `compare_two_runs(run1, run2)` | 回帰テスト差分分析      |
| `generate_debug_report()`      | 失敗ケースをPDFでまとめる |
| `launch_waveform_viewer()`     | 波形可視化ツールを起動    |

---

## 🧱 補足設計ルール

* すべてのツール関数は `@mcp.tool()` デコレーターを付与する。
* 戻り値は必ず `dict` 形式または `str`。
* すべてのファイルI/Oは非同期 (`aiofiles`) で実装する。
* エラー時は `{"error": "<message>"}` を返す。
* ログの解析パターンは `server/tools/utils.py` にまとめる。

---

## 🚀 次のステップ候補

1. フェーズ0〜1を先に実装してMCP通信確認。
2. フェーズ2から優先して追加（`analyze_uvm_log` → `summarize_test_result` の順）。
3. フェーズ3はAI解析（ChatGPTとの協調）段階で実装。

---

もし希望があれば、
この作業指示書をもとに **「agent AI用YAMLタスク定義」** に変換できます（自動実行用）。
それも出力しますか？
