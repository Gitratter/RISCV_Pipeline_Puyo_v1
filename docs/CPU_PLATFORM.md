# v3 から v3.1 同期メモリ基盤への移行

元コードは `y0sh120040803-cpu/TD8_To_RISCV_v3-pipeline` のコミット
`e8b9219f745e60d78dfa04ccef3416b58ad2efd9` である。比較元を
`baseline_v3/` に残した。元の CPU モジュール名は v3 リポジトリでも
`TD8_RISCV_V2_Core` であった。本実装は派生モジュールを
`TD8_RISCV_V31_Core` として分離し、研究段階を区別する。

## 継承した構成

IF → ID → EX → MEM → WB の 5 段構造、EX/MEM と MEM/WB からの
Forwarding、WB → ID の読み出しバイパス、Load-use バブル、EX 段での
分岐判定、若い命令の Flush、例外トークンによる順序を守った停止を継承した。
`ALUV2`、`DecoderV2`、`ImmGenV2` の論理は変更していない。
`ProgramCounterV2` と `RegisterFileV2` は機能を維持しつつ、CPU 内の
パイプラインレジスタとともに reset を同期方式へ変更した（後述）。
レジスタ配列全体をリセットせず、有効ビットによって
リセット直後の読み出しをゼロとする v1.1 の Register File 方針も継承する。

ISA の位置付けも元の実行環境と同じであり、RV32I の命令デコードと実行を
備えるが、特権 CSR、割り込み、例外ベクタや OS の実行環境は追加していない。
ECALL、EBREAK、非整列アクセス、命令不正などは原因と値を保持する停止型例外
となる。FENCE は単一 hart・キャッシュなし・順序実行の構成における no-op
として扱う。命令 ROM をデータ STORE で変更する機能はない。

## メモリ配置

### BRAM 制御とリセットの変更

初回の配置配線で `REQP-1839`（BRAM 制御端子を非同期 reset FF が駆動）が
報告された。元の CPU は `always @(posedge clk or posedge reset)` であり、
BRAM のアドレスや enable がクロックとは無関係に変化し得たためである。
本版は CPU core、ProgramCounter、有効ビットの reset を `posedge clk`
内で評価する同期方式へ変更した。さらに `PuyoSystem` で reset を 1 段の
同期 FF (`cpu_reset`) に通してから core に渡し、`!reset` の組合せゲートも
非同期 FF から直接 BRAM 制御へ伝搬しない構成とした。

外部 SW15 / MMCM unlock はまず `ResetSync` で非同期 assert・3 クロック同期
解除される。その後 CPU 用 FF の 1 クロックが加わる。CPU 単体を再利用する際も
**reset と cpu_enable は clk に同期した信号として与える**。MMIO 応答信号も
同一クロック領域であることが前提で、非同期 ready を直結しない。
ゲーム再開始は CPU reset ではない。CPU RAM 配列に runtime reset は追加していない。

| 空間 | CPU アドレス | 容量・アクセス |
|---|---|---|
| 命令 ROM | 命令 PC `0x00000000`–`0x00003fff` | 4096 × 32 bit、16 KiB、同期読出し |
| 旧データ RAM | データ `0x00000000`–`0x000000ff` | 旧 256 B を維持、下記 RAM 先頭への別名 |
| 旧入力 MMIO | `0x00000100` | LW のみ、同期済み `input_port` |
| 旧 LED MMIO | `0x00000104` | LW/SW のみ、下位 8 bit |
| 拡張データ RAM | `0x00001000`–`0x00001fff` | 1024 × 32 bit、4 KiB、同期読出し |
| 外部周辺 MMIO | `0x00002000`–`0x000020ff` | 整列 LW/SW、外部 ready 応答 |

