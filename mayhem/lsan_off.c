/* Disable LeakSanitizer at build time (never at runtime, never via ASAN_OPTIONS — Mayhem alone
 * owns the runtime ASan/LSan option set). hicolor's CLI is a short-lived, run-once-per-input
 * process whose `encode`/`quantize`/`decode` paths intentionally do not free every allocation
 * before exit, so LSan's default leak checks would fire on nearly every input and bury the real
 * memory-safety bugs (ASan's heap/stack/global out-of-bounds and use-after-free stay fully active).
 */
int __lsan_is_turned_off(void) { return 1; }
