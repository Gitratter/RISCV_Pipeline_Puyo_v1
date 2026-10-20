# TD8 RISC-V Puyo v4 — v3.1 Game Platform + VGA / ぷよぷよ風ゲーム

既存の TD8 由来 5 段パイプライン CPU を残して、同期 BRAM、待機制御、MMIO、入力、VGA、1 人用ゲーム処理器へ段階的に拡張した。

**本版は「RV32I CPU が専用ゲーム回路を制御するシステム」です。衝突判定・重力・連結探索・消去・連鎖計算の全てを RV32I ソフトウェアで実行する版ではありません。** CPU は実際に ROM 内のプログラムを実行し、入力イベントを読んでゲーム回路へ操作を書き込み、スコアを読み出します。CPU を除いても同じ接続のままで遊べる飾りの CPU にはしていません。

## まず読むファイル

- [検証結果と未確認事項](docs/VALIDATION.md)
- [研究過程・変更点・MMIO・実機手順](docs/INTEGRATION.md)
- [CPU / 同期メモリ移行](docs/CPU_PLATFORM.md)
- [ゲーム規則・状態機械・テスト対応表](docs/GAME_ENGINE.md)
- [ボタン入力・VGA 描画](docs/VIDEO_INPUT.md)

対象は **Basys 3 / xc7a35tcpg236-1** です。ボードの 100 MHz 発振器から MMCM で **25 MHz の実クロック**を作り、CPU・ゲーム・VGA を同一クロックで動かします。CPU は常時 enable ですが、同期メモリ待ちに応じてパイプラインを保持します。100 MHz CPU の動作保証を追加したという意味ではありません。ゲームの落下やボタン反復周期は 1 ms enable で別に管理します。

VGA は 640×480、総画素 800×525、負極性同期、25 MHz / 800 / 525 ≒ **59.5238 Hz** です。標準 25.175 MHz と完全には同一ではないため、使用モニタでの同期確認は実機項目としています。

## 操作

| Basys 3 | 操作 |
|---|---|
| btnL / btnR | 左 / 右。押した瞬間に 1 マス、長押し反復 |
| btnU | 時計回りに 1 回回転 |
| btnC | 反時計回りに 1 回回転 |
| btnD | 高速落下 |
| SW14 を OFF→ON | ゲーム再開始。次に押すには OFF に戻す |
| SW15 ON | システムリセット保持。OFF で開始 |

SW0〜13 と 7 セグメント表示は本版では使いません。LED15=CPU fault、LED14=ゲームオーバー、LED13=解決処理中、LED12=ゲーム開始許可、LED11〜8=命令リタイア数の一部、LED7〜0=スコア下位 8 bit です。

## ファイル構成と研究段階

```text
baseline_v3/             取得した比較元。新設計と同時に合成しない
rtl/cpu/                 v3 の 5 段構造 + v3.1 の応答待機対応
rtl/platform/            同期 ROM/RAM・MMIO・clock/reset・統合 top
rtl/game/PuyoEngine.v    盤面更新を一元化したゲーム FSM
rtl/input/PuyoInput.v    2FF同期・デバウンス・押下・長押し
rtl/video/PuyoVideo.v    フレームスナップショット・文字・色付き図形
firmware/               8 命令の RV32I supervisor と ROM 生成器
sim/                    ゲーム・CPU・入力・MMIO・映像・統合テスト
constrs/                Basys 3 ピン / クロック制約
scripts/                シミュレーション・合成・配置配線・梱包
docs/                   日本語解説、検証記録、変更差分
reports/                配布用の検証ログ・Vivado レポート
```

1. `baseline_v3`：元の非同期小容量メモリを使用するパイプライン CPU。
2. `rtl/cpu` + `rtl/platform/PipelineMemoryV31.v`：同期メモリに対応した v3.1。CPU 単体テストで独立検証できます。
3. `PuyoSystem` / `TD8_RISCV_PUYO_TOP`：v4。CPU をゲーム、入力、VGA と統合します。