命令とデータは Harvard 空間であり、同じ数値のアドレスでも独立している。
RAM は LB/LBU/LH/LHU/LW、SB/SH/SW に対応し、little-endian とする。
旧 RAM `0x00` と拡張 RAM `0x1000` は同じ物理 word、`0xff` と `0x10ff`
も同じ物理 byte である。別々の RAM と解釈しないこと。
非整列アクセスは EX 段で例外となり、実メモリ要求は発行しない。
上記以外のデータアドレスはアクセス例外になる。外部 MMIO 窓内の未定義
レジスタの動作はプラットフォームの MMIO デコーダで定義する。

`PipelineInstructionMemoryV31` と `PipelineDataMemoryV31` は同期読出しの
block RAM 推論用テンプレートを用いる。データ RAM は 4 本の byte write
enable を持つ 1 個の 1024 × 32 bit 配列である。配列に runtime reset を
適用していない。FPGA コンフィギュレーション時にデータをゼロ、未使用 ROM を
NOP で初期化し、ROM ファイルを読み込む。CPU reset は物理 RAM の内容を保持
するので、ソフトウェアは作業領域を必要に応じて初期化する。
`ENABLE_MEM_DEBUG=1` の非同期 debug 読出しはシミュレーション専用であり、
合成用 top では必ず 0 とする。BRAM の実割当数と読出し構造は、対象部品での
Vivado 合成結果を確認する。ROM の未使用領域が大きいため最適化によって
物理的な割当量が宣言容量より減る場合がある。

## 応答トークンと全段保持

本版では、5 段の論理構成を維持しながら安全に同期メモリへ移行するため、
IF と MEM の応答が揃うまで全段を保持する。高スループットの独立した
instruction cache や speculative fetch queue は実装していない。

1. `fetch_done=0` の間に 1 回だけ命令 ROM を読出す。立上りで同期読出し
   結果と `fetch_done=1` が保持される。
2. MEM に有効な LOAD/STORE がある場合、`mem_done=0` の間に RAM または
   MMIO 要求を発行する。RAM はその立上りで読出し／書込みを完了する。
   外部 MMIO は `mmio_valid && mmio_ready` の立上りで 1 回だけ受理する。
3. RAM 応答または MMIO 応答を保持して `mem_done=1` とする。MEM が無効、
   例外トークン、またはメモリ命令でなければ MEM 応答待ちは不要である。
4. `cpu_enable && fetch_done && mem_complete && !fault` の立上りで全段を
   1 回進める。その後に応答トークンを解除し、次の段階の要求を発行する。

同期読出しを行う立上りと、そのデータを取り込んでパイプラインを進める
立上りを分けているため、依存も分岐もない連続命令でも、基本の進行間隔は
2 物理クロックである。Load-use の「1 Stall」は 1 論理バブルを意味し、
さらにこのメモリ取得時間が加わる。したがって v3 の CPI と同一ではない。
高いクロック周波数だけを根拠に v3 より高速化したとは評価しない。
将来、IF 応答キューや段ごとの valid/ready を導入してこの全段待機を減らす
余地がある。

最も重要な STORE の実行条件は `mem_issue && ex_mem_mem_write` である。
一度応答を受けた命令は `mem_done=1` により要求を再発行しない。
パイプラインが待っていても、RAM 書込み、LED 更新、MMIO の読出し副作用や
ゲームコマンドが繰り返されることはない。MMIO の受信側も必ず valid と
ready の両方が 1 の立上りだけを副作用の発生条件にする。

`cpu_enable=0` は新しい要求と retirement を停止する。完了済み応答は保持
されるので再開時に失わない。未完了の MMIO は valid が一時的に 0 となる。
このインターフェースは **単一の同期 ready/valid 受理**を意味し、valid だけ
を先に受理する split transaction バスではない。外部装置は valid と ready
が同時に立った時だけ要求を実行する必要がある。ゲーム top は常時実行とし、
1 Hz／10 Hz の観察用 enable とゲーム時間を結合しない。

