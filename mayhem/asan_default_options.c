/* Weak __asan_default_options baked into the sanitized hicolor binary.
 *
 * hicolor's CLI is a short-lived, run-once-per-input process whose `encode`/`quantize`/`decode`
 * paths intentionally do NOT free every allocation before exit (e.g. the `alpha` buffer and the
 * generated `arg_dest` string, and `rgb_img` on some libpng error paths). Under ASan's default
 * leak detection those benign process-exit leaks fire on essentially EVERY input, which would
 * drown out the real memory-safety bugs Mayhem is meant to find in the PNG/HiColor parsing code.
 * Disable leak detection (detect_leaks=0) while keeping all of ASan's heap/stack/global
 * out-of-bounds and use-after-free checks ON and halting. This is linked as a weak symbol so it is
 * a default that can still be overridden at runtime via ASAN_OPTIONS if ever needed.
 *
 * NOTE: we do NOT set ASAN_OPTIONS in the Mayhemfile (Mayhem owns the runtime option set); baking
 * the default into the binary is the supported way to turn leak detection off for fuzzing.
 */
const char *__asan_default_options(void) {
    return "detect_leaks=0";
}
