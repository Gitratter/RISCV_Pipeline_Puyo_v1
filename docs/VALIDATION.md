# 検証結果・未確認事項

検証日：2026-10-18。コードは GitHub へ書き戻していない。

## 結論の範囲

- ゲームの必須ケースを含む **23 シナリオ**は、RTL シミュレーションのアサーションが全て期待値に一致した。
- CPU 回帰 11 本 + 新規メモリ基盤 1 本の計 **12 本**、プロジェクト統合側 **7 本**について、生成した VVP の実行終了値は全て 0。`tb_cpu_platform` が両方にあるので、ユニークなテストベンチは **18 本**である。
- **コンパイラの正常終了まで含めた無条件の「全テスト PASS」ではない。** 下記の環境問題を明示している。
- Vivado 2025.2 で Basys 3 向けに合成・配置配線・タイミング解析・bitstream 生成を実施した。最終の数値は同梱 `reports/vivado/` のレポートを正とする。
- FPGA への書込み、実モニタとの VGA 同期、人間による操作性評価、長時間実機試験は **未実施**。

## 1. RTL シミュレーション

| ベンチ | 確認内容 | 検査結果 |
|---|---|---|
| tb_clock_reset | divide4 モデル、非同期 assert、3 edge 解除、ms tick 周期/幅/初期化 | 一致 |
| tb_input | bounce 除去、押下 1 回、DAS/ARR、両方向同時、SW14 再装填 | 一致 |
| tb_mmio | read-to-clear 競合、新イベント保持、busy中操作排除、restart、index範囲 | 一致 |
| tb_puyo_engine | 23 シナリオ、BFS queue 上限、盤面と操作中組の不変条件 | 一致 |
| tb_system | 実 ROM の起動、入力→CPU LW/SW→ゲーム、固定/NEXT、再開始 | 一致 |
| tb_video | 800×525 全走査、HS/VS 幅、blank RGB、snapshot、色、BCD | 一致 |
| tb_cpu_platform | 同期 RAM byte lane/alias/最終位置、遅延 MMIO、pause、非重複STORE、trap | 一致 |

CPU 回帰は integer、immediates、decoder、memory、memory_boundaries、control_flow、boundaries、faults、mmio、lutram_reset、pipeline の 11 本。旧 v3 の ISA・期待値を継承し、同期メモリの実際の要求エッジで STORE を数えるように監視側を変更した。リセットについては v3.1 の同期方式に合わせ、`tb_cpu_lutram_reset` と `tb_cpu_pipeline` をクロック立上り後の検査へ変更した。前者はクロック前に PC/RF が変わらないことも追加確認している。失敗した検査を単に削除したものではなく、仕様変更の前後を明示している。

既知 2 連鎖の得点は 120、既知 3 連鎖の得点は 260、両者の最終盤面は空。離れた複数の組の消去は 1 段階として数える。84 個全てが同色のテストで探索 queue が最大成分を収容できることも確認した。必須項目と個別シナリオの対応は `GAME_ENGINE.md` を参照。

VGA は HS low 50,400 pixel clocks / frame（96×525）、VS low 1,600（800×2）、visible 307,200（640×480）を確認。最大 uint32 スコア 4294967295 と、8 bit 連鎖表示の全 256 値も検査した。`reports/puyo_video.png` は実 RTL の RGB 出力から生成した確認画像で、広告用モックアップではない。ただし最大数値・RESOLVING・GAME OVER を同時に与えた**描画単体のテスト配置**であり、通常プレイの実機写真ではない。

### 使用環境にあるシミュレータの問題

今回の portable Icarus Verilog 14 development build は、parse / elaborate / code generation の `DONE.` 出力後に、多くのコンパイルで **−1073741819 = 0xC0000005** を返した。新しく生成した VVP だけを診断目的で起動した結果、vvp は正常終了し、上述の検査を通過した。古い VVP を使い回して合格扱いしたものではない。コンパイル終了値と実行終了値は別フィールドとして JSON に保存した。

代替の Vivado XSim も試した。`xvlog` による読み込みは成功したが、`xelab` の生成 C コンパイルで、同梱 GCC 6.2.0 が Windows の「システム DLL の無効な再配置」により起動できなかった。これは XSim で回帰を完了した結果ではない。最終の reset 修正後にも全 RTL と全 18 ベンチを `xvlog` で読み直し、終了値 0 を確認した（`reports/xsim_latest_syntax.log`）。最新版 RTL の全体合成は Vivado synthesis 側で別途行っている。

`reports/project_diagnostic/` と `reports/cpu_diagnostic/` に compiler/run log と結果 JSON、`reports/xsim_attempt/` に代替実行のログを残した。通常の `run_tests.ps1` / `run_cpu_tests.ps1` / XSim runner は非ゼロ終了値で停止する。`diagnose_icarus.ps1` は既知の終了時例外を明示して調査する専用 runner であり、クリーンビルド認定用ではない。

論文での安全な記述は「生成された RTL シミュレーションにおいて期待値との一致を確認した。ただし使用環境のコンパイラ終了時例外が残り、正常環境での再実行が必要」である。独立した正式 RISC-V compliance test suite、形式検証、網羅的な長時間乱数テストを実施したとは主張しない。

## 2. FPGA 配置配線

対象：`xc7a35tcpg236-1`、top：`TD8_RISCV_PUYO_TOP`、Vivado：2025.2。外部 100 MHz → MMCM → 実システム 25 MHz、内部周期 40 ns。

2026-10-18 22:25 JST 完了の最終ビルドで得た値は以下。`timing_summary.rpt`、`timing_worst20.rpt`、`utilization_summary.rpt`、`utilization_route.rpt`、`ram_route.rpt` を同梱した。

