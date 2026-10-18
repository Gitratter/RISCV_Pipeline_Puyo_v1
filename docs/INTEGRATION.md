# 研究過程に沿った統合設計と実機への引継ぎ

## 1. 論文の段階を混同しない構成

参照した卒研論文は `Kodera_CPU_Report_2026_RISC-V_10_17.pdf`。4 bit → RAM を持つ 8 bit → RV32I → 5 段パイプラインという過程を前提に、今回は「メモリの実用化」と「ゲーム・映像の統合」を分けた。

論文にある v3 の WNS −2.022 ns、TNS −397.310 ns、100 MHz 制約からの推定 Fmax 約 83.18 MHz は**以前の CPU 単体設計の値**である。v4 全体の実測値や、本版を 100 MHz で動かした値に転用してはいけない。本版は CPU・VGA の実クロックを 25 MHz として設計している。基板の発振器は 100 MHz のままであり、`cpu_enable` を間引いただけではない。

また v3.1 はメモリ応答待ちを全段保持で実現したため、定常時も 1 論理ステップに 2 物理クロックを要する。原版の「Load-use 1 Stall」は、全てのメモリ待ちが 1 クロックで済むという意味ではない。周波数、CPI、経過時間、資源使用量を区別して比較する。

卒論への整理例は次のとおり。

| 段階 | 設計上の課題 | 本版の対応 | 論文に残す証拠 |
|---|---|---|---|
| v3 の確認 | 非同期 ROM/RAM と観察用低速 enable | 元ソースを baseline_v3 に保存 | 取得コミット、既存テスト |
| v3.1 同期メモリ | BRAM では読出しにクロックが必要 | 応答トークン、全段保持、1 回だけの副作用 | CPU 差分、遅延 MMIO / STORE 回数テスト |
| v3.1 実時間基盤 | CPU 実行と落下周期の混同 | 実クロック 25 MHz + 1 ms enable | clock/reset テスト、Vivado clock report |
| v4 入出力 | 非同期ボタンと映像走査 | 2FF同期、デバウンス、VGA snapshot | 入力・全フレームテスト |
| v4 ゲーム | 消去の順序と盤面競合 | 単一書込 FSM、BFS、全体同時消去 | 23 の固定盤面シナリオ |
| v4 統合 | CPU が何を実行したか曖昧 | 実 ROM の LW/SW による操作制御 | CPU→MMIO→ゲームの統合テスト |
| 実機評価 | 合成と実際に遊べることは別 | 下記チェックリスト | 写真、操作記録、モニタ同期確認 |

## 2. 継承・置換・追加

| 元の構成 | 本版 | 理由 |
|---|---|---|
| ALUV2 / DecoderV2 / ImmGenV2 | 同名、論理継承 | ISA をゲーム都合で変えない |
| ProgramCounterV2 | 同名、機能継承、同期 reset へ変更 | BRAM アドレスの非同期変化を防ぐ |
| RegisterFileV2 | 同名、LUTRAM 方針継承、有効 bit 同期 reset | 配列全 reset を戻さない |
| TD8_RISCV_V2_Core（実体は v3） | TD8_RISCV_V31_Core | 同期応答保持、MMIO、性能カウンタ |
| InstructionMemoryV2 | PipelineInstructionMemoryV31 | 64 word 非同期 → 4096 word 同期 |
| DataMemoryV2 | PipelineDataMemoryV31 | 256 B 非同期 → 4 KiB 同期、byte enable |
| 観察用 Board top / 低速 enable | TD8_RISCV_PUYO_TOP / PuyoSystem | ゲーム用の常時 CPU 実行と映像接続 |
| 既存表示・デモ ROM | 旧版に保存、新 top には使わない | 新表示と実プログラムを明確化 |
| — | Clock25 / ResetSync / MillisecondTick | クロック変換、同期解除、実時間 |
| — | PuyoMMIO / supervisor | 入出力イベントと CPU の仲介 |
| — | PuyoEngine / PuyoInput / PuyoVideo | ゲーム・入力・描画の分離 |

「削除」は旧ファイルの消去ではなく、新 top から使わなくなったことを意味する。比較元は全て `baseline_v3` に残している。新旧同名モジュールの重複があるので両ツリーをまとめてコンパイルしない。

## 3. 情報の流れ

```text
100 MHz oscillator → MMCM → 25 MHz（全回路）
                              └ 1 ms enable → input / game timers

physical buttons → sync/debounce/DAS → MMIO event latch
                                           ↓ LW
BRAM ROM → 5-stage RV32I CPU → SW action → game FSM
                  ↑ LW status/score          │
                  └──────────────────────────┤
                                             ↓ board / active / score
                                    vblank snapshot → VGA renderer → pins
```

盤面は `PuyoEngine` の 84×3 bit 配列が所有する。描画器は読み出してフレーム境界でコピーするだけである。CPU は盤面情報を MMIO から読み出せるが、盤面を書き換える権限はない。CPU と描画が同じ盤面へ同時に書き込む競合は作らない。BFS の途中で見つけた消去対象はその場で消さず、盤面全体の探索完了後にまとめて消す。`clear_mask` の途中結果は VGA に出さず、全対象確定後の状態 12/13 で表示する。

## 4. MMIO レジスタ

全て 32 bit の整列 LW/SW。LB/SB などは外部 MMIO に許可していない。R=読出し、W=書込み。

