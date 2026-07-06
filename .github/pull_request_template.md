## Summary

<!-- What does this change, and why? Link any related issue. -->

## Checklist

- [ ] Compiles on both Delphi and Free Pascal (`{$MODE DELPHI}`)
- [ ] Works on the platforms it touches (Linux x86-64 / ARM64 / ARM32, macOS, Windows)
- [ ] Ported logic keeps (or adds) its `{ ev.c:NNNN name }` reference to the libev source
- [ ] On FPC, platform types/syscalls come from the RTL — no needless hand-rolled `external` bindings
- [ ] Comments and messages are in English; no AI-attribution text anywhere
- [ ] `docs/MANUAL.md` / `README.md` updated if the public API changed
- [ ] The relevant `examples/` demo still passes, or a new self-testing demo was added