| 項目 | 最終結果 |
|---|---:|
| システム実クロック | 25.000 MHz |
| Slice LUTs（LUTRAM含む） | 5,458 / 20,800（26.24%） |
| LUT as Logic | 5,414 |
| LUTRAM | 44 / 9,600 |
| FF | 2,683 / 41,600（6.45%） |
| Latch | 0 |
| RAMB36E1 | 5 / 50（10.00%） |
| DSP48 | 1 / 90 |
| WNS | +8.379 ns |
| TNS | 0.000 ns |
| WHS / THS | +0.030 ns / 0.000 ns |
| 最小 pulse width slack | +3.000 ns |
| 推定オンチップ消費電力 | 0.194 W（Dynamic 0.122 / Static 0.072） |
| Bitstream | 生成成功、実機への書込みは未実施 |

最終ビルドログに ERROR / CRITICAL WARNING はない。通常 warning は残っており、DRC の 2 件は DSP パイプラインに関する推奨である。

命令メモリは 4 個、データ RAM は 1 個の RAMB36E1 に推論された。Register File は分散 RAM を維持する。ゲーム盤面、探索 queue、描画 snapshot は別の小容量状態レジスタであるため、システム全体の FF が CPU 単体の v1.1 より多いことを、CPU メモリ推論の退行と混同してはいけない。

初回の DRC で BRAM のアドレス・enable を非同期 reset FF が駆動する `REQP-1839` が見つかった。CPU register の同期 reset 化と、CPU reset 入力の同期レジスタ化によって解消した。この変更は `CPU_PLATFORM.md` と `CPU_v3_to_v31.diff` に残した。

最終チェックでは `no_clock=0`、`unconstrained_internal_endpoints=0`、`no_output_delay=0`、組合せ loop=0 を確認した。非同期ボタン 5 本と SW14/SW15 の計 7 入力は同期器の最初の経路・専用 reset assert だけを false path として扱うため、通常の同期入力 delay は与えない。CPU の一般データパスは除外していない。`report_cdc` の出力だけでは無制約の外部入力全てを検証したことにはならないので、XDC と 2FF 同期器の RTL を併せて点検した。

残る DSP の入力 / 乗算段パイプラインに関する推奨 warning は、得点 `消去数×10×連鎖数` に対応する。これは実装失敗ではないが、さらに高速化する場合は得点計算に段を追加する余地がある。warning が一切ない設計とは記載しない。

別の methodology report には、reset 要求を `SW15 OR !LOCKED` で合成するための `LUTAR-1`、BRAM の専用出力 FF 利用に関する `SYNTH-6` 2 件、XDC 検索の効率に関する `XDCB-5` 1 件がある。reset の OR は非同期 assert 専用であり、解除は 3 段同期、CPU へはさらに同期 FF を通す。通常プレイ中は SW15=0、LOCKED=1 で固定する。入力の切替や電源投入時の余分な reset を含む実機安定性は未検証で、LUTAR を無条件に安全判定したわけではない。BRAM 出力の追加 FF 化は応答遅延も変わるため、将来の性能改善段階で扱う。

## 3. 性能・電力の読み方

正式に制約を設定して配置配線した動作周波数は **25 MHz**。100 MHz の入力発振器と混同しない。同一 clock の setup WNS から `Tmin ≈ 40 ns − WNS`、`Fmax推定 ≈ 1000 / Tmin [MHz]` を計算できるが、これはその配置配線に対する目安で、別周波数での再実装・実機保証ではない。VGA と CPU を同一 clock で動かすため、そのまま clock を上げると映像タイミングも変わる。

今回の値では `40 − 8.379 = 31.621 ns`、`1000 / 31.621 ≒ 31.62 MHz` となる。最悪経路は VGA の `pixel_y_reg[1]` → `vga_blue_reg[3]`、データパス 31.519 ns（論理 12.782 ns、配線 18.737 ns）、42 logic levels であった。従来 v3 の PC enable 経路とは別の制限である。高速化するときは描画の座標判定・文字処理を分割し、RGB と HS/VS の遅延を揃える改善が候補になる。本版の 25 MHz に対しては setup/hold を満たしている。

最悪経路は `timing_worst20.rpt` の Source/Destination を読み、CPU の PC 制御、ゲーム探索、VGA 描画のいずれが制限しているか区別する。システム全体に描画器などを加えた結果と、旧 CPU 単体の Fmax を直接比較して「CPU が低速化した」とは結論しない。CPU 本体も全段メモリ待機を追加しているので、同じ命令列を用いた cycle / instret / CPI / 実行時間の比較が次の評価である。

`power_estimate.rpt` は vector-less activity によるオンチップ推定であり、Confidence Level は Low。VCD/SAIF によるゲーム動作 activity を与えた電力評価や、電源端子の実測電力ではない。MMCM の電力を含むシステム全体なので旧 CPU 単体と条件も異なる。

## 4. 残作業

1. 安定したシミュレータ環境で通常 runner を再実行し、コンパイル正常終了を含めた回帰を確定する。
2. Basys 3 へ書込み、VGA モニタ互換性と実ボタンの操作性を確認する。
3. 長時間プレイ、連続 restart、電源投入直後の表示、SW15 reset を実機で確認する。
4. 必要なら自動落下 / DAS / ARR を被験者の操作感に合わせ調整する。
5. 「ゲーム規則を CPU が実行する」研究へ進む場合は、ハードウェア FSM を参照モデルにして RV32I ソフトウェアへ別段階で移植する。

上記未実施項目を完了した扱いにせず、同梱 bitstream も実機未確認版として扱う。