| アドレス | 方向 | 内容 |
|---|---|---|
| 0x2000 | R/W | bit0=start_enable。最初の開始許可。0 にしても進行中の一時停止にはならない |
| 0x2004 | R | bit0=start、bit1=busy、bit2=game_over、bit3=active、bit15:8=state |
| 0x2008 | R | 32 bit score |
| 0x200c | R | bit7:0=chain、bit15:8=last_chain |
| 0x2010 | R-to-clear | bit0=左、1=右、2=反時計回り、3=時計回り、4=下保持、5=再開始 |
| 0x2014 | W | 上と同じビット配置の操作。0〜3/5 は 1 クロック pulse、4 は保持レベル |
| 0x2018 | R | システム reset からの ms、32 bit wrap。ゲーム restart では戻さない |
| 0x201c | R | bit2:0=next軸色、bit5:3=next付随色 |
| 0x2020 | R/W | 盤面読出し index (0〜83)。低 7 bit を保持 |
| 0x2024 | R | board[index]。index≧84 は 0 |
| 0x2030 | R | cycle |
| 0x2034 | R | instret |
| 0x2038 | R | memory-wait cycles |
| 0x203c | R | load-use bubbles |
| 0x2040 | R | redirects / flush events |
| 0x2044 | R | 0x5055594f（PUYO） |

0x2000〜0x20ff の未定義整列 word は read=0 / write無視。CPU 側でそれ以外の不正領域や非整列アクセスを検出する。旧 0x100 入力、0x104 LED も維持するが、本 top の旧入力ポートは 0 固定である。

イベントは bit latch であり、任意個数を保存する FIFO ではない。同一イベントが CPU の読出し前に 2 回到来すると 1 回にまとめられる。標準設定では入力が ms 単位、supervisor は少数命令のループなので十分な余裕がある。別の長い処理を firmware に追加する場合は FIFO 化または最大ポーリング遅延の検証が必要。

読出しと新イベントが同じエッジでも新イベントを保持する。解決処理中の移動・回転は捨て、再開始は受け付ける。再開始ではゲーム盤面、操作中の組、スコア、連鎖、ゲームタイマー、BFS 状態をクリアする。物理入力同期器をゲーム再開始で reset しないのは、SW14 を ON のままにした際に再押下と誤認しないためである。システムの ms/cycle カウンタはゲームとは別の観測値として継続する。

## 5. ROM プログラム

`firmware/puyo_supervisor.S` は RV32I 8 命令。LUI で MMIO base を作り、開始を 1 回書いた後、入力 LW → 操作 SW → スコア LW → 旧 LED SW → JAL を反復する。分岐 flush、Load-use、load/store、同期命令読出しを実際に通る。`build_firmware.py` は .S の LUI / ADDI / LW / SW / JAL とラベルを読み取る小さな専用アセンブラであり、全 RV32I 命令や GNU assembler の全構文を扱うものではない。未対応命令を追加する場合は生成器側も変更するか、正式な RV32I ツールチェーンを使用する。

初版はゲームの CPU 化よりも、従来 CPU を壊さず実時間周辺へ接続することを優先した。論文での正確な表現は「RISC-V CPU により制御されるゲーム専用ハードウェアと VGA の統合」である。「CPU がぷよぷよの全アルゴリズムを実行した」は未達成である。

## 6. タイミング・同期の扱い

外部操作入力だけを 2FF 同期化し、さらに ms デバウンスを行う。SW15 と MMCM LOCKED は reset 同期器への非同期 assert にだけ使用し、解除を 3 FF で同期化する。CPU へはさらに 1 段の同期 FF を通す。CPU 内の PC / パイプライン / Register File 有効 bit も同期 reset に変更し、BRAM 制御へ非同期 reset が伝わらないようにした。これは初回の Vivado DRC `REQP-1839` を受けた改善であり、元 CPU の reset 仕様をそのまま継承したわけではない。VGA、CPU、ゲームの間に別クロック領域はない。

XDC は CPU のクリティカルパスを false path にしていない。外部非同期入力から同期器 1 段目 D、reset assert の経路のみを除外する。VGA/LED には 5 ns の出力予算を設定しているが、これはモニタを同期デジタル受信器と仮定した検証ではなく、ピン到達まで余裕を確保する設計条件である。モニタが 25 MHz VGA を受け付けるかは実機確認が必要。

## 7. 実機確認の手順（未実施）

1. Basys 3 の部品型番を確認し、VGA モニタを接続。SW14/15 は OFF にする。
2. 正常に生成した `TD8_RISCV_PUYO_TOP.bit` を Vivado Hardware Manager で volatile configuration に書く。flash 永続化は別手順であり本スクリプトは行わない。
3. LED15 が OFF、LED12 が ON、VGA 画面が安定していることを確認。
4. btnL/R の単押し・長押し・同時押し、btnU/C の押しっぱなし 1 回回転、btnD 高速落下を確認。
5. NEXT と新しい組が一致すること、段差で片方だけ落ちること、4 個以上の塊が消えること、連鎖中に操作で盤面が壊れないことを確認。
6. GAME OVER 後 SW14 を OFF→ON。ON のままで再開始が繰り返されないことを確認。もう一度 OFF→ON で再開始できることを確認。
7. SW15 の ON/OFF でシステムを再開し、長時間プレイ時の安定性を記録。
8. 使用モニタ型番、写真、ボタン感触、最長連鎖、連続運転時間を卒論の実機結果として記録。

ボード実機の写真や人間のプレイ確認は RTL シミュレーションで代用しない。Vivado power report は推定値であり、基板の実測消費電力として記載しない。

## 8. 参照元

- 元 CPU: https://github.com/y0sh120040803-cpu/TD8_To_RISCV_v3-pipeline
- Basys 3 公式制約: https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc
- ユーザー提供論文: Kodera_CPU_Report_2026_RISC-V_10_17.pdf（参照のみ。原本変更・再配布なし）
