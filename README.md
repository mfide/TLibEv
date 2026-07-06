# TLibEv

[![CI](https://github.com/mfide/TLibEv/actions/workflows/ci.yml/badge.svg)](https://github.com/mfide/TLibEv/actions/workflows/ci.yml)

An object-oriented, line-by-line port of [libev 4.33](http://software.schmorp.de/pkg/libev.html)
to Delphi and Free Pascal / Lazarus.

- **Version:** TLibEv 1.0 (an original library, versioned on its own; it ports libev 4.33)
- **Platforms:** Linux (epoll or poll backend), macOS (poll backend) and Windows (winsock select backend)
- **Architectures:** Linux on x86-64, ARM64 (aarch64) and 32-bit ARM, and macOS on Apple Silicon — Free Pascal takes its platform types and syscalls from the RTL, so they are laid out per OS and architecture; Windows on x86/x64. macOS is a Free Pascal target; Delphi's Linux target is x86-64 only.
- **Compilers:** Delphi 12+/13 (`dcc32`, `dcc64`, `dcclinux64`) and FPC 3.2+ (`{$MODE DELPHI}`)
- **License:** 2-clause BSD (see `LICENSE`; derivative of libev, BSD option exercised)

Every method is annotated with an `ev.c:NNNN name` comment pointing at the
corresponding line of the upstream [libev 4.33](http://software.schmorp.de/pkg/libev.html)
C source, so the port can be audited against it side by side. The C source
itself is not redistributed here — fetch it from the link above if you want to
follow the references.

## Installation

There is no package to install and no external dependency: just add
[`src/LibEv.pas`](src/LibEv.pas) to your project (or put its folder on your unit
search path) and `uses LibEv`.

**Full manual:** [docs/MANUAL.md](docs/MANUAL.md) - a faithful adaptation of
libev's `ev.pod` documentation to this port's API, covering loop semantics,
every watcher type in depth, common idioms and algorithmic complexities.

## Watchers

| Class | libev type | Purpose |
|---|---|---|
| `TEvIo` | `ev_io` | fd readable/writable |
| `TEvTimer` | `ev_timer` | relative timer (monotonic clock), `Again`, `Remaining` |
| `TEvPeriodic` | `ev_periodic` | wall-clock timer with interval/reschedule callback |
| `TEvSignal` | `ev_signal` | signals (sigaction on Linux, CRT `signal()` on Windows) |
| `TEvChild` | `ev_child` | child process status via SIGCHLD (Linux only, default loop) |
| `TEvStat` | `ev_stat` | path attribute changes; inotify fast path on Linux, timed polling elsewhere |
| `TEvIdle` | `ev_idle` | runs when nothing else is pending |
| `TEvPrepare` / `TEvCheck` | `ev_prepare` / `ev_check` | around each poll |
| `TEvFork` | `ev_fork` | fires in the child after `LoopFork` |
| `TEvCleanup` | `ev_cleanup` | fires when the loop is destroyed |
| `TEvAsync` | `ev_async` | thread-safe loop wakeup (`Send`) |

Plus `TEvLoop.Once` (`ev_once`), `TEvLoop.Verify` (`ev_verify`), `Suspend`/`Resume`,
`Ref`/`Unref`, `IoCollectInterval`/`TimeoutCollectInterval`.

## Example

```pascal
uses LibEv;

type
  TApp = class
    procedure OnTick(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnRead(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;

procedure TApp.OnTick(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Writeln('tick at ', Loop.Now:0:3);
end;

procedure TApp.OnRead(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  // socket TEvIo(W).Fd is readable
end;

var
  Loop: TEvLoop;
  Timer: TEvTimer;
  Io: TEvIo;
  App: TApp;
begin
  App := TApp.Create;
  Loop := TEvLoop.Default;

  Timer := TEvTimer.Create(1.0, 1.0); // after 1s, repeat every 1s
  Timer.OnTimeout := App.OnTick;
  Timer.Start(Loop);

  Io := TEvIo.Create(SocketFd, [evRead]);
  Io.OnEvent := App.OnRead;
  Io.Start(Loop);

  Loop.Run;
end;
```

The `examples/` folder has a self-testing program for every feature:

| Demo | Shows |
|---|---|
| `TimerDemo` | timers and periodics |
| `IoDemo` / `EchoDemo` | socket I/O (UDP; a full non-blocking TCP echo server) |
| `AsyncDemo` | cross-thread wakeup with `TEvAsync` |
| `SignalDemo` | signal and child watchers, forking a child (Linux) |
| `SignalSelfDemo` | signal watcher, raising SIGINT to self (Linux and Windows) |
| `SignalFdDemo` | signal delivery via signalfd, `evflagSignalFd` (Linux) |
| `ForkDemo` | fork watcher (Linux) |
| `StatDemo` | path watching, `Once` and cleanup watchers |
| `LoopHooksDemo` | `TEvPrepare` / `TEvCheck` / `TEvIdle` |
| `TimeoutDemo` | the inactivity-timeout idiom with `Again` |
| `PriorityDemo` | watcher priorities |
| `ExtrasDemo` | `FeedEvent`, `Suspend`/`Resume`, collect intervals |
| `HooksDemo` | `Invoke`, `FeedFdEvent`, invoke-pending / release-acquire hooks |
| `PollDemo` | selecting the poll backend explicitly (Linux) |
| `KeyDemo` | one event per keypress, with Unicode (interactive) |
| `UartLoopbackDemo` | event-driven serial I/O (Linux via a PTY pair; Windows on a real COM port with a physical RX↔TX loopback) |

Every demo except the interactive `KeyDemo` drives its own scenario and exits
non-zero on failure, so they double as the test suite that CI runs.

## Building

Windows (Delphi):

```powershell
cd examples
dcc64 -B "-NSSystem;Winapi;System.Win" -U..\src -E..\bin EchoDemo.dpr
```

Linux (Delphi cross-compile; SDK installed via PAServer, e.g. ubuntu24.04.sdk):

```powershell
$sdk = "$env:USERPROFILE\Documents\Embarcadero\Studio\SDKs\ubuntu24.04.sdk"
$bds = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$lp  = "$bds\lib\linux64\release;$sdk\lib\x86_64-linux-gnu;$sdk\usr\lib\x86_64-linux-gnu;$sdk\usr\lib\gcc\x86_64-linux-gnu\13"
dcclinux64 -B -U..\src -E..\binlinux "--syslibroot:$sdk" "--libpath:$lp" EchoDemo.dpr
```

Linux (FPC):

```bash
cd examples
fpc -Mdelphi -Sh -Fu../src EchoDemo.dpr
```

Define `EV_VERIFY_2` to run the `ev_verify` consistency checks on every loop
iteration (debug builds).

## Backends and extras

- **Backends:** epoll (default) or poll on Linux, poll on macOS, select on
  Windows. Request one with `TEvLoop.Create([], [evbackendPoll])`; the choice is
  fixed for the loop's lifetime. `EvSupportedBackends`/`EvRecommendedBackends`
  report them.
- **Signals:** `sigaction` on Linux/macOS, `signalfd` with `evflagSignalFd`
  (Linux), or the CRT `signal()` on Windows.
- **timerfd** time-jump detection is used by default on Linux (disable with
  `evflagNoTimerFd`).
- **Extensibility:** `EvSetSyserrCb`, `Watcher.Invoke`, `Loop.FeedFdEvent`,
  `SetInvokePendingCb`, `SetLoopReleaseCb` (threaded loop sharing).
- **Platform layer:** on Free Pascal the OS types, structs and syscalls come
  from the RTL units (`BaseUnix`, `UnixType`, `Linux`), which define them per OS
  and architecture — that is what makes the same source correct on Linux
  (x86-64, arm64, arm32) and macOS. Delphi/Linux keeps hand-written x86-64
  bindings (its Linux compiler targets x86-64 only). The Linux-only kernel
  interfaces (epoll, inotify, `eventfd`, `signalfd`, `timerfd`) and child
  watchers are absent on macOS, where signals use `sigaction`, `TEvStat` polls,
  and the wakeup pipe is a plain pipe.

## Notes / deviations from C

- Event masks are Pascal sets (`TEvEvents`); enum ordinals equal the C bit numbers.
- On Windows an "fd" is the `SOCKET` value itself (no CRT fd layer).
- Watchers are objects owned by the caller; destroying an active watcher stops it first.
- Backend selection has no fallback chain (a failed backend raises rather than
  trying the next), and `LIBEV_FLAGS` is not consulted.
- On macOS the poll backend is used (the native kqueue backend is not ported);
  `TEvChild` is Linux-only (as in libev on non-Linux).
- Not ported: `ev_embed` (needs embeddable backends like kqueue), the kqueue /
  Solaris ports / Linux aio / io_uring backends, custom allocators, and
  `ev_walk` (off by default in C too).

## Testing

Each program in `examples/` is self-checking (it drives the loop and verifies
the observed behaviour, returning a non-zero exit code on failure). On every
push, CI compiles and runs them with Free Pascal on:

- Linux x86-64, Windows and macOS (Apple Silicon) hosted runners,
- Linux ARM64 (a hosted `ubuntu-24.04-arm` runner),
- Linux 32-bit ARM (an `armhf` container under QEMU emulation).
