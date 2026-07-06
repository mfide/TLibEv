# TLibEv Manual

*This manual is a faithful adaptation of libev's `ev.pod` documentation
(<http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod>) for the TLibEv
Delphi/Free Pascal port. The section structure mirrors the original; text
has been adjusted to the object-oriented Pascal API, and sections that do
not apply to this port are kept as short stubs explaining why.*

## NAME

TLibEv - a high performance full-featured event loop, ported line-by-line
from libev (C) to Delphi / Free Pascal.

## SYNOPSIS

```pascal
uses LibEv;
```

### EXAMPLE PROGRAM

```pascal
program Example;
{$APPTYPE CONSOLE}
uses LibEv;

type
  // callbacks are "of object" methods, so they live on some class
  TApp = class
    procedure IoCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
    procedure TimeoutCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
  end;

// all watcher callbacks have the same signature.
// this callback is called when the socket is readable
procedure TApp.IoCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  Writeln('socket ready');
  // for one-shot events, one must manually stop the watcher
  // with its Stop method.
  W.Stop;
  // this causes all nested Run calls to stop iterating
  Loop.BreakLoop(evbreakAll);
end;

// another callback, this time for a time-out
procedure TApp.TimeoutCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  Writeln('timeout');
  // this causes the innermost Run to stop iterating
  Loop.BreakLoop(evbreakOne);
end;

var
  App: TApp;
  Loop: TEvLoop;
  IoWatcher: TEvIo;
  TimeoutWatcher: TEvTimer;
begin
  App := TApp.Create;

  // use the default event loop unless you have special needs
  Loop := TEvLoop.Default;

  // create an io watcher, then start it
  // this one will watch for a socket to become readable
  IoWatcher := TEvIo.Create(SomeSocketFd, [evRead]);
  IoWatcher.OnEvent := App.IoCb;
  IoWatcher.Start(Loop);

  // create a timer watcher, then start it
  // simple non-repeating 5.5 second timeout
  TimeoutWatcher := TEvTimer.Create(5.5, 0);
  TimeoutWatcher.OnTimeout := App.TimeoutCb;
  TimeoutWatcher.Start(Loop);

  // now wait for events to arrive
  Loop.Run;

  // break was called, so exit
end.
```

## ABOUT THIS DOCUMENT

This document documents the TLibEv port of the libev software package. It
tries to be as complete as the original in documenting the library, its
usage and the rationale behind its design, but it is not a tutorial on
event-based programming, nor will it introduce event-based programming
with TLibEv. Familiarity with event based programming techniques in
general is assumed throughout this document.

## WHAT TO READ WHEN IN A HURRY

