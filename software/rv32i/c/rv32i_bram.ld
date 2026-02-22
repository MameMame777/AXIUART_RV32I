/* rv32i_bram.ld — AXIUART_RV32I BRAM リンカスクリプト
 *
 * BRAM: 0x80000000 – 0x80001FFF (8 KB)
 * MMIO: 0x80004000 – 0x80007FFF (ペリフェラル、リンカは管理しない)
 *
 * セクション配置:
 *   .text  → BRAM 先頭 (実行コード)
 *   .data  → .text 直後 (初期化済みグローバル変数)
 *   .bss   → .data 直後 (未初期化グローバル変数)
 *   stack  → BRAM 末尾から下向き (crt0.s で設定)
 */

MEMORY
{
    BRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 8K
}

ENTRY(_start)

SECTIONS
{
    /* ── 実行コード ── */
    .text ORIGIN(BRAM) :
    {
        /* スタートアップを必ず先頭に配置 */
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > BRAM

    /* ── 初期化済みグローバル変数 ── */
    .data :
    {
        . = ALIGN(4);
        *(.data .data.*)
        . = ALIGN(4);
    } > BRAM

    /* ── 未初期化グローバル変数 (crt0.s でゼロクリア) ── */
    .bss :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > BRAM

    /* BRAM 使用量チェック: 8KB を超えたらリンクエラー */
    ASSERT(. <= ORIGIN(BRAM) + LENGTH(BRAM) - 256,
           "ERROR: BRAM overflow! Code+data exceeds 8KB limit.")

    /* デバッグ情報 (バイナリには含めない) */
    /DISCARD/ :
    {
        *(.comment)
        *(.note.*)
    }
}
