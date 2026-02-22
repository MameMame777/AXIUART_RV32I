/* crt0.s — RV32I ベアメタル最小スタートアップ
 *
 * BRAM レイアウト (8KB = 0x80000000 – 0x80001FFF):
 *   .text  : 0x80000000 〜 (コード)
 *   .data  : コード直後 (初期化済みグローバル変数)
 *   .bss   : .data 直後 (未初期化グローバル変数, ゼロクリア)
 *   stack  : 0x80001FF0 から下向き
 */

    .section .text.start, "ax"
    .global  _start
    .type    _start, @function

_start:
    /* スタックポインタを BRAM 末尾に設定 (8バイトアライン) */
    lui  sp, 0x80002          /* sp = 0x80002000 */
    addi sp, sp, -16          /* sp = 0x80001FF0 */

    /* .bss セクションをゼロクリア */
    la   a0, __bss_start
    la   a1, __bss_end
    beq  a0, a1, .Lbss_done
.Lbss_loop:
    sw   zero, 0(a0)
    addi a0, a0, 4
    blt  a0, a1, .Lbss_loop
.Lbss_done:

    /* main を呼び出す */
    call main

    /* main が戻っても無限ループ (リセットなし) */
.Lhalt:
    j    .Lhalt

    .size _start, . - _start
