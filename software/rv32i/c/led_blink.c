/**
 * led_blink.c — Lチカ (ナイトライダー) for AXIUART_RV32I
 *
 * LED MMIO アドレス: 0x8000407C
 *   bit[3:0] → LED[3:0]
 *
 * パターン: 0001 → 0010 → 0100 → 1000 → 繰り返し
 *
 * ビルド:
 *   riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Os
 *                      -T rv32i_bram.ld crt0.s led_blink.c -o led_blink.elf
 */

/* LED MMIO レジスタアドレス (CPU アドレス空間) */
#define LED_ADDR   ((volatile unsigned int *)0x8000407CU)

/*
 * ソフトウェアディレイ
 * 125MHz クロックで約 250ms:
 *   DELAY_CYCLES = 125_000_000 * 0.25 / 2 ≈ 15_625_000
 *   (ループ1回 = 約2サイクル: ADDI + BNE)
 */
#define DELAY_CYCLES  15625000U

static void delay(void)
{
    volatile unsigned int cnt = DELAY_CYCLES;
    while (cnt--) {
        /* 何もしない (最適化されないよう volatile) */
    }
}

int main(void)
{
    /* ナイトライダーパターン: bit0 → bit1 → bit2 → bit3 → 繰り返し */
    static const unsigned int patterns[] = { 0x1U, 0x2U, 0x4U, 0x8U };
    const unsigned int n_patterns = sizeof(patterns) / sizeof(patterns[0]);
    unsigned int i = 0;

    for (;;) {
        *LED_ADDR = patterns[i];
        delay();
        i = (i + 1 >= n_patterns) ? 0U : i + 1U;
    }

    /* never reached */
    return 0;
}