This manual tries to be very detailed, but unfortunately, this also makes
it very long. If you just want to know the basics, read
[ANATOMY OF A WATCHER](#anatomy-of-a-watcher), then the example program
above, and look up the missing pieces in
[GLOBAL FUNCTIONS](#global-functions) and the `TEvIo` and `TEvTimer`
sections in [WATCHER TYPES](#watcher-types).

## ABOUT LIBEV / TLIBEV

Libev is an event loop: you register interest in certain events (such as
a file descriptor being readable or a timeout occurring), and it will
manage these event sources and provide your program with events.

To do this, it must take more or less complete control over your process
(or thread) by executing the *event loop* handler, and will then
communicate events via a callback mechanism.

You register interest in certain events by registering so-called *event
watchers*, which in this port are ordinary Pascal objects you construct
with the details of the event, and then hand over to the library by
*starting* the watcher.

### FEATURES

This port supports the Linux-specific `epoll` interface and a `select`
backend (the only viable mechanism on Windows) for file descriptor events
(`TEvIo`), the Linux `inotify` interface (for `TEvStat`), Linux
`eventfd` for faster and cleaner inter-thread wakeup (`TEvAsync`),
relative timers (`TEvTimer`), absolute timers with customised
rescheduling (`TEvPeriodic`), synchronous signals (`TEvSignal`), process
status change events (`TEvChild`), and event watchers dealing with the
event loop mechanism itself (`TEvIdle`, `TEvPrepare` and `TEvCheck`
watchers) as well as file watchers (`TEvStat`) and limited support for
fork events (`TEvFork`).

*(The C original additionally supports `poll`, Linux aio/io_uring, BSD
`kqueue` and Solaris event ports, plus loop embedding via `ev_embed`;
those backends and `ev_embed` are not part of this port.)*

### CONVENTIONS

Libev is very configurable at C compile time; this port corresponds to
the default (and most common) configuration, which supports multiple
event loops. Wherever the C API takes a `struct ev_loop *loop` first
parameter, the port uses a `TEvLoop` instance: either as the object a
method is called on (`Loop.Run`), or as the argument of `Watcher.Start`.

### TIME REPRESENTATION

Libev represents time as a single floating point number, representing
the (fractional) number of seconds since the (POSIX) epoch (in practice
somewhere near the beginning of 1970, details are complicated, don't
ask). This type is called `TEvTstamp` (= `Double`). Unlike the name
component *stamp* might indicate, it is also used for time differences
(e.g. delays) throughout the library.

## ERROR HANDLING

Libev knows three classes of errors: operating system errors, usage
errors and internal errors (bugs).

For a retryable operating-system error (a failed `select`/`poll`/
`epoll_wait`), the port routes through a settable callback just like C's
`ev_set_syserr_cb`: call `EvSetSyserrCb` to install one. With no callback
set, the default **raises an `EEvError` exception** (a catchable,
Pascal-idiomatic replacement for C's default of printing a message and
calling `abort()`).

Where the C library detects usage errors (such as a negative timer
interval) via `assert`, **this port raises `EEvError`** with the same
message text as the C assertion. These are programming errors in the
calling code and need to be fixed there.

Consistency checking of the loop's internal structures is available via
`TEvLoop.Verify` (see below) and, when the unit is compiled with
`EV_VERIFY_2` defined, runs automatically on every loop iteration.

## GLOBAL FUNCTIONS

These functions can be called anytime, even before creating any loop.

### function EvTime: TEvTstamp

Returns the current time as the library would use it. Please note that
the `TEvLoop.Now` property is usually faster and also often returns the
timestamp you actually want to know. Also interesting is the combination
of `NowUpdate` and `Now`.

### procedure EvSleep(Delay: TEvTstamp)

Sleep for the given interval: The current thread will be blocked until
either it is interrupted or the given time interval has passed
(approximately - it might return a bit earlier even if not interrupted).
Returns immediately if `Delay <= 0`. Basically this is a
sub-second-resolution `Sleep`. Only sleep times of up to one day
(`Delay <= 86400`) are guaranteed to work.

### function EvClock: TEvTstamp

*(Port extra.)* Returns the current monotonic clock value, the time base
used by `TEvTimer`. Exposed mainly for tests and diagnostics.

### TLIBEV_VERSION_MAJOR / TLIBEV_VERSION_MINOR / TLIBEV_VERSION

This library's own version (currently 1.0). TLibEv is versioned
independently: it is a line-by-line port of libev, but a Delphi / Free
Pascal library in its own right. `LIBEV_UPSTREAM_VERSION` records the libev
release the port follows (`'4.33'`).

### EvSupportedBackends / EvRecommendedBackends / EvEmbeddableBackends

Return the backends compiled into this build as a `TEvBackendKinds` set.
On Linux `EvSupportedBackends` is `[evbackendEpoll, evbackendPoll]` and
`EvRecommendedBackends` is `[evbackendEpoll]`; on Windows both are
`[evbackendSelect]`. `EvEmbeddableBackends` is always `[]` (no embeddable
backend is compiled). Use `TEvLoop.Backend.Kind` to see which one a given
loop actually uses.

### procedure EvSetSyserrCb(Cb: TEvSyserrCb)

Ports `ev_set_syserr_cb`: set the callback invoked on a retryable syscall
error (see ERROR HANDLING). With no callback, the default raises
`EEvError`. `ev_set_allocator` is *not* ported — memory is managed by the
Pascal runtime.

### procedure EvFeedSignal(SigNum: Integer)

This function can be used to "simulate" a signal receive. It is
completely safe to call this function at any time, from any context,
including signal handlers or random threads.

Its main use is to customise signal handling in your process: you could
block signals by default in all threads, and in one thread use
`sigwait` or any other mechanism to wait for signals, then "deliver"
them to the library by calling `EvFeedSignal`.

## FUNCTIONS CONTROLLING EVENT LOOPS

An event loop is described by a `TEvLoop` instance. The library knows two
types of such loops, the *default* loop, which supports child process
events, and dynamically created event loops which do not.

### class function TEvLoop.Default: TEvLoop

This returns the "default" event loop object, which is what you should
normally use when you just need "the event loop". It is created lazily on
the first call and returned unchanged afterwards.

If you don't know what event loop to use, use the one returned from this
function.

Note that this function is *not* thread-safe, so if you want to use it
from multiple threads, you have to employ some kind of mutex (note also
that this case is unlikely, as loops cannot be shared easily between
threads anyway).

The default loop is the only loop that can handle `TEvChild` watchers,
and to do this, it always registers a handler for `SIGCHLD` (on Linux).
If this is a problem for your application you can create a dynamic loop
with `TEvLoop.Create`, which doesn't do that.

### constructor TEvLoop.Create(AFlags: TEvFlags = []; ABackends: TEvBackendKinds = [])

This creates and initialises a new event loop object. If the backend
cannot be initialised, `EEvError` is raised (the C API returns `nil`
instead).

This is also the way to create per-thread loops: one common way to use
the library with threads is to create one loop per thread, and use the
default loop in the "main" or "initial" thread.

`ABackends` requests a specific backend. On Linux, `[evbackendPoll]`
forces the poll backend; `[]` (the default) uses the recommended one
(epoll on Linux). macOS always uses poll and Windows always uses select.
The choice is made here, once, and stays fixed for the loop's lifetime.

The `AFlags` argument can be used to specify special behaviour, and is
usually specified as `[]` (the equivalent of C's `EVFLAG_AUTO`).

The following flags are supported:

- **`[]` (EVFLAG_AUTO)** - The default flags value. Use this if you have
  no clue (it's the right thing, believe me).

- **`evflagForkCheck` (EVFLAG_FORKCHECK)** *(Linux)* - Instead of calling
  `LoopFork` manually after a fork, you can also make the library check
  for a fork in each iteration by enabling this flag. This works by
  calling `getpid()` on every iteration of the loop, and thus this might
  slow down your event loop if you do a lot of loop iterations and little
  real work, but is usually not noticeable. The big advantage of this
  flag is that you can forget about fork (although you still have to
  ignore `SIGPIPE`).

- **`evflagNoInotify` (EVFLAG_NOINOTIFY)** *(Linux)* - When this flag is
  specified, the library will not attempt to use the *inotify* API for
  its `TEvStat` watchers. Apart from debugging and testing, this flag can
  be useful to conserve inotify file descriptors, as otherwise each loop
  using `TEvStat` watchers consumes one inotify handle.

- **`evflagSignalFd` (EVFLAG_SIGNALFD)** *(Linux)* - Deliver signals
  through a `signalfd` (blocked and read from a file descriptor) instead
  of a sigaction handler + wakeup pipe. Off by default, as in C.

- **`evflagNoTimerFd` (EVFLAG_NOTIMERFD)** *(Linux)* - Do not use a
  `timerfd` to detect time jumps. A timerfd is created by default when the
  first `TEvPeriodic` starts; with this flag the port falls back to the
  monotonic-clock interpolation path (still correct, just polls the
  realtime clock more often).

- **`evflagNoEnv` (EVFLAG_NOENV)** - Kept for parity with C, but has no
  effect: this port never consults the `LIBEV_FLAGS` environment
  variable.

- *(Not ported: `EVFLAG_NOSIGMASK` - the port never modifies the signal
  mask outside the signalfd path.)*

Backend selection: pass the wanted backend in `ABackends` (above). On
Linux `[evbackendPoll]` selects poll, otherwise epoll is used; Windows
always uses select. Unlike C there is no fallback chain (if the requested
backend's kernel object cannot be created, `EEvError` is raised rather
than trying the next backend). The backends:

- **select** (`evbackendSelect`, C value 1) - The standard select(2)
  backend, and the only mechanism used on Windows. This port rolls its
  own `fd_set` with a capacity of 1024 sockets (the winsock default is
  64). It doesn't scale too well (O(highest_fd)), but it's usually the
  fastest backend for a low number of fds. To get good performance out of
  this backend you need a high amount of parallelism (most of the file
  descriptors should be busy). If you are writing a server, you should
  `accept()` in a loop to accept as many connections as possible during
  one iteration. You might also want to have a look at
  `IoCollectInterval` to increase the amount of readiness notifications
  you get per iteration. This backend maps `evRead` to the `readfds` set
  and `evWrite` to the `writefds` set, and (to work around Microsoft
  Windows bugs) also onto the `exceptfds` set on that platform.

- **epoll** (`evbackendEpoll`, C value 4) - The Linux-specific epoll(7)
  interface. For few fds, this backend is a bit little slower than poll
  and select, but it scales phenomenally better: while poll and select
  usually scale like O(total_fds), epoll scales either O(1) or
  O(active_fds).

  The epoll mechanism deserves honorable mention as the most misdesigned
  of the more advanced event mechanisms: mere annoyances include silently
  dropping file descriptors, requiring a system call per change per file
  descriptor (and unnecessary guessing of parameters), problems with dup,
  returning before the timeout value, and so on. The biggest issue is
  fork races - if a program forks then *both* parent and child process
  have to recreate the epoll set, which can take considerable time (one
  syscall per file descriptor) and is of course hard to detect. Epoll
  also loves to report events for totally *different* file descriptors
  (even already closed ones) than registered in the set. The library
  counters these spurious notifications by employing an additional
  generation counter and comparing that against the events to filter out
  spurious ones, recreating the set when required.

  Best performance from this backend is achieved by not unregistering all
  watchers for a file descriptor until it has been closed, if possible,
  i.e. keep at least one watcher active per fd at all times. Stopping and
  starting a watcher (without re-setting it) also usually doesn't cause
  extra overhead. A fork can both result in spurious notifications as
  well as in the library having to destroy and recreate the epoll object,
  which can take considerable time and thus should be avoided.

  All this means that, in practice, `select` can be as fast or faster
  than epoll for maybe up to a hundred file descriptors, depending on the
  usage.

- **poll** (`evbackendPoll`, C value 2) - The standard poll(2) backend
  (Linux; opt in with `[evbackendPoll]`). More complicated than select
  but handles sparse fds better and has no artificial limit on the number
  of fds. It scales like O(total_fds). Maps `evRead` to
  `POLLIN | POLLERR | POLLHUP` and `evWrite` to
  `POLLOUT | POLLERR | POLLHUP`. Useful as an epoll-free alternative on
  older or unusual kernels.

*(Not in this port: `kqueue`, Solaris ports, Linux aio and io_uring
backends.)*

### destructor TEvLoop.Destroy

Destroys an event loop object (frees all memory and kernel state etc.).
Cleanup watchers are queued and invoked first (see `TEvCleanup`). None of
the other active event watchers will be stopped in the normal sense, so
e.g. `IsActive` might still return true. It is your responsibility to
either stop all watchers cleanly yourself *before* destroying the loop,
or cope with the fact afterwards.

Note that per-signal global state (installed signal handlers) will not be
freed by destroying a loop, and signal/child watchers would need to be
stopped manually.

Destroying the default loop is done automatically at unit finalization;
doing it manually is rarely needed.

### procedure TEvLoop.LoopFork

This method (C: `ev_loop_fork`) sets a flag that causes subsequent `Run`
iterations to reinitialise the kernel state for the backend. Despite the
name, you can call it anytime you are allowed to start or stop watchers
(except inside a `TEvPrepare` callback), but it makes most sense after
forking, in the child process. You *must* call it (or use
`evflagForkCheck`) in the child before resuming or calling `Run`.

In addition, if you want to reuse a loop after fork, you *also* have to
ignore `SIGPIPE`.

You only need to call this function in the child process if and only if
you want to use the event loop in the child. If you just fork+exec or
create a new loop in the child, you don't have to call it at all.

The function itself is quite fast and it's usually not a problem to call
it just in case after a fork.

### function TEvLoop.IsDefaultLoop: Boolean

Returns true when the given loop is, in fact, the default loop, and false
otherwise.

### property TEvLoop.Iterations: Cardinal

Returns the current iteration count for the event loop, which is
identical to the number of times the library did poll for new events. It
starts at 0 and happily wraps around with enough iterations. This value
can sometimes be useful as a generation counter of sorts, as it roughly
corresponds with `TEvPrepare` and `TEvCheck` calls - and is incremented
between the prepare and check phases.

### property TEvLoop.Depth: Cardinal

Returns the number of times `Run` was entered minus the number of times
`Run` was exited normally, in other words, the recursion depth. Outside
`Run`, this number is zero; in a callback it is 1, unless `Run` was
invoked recursively (or from another thread), in which case it is higher.

Leaving `Run` abnormally (raising an exception through it, etc.) doesn't
count as "exit".

### property TEvLoop.Backend: TEvBackend

Returns the backend object in use; `Backend.Kind` is the `TEvBackendKind`
(`evbackendSelect` or `evbackendEpoll`) corresponding to C's
`ev_backend()` flags.

### function TEvLoop.Now: TEvTstamp

Returns the current "event loop time", which is the time the event loop
received events and started processing them. This timestamp does not
change as long as callbacks are being processed, and this is also the
base time used for relative timers. You can treat it as the timestamp of
the event occurring (or more correctly, the library finding out about
it).

### procedure TEvLoop.NowUpdate

Establishes the current time by querying the kernel, updating the time
returned by `Now` in the progress. This is a costly operation and is
usually done automatically within `Run`.

This function is rarely useful, but when some event callback runs for a
very long time without entering the event loop, updating the library's
idea of the current time is a good idea.

See also "The special problem of time updates" in the `TEvTimer` section.

### procedure TEvLoop.Suspend / procedure TEvLoop.Resume

These two functions suspend and resume an event loop, for use when the
loop is not used for a while and timeouts should not be processed.

A typical use case would be an interactive program such as a game: when
the user presses Ctrl+Z to suspend the game and resumes it an hour later,
it would be best to handle timeouts as if no time had actually passed
while the program was suspended. This can be achieved by calling
`Suspend` in your `SIGTSTP` handler, sending yourself a `SIGSTOP` and
calling `Resume` directly afterwards to resume timer processing.

Effectively, all `TEvTimer` watchers will be delayed by the time spent
between `Suspend` and `Resume`, and all `TEvPeriodic` watchers will be
rescheduled (that is, they will lose any events that would have occurred
while suspended).

After calling `Suspend` you **must not** call *any* function on the given
loop other than `Resume`, and you **must not** call `Resume` without a
previous call to `Suspend`.

Calling `Suspend`/`Resume` has the side effect of updating the event loop
time (see `NowUpdate`).

### function TEvLoop.Run(Flags: TEvRunFlags = []): Boolean

Finally, this is it, the event handler. This function usually is called
after you have initialised all your watchers and you want to start
handling events. It will ask the operating system for any new events,
call the watcher callbacks, and then repeat the whole process
indefinitely: this is why event loops are called *loops*.

If the flags argument is specified as `[]`, it will keep handling events
until either no event watchers are active anymore or `BreakLoop` was
called.

The return value is false if there are no more active watchers (which
usually means "all jobs done" or "deadlock"), and true in all other cases
(which usually means "you should call `Run` again").

Please note that an explicit `BreakLoop` is usually better than relying
on all watchers to be stopped when deciding when a program has finished
(especially in interactive programs), but having a program that
automatically loops as long as it has to and no longer by virtue of
relying on its watchers stopping correctly, that is truly a thing of
beauty.

This function is *mostly* exception-safe - you can break out of a `Run`
call by raising an exception in a callback. This does not decrement the
`Depth` value, nor will it clear any outstanding `evbreakOne` breaks.

A flags value of `[evrunNoWait]` will look for new events, will handle
those events and any already outstanding ones, but will not wait and
block your process in case there are no events and will return after one
iteration of the loop. This is sometimes useful to poll and handle new
events while doing lengthy calculations, to keep the program responsive.

A flags value of `[evrunOnce]` will look for new events (waiting if
necessary) and will handle those and any already outstanding ones. It
will block your process until at least one new event arrives (which could
be an event internal to the library itself, so there is no guarantee that
a user-registered callback will be called), and will return after one
iteration of the loop.

Here are the gory details of what `Run` does (this is for your
understanding, not a guarantee that things will work exactly like this in
future versions):

```
- Increment loop depth.
- Reset the break status.
- Before the first iteration, call any pending watchers.
LOOP:
- If evflagForkCheck was used, check for a fork.
- If a fork was detected (by any means), queue and call all fork watchers.
- Queue and call all prepare watchers.
- If BreakLoop was called, goto FINISH.
- If we have been forked, detach and recreate the kernel state
  as to not disturb the other process.
- Update the kernel state with all outstanding changes.
- Update the "event loop time" (Now).
- Calculate for how long to sleep or block, if at all
  (active idle watchers, evrunNoWait or not having
  any active watchers at all will result in not sleeping).
- Sleep if the I/O and timer collect interval say so.
- Increment loop iteration counter.
- Block the process, waiting for any events.
- Queue all outstanding I/O (fd) events.
- Update the "event loop time" (Now), and do time jump adjustments.
- Queue all expired timers.
- Queue all expired periodics.
- Queue all idle watchers with priority higher than that of pending events.
- Queue all check watchers.
- Call all queued watchers in reverse order (i.e. check watchers first).
  Signals and child watchers are implemented as I/O watchers, and will
  be handled here by queueing them when their watcher gets executed.
- If BreakLoop has been called, or evrunOnce or evrunNoWait
  were used, or there are no active watchers, goto FINISH, otherwise
  continue with step LOOP.
FINISH:
- Reset the break status iff it was evbreakOne.
- Decrement the loop depth.
- Return.
```

### procedure TEvLoop.BreakLoop(How: TEvBreakHow = evbreakOne)

Can be used to make a call to `Run` return early (but only after it has
processed all outstanding events). The `How` argument must be either
`evbreakOne`, which will make the innermost `Run` call return, or
`evbreakAll`, which will make all nested `Run` calls return.

This "break state" will be cleared on the next call to `Run`.

It is safe to call `BreakLoop` from outside any `Run` calls, too, in
which case it will have no effect.

### procedure TEvLoop.Ref / procedure TEvLoop.Unref

Ref/unref can be used to add or remove a reference count on the event
loop: every watcher keeps one reference, and as long as the reference
count is nonzero, `Run` will not return on its own.

This is useful when you have a watcher that you never intend to
unregister, but that nevertheless should not keep `Run` from returning.
In such a case, call `Unref` after starting, and `Ref` before stopping
it.

As an example, the library itself uses this for its internal signal pipe:
it is not visible to the user and should not keep `Run` from exiting if
no event watchers registered by the user are active. Just remember to
*unref after start* and *ref before stop* (but only if the watcher wasn't
active before, or was active before, respectively. Note also that the
library might stop watchers itself (e.g. non-repeating timers) in which
case you have to `Ref` in the callback).

Example: create a signal watcher, but keep it from keeping `Run` running
when nothing else is active (Linux):

```pascal
ExitSig := TEvSignal.Create(SIGINT);
ExitSig.OnEvent := App.SigCb;
ExitSig.Start(Loop);
Loop.Unref;
```

Example: for some weird reason, unregister the above signal handler again:

```pascal
Loop.Ref;
ExitSig.Stop;
```

### property IoCollectInterval / property TimeoutCollectInterval

These advanced properties influence the time that the library will spend
waiting for events. Both time intervals are by default `0`, meaning that
the library will try to invoke timer/periodic callbacks and I/O callbacks
with minimum latency.

Setting these to a higher value (the interval *must* be >= 0) allows the
library to delay invocation of I/O and timer/periodic callbacks to
increase efficiency of loop iterations (or to increase power-saving
opportunities).

The idea is that sometimes your program runs just fast enough to handle
one (or very few) event(s) per loop iteration. While this makes the
program responsive, it also wastes a lot of CPU time to poll for new
events, especially with backends like `select` which have a high overhead
for the actual polling but can deliver many events at once.

By setting a higher *io collect interval* you allow the library to spend
more time collecting I/O events, so you can handle more events per
iteration, at the cost of increasing latency. Timeouts (both `TEvPeriodic`
and `TEvTimer`) will not be affected. Setting this to a non-zero value
will introduce an additional `EvSleep` call into most loop iterations.

Likewise, by setting a higher *timeout collect interval* you allow the
library to spend more time collecting timeouts, at the expense of
increased latency/jitter/inexactness (the watcher callback will be called
later). `TEvIo` watchers will not be affected. Setting this to a non-zero
value will not introduce any overhead.

Many (busy) programs can usually benefit by setting the I/O collect
interval to a value near `0.1` or so, which is often enough for
interactive servers (of course not for games), likewise for timeouts. It
usually doesn't make much sense to set it to a lower value than `0.01`,
as this approaches the timing granularity of most systems.

Setting the *timeout collect interval* can improve the opportunity for
saving power, as the program will "bundle" timer callback invocations
that are "near" in time together, by delaying some, thus reducing the
number of times the process sleeps and wakes up again. Another useful
technique to reduce iterations/wake-ups is to use `TEvPeriodic` watchers
and make sure they fire on, say, one-second boundaries only.

Example: we only need 0.1s timeout granularity, and we wish not to poll
more often than 100 times per second:

```pascal
Loop.TimeoutCollectInterval := 0.1;
Loop.IoCollectInterval := 0.01;
```

### procedure TEvLoop.InvokePending

This call will simply invoke all pending watchers while resetting their
pending state. Normally, `Run` does this automatically when required.
This function can be invoked from a watcher.

### function TEvLoop.PendingCount: Cardinal

Returns the number of pending watchers - zero indicates that no watchers
are pending.

### procedure TEvLoop.Invoke(...)  /  procedure Watcher.Invoke(REvents)

`Watcher.Invoke(REvents)` (C: `ev_invoke`) calls the watcher's callback
directly with the given events; the loop/revents need not otherwise be
valid.

### procedure TEvLoop.FeedFdEvent(Fd; REvents)

Ports `ev_feed_fd_event`: feed an event to all io watchers on `Fd`, as if
the backend had reported it.

### procedure TEvLoop.SetInvokePendingCb / SetLoopReleaseCb

Port `ev_set_invoke_pending_cb` and `ev_set_loop_release_cb`.
`SetInvokePendingCb` overrides how pending watchers are invoked (e.g. hand
them to another thread); `SetLoopReleaseCb(Release, Acquire)` runs
`Release` just before the loop blocks for events and `Acquire` just after
- the standard way to share one loop across threads by unlocking/locking
a mutex around the blocking poll. See THREAD LOCKING below.

### property TEvLoop.UserData: Pointer

Set and retrieve a single `Pointer` associated with a loop (initially
`nil`). Can be (ab-)used for any purpose.

### procedure TEvLoop.Verify

Goes through all internal structures and checks them for validity. If
anything is found to be inconsistent, it raises `EEvError` (the C version
prints to stderr and aborts). Compile the unit with `EV_VERIFY_2` defined
to run this automatically on every loop iteration.

This can be used to catch bugs inside the library itself: under normal
circumstances, this function will never fail, as the library keeps its
data structures consistent.

## ANATOMY OF A WATCHER

In the following description, `TEvTYPE` stands for the watcher type, e.g.
`TEvTimer` for timer watchers and `TEvIo` for I/O watchers.

A watcher is an object that you create and register to record your
interest in some event. To make a concrete example, imagine you want to
wait for a socket to become readable, you would create a `TEvIo` watcher
for that:

```pascal
procedure TApp.MyCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  W.Stop;
  Loop.BreakLoop(evbreakAll);
end;

var
  Loop: TEvLoop;
  Watcher: TEvIo;
begin
  Loop := TEvLoop.Default;

  Watcher := TEvIo.Create(SockFd, [evRead]);
  Watcher.OnEvent := App.MyCb;
  Watcher.Start(Loop);

  Loop.Run;
end;
```

You are responsible for the lifetime of your watcher objects: the loop
never owns or frees user watchers (the port adds one safety net over C:
destroying a still-active watcher stops it first).

Where C initialises watchers with `ev_init` + `ev_TYPE_set` (or the
combined `ev_TYPE_init`), the port uses the constructor
(`TEvIo.Create(Fd, Events)`) and a re-configuration method
(`SetIo`, `SetTimer`, `SetPeriodic`, `SetSignal`, `SetChild`,
`SetStat`) that may only be called while the watcher is stopped. The
callback (C: `ev_set_cb`) is the `OnEvent` property (with per-type
aliases such as `TEvTimer.OnTimeout`) and can be changed at virtually any
time.

To make the watcher actually watch out for events, you have to start it
with `Watcher.Start(Loop)`, and you can stop watching for events at any
time by calling `Watcher.Stop`.

As long as your watcher is active (has been started but not stopped) you
must not touch the values stored in it except when explicitly documented
otherwise. Most specifically you must never reconfigure it via its
`SetTYPE` method.

Each and every callback receives the event loop as first, the registered
watcher as second, and a set of received events as third argument
(`TEvEvents`). You can receive multiple events at the same time. The
possible event flags are:

- **`evRead`** / **`evWrite`** - The file descriptor in the `TEvIo`
  watcher has become readable and/or writable.
- **`evTimer`** - The `TEvTimer` watcher has timed out.
- **`evPeriodic`** - The `TEvPeriodic` watcher has timed out.
- **`evSignal`** - The signal specified in the `TEvSignal` watcher has
  been received by a thread.
- **`evChild`** - The pid specified in the `TEvChild` watcher has
  received a status change.
- **`evStat`** - The path specified in the `TEvStat` watcher changed its
  attributes somehow.
- **`evIdle`** - The `TEvIdle` watcher has determined that you have
  nothing better to do.
- **`evPrepare`** / **`evCheck`** - All `TEvPrepare` watchers are invoked
  just *before* `Run` starts to gather new events, and all `TEvCheck`
  watchers are queued (not invoked) just after `Run` has gathered them,
  but before it queues any callbacks for any received events. That means
  `TEvPrepare` watchers are the last watchers invoked before the event
  loop sleeps or polls for new events, and `TEvCheck` watchers will be
  invoked before any other watchers of the same or lower priority within
  an event loop iteration. Callbacks of both watcher types can start and
  stop as many watchers as they want, and all of them will be taken into
  account (for example, a `TEvPrepare` watcher might start an idle
  watcher to keep `Run` from blocking).
- **`evFork`** - The event loop has been resumed in the child process
  after fork (see `TEvFork`).
- **`evCleanup`** - The event loop is about to be destroyed (see
  `TEvCleanup`).
- **`evAsync`** - The given async watcher has been asynchronously
  notified (see `TEvAsync`).
- **`evCustom`** - Not ever sent (or otherwise used) by the library
  itself, but can be freely used by users to signal watchers (e.g. via
  `FeedEvent`).
- **`evError`** - An unspecified error has occurred, the watcher has been
  stopped. This might happen because the watcher could not be properly
  started, a file descriptor was found to be closed or any other problem.
  The library considers these application bugs. It will usually signal a
  few "dummy" events together with an error, for example it might
  indicate that a fd is readable or writable, and if your callback is
  well-written it can just attempt the operation and cope with the error
  from `recv()` or `send()`. This will not work in multi-threaded
  programs, though, as the fd could already be closed and reused for
  another thing, so beware.

### GENERIC WATCHER FUNCTIONS

- **`TEvTYPE.Create(...)`** *(C: `ev_TYPE_init`)* - Creates the watcher
  and initialises both the generic and the type-specific parts. You can
  reconfigure a watcher at any time as long as it has been stopped (or
  never started) and there are no pending events outstanding.

- **`SetTYPE(...)`** *(C: `ev_TYPE_set`)* - Reconfigures the type-specific
  parts of a watcher. You can call this any number of times, but not on a
  watcher that is active (pending is fine).

- **`Watcher.Start(Loop)`** *(C: `ev_TYPE_start`)* - Starts (activates)
  the given watcher. Only active watchers will receive events. If the
  watcher is already active nothing will happen. The loop the watcher is
  bound to is remembered and available via the `Loop` property.

- **`Watcher.Stop`** *(C: `ev_TYPE_stop`)* - Stops the given watcher if
  active, and clears the pending status (whether the watcher was active
  or not). It is possible that stopped watchers are pending - for
  example, non-repeating timers are being stopped when they become
  pending - but calling `Stop` ensures that the watcher is neither active
  nor pending. If you want to free or reuse a watcher it is therefore a
  good idea to always call its `Stop` first (the destructor does this
  automatically as a safety net).

- **`Watcher.IsActive: Boolean`** *(C: `ev_is_active`)* - True iff the
  watcher is active (i.e. it has been started and not yet been stopped).
  As long as a watcher is active you must not modify it.

- **`Watcher.IsPending: Boolean`** *(C: `ev_is_pending`)* - True iff the
  watcher is pending (i.e. it has outstanding events but its callback has
  not yet been invoked). As long as a watcher is pending (but not active)
  you must not change its priority, and you must not free the object.

- **`Watcher.OnEvent`** *(C: `ev_cb` / `ev_set_cb`)* - Read or change the
  callback. You can change the callback at virtually any time (modulo
  threads).

- **`Watcher.Priority: Integer`** *(C: `ev_priority` /
  `ev_set_priority`)* - Set and query the priority of the watcher. The
  priority is a small integer between `EV_MAXPRI` (2) and `EV_MINPRI`
  (-2). Pending watchers with higher priority will be invoked before
  watchers with lower priority, but priority will not keep watchers from
  being executed (except for `TEvIdle` watchers). If you need to suppress
  invocation when higher priority events are pending you need to look at
  `TEvIdle` watchers, which provide this functionality.

  You *must not* change the priority of a watcher as long as it is active
  or pending. Setting a priority outside the valid range is fine - it is
  clamped when the watcher is started. The default priority is 0, which
  is supposed to not be too high and not be too low :).

  See [WATCHER PRIORITY MODELS](#watcher-priority-models) below for a
  more thorough treatment of priorities.

- **`Watcher.ClearPending: TEvEvents`** *(C: `ev_clear_pending`)* - If
  the watcher is pending, clears its pending status and returns its
  `revents` set (as if its callback was invoked). If the watcher isn't
  pending it does nothing and returns `[]`. Sometimes it can be useful to
  "poll" a watcher instead of waiting for its callback to be invoked.

- **`Watcher.FeedEvent(REvents)`** *(C: `ev_feed_event`)* - Feeds the
  given event set into the event loop, as if the specified event had
  happened for the specified watcher (which must have been bound to a
  loop with `Start` at least once, but need not be active). Obviously you
  must not free the watcher as long as it has pending events. Stopping
  the watcher, letting the library invoke it, or calling `ClearPending`
  will clear the pending event.

- **`Watcher.Data: Pointer`** *(C: the `data` member)* - A pointer-sized
  slot entirely for your own use. In this port the more natural way to
  associate data with a watcher is to subclass it, or to keep the state
  in the object that provides the callback method.

### WATCHER STATES

There are various watcher states mentioned throughout this manual -
active, pending and so on. In this section these states and the rules to
transition between them will be described in more detail - and while
these rules might look complicated, they usually do "the right thing".

- **initialised** - Once created (and before being started), the watcher
  is simply an ordinary object. It can be reconfigured, freed or reused
  at will.

- **started/running/active** - Once a watcher has been started with
  `Start` it becomes property of the event loop, and is actively waiting
  for events. While in this state it cannot be accessed (except in a few
  documented ways) or freed - the only legal thing is to keep a reference
  to it, and call methods on it that are documented to work on active
  watchers.

- **pending** - If a watcher is active and the library determines that an
  event it is interested in has occurred (such as a timer expiring), it
  will become pending. It will stay in this pending state until either it
  is stopped or its callback is about to be invoked, so it is not
  normally pending inside the watcher callback.

  The watcher might or might not be active while it is pending (for
  example, an expired non-repeating timer can be pending but no longer
  active). If it is stopped, it can be freely reconfigured, but it is
  still property of the event loop at this time, so it cannot be freed or
  reused. It is also possible to feed an event on a watcher that is not
  active (e.g. via `FeedEvent`), in which case it becomes pending without
  being active.

- **stopped** - A watcher can be stopped implicitly by the library (in
  which case it might still be pending), or explicitly by calling its
  `Stop` method. The latter will clear any pending state the watcher
  might be in, regardless of whether it was active or not, so stopping a
  watcher explicitly before freeing it is often a good idea. While
  stopped (and not pending) the watcher is essentially in the initialised
  state: it can be reused, reconfigured and modified in any way you wish.

### WATCHER PRIORITY MODELS

Many event loops support *watcher priorities*, which are usually small
integers that influence the ordering of event callback invocation
between watchers in some way, all else being equal.

In TLibEv, watcher priorities can be set using the `Priority` property.
See its description for the more technical details such as the actual
priority range.

There are two common ways how these priorities are being interpreted by
event loops:

In the more common lock-out model, higher priorities "lock out"
invocation of lower priority watchers, which means as long as higher
priority watchers receive events, lower priority watchers are not being
invoked.

The less common only-for-ordering model uses priorities solely to order
callback invocation within a single event loop iteration: higher priority
watchers are invoked before lower priority ones, but they all get invoked
before polling for new events.

The library uses the second (only-for-ordering) model for all its
watchers except for idle watchers (which use the lock-out model).

The rationale behind this is that implementing the lock-out model for
watchers is not well supported by most kernel interfaces, and most event
libraries will just poll for the same events again and again as long as
their callbacks have not been executed, which is very inefficient in the
common case of one high-priority watcher locking out a mass of lower
priority ones.

Static (ordering) priorities are most useful when you have two or more
watchers handling the same resource: a typical usage example is having a
`TEvIo` watcher to receive data, and an associated `TEvTimer` to handle
timeouts. Under load, data might be received while the program handles
other jobs, but since timers normally get invoked first, the timeout
handler will be executed before checking for data. In that case, giving
the timer a lower priority than the I/O watcher ensures that I/O will be
handled first even under adverse conditions (which is usually, but not
always, what you want).

Since idle watchers use the "lock-out" model, meaning that idle watchers
will only be executed when no same or higher priority watchers have
received events, they can be used to implement the "lock-out" model when
required. For example, to emulate how many other event libraries handle
priorities, you can associate a `TEvIdle` watcher to each such watcher,
and in the normal watcher callback, you just start the idle watcher. The
real processing is done in the idle watcher callback. This causes the
library to continuously poll and process kernel event data for the
watcher, but when the lock-out case is known to be rare (which in turn is
rare :), this is workable.

Usually, however, the lock-out model implemented that way will perform
miserably under the type of load it was designed to handle. In that case,
it might be preferable to stop the real watcher before starting the idle
watcher, so the kernel will not have to process the event in case the
actual processing will be delayed for considerable time.

Here is an example of an I/O watcher that should run at a strictly lower
priority than the default, and which should only process data when no
other events are pending:

```pascal
procedure TApp.IoCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  // stop the I/O watcher, we received the event, but
  // are not yet ready to handle it.
  W.Stop;

  // start the idle watcher to handle the actual event.
  // it will not be executed as long as other watchers
  // with the default priority are receiving events.
  FIdle.Start(Loop);
end;

procedure TApp.IdleCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  // actual processing
  Recv(FSock, ...);

  // have to start the I/O watcher again, as
  // we have handled the event
  FIo.Start(Loop);
end;

// initialisation
FIdle := TEvIdle.Create;
FIdle.OnEvent := IdleCb;
FIo := TEvIo.Create(FSock, [evRead]);
FIo.OnEvent := IoCb;
FIo.Start(TEvLoop.Default);
```

In the "real" world, it might also be beneficial to start a timer, so
that low-priority connections can not be locked out forever under load.
This enables your program to keep a lower latency for important
connections during short periods of high load, while not completely
locking out less important ones.

## WATCHER TYPES

This section describes each watcher in detail, but will not repeat
information given in the last section. Any constructors, methods and
properties specific to the watcher type are explained.

Members are additionally marked with either *[read-only]*, meaning that,
while the watcher is active, you can look at the member and expect some
sensible content, but you must not modify it (you can modify it while the
watcher is stopped to your hearts content), or *[read-write]*, which
means you can expect it to have some sensible content while the watcher
is active, but you can also modify it (within the same thread as the
event loop). Modifying it may not do something sensible or take immediate
effect (or do anything at all), but the library will not crash or
malfunction in any way.

### TEvIo - is this file descriptor readable or writable?

I/O watchers check whether a file descriptor is readable or writable in
each iteration of the event loop, or, more precisely, when reading would
not block the process and writing would at least be able to write some
data. This behaviour is called level-triggering because you keep
receiving events as long as the condition persists. Remember you can stop
the watcher if you don't want to act on the event and neither want to
receive future events.

In general you can register as many read and/or write event watchers per
fd as you want (as long as you don't confuse yourself). Setting all file
descriptors to non-blocking mode is also usually a good idea (but not
required if you know what you are doing).

Another thing you have to watch out for is that it is quite easy to
receive "spurious" readiness notifications, that is, your callback might
be called with `evRead` but a subsequent `recv` will actually block
because there is no data. It is very easy to get into this situation even
with a relatively standard program structure. Thus it is best to always
use non-blocking I/O: an extra `recv` returning `EAGAIN` is far
preferable to a program hanging until some data arrives.

**Note on this port:** on Windows the `Fd` of a `TEvIo` is a winsock
`SOCKET` value, and only sockets can be watched (a limitation of the
select backend). On Linux any file descriptor works, with the caveats
below.

#### The special problem of disappearing file descriptors

Some backends (e.g. epoll) need to be told about closing a file
descriptor (either due to calling `close` explicitly or any other means,
such as `dup2`). The reason is that you register interest in some file
descriptor, but when it goes away, the operating system will silently
drop this interest. If another file descriptor with the same number then
is registered with the library, there is no efficient way to see that
this is, in fact, a different file descriptor.

To avoid having to explicitly tell the library about such cases, it
follows the following policy: each time `SetIo` is being called, the
library will assume that this is potentially a new file descriptor,
otherwise it is assumed that the file descriptor stays the same. That
means that you *have* to call `SetIo` (or recreate the watcher) when you
change the descriptor even if the file descriptor number itself did not
change. This is how one would do it normally anyway, the important point
is that the application should not optimise around the library but should
leave optimisations to it.

#### The special problem of dup'ed file descriptors

Some backends (e.g. epoll) cannot register events for file descriptors,
but only events for the underlying file descriptions. That means when you
have `dup()`'ed file descriptors or weirder constellations, and register
events for them, only one file descriptor might actually receive events.
There is no workaround possible except not registering events for
potentially `dup()`'ed file descriptors.

#### The special problem of files

Many people try to use `select` (or this library) on file descriptors
representing files, and expect it to become ready when their program
doesn't block on disk accesses (which can take a long time on their own).
However, this cannot ever work in the "expected" way - you get a
readiness notification as soon as the kernel knows whether and how much
data is there, and in the case of open files, that's always the case, so
you always get a readiness notification instantly, and your read (or
possibly write) will still block on the disk I/O.

In the case of sockets, pipes, character devices and so on, there is
another party (the sender) that delivers data on its own, but in the case
of files, there is no such thing: the disk will not send data on its own,
simply because it doesn't know what you wish to read.

So avoid file descriptors pointing to files when you know it, but use
them when it is convenient, e.g. for STDIN/STDOUT, or when you rarely
read from a file instead of from a socket, and want to reuse the same
code path.

#### The special problem of fork

The epoll backend does not support `fork()` well. The library fully
supports fork, but needs to be told about it in the child if you want to
continue to use it in the child. To support fork in your child processes,
you have to call `Loop.LoopFork` after a fork in the child, or enable
`evflagForkCheck`.

#### The special problem of SIGPIPE

While not really specific to this library, it is easy to forget about
`SIGPIPE`: when writing to a pipe whose other end has been closed, your
program gets sent a SIGPIPE, which, by default, aborts your program. For
most programs this is sensible behaviour, for daemons, this is usually
undesirable. So when you encounter spurious, unexplained daemon exits,
make sure you ignore SIGPIPE (and maybe make sure you log the exit status
of your daemon somewhere, as that would have given you a big clue).

#### The special problem of accept()ing when you can't

Many implementations of the POSIX `accept` function (for example, found
in post-2004 Linux) have the peculiar behaviour of not removing a
connection from the pending queue in all error cases. For example, larger
servers often run out of file descriptors (because of resource limits),
causing `accept` to fail with `ENFILE` but not rejecting the connection,
leading to the library signalling readiness on the next iteration again
(the connection still exists after all), and typically causing the
program to loop at 100% CPU usage.

Unfortunately, the set of errors that cause this issue differs between
operating systems, and there is usually little the app can do to remedy
the situation. One of the easiest ways to handle it is to just ignore it
- when the program encounters an overload, it will just loop until the
situation is over. A better way is to log any errors other than `EAGAIN`
and `EWOULDBLOCK`, making sure not to flood the log, and continue as
usual. For extra points one could stop the `TEvIo` watcher on the
listening fd "for a while", which reduces CPU usage.

If your program is single-threaded, then you could also keep a dummy file
descriptor for overload situations (e.g. by opening `/dev/null`), and
when you run into `ENFILE` or `EMFILE`, close it, run `accept`, close
that fd, and create a new dummy fd. This will gracefully refuse clients
under typical overload conditions.

#### Watcher-Specific Functions

- **`constructor Create(AFd: Integer; AEvents: TEvEvents)`** /
  **`procedure SetIo(AFd: Integer; AEvents: TEvEvents)`** - Configures
  the watcher. `AFd` is the file descriptor to receive events for and
  `AEvents` is `[evRead]`, `[evWrite]`, `[evRead, evWrite]` or `[]`, to
  express the desire to receive the given events. Note that setting the
  events to `[]` and starting the watcher is supported, but not specially
  optimized.

- **`procedure Modify(AEvents: TEvEvents)`** *(C: `ev_io_modify`)* -
  Similar to `SetIo`, but only changes the requested events. Using this
  might be faster with some backends, as the library can assume that the
  `Fd` still refers to the same underlying file description, something it
  cannot do when using `SetIo`.

- **`property Fd: Integer`** *[no-modify]* - The file descriptor being
  watched. While it can be read at any time, you must not modify it even
  when the watcher is stopped - always use `SetIo` for that.

- **`property Events: TEvEvents`** *[no-modify]* - The set of events the
  fd is being watched for. To test for `evRead`, use
  `evRead in W.Events`, and similarly for `evWrite`. As with `Fd`, always
  use `SetIo` or `Modify` to change it.

### TEvTimer - relative and optionally repeating timeouts

Timer watchers are simple relative timers that generate an event after a
given time, and optionally repeating in regular intervals after that.

The timers are based on real time, that is, if you register an event that
times out after an hour and you reset your system clock to January last
year, it will still time out after (roughly) one hour. "Roughly" because
detecting time jumps is hard, and some inaccuracies are unavoidable (the
monotonic clock - which both platforms of this port have - helps a lot
here).

The callback is guaranteed to be invoked only *after* its timeout has
passed (not *at*, so on systems with very low-resolution clocks this
might introduce a small delay, see "the special problem of being too
early", below). If multiple timers become ready during the same loop
iteration then the ones with earlier time-out values are invoked before
ones of the same priority with later time-out values (but this is no
longer true when a callback calls `Run` recursively).

#### Be smart about timeouts

Many real-world problems involve some kind of timeout, usually for error
recovery. A typical example is an HTTP request - if the other side hangs,
you want to raise some error after a while.

What follows are some ways to handle this problem, from obvious and
inefficient to smart and efficient. In the following, a 60 second
activity timeout is assumed - a timeout that gets reset to 60 seconds
each time there is activity (e.g. each time some data or other life sign
was received).

**1. Use a timer and stop, reinitialise and start it on activity.**

This is the most obvious, but not the most simple way: in the beginning,
start the watcher:

```pascal
Timer := TEvTimer.Create(60, 0);
Timer.OnTimeout := App.TimeoutCb;
Timer.Start(Loop);
```

Then, each time there is some activity, stop it, reconfigure it and start
it again:

```pascal
Timer.Stop;
Timer.SetTimer(60, 0);
Timer.Start(Loop);
```

This is relatively simple to implement, but means that each time there is
some activity, the library will first have to remove the timer from its
internal data structure and then add it again. It tries to be fast, but
it's still not a constant-time operation.

**2. Use a timer and re-start it with `Again` on inactivity.**

This is the easiest way, and involves using `Again` instead of `Start`.

To implement this, configure a `TEvTimer` with a `RepeatInterval` value
of 60 and then call `Again` at start and each time you successfully read
or write some data. If you go into an idle state where you do not expect
data to travel on the socket, you can `Stop` the timer, and `Again` will
automatically restart it if need be.

That means you can ignore both the `Start` method and the `AAfter`
argument to `SetTimer`, and only ever use the `RepeatInterval` property
and `Again`.

At start:

```pascal
Timer := TEvTimer.Create(0, 60);
Timer.OnTimeout := App.TimeoutCb;
Timer.Start(Loop); // bind the loop once; or just call Timer.Again after a first Start
Timer.Again;
```

Each time there is some activity:

```pascal
Timer.Again;
```

It is even possible to change the time-out on the fly, regardless of
whether the watcher is active or not:

```pascal
Timer.RepeatInterval := 30;
Timer.Again;
```

This is slightly more efficient than stopping/starting the timer each
time you want to modify its timeout value, as the library does not have
to completely remove and re-insert the timer from/into its internal data
structure. It is, however, even simpler than the "obvious" way to do it.

**3. Let the timer time out, but then re-arm it as required.**

This method is more tricky, but usually most efficient: most timeouts are
relatively long compared to the intervals between other activity - in our
example, within 60 seconds, there are usually many I/O events with
associated activity resets.

In this case, it would be more efficient to leave the `TEvTimer` alone,
but remember the time of last activity, and check for a real timeout only
within the callback:

```pascal
const
  Timeout = 60.0;
var
  LastActivity: TEvTstamp; // time of last activity

procedure TApp.TimeoutCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
var
  After: TEvTstamp;
begin
  // calculate when the timeout would happen
  After := LastActivity - Loop.Now + Timeout;

  if After < 0 then
  begin
    // timeout occurred, take action
  end
  else
  begin
    // callback was invoked, but there was some recent
    // activity. simply restart the timer to time out
    // after "After" seconds, which is the earliest time
    // the timeout can occur.
    TEvTimer(W).SetTimer(After, 0);
    TEvTimer(W).Start(Loop);
  end;
end;
```

To summarise the callback: first calculate in how many seconds the
timeout will occur (by calculating the absolute time when it would occur,
`LastActivity + Timeout`, and subtracting the current time, `Loop.Now`,
from that). If this value is negative, then we are already past the
timeout and need to do whatever is needed in this case. Otherwise, we now
know the earliest time at which the timeout would trigger, and simply
start the timer with this timeout value.

In other words, each time the callback is invoked it will check whether
the timeout occurred. If not, it will simply reschedule itself to check
again at the earliest time it could time out. Rinse. Repeat.

This scheme causes more callback invocations (about one every 60 seconds
minus half the average time between activity), but virtually no calls to
the library to change the timeout.

To start the machinery, simply set `LastActivity` to the current time
(meaning there was some activity just now), then call the callback, which
will "do the right thing" and start the timer. When there is some
activity, simply store the current time in `LastActivity` - no library
calls at all. When your timeout value changes, stop the timer and call
the callback with the new value, which will again do the right thing.

This technique is slightly more complex, but in most cases where the
time-out is unlikely to be triggered, much more efficient.

**4. Wee, just use a double-linked list for your timeouts.**

If there is not one request, but many thousands (millions...), all
employing some kind of timeout with the same timeout value, then one can
do even better: when starting the timeout, calculate the timeout value
and put the timeout at the *end* of the list. Then use a single
`TEvTimer` to fire when the timeout at the *beginning* of the list is
expected to fire (for example, using technique #3). When there is some
activity, remove the timer from the list, recalculate the timeout, append
it to the end of the list again, and make sure to update the `TEvTimer`
if it was taken from the beginning of the list.

This way, one can manage an unlimited number of timeouts in O(1) time for
starting, stopping and updating the timers, at the expense of a major
complication, and having to use a constant timeout (which ensures the
list stays sorted).

**So which method is the best?**

Method #2 is a simple no-brain-required solution that is adequate in most
situations. Method #3 requires a bit more thinking, but handles many
cases better, and isn't very complicated either. In most cases, choosing
either one is fine, with #3 being better in typical situations. Method #1
is almost always a bad idea, and buys you nothing. Method #4 is rather
complicated, but extremely efficient, something that really pays off
after the first million or so of active timers, i.e. it's usually
overkill :)

#### The special problem of being too early

If you ask a timer to call your callback after three seconds, then you
expect it to be invoked after three seconds - but of course, this cannot
be guaranteed to infinite precision. Less obviously, it cannot be
guaranteed to any precision - imagine somebody suspending the process
with a STOP signal for a few hours for example.

A less obvious failure mode is calling your callback too early: many
event loops compare timestamps with a "elapsed delay >= requested delay",
but this can cause your callback to be invoked much earlier than you
would expect. To see why, imagine a system with a clock that only offers
full second resolution. If you schedule a one-second timer at the time
500.9, then the event loop will schedule your timeout to elapse at a
system time of 500 (500.9 truncated to the resolution) + 1, or 501. If an
event library looks at the timeout 0.1s later, it will see "501 >= 501"
and invoke the callback 0.1s after it was started, even though a
one-second delay was requested.

This is the reason why this library will never invoke the callback if the
elapsed delay equals the requested delay, but only when the elapsed delay
is larger than the requested delay. In the example above, it would only
invoke the callback at system time 502, or 1.1s after the timer was
started. So, while it cannot guarantee that your callback will be invoked
exactly when requested, it *can* and *does* guarantee that the requested
delay has actually elapsed, or in other words, it always errs on the "too
late" side of things.

#### The special problem of time updates

Establishing the current time is a costly operation (it usually takes at
least one system call): the library therefore updates its idea of the
current time only before and after `Run` collects new events, which
causes a growing difference between `Loop.Now` and `EvTime` when handling
lots of events in one iteration.

The relative timeouts are calculated relative to the `Loop.Now` time.
This is usually the right thing as this timestamp refers to the time of
the event triggering whatever timeout you are modifying/starting. If you
suspect event processing to be delayed and you *need* to base the timeout
on the current time, use something like the following to adjust for it:

```pascal
Timer.SetTimer(After + (EvTime - Loop.Now), 0);
```

If the event loop is suspended for a long time, you can also force an
update of the time returned by `Now` by calling `NowUpdate`, although
that will push the event time of all outstanding events further into the
future.

#### The special problem of unsynchronised clocks

Modern systems have a variety of clocks - the library itself uses the
normal "wall clock" clock and the monotonic clock (to avoid time jumps).
Neither of these clocks is synchronised with each other or any other
clock on the system, so `EvTime` might return a considerably different
time than other time sources. The moral of this is to only compare
library-related timestamps with `EvTime` and `Loop.Now`, at least if you
want better precision than a second or so.

Because `TEvTimer` watchers work in real time (measured by the monotonic
clock), comparing wall clock timestamps from when you started your timer
and when your callback is invoked may make the callback look a bit
"early". If your timeouts are based on a physical timescale (e.g. "time
out this connection after 100 seconds") then this is exactly the right
behaviour. If you want to compare wall clock/system timestamps to your
timers, then you need to use `TEvPeriodic` watchers, as these are based
on the wall clock time.

#### The special problems of suspended animation

What happens to the clocks when a machine suspends/hibernates? On Linux,
a suspend freezes all processes and the monotonic clock does not advance
while the system is suspended: on resume, it will be as if the program
was frozen for a few seconds, but the suspend time will not be counted
towards `TEvTimer` watchers. The real time clock advances as expected.

The other form of suspend (job control, or sending a SIGSTOP) will see a
time jump in the monotonic clocks and the realtime clock. If the program
is suspended for a very long time you can expect `TEvTimer` watchers to
expire, as the full suspension time will be counted towards the timers.
It might be beneficial for this case to call `Suspend` and `Resume` in
code that handles `SIGTSTP`, to at least get deterministic behaviour (you
can do nothing against `SIGSTOP`).

#### Watcher-Specific Functions and Data Members

- **`constructor Create(AAfter, ARepeat: TEvTstamp)`** /
  **`procedure SetTimer(AAfter, ARepeat: TEvTstamp)`** - Configure the
  timer to trigger after `AAfter` seconds (fractional and negative values
  are supported). If `ARepeat` is 0, then it will automatically be
  stopped once the timeout is reached. If it is positive, then the timer
  will automatically be configured to trigger again `ARepeat` seconds
  later, again, and again, until stopped manually.

  The timer itself will do a best-effort at avoiding drift, that is, if
  you configure a timer to trigger every 10 seconds, then it will
  normally trigger at exactly 10 second intervals. If, however, your
  program cannot keep up with the timer (because it takes longer than
  those 10 seconds to do stuff) the timer will not fire more than once
  per event loop iteration.

- **`procedure Again`** *(C: `ev_timer_again`)* - This will act as if the
  timer timed out, and restarts it again if it is repeating. It basically
  works like calling `Stop`, updating the timeout to the
  `RepeatInterval` value and calling `Start`. The exact semantics:
  - If the timer is pending, the pending status is always cleared.
  - If the timer is started but non-repeating, stop it (as if it timed
    out, without invoking it).
  - If the timer is repeating, make the `RepeatInterval` value the new
    timeout and start the timer, if necessary.

  See "Be smart about timeouts", above, for a usage example.

- **`property Remaining: TEvTstamp`** *(C: `ev_timer_remaining`)* -
  Returns the remaining time until the timer fires. If the timer is
  active, then this time is relative to the current event loop time,
  otherwise it's the timeout value currently configured.

  That is, after `SetTimer(5, 7)`, `Remaining` returns 5. When the timer
  is started and one second passes, it will return 4. When the timer
  expires and is restarted, it will return roughly 7 (likely slightly
  less as callback invocation takes some time, too), and so on.

- **`property RepeatInterval: TEvTstamp`** *[read-write]* (C: `repeat`) -
  The current repeat value. Will be used each time the watcher times out
  or `Again` is called, and determines the next timeout (if any), which
  is also when any modifications are taken into account.

### TEvPeriodic - to cron or not to cron?

Periodic watchers are also timers of a kind, but they are very versatile
(and unfortunately a bit complex).

Unlike `TEvTimer`, periodic watchers are not based on real time (or
relative time, the physical time that passes) but on wall clock time
(absolute time, the thing you can read on your calendar or clock). The
difference is that wall clock time can run faster or slower than real
time, and time jumps are not uncommon (e.g. when you adjust your
wrist-watch).

You can tell a periodic watcher to trigger after some specific point in
time: for example, if you tell a periodic watcher to trigger "in 10
seconds" (by specifying e.g. `Loop.Now + 10`, that is, an absolute time
not a delay) and then reset your system clock to January of the previous
year, then it will take a year or more to trigger the event (unlike a
`TEvTimer`, which would still trigger roughly 10 seconds after starting
it, as it uses a relative timeout).

`TEvPeriodic` watchers can also be used to implement vastly more complex
timers, such as triggering an event on each "midnight, local time", or
other complicated rules. This cannot easily be done with `TEvTimer`
watchers, as those cannot react to time jumps.

As with timers, the callback is guaranteed to be invoked only when the
point in time where it is supposed to trigger has passed. If multiple
timers become ready during the same loop iteration then the ones with
earlier time-out values are invoked before ones with later time-out
values (but this is no longer true when a callback calls `Run`
recursively).

#### Watcher-Specific Functions and Data Members

- **`constructor Create(AOffset, AInterval: TEvTstamp)`** /
  **`procedure SetPeriodic(AOffset, AInterval: TEvTstamp)`** plus the
  **`OnReschedule`** property - Lots of arguments, let's sort it out...
  There are basically three modes of operation:

  **Absolute timer** (`AOffset` = absolute time, `AInterval` = 0,
  `OnReschedule` unset): in this configuration the watcher triggers an
  event after the wall clock time `AOffset` has passed. It will not
  repeat and will not adjust when a time jump occurs, that is, if it is
  to be run at January 1st 2011 then it will be stopped and invoked when
  the system clock reaches or surpasses this point in time.

  **Repeating interval timer** (`AOffset` = offset within interval,
  `AInterval` > 0, `OnReschedule` unset): in this mode the watcher will
  always be scheduled to time out at the next `AOffset + N * AInterval`
  time (for some integer N, which can also be negative) and then repeat,
  regardless of any time jumps. The offset argument is merely an offset
  into the interval periods.

  This can be used to create timers that do not drift with respect to the
  system clock, for example, here is a `TEvPeriodic` that triggers each
  hour, on the hour (with respect to UTC):

  ```pascal
  Periodic.SetPeriodic(0, 3600);
  ```

  This doesn't mean there will always be 3600 seconds in between
  triggers, but only that the callback will be called when the system
  time shows a full hour (UTC), or more correctly, when the system time
  is evenly divisible by 3600. Another way to think about it (for the
  mathematically inclined) is that it will try to run the callback in
  this mode at the next possible time where `time = offset (mod
  interval)`, regardless of any time jumps.

  The interval *MUST* be positive, and for numerical stability, the
  interval value should be higher than `1/8192` (which is around 100
  microseconds) and the offset should be higher than 0 and should have at
  most a similar magnitude as the current time (say, within a factor of
  ten). Typical values for offset are, in fact, 0 or something between 0
  and the interval, which is also the recommended range.

  Note also that there is an upper limit to how often a timer can fire
  (CPU speed for example), so if the interval is very small then timing
  stability will of course deteriorate.

  **Manual reschedule mode** (offset and interval ignored,
  `OnReschedule` set): in this mode, each time the periodic watcher gets
  scheduled, the reschedule callback will be called with the watcher as
  first, and the current time as second argument.

  NOTE: *This callback MUST NOT stop or destroy any periodic watcher,
  ever, or make ANY other event loop modifications whatsoever, unless
  explicitly allowed by documentation*. If you need to stop it, return
  `NowTime + 1e30` and stop it afterwards (e.g. by starting a
  `TEvPrepare` watcher, which is the only event loop modification you are
  allowed to do).

  The callback type is
  `function(Watcher: TEvPeriodic; NowTime: TEvTstamp): TEvTstamp of object`,
  e.g.:

  ```pascal
  function TApp.MyRescheduler(Watcher: TEvPeriodic; NowTime: TEvTstamp): TEvTstamp;
  begin
    Result := NowTime + 60;
  end;
  ```

  It must return the next time to trigger, based on the passed time value
  (that is, the lowest time value larger than the second argument). It
  will usually be called just before the callback will be triggered, but
  might be called at other times, too.

  NOTE: *this callback must always return a time that is higher than or
  equal to the passed `NowTime` value*.

  This can be used to create very complex timers, such as a timer that
  triggers on "next midnight, local time": calculate the next midnight
  after `NowTime` and return the timestamp value for it.

- **`procedure Again`** *(C: `ev_periodic_again`)* - Simply stops and
  restarts the periodic watcher again. This is only useful when you
  changed some parameters or the reschedule callback would return a
  different time than the last time it was called (e.g. in a crond like
  program when the crontabs have changed).

- **`property At: TEvTstamp`** *[read-only]* (C: `ev_periodic_at`) - When
  active, returns the absolute time that the watcher is supposed to
  trigger next. This is not the same as the offset argument, but indeed
  works even in interval and manual rescheduling modes.

- **`property Offset: TEvTstamp`** *[read-write]* - When repeating, this
  contains the offset value, otherwise this is the absolute point in time
  (although the library might modify this value for better numerical
  stability). Can be modified any time, but changes only take effect when
  the periodic timer fires or `Again` is being called.

- **`property Interval: TEvTstamp`** *[read-write]* - The current
  interval value. Can be modified any time, but changes only take effect
  when the periodic timer fires or `Again` is being called.

- **`property OnReschedule: TEvPeriodicRescheduleCb`** *[read-write]* -
  The current reschedule callback, or unassigned, if this functionality
  is switched off. Can be changed any time, but changes only take effect
  when the periodic timer fires or `Again` is being called.

#### Examples

Example: call a callback every hour, or, more precisely, whenever the
system time is divisible by 3600. The callback invocation times have
potentially a lot of jitter, but good long-term stability.

```pascal
HourlyTick := TEvPeriodic.Create(0, 3600);
HourlyTick.OnEvent := App.ClockCb;
HourlyTick.Start(Loop);
```

Example: the same as above, but use a reschedule callback to do it:

```pascal
function TApp.MyScheduler(W: TEvPeriodic; NowTime: TEvTstamp): TEvTstamp;
begin
  // math.h fmod equivalent
  Result := NowTime + (3600 - (NowTime - Int(NowTime / 3600) * 3600));
end;

HourlyTick := TEvPeriodic.Create(0, 0);
HourlyTick.OnReschedule := App.MyScheduler;
```

Example: call a callback every hour, starting now:

```pascal
HourlyTick := TEvPeriodic.Create(
  Loop.Now - Int(Loop.Now / 3600) * 3600, 3600);
HourlyTick.OnEvent := App.ClockCb;
HourlyTick.Start(Loop);
```

### TEvSignal - signal me when a signal gets signalled!

Signal watchers will trigger an event when the process receives a
specific signal one or more times. Even though signals are very
asynchronous, the library will try its best to deliver signals
synchronously, i.e. as part of the normal event processing, like any
other event.

This works on both targets: on Linux the handler is installed with
`sigaction` (or, with `evflagSignalFd`, delivered through a `signalfd`);
on Windows it uses the CRT `signal()` function, where only a handful of
signals (SIGINT, SIGTERM, SIGABRT, ...) are actually meaningful.

You can configure as many watchers as you like for the same signal, but
only within the same loop, i.e. you can watch for `SIGINT` in your
default loop and for `SIGIO` in another loop, but you cannot watch for
`SIGINT` in both the default loop and another loop at the same time. At
the moment, `SIGCHLD` is permanently tied to the default loop.

Only after the first watcher for a signal is started will the library
actually register something with the kernel. It thus coexists with your
own signal handlers as long as you don't register any with the library
for the same signal.

The library installs its handlers with `SA_RESTART` behaviour enabled, so
system calls should not be unduly interrupted. If you have a problem with
system calls getting interrupted by signals you can block all signals in
a `TEvCheck` watcher and unblock them in a `TEvPrepare` watcher.

#### The special problem of inheritance over fork/execve

The signal disposition is unspecified after starting a signal watcher
(and after stopping it again), that is, the library might or might not
set or restore the installed signal handler (it never sets signals to
`SIG_IGN`, so handlers will be reset to `SIG_DFL` on `execve`). This port
never modifies the signal *mask*, so the C manual's warnings about
inherited signal masks do not apply.

#### Watcher-Specific Functions and Data Members

- **`constructor Create(ASigNum: Integer)`** /
  **`procedure SetSignal(ASigNum: Integer)`** - Configures the watcher to
  trigger on the given signal number.

- **`property SigNum: Integer`** *[read-only]* - The signal the watcher
  watches out for.

#### Examples

Example: try to exit cleanly on SIGINT.

```pascal
procedure TApp.SigIntCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  Loop.BreakLoop(evbreakAll);
end;

SignalWatcher := TEvSignal.Create(SIGINT);
SignalWatcher.OnEvent := App.SigIntCb;
SignalWatcher.Start(Loop);
```

### TEvChild - watch out for process status changes  *(Linux only)*

Child watchers trigger when your process receives a SIGCHLD in response
to some child status changes (most typically when a child of yours dies
or exits). It is permissible to install a child watcher *after* the child
has been forked (which implies it might have already exited), as long as
the event loop isn't entered (or is continued from a watcher), i.e.,
forking and then immediately registering a watcher for the child is fine,
but forking and registering a watcher a few event loop iterations later
or in the next callback invocation is not.

Only the default event loop is capable of handling signals, and therefore
you can only register child watchers in the default event loop.

Due to some design glitches inside libev, child watchers will always be
handled at maximum priority (their priority is set to `EV_MAXPRI` by the
library).

#### Process Interaction

The library grabs `SIGCHLD` as soon as the default event loop is
initialised. This is necessary to guarantee proper behaviour even if the
first child watcher is started after the child exits. The occurrence of
`SIGCHLD` is recorded asynchronously, but child reaping is done
synchronously as part of the event loop processing. The library always
reaps all children, even ones not watched.

#### Overriding the Built-In Processing

The library offers no special support for overriding the built-in child
processing, but if your application collides with its default child
handler, you can override it easily by installing your own handler for
`SIGCHLD` after initialising the default loop, and making sure the
default loop never gets destroyed. You are encouraged, however, to use an
event-based approach to child reaping and thus use the library's support
for that, so other users can use `TEvChild` watchers freely.

#### Stopping the Child Watcher

Currently, the child watcher never gets stopped, even when the child
terminates, so normally one needs to stop the watcher in the callback
(calling `Stop` twice is not a problem).

#### Watcher-Specific Functions and Data Members

- **`constructor Create(APid: Integer; ATrace: Boolean)`** /
  **`procedure SetChild(APid: Integer; ATrace: Boolean)`** - Configures
  the watcher to wait for status changes of process `APid` (or *any*
  process if `APid` is specified as 0). The callback can look at the
  `RStatus` property to see the status word (use the `sys/wait.h` macro
  semantics; the exit code is `RStatus shr 8`). The `RPid` property
  contains the pid of the process causing the status change. `ATrace`
  must be either `False` (only activate the watcher when the process
  terminates) or `True` (additionally activate the watcher when the
  process is stopped or continued).

- **`property Pid: Integer`** *[read-only]* - The process id this watcher
  watches out for, or 0, meaning any process id.

- **`property RPid: Integer`** *[read-write]* - The process id that
  detected a status change.

- **`property RStatus: Integer`** *[read-write]* - The process exit/trace
  status caused by `RPid`.

#### Examples

Example: `fork()` a new process and install a child handler to wait for
its completion.

```pascal
procedure TApp.ChildCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  W.Stop;
  Writeln(Format('process %d exited with status %x',
    [TEvChild(W).RPid, TEvChild(W).RStatus]));
end;

Pid := c_fork;
if Pid < 0 then
  // error
else if Pid = 0 then
begin
  // the forked child executes here
  c_exit(1);
end
else
begin
  ChildWatcher := TEvChild.Create(Pid, False);
  ChildWatcher.OnEvent := App.ChildCb;
  ChildWatcher.Start(TEvLoop.Default);
end;
```

### TEvStat - did the file attributes just change?

This watches a file system path for attribute changes. That is, it calls
`stat` on that path in regular intervals (or when the OS says it changed)
and sees if it changed compared to the last time, invoking the callback
if it did. Starting the watcher `stat`'s the file, so only changes that
happen after the watcher has been started will be reported.

The path does not need to exist: changing from "path exists" to "path
does not exist" is a status change like any other. The condition "path
does not exist" (or more correctly "path cannot be stat'ed") is signified
by the `st_nlink` field being zero (which is otherwise always forced to
be at least one) and all the other fields of the stat buffer having
unspecified contents.

The path *must not* end in a slash or contain special components such as
`.` or `..`. The path *should* be absolute: if it is relative and your
working directory changes, then the behaviour is undefined.

Since there is no portable change notification interface available, the
portable implementation simply calls `stat(2)` regularly on the path to
see if it changed somehow. You can specify a recommended polling interval
for this case. If you specify a polling interval of 0 (highly
recommended!) then a *suitable, unspecified default* value will be used
(which you can expect to be around five seconds, although this might
change dynamically). The library will also impose a minimum interval
which is currently around 0.1, but that's usually overkill.

This watcher type is not meant for massive numbers of stat watchers, as
even with OS-supported change notifications, this can be
resource-intensive.

On Linux, the `inotify(7)` interface is used to speed up change
detection where possible; on Windows the port always polls.

#### Inotify

When inotify support is present at runtime, it will be used to speed up
change detection where possible. The inotify descriptor will be created
lazily when the first `TEvStat` watcher is being started.

Inotify presence does not change the semantics of `TEvStat` watchers
except that changes might be detected earlier, and in some cases, to
avoid making regular `stat` calls. Even in the presence of inotify
support there are many cases where the library has to resort to regular
`stat` polling, but as long as kernel 2.6.25 or newer is used, the path
exists (i.e. stat succeeds), and the path resides on a local filesystem
(ext2/3, btrfs, xfs, tmpfs and others are recognised) the library usually
gets away without polling.

#### `stat()` is a synchronous operation

The library doesn't normally do any kind of I/O itself, and so is not
blocking the process. The exception are `TEvStat` watchers - those call
`stat()`, which is a synchronous operation.

For local paths, this usually doesn't matter: unless the system is very
busy or the intervals between stat's are large, a stat call will be fast,
as the path data is usually in memory already (except when starting the
watcher). For networked file systems, calling `stat()` can block an
indefinite time due to network issues, and even under good conditions, a
stat call often takes multiple milliseconds. Therefore, it is best to
avoid using `TEvStat` watchers on networked paths, although this is fully
supported.

#### The special problem of stat time resolution

The `stat()` system call only supports full-second resolution portably,
and even on systems where the resolution is higher, most file systems
still only support whole seconds.

That means that, if the time is the only thing that changes, you can
easily miss updates: on the first update, `TEvStat` detects a change and
calls your callback, which does something. When there is another update
within the same second, it will be unable to detect unless the stat data
does change in other ways (e.g. file size).

The solution to this is to delay acting on a change for slightly more
than a second (or till slightly after the next full second boundary),
using a roughly one-second-delay `TEvTimer` (e.g.
`Timer.SetTimer(0, 1.02); Timer.Again;`). The `.02` offset is added to
work around small timing inconsistencies of some operating systems.

#### Watcher-Specific Functions and Data Members

- **`constructor Create(const APath: string; AInterval: TEvTstamp)`** /
  **`procedure SetStat(const APath: string; AInterval: TEvTstamp)`** -
  Configures the watcher to wait for status changes of the given path.
  The interval is a hint on how quickly a change is expected to be
  detected and should normally be specified as 0 to let the library
  choose a suitable value. The callback will receive an `evStat` event
  when a change was detected, relative to the attributes at the time the
  watcher was started (or the last change was detected).

- **`procedure StatNow`** *(C: `ev_stat_stat`)* - Updates the stat buffer
  immediately with new values. If you change the watched path in your
  callback, you could call this function to avoid detecting this change
  (while introducing a race condition if you are not the only one
  changing the path). Can also be useful simply to find out the new
  values.

- **`property Attr: TEvStatData`** *[read-only]* - The most-recently
  detected attributes of the file. If the `st_nlink` member is 0, then
  there was some error while `stat`ing the file. (On Windows the record
  is filled from `GetFileAttributesEx`; only size, times, directory bit
  and existence carry information there.)

- **`property Prev: TEvStatData`** *[read-only]* - The previous
  attributes of the file. The callback gets invoked whenever
  `Prev <> Attr`, or, more precisely, one or more of these members
  differ: `st_dev`, `st_ino`, `st_mode`, `st_nlink`, `st_uid`, `st_gid`,
  `st_rdev`, `st_size`, `st_atime`, `st_mtime`, `st_ctime`.

- **`property Interval: TEvTstamp`** *[read-only]* - The specified
  interval.

- **`property Path: string`** *[read-only]* - The path being watched.

#### Examples

Example: watch `/etc/passwd` for attribute changes.

```pascal
procedure TApp.PasswdCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  // /etc/passwd changed in some way
  if TEvStat(W).Attr.st_nlink <> 0 then
  begin
    Writeln('passwd current size  ', TEvStat(W).Attr.st_size);
    Writeln('passwd current mtime ', TEvStat(W).Attr.st_mtime);
  end
  else
    Writeln('wow, /etc/passwd is not there, expect problems.');
end;

Passwd := TEvStat.Create('/etc/passwd', 0);
Passwd.OnEvent := App.PasswdCb;
Passwd.Start(Loop);
```

Example: like above, but additionally use a one-second delay so we do not
miss updates (however, frequent updates will delay processing, too, so
one might do the work both on `TEvStat` callback invocation *and* on
`TEvTimer` callback invocation).

```pascal
procedure TApp.TimerCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  W.Stop;
  // now it's one second after the most recent passwd change
end;

procedure TApp.StatCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  // reset the one-second timer
  FDelayTimer.Again;
end;

FPasswd := TEvStat.Create('/etc/passwd', 0);
FPasswd.OnEvent := StatCb;
FPasswd.Start(Loop);
FDelayTimer := TEvTimer.Create(0, 1.02);
FDelayTimer.OnTimeout := TimerCb;
FDelayTimer.Start(Loop); // binds the loop; Again re-arms it
```

### TEvIdle - when you've got nothing better to do...

Idle watchers trigger events when no other events of the same or higher
priority are pending (prepare, check and other idle watchers do not count
as receiving "events").

That is, as long as your process is busy handling sockets or timeouts (or
even signals, imagine) of the same or higher priority it will not be
triggered. But when your process is idle (or only lower-priority watchers
are pending), the idle watchers are being called once per event loop
iteration - until stopped, that is, or your process receives more events
and becomes busy again with higher priority stuff.

The most noteworthy effect is that as long as any idle watchers are
active, the process will not block when waiting for new events.

Apart from keeping your process non-blocking (which is a useful effect on
its own sometimes), idle watchers are a good place to do
"pseudo-background processing", or delay processing stuff to after the
event loop has handled all outstanding events.

#### Abusing a TEvIdle watcher for its side-effect

As long as there is at least one active idle watcher, the library will
never sleep unnecessarily. Or in other words, it will loop as fast as
possible. For this to work, the idle watcher doesn't need to be invoked
at all - the lowest priority will do.

This mode of operation can be useful together with a `TEvCheck` watcher,
to do something on each event loop iteration - for example to balance
load between different connections. See "Abusing a TEvCheck watcher" for
a longer example.

#### Watcher-Specific Functions and Data Members

- **`constructor Create`** - Creates the idle watcher - it has no
  parameters of any kind.

#### Examples

Example: dynamically allocate a `TEvIdle` watcher, start it, and in the
callback, free it. Also, use no error checking, as usual.

```pascal
procedure TApp.IdleCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  // stop the watcher
  W.Stop;

  // now we can free it
  W.Free;

  // now do something you wanted to do when the program has
  // no longer anything immediate to do.
end;

IdleWatcher := TEvIdle.Create;
IdleWatcher.OnEvent := App.IdleCb;
IdleWatcher.Start(Loop);
```

### TEvPrepare and TEvCheck - customise your event loop!

Prepare and check watchers are often (but not always) used in pairs:
prepare watchers get invoked before the process blocks and check watchers
afterwards.

You *must not* call `Run` (or similar functions that enter the current
event loop) or `LoopFork` from either `TEvPrepare` or `TEvCheck`
watchers. Other loops than the current one are fine, however. The
rationale behind this is that you do not need to check for recursion in
those watchers, i.e. the sequence will always be prepare, blocking,
check, so if you have one watcher of each kind they will always be called
in pairs bracketing the blocking call.

Their main purpose is to integrate other event mechanisms into the
library and their use is somewhat advanced. They could be used, for
example, to track variable changes, implement your own watchers,
integrate other event libraries or a coroutine library and lots more.
They are also occasionally useful if you cache some data and want to
flush it before blocking.

This is done by examining in each prepare call which file descriptors
need to be watched by the other library, registering `TEvIo` watchers for
them and starting a `TEvTimer` watcher for any timeouts (many libraries
provide exactly this functionality). Then, in the check watcher, you
check for any events that occurred (by checking the pending status of all
watchers and stopping them) and call back into the library.

When used for this purpose, it is recommended to give `TEvCheck` watchers
highest (`EV_MAXPRI`) priority, to ensure that they are being run before
any other watchers after the poll (this doesn't matter for `TEvPrepare`
watchers).

Also, `TEvCheck` watchers (and `TEvPrepare` watchers, too) should not
activate ("feed") events into the library. While the library fully
supports this, they might get executed before other `TEvCheck` watchers
did their job. As `TEvCheck` watchers are often used to embed other
(non-libev) event loops those other event loops might be in an unusable
state until their `TEvCheck` watcher ran (always remind yourself to
coexist peacefully with others).

#### Abusing a TEvCheck watcher for its side-effect

`TEvCheck` (and less often also `TEvPrepare`) watchers can also be useful
because they are called once per event loop iteration. For example, if
you want to handle a large number of connections fairly, you normally
only do a bit of work for each active connection, and if there is more
work to do, you wait for the next event loop iteration, so other
connections have a chance of making progress.

Using a `TEvCheck` watcher is almost enough: it will be called on the
next event loop iteration. However, that isn't as soon as possible -
without external events, your `TEvCheck` watcher will not be invoked.

This is where `TEvIdle` watchers come in handy - all you need is a single
global idle watcher that is active as long as you have one active
`TEvCheck` watcher. The `TEvIdle` watcher makes sure the event loop will
not sleep, and the `TEvCheck` watcher makes sure a callback gets invoked.
Neither watcher alone can do that.

#### Watcher-Specific Functions and Data Members

- **`constructor Create`** - Creates the prepare or check watcher - they
  have no parameters of any kind.

### TEvEmbed - when one backend isn't enough...

**Not ported.** `ev_embed` lets a C libev embed one event loop into
another, which is only useful with *embeddable* backends (kqueue, Solaris
ports). None of this port's backends (epoll, poll, select) is embeddable,
so the watcher type was left out. The original documentation applies to the
C library only.

### TEvFork - the audacity to resume the event loop after a fork

Fork watchers are called when a `fork()` was detected (usually because
whoever is a good citizen cared to tell the library about it by calling
`LoopFork`). The invocation is done before the event loop blocks next and
before `TEvCheck` watchers are being called, and only in the child after
the fork. If whoever good citizen calling `LoopFork` cheats and calls it
in the wrong process, the fork handlers will be invoked, too, of course.

#### The special problem of life after fork - how is it possible?

Most uses of `fork()` consist of forking, then some simple calls to set
up/change the process environment, followed by a call to `exec()`. This
sequence should be handled without any problems.

This changes when the application actually wants to do event handling in
the child, or both parent in child, in effect "continuing" after the
fork. The default mode of operation (with application help to detect
forks) is to duplicate all the state in the child, as would be expected
when *either* the parent *or* the child process continues.

When both processes want to continue using the library, then this is
usually the wrong result. In that case, usually one process (typically
the parent) is supposed to continue with all watchers in place as before,
while the other process typically wants to start fresh, i.e. without any
active watchers.

The cleanest and most efficient way to achieve that is to simply create a
new event loop, which of course will be "empty", and use that for new
watchers. This has the advantage of not touching more memory than
necessary, and thus avoiding the copy-on-write, and the disadvantage of
having to use multiple event loops (which do not support signal
watchers).

#### Watcher-Specific Functions and Data Members

- **`constructor Create`** - Creates the fork watcher - it has no
  parameters of any kind.

### TEvCleanup - even the best things end

Cleanup watchers are called just before the event loop is being destroyed
(`TEvLoop.Free`).

While there is no guarantee that the event loop gets destroyed, cleanup
watchers provide a convenient method to install cleanup hooks for your
program, worker threads and so on - you just have to make sure to destroy
the loop when you want them to be invoked.

Cleanup watchers are invoked in the same way as any other watcher. Unlike
all other watchers, they do not keep a reference to the event loop (which
makes a lot of sense if you think about it). Like all other watchers, you
can call library functions in the callback, except starting another
cleanup watcher.

*(Port note: after the cleanup callbacks have run, the dying loop detaches
the cleanup watchers from itself, so freeing them afterwards is safe.)*

#### Watcher-Specific Functions and Data Members

- **`constructor Create`** - Creates the cleanup watcher - it has no
  parameters of any kind.

Example: the default loop is destroyed at unit finalization, so any
cleanup watchers registered on it are called at program exit.

### TEvAsync - how to wake up an event loop

In general, you cannot use a `TEvLoop` from multiple threads or other
asynchronous sources such as signal handlers (as opposed to multiple
event loops - those are of course safe to use in different threads).

Sometimes, however, you need to wake up an event loop you do not control,
for example because it belongs to another thread. This is what `TEvAsync`
watchers do: as long as the `TEvAsync` watcher is active, you can signal
it by calling `Send`, which is thread- and signal safe.

This functionality is very similar to `TEvSignal` watchers, as signals,
too, are asynchronous in nature, and signals, too, will be compressed
(i.e. the number of callback invocations may be less than the number of
`Send` calls). In fact, you could use signal watchers as a kind of
"global async watchers" by using a watcher on an otherwise unused signal,
and `EvFeedSignal` to signal this watcher from another thread, even
without knowing which loop owns the signal.

#### Queueing

`TEvAsync` does not support queueing of data in any way. The reason is
that the author does not know of a simple (or any) algorithm for a
multiple-writer-single-reader queue that works in all cases. That means
that if you want to queue data, you have to provide your own queue. The
strategy is the same as in C: protect the queue with a mutex
(`TCriticalSection`), put data into it in the producer thread, call
`Send`, and drain the queue under the same lock inside the async watcher
callback.

```pascal
// producer thread:
FQueueLock.Enter;
FQueue.Add(Data);
FQueueLock.Leave;
FAsync.Send;

// async watcher callback (loop thread):
procedure TApp.AsyncCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
begin
  FQueueLock.Enter;
  try
    while FQueue.Count > 0 do
      Process(FQueue.Extract);
  finally
    FQueueLock.Leave;
  end;
end;
```

#### Watcher-Specific Functions and Data Members

- **`constructor Create`** - Creates the async watcher - it has no
  parameters of any kind.

- **`procedure Send`** *(C: `ev_async_send`)* - Sends/signals/activates
  the watcher, that is, feeds an `evAsync` event on the watcher into the
  event loop, and instantly returns. Unlike `FeedEvent`, this call is
  safe to do from other threads or signal contexts.

  Note that, as with other watchers, multiple events might get compressed
  into a single callback invocation (another way to look at this is that
  `TEvAsync` watchers are level-triggered: they are set on `Send`, reset
  when the event loop detects that).

  This call incurs the overhead of at most one extra system call per
  event loop iteration, if the event loop is blocked, and no syscall at
  all if the event loop (or your program) is processing events. That
  means that repeated calls are basically free (there is no need to avoid
  calls for performance reasons) and that the overhead becomes smaller
  (typically zero) under load.

- **`property AsyncPending: Boolean`** *(C: `ev_async_pending`)* -
  Returns true when `Send` has been called on the watcher but the event
  has not yet been processed (or even noted) by the event loop. `Send`
  sets a flag in the watcher and wakes up the loop; when the loop
  iterates next and checks for the watcher to have become active, it will
  reset the flag again. `AsyncPending` can be used to very quickly check
  whether invoking the loop might be a good idea.

  Note that this does *not* check whether the watcher itself is pending,
  only whether it has been requested to make this watcher pending: there
  is a time window between the event loop checking and resetting the
  async notification, and the callback being invoked.

## OTHER FUNCTIONS

There are some other functions of possible interest. Described. Here.
Now.

### TEvLoop.Once(Fd, Events, Timeout, Callback)

This function combines a simple timer and an I/O watcher, calls your
callback on whichever event happens first and automatically stops both
watchers. This is useful if you want to wait for a single event on an fd
or timeout without having to allocate/configure/start/stop/free one or
more watchers yourself.

If `Fd` is less than 0, then no I/O watcher will be started and the
`Events` argument is being ignored. Otherwise, a `TEvIo` watcher for the
given `Fd` and `Events` set will be created and started.

If `Timeout` is less than 0, then no timeout watcher will be started.
Otherwise a `TEvTimer` watcher with after = `Timeout` (and repeat = 0)
will be started. 0 is a valid timeout.

The callback has the type
`procedure(REvents: TEvEvents) of object` and is passed a `REvents` set
like normal event callbacks (a combination of `evError`, `evRead`,
`evWrite` or `evTimer`). Note that it is possible to receive *both* a
timeout and an io event at the same time - you probably should give io
events precedence.

Example: wait up to ten seconds for data to appear on a socket.

```pascal
procedure TApp.SockReady(REvents: TEvEvents);
begin
  if evRead in REvents then
    // socket might have data for us, joy!
  else if evTimer in REvents then
    // doh, nothing arrived
end;

Loop.Once(SockFd, [evRead], 10.0, App.SockReady);
```

### Watcher.FeedEvent / TEvLoop.FeedFdEvent / TEvLoop.FeedSignalEvent

`Watcher.FeedEvent(REvents)` feeds the given events as if they had
happened (see the generic watcher functions). `Loop.FeedFdEvent(Fd,
REvents)` (C: `ev_feed_fd_event`) feeds an event to all io watchers on an
fd. `Loop.FeedSignalEvent(SigNum)` feeds an event as if the given signal
occurred on the loop; see also the async-safe global `EvFeedSignal`.

## COMMON OR USEFUL IDIOMS (OR BOTH)

This section explains some common idioms that are not immediately
obvious. Note that examples are sprinkled over the whole manual, and this
section only contains stuff that wouldn't fit anywhere else.

### ASSOCIATING CUSTOM DATA WITH A WATCHER

Each watcher has a `Data: Pointer` property that you can read or modify
at any time: the library will completely ignore it. This can be used to
associate arbitrary data with your watcher.

In this port there are two more natural options. Since callbacks are `of
object` methods, per-watcher state usually lives in the object providing
the callback. And since watchers are classes, you can simply subclass
them (the equivalent of C's struct-embedding idiom):

```pascal
type
  TMyIo = class(TEvIo)
  public
    OtherFd: Integer;
    SomeData: Pointer;
    MostInteresting: TWhatever;
  end;
```

And since your callback will be called with a reference to the watcher,
you can cast it back to your own type:

```pascal
procedure TApp.MyCb(Loop: TEvLoop; W: TEvWatcher; REvents: TEvEvents);
var
  Mine: TMyIo;
begin
  Mine := TMyIo(W);
  ...
end;
```

### BUILDING YOUR OWN COMPOSITE WATCHERS

Another common scenario is to use some object with multiple embedded
watchers, in effect creating your own watcher that combines multiple
event sources into one "super-watcher". Where C needs `offsetof` pointer
arithmetic to find the containing struct from the watcher, in this port
the containing object is simply captured by the method callback:

```pascal
type
  TMyBiggy = class
    SomeData: Integer;
    T1, T2: TEvTimer;
    procedure T1Cb(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure T2Cb(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;
// inside T1Cb/T2Cb, "Self" *is* the TMyBiggy instance
```

### AVOIDING FINISHING BEFORE RETURNING

Often you have structures like this in event-based programs:

```pascal
procedure Callback...
begin
  Request.Free;
end;

Request := StartNewRequest(..., Callback);
```

The intent is to start some "lengthy" operation. The `Request` could be
used to cancel the operation, or do other things with it.

It's not uncommon to have code paths in `StartNewRequest` that
immediately invoke the callback, for example, to report errors. Or you
add some caching layer that finds that it can skip the lengthy aspects of
the operation and simply invoke the callback with the result. The problem
here is that this will happen *before* `StartNewRequest` has returned, so
`Request` is not set.

A common way around all these issues is to make sure that
`StartNewRequest` *always* returns before the callback is invoked. If it
immediately knows the result, it can artificially delay invoking the
callback by using a prepare or idle watcher for example, or more
sneakily, by reusing an existing (stopped) watcher and pushing it into
the pending queue:

```pascal
Watcher.OnEvent := Callback;
Watcher.FeedEvent([]);
```

This way, `StartNewRequest` can safely return before the callback is
invoked, while not delaying callback invocation too much.

### MODEL/NESTED EVENT LOOP INVOCATIONS AND EXIT CONDITIONS

Often (especially in GUI toolkits) there are places where you have
*modal* interaction, which is most easily implemented by recursively
invoking `Run`.

This brings the problem of exiting - a callback might want to finish the
main `Run` call, but not the nested one (e.g. user clicked "Quit", but a
modal "Are you sure?" dialog is still waiting), or just the nested one
and not the main one (e.g. user clicked "Ok" in a modal dialog), or some
other combination: in these cases, a simple `BreakLoop` will not work.

The solution is to maintain a "break this loop" variable for each `Run`
invocation, and use a loop around `Run` until the condition is triggered,
using `[evrunOnce]`:

```pascal
// main loop
while not ExitMainLoop do
  Loop.Run([evrunOnce]);

// in a modal watcher
while not ExitNestedLoop do
  Loop.Run([evrunOnce]);
```

To exit from any of these loops, just set the corresponding exit
variable (both, to exit both).

### THREAD LOCKING

The C manual shares one loop between threads using
`ev_set_loop_release_cb` and `ev_set_invoke_pending_cb`; both are ported
(`SetLoopReleaseCb`, `SetInvokePendingCb`). The release callback runs just
before the loop blocks and the acquire callback just after, so you can
unlock/lock a mutex around the blocking poll and drive callbacks in
another thread.

Often a simpler strategy is enough and covers most real uses:

- run the loop in one dedicated thread;
- protect watcher starts/stops with a mutex of your own;
- after modifying the loop from another thread, wake it with a
  `TEvAsync.Send` so the blocking poll picks up the changes.

```pascal
// in the controlling thread:
QueueLock.Enter;
Timer.Start(Loop);   // modify the loop under the lock
QueueLock.Leave;
WakeUp.Send;         // required: otherwise the loop, currently blocking
                     // in the kernel, has no knowledge of the new timer
```

## SECTIONS OF THE C MANUAL NOT APPLICABLE TO THIS PORT

For completeness, the remaining `ev.pod` chapters and why they are
absent here:

- **LIBEVENT EMULATION / C++ SUPPORT / OTHER LANGUAGE BINDINGS** - about
  the C library's compatibility layers; this port *is* a language
  binding of sorts, with its own OO API.
- **MACRO MAGIC** - C preprocessor conveniences (`EV_P_`, `EV_A_`, ...);
  meaningless in Pascal.
- **EMBEDDING (the chapter)** - about compiling libev's C source into
  applications and its compile-time configuration (`EV_FEATURES`,
  `EV_USE_*`); this port corresponds to the default full-featured
  configuration with the epoll and select backends compiled in.
- **PORTING FROM LIBEV 3.X TO 4.X** - this port only ever implemented
  the 4.x API (`Run`/`BreakLoop`, `evTimer` etc.).

## PORTABILITY NOTES

### WIN32 PLATFORM LIMITATIONS AND WORKAROUNDS

Win32 doesn't support any of the standards (e.g. POSIX) that libev
requires, and its I/O model is fundamentally incompatible with the POSIX
model. The library still offers limited functionality on this platform in
the form of the select backend, and only supports *socket* descriptors.

In this port, an "fd" on Windows *is* the winsock `SOCKET` value itself
(the C library optionally maps C runtime descriptors; there is no CRT
descriptor layer in Pascal). The port rolls its own `fd_set` with a
capacity of 1024 sockets instead of winsock's default 64.

Sensible signal handling is officially unsupported by Microsoft, so on
Windows `TEvSignal` maps to the CRT `signal()` function and only a handful
of signals work; `TEvChild` is Linux-only (as in libev, where child
watchers are disabled on Windows).

Not a library limitation but worth mentioning: windows apparently doesn't
accept large writes: instead of resulting in a partial write, windows
will either accept everything or return `ENOBUFS` if the buffer is too
large, so make sure you only write small amounts into your sockets (less
than a megabyte seems safe, but this apparently depends on the amount of
memory available).

### GNU/LINUX NOTES

On Free Pascal the platform types and syscalls (`struct stat`, `timespec`,
`struct sigaction`, and the read/write/poll/signal/wait calls, plus
`struct epoll_event` on Linux) are taken from the RTL units `BaseUnix`,
`UnixType` and `Linux`, which define them per OS and architecture. That is
what lets the same `LibEv.pas` build and run on Linux (x86-64, ARM64, 32-bit
ARM) and on macOS; CI exercises all of them. Delphi's Linux compiler targets
x86-64 only, so on Delphi the equivalent structs are hand-written for that ABI.

On macOS the loop uses the poll backend (the native kqueue backend is not
ported), signals use `sigaction`, `TEvStat` uses timed polling, and the async
/ signal wakeup uses a plain pipe; the Linux-only kernel interfaces (epoll,
inotify, `eventfd`, `signalfd`, `timerfd`) and `TEvChild` are unavailable
there. The remaining portability chapters of `ev.pod` (Solaris, AIX) concern
platforms outside this port's scope.

## ALGORITHMIC COMPLEXITIES

In this section the complexities of (many of) the algorithms used inside
the library will be documented. For complexity discussions about backends
see the loop documentation above.

All of the following are about amortised time: if an array needs to be
extended, the library needs to reallocate and move the whole array, but
this happens asymptotically rarer with higher number of elements, so O(1)
might mean a lengthy reallocation operation in rare cases, but on average
it is much faster and asymptotically approaches constant time.

- **Starting and stopping timer/periodic watchers:
  O(log skipped_other_timers)** - This means that, when you have a
  watcher that triggers in one hour and there are 100 watchers that would
  trigger before that, then inserting will have to skip roughly seven
  (ld 100) of these watchers.
- **Changing timer/periodic watchers (by autorepeat or calling Again):
  O(log skipped_other_timers)** - That means that changing a timer costs
  less than removing/adding them, as only the relative motion in the
  event queue has to be paid for.
- **Starting io/check/prepare/idle/signal/child/fork/async watchers:
  O(1)** - These just add the watcher into an array or at the head of a
  list.
- **Stopping check/prepare/idle/fork/async watchers: O(1)**
- **Stopping an io/signal/child watcher:
  O(number_of_watchers_for_this_(fd/signal/pid mod EV_PID_HASHSIZE))** -
  These watchers are stored in lists, so they need to be walked to find
  the correct watcher to remove. The lists are usually short (you don't
  usually have many watchers waiting for the same fd or signal: one is
  typical, two is rare).
- **Finding the next timer in each loop iteration: O(1)** - By virtue of
  using a 4-heap, the next timer is always found at a fixed position in
  the storage array.
- **Each change on a file descriptor per loop iteration:
  O(number_of_watchers_for_this_fd)** - A change means an I/O watcher
  gets started or stopped, which requires the library to recalculate its
  status (and possibly tell the kernel, depending on backend and whether
  `SetIo` was used).
- **Activating one watcher (putting it into the pending state): O(1)**
- **Priority handling: O(number_of_priorities)** - Priorities are
  implemented by allocating some space for each priority. When doing
  priority-based operations, the library usually has to linearly search
  all the priorities, but starting/stopping and activating watchers
  becomes O(1) with respect to priority handling.
- **Sending a TEvAsync: O(1)**
- **Processing TEvAsync.Send: O(number_of_async_watchers)**
- **Processing signals: O(max_signal_number)** - Sending involves a
  system call *iff* there were no other `Send` calls in the current loop
  iteration and the loop is currently blocked. Checking for async and
  signal events involves iterating over all running async watchers or all
  signal numbers.

## GLOSSARY

- **active** - A watcher is active as long as it has been started and not
  yet stopped. See [WATCHER STATES](#watcher-states) for details.
- **application** - In this document, an application is whatever is using
  the library.
- **backend** - The part of the code dealing with the operating system
  interfaces.
- **callback** - The method that is called when some event has been
  detected. Callbacks are being passed the event loop, the watcher that
  received the event, and the actual event set.
- **callback/watcher invocation** - The act of calling the callback
  associated with a watcher.
- **event** - A change of state of some external event, such as data now
  being available for reading on a file descriptor, time having passed or
  simply not having any other events happening anymore. In this library,
  events are represented as elements of a set (such as `evRead` or
  `evTimer`).
- **event library** - A software package implementing an event model and
  loop.
- **event loop** - An entity that handles and processes external events
  and converts them into callback invocations.
- **event model** - The model used to describe how an event loop handles
  and processes watchers and events.
- **pending** - A watcher is pending as soon as the corresponding event
  has been detected. See [WATCHER STATES](#watcher-states) for details.
- **real time** - The physical time that is observed. It is apparently
  strictly monotonic :)
- **wall-clock time** - The time and date as shown on clocks. Unlike real
  time, it can actually be wrong and jump forwards and backwards, e.g.
  when you adjust your clock.
- **watcher** - An object that describes interest in certain events.
  Watchers need to be started (attached to an event loop) before they can
  receive events.

## AUTHOR

The original libev and its manual: Marc Lehmann <libev@schmorp.de>, with
repeated corrections by Mikael Magnusson and Emanuele Giaquinta, and
minor corrections by many others.

This adaptation for the TLibEv Delphi/Free Pascal port: Mehmet Fide
(2026). Distributed under the same 2-clause BSD license as the port (see
`LICENSE`).