比較元は [TD8_To_RISCV_v3-pipeline](https://github.com/y0sh120040803-cpu/TD8_To_RISCV_v3-pipeline)、取得コミットは `e8b9219f745e60d78dfa04ccef3416b58ad2efd9` です。取得元のファイル一覧・GitHub blob SHA は `BASELINE_MANIFEST.json` に保存しました。保存時の改行正規化を含むため、ローカルファイルの byte hash と同一と主張するものではありません。

## 実行・再検証

プロジェクトのルートをカレントディレクトリとして実行します。`firmware/puyo_supervisor.hex` は同梱済みなので RISC-V コンパイラは不要です。再生成する場合：

Vivado のパス長制限を避けるため、ZIP は `C:/work/TD8_RISCV_Puyo_v4` のような短い半角英数字のパスへ展開することを推奨します。

```powershell
python firmware/build_firmware.py
```

Icarus Verilog と vvp が PATH 上にある環境：

```powershell
./scripts/run_tests.ps1
./scripts/run_cpu_tests.ps1
```

実行ファイルを指定する場合は `-Iverilog`, `-Vvp`, 必要に応じて `-IverilogBase` を指定してください。通常の runner はコンパイル異常を成功として扱いません。今回使用した Windows portable Icarus の終了時例外と、代替 XSim の起動制約は [検証結果](docs/VALIDATION.md) に分離して記録しています。

Vivado 2025.2 の Windows 用再検証：

```powershell
./scripts/run_xsim.ps1 -VivadoRoot 'C:/AMDDesignTools/2025.2/Vivado'
./scripts/run_cpu_xsim.ps1 -VivadoRoot 'C:/AMDDesignTools/2025.2/Vivado'
./scripts/run_vivado.ps1 -VivadoRoot 'C:/AMDDesignTools/2025.2/Vivado'
```

通常の Vivado 環境が設定済みなら、次でも合成から bitstream 生成まで実行できます。

```text
vivado -mode batch -source scripts/vivado_build.tcl
```

合成 top は **TD8_RISCV_PUYO_TOP**。`rtl/` の `.v` のみを設計ソース、`constrs/Basys3_Puyo.xdc` を制約にします。`baseline_v3/`、`sim/` は合成ソースへ追加しません。`SIMULATION` define は合成時に設定しません。ROM ファイルの相対パスを解決するため、ルートから実行してください。

生成物は `build/vivado/` です。スクリプトは setup/hold の未達なら bitstream を生成しません。レポートの確認は [実機前チェック](docs/INTEGRATION.md) に沿って行ってください。ボードへの書込み・実モニタでの操作確認は実施していません。

## 調整と拡張

`PuyoSystem` の `AUTO_DROP_MS`、`SOFT_DROP_MS`、`DAS_MS`、`ARR_MS`、`FALL_STEP_MS`、`CLEAR_DELAY_MS` を別々に調整できます。標準値は順に 700 / 40 / 180 / 60 / 40 / 180 ms です。

`FIXED_SEQUENCE=1` で固定出現順、`SEQUENCE_FILE` で独自の 256 組の順序を指定できます。形式は [ゲーム仕様](docs/GAME_ENGINE.md) を参照してください。テスト用盤面設定ポートは `ENABLE_DEBUG=1` のときだけ有効で、FPGA top では無効です。

描画は色番号と RGB/図形を分離しています。画像へ変更する場合も `PuyoEngine` の消去判定や色番号は変更せず、`PuyoVideo` の色・図形部分を差し替えます。原作画像や音声は使用していません。

将来、ゲーム規則を RV32I プログラムへ移す場合は別研究段階です。本版の固定盤面テストを参照として移植し、CPU 書込み可能なタイルメモリと描画スナップショットを設計してください。本版にフル画素 framebuffer や汎用の書込み可能 VRAM はありません。