分岐または例外を EX で検出しても、まだ古い MEM 要求が完了していなければ
全段を保持する。古い要求が完了して段を進める際に IF/ID と ID/EX を Flush
する。同時に fetch 応答トークンを解除し、次の fetch は更新済み PC に対して
発行する。このため分岐前の同期 ROM 応答が誤った命令として再利用されない。
例外は元と同様に WB まで進め、古い命令を retire させた後で停止する。

## 性能カウンタ

全カウンタは reset で 0、32 bit で循環する。MMIO アドレスは top の表を参照。

| 出力 | 意味 |
|---|---|
| `counter_cycle` | reset 解除後の物理クロック数。pause や fault 停止中も増える |
| `counter_instret` | 正常に retire した動的命令数。例外命令は含めない |
| `counter_mem_stall` | 実行 enable 中、応答不足で全段を進めなかったクロック数 |
| `counter_load_stall` | 実際に挿入した load-use 論理バブル数 |
| `counter_flush` | 採用した分岐／ジャンプまたは EX 例外による Flush イベント数 |

`mem_stall` は IF 同期読出し時間も含むため、データ RAM 待機だけの値では
ない。`flush` は捨てた命令数ではない。停止を含まない同じプログラム区間で
cycle と instret の差分を取得し、CPI = Δcycle / Δinstret とする。CPU の
実行時間は Δcycle / 実際の CPU クロック周波数で評価する。

## RV32I ファームウェアとゲーム回路の担当範囲

`firmware/puyo_supervisor.S` は、ROM の固定デモを置き換える実際の RV32I
プログラムである。ゲーム開始、入力イベントの読み出し、操作コマンドの送信、
スコアの読み出し、LED への表示を反復する。`build_firmware.py` は使用する
LUI、ADDI、LW、SW、JAL だけを厳密にエンコードする小規模アセンブラであり、
外部 C コンパイラなしで ROM を再生成できる。一般的な GNU assembler の
全構文を扱うものではない。

この初版のゲームの衝突判定、盤面更新、重力、連結探索、消去、連鎖、得点は
**独立した Verilog のゲーム処理器**が行う。RISC-V CPU がプログラムとして
ゲームの全ルールを実行する実装ではない。卒論では「RISC-V CPU と MMIO
ゲーム処理器を統合したシステム」「CPU からの入力転送と表示状態監視」と
記述できる。「ぷよぷよの全ロジックを RV32I ソフトウェアで実行した」とは
記述できない。今後全ルールをソフトウェアへ移す際も、同じメモリ応答基盤、
入力 MMIO、表示インターフェースを活用できる。

## 検証と再現

`scripts/run_cpu_tests.ps1` は元の 11 個の CPU 単体・ISA 回帰テストを本コアに
適用し、新規 `tb_cpu_platform` を加える。旧 board top 自体のテストは
`baseline_v3` に残る。移行した回帰テストは module 名と、同期メモリの実要求
時点で STORE 数を数える監視条件を調整した。命令・期待される値・例外条件は
維持する。reset の確認は v3.1 の同期 reset 仕様に合わせ、立上り後に PC と
パイプラインのクリアを検査する。`tb_cpu_lutram_reset` ではさらに、reset を
assert しても次のクロック以前には PC / RF が変化しないことを確認する。
テストの時間上限が同期メモリに不足する場合は明記して拡張する。

新規テストでは同期 RAM の byte lane と符号拡張、先頭 alias、最終 word、
load-use、遅延 MMIO 応答、受理前／応答保持後の CPU pause、分岐後の不正命令
と STORE の破棄、正確な EBREAK、STORE の非重複、retirement と各カウンタを
確認する。テスト結果は `docs/VALIDATION.md` または全体 README を参照する。
シミュレーション合格だけで配置配線後の動作周波数や FPGA 実機動作は確定しない。

タイミング制約は実際に供給する CPU クロックの周期で設定する。メモリ待機が
あることだけを理由に全データ経路を一括 multicycle にしない。reset の同期解除
と外部入力の同期化は board top 側で行い、異なるクロックがある場合の表示データ
転送はプラットフォームの clock-domain 設計に従う。
