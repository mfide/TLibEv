//
// LibEv - an object-oriented, line-by-line port of libev 4.33 to Delphi/Free Pascal.
//
// C source: libev-4.33/ev.c, ev.h, ev_select.c, ev_epoll.c, ev_win32.c
// (Marc Alexander Lehmann, BSD/GPL dual license; this port exercises the
// BSD option and is distributed under the 2-clause BSD license, see the
// LICENSE file in the project root).
// The "ev.c:NNNN name" comments above each method point to the C counterpart.
//
// Deliberate deviations:
// - Event masks are Pascal sets (TEvEvents) instead of C bit masks; the enum
//   ordinals equal the C bit numbers (evRead=0 <-> 0x01, evTimer=8 <-> 0x100 ...).
// - Dynamic arrays + ArrayNextSize replace ev_realloc/array_needsize while
//   keeping the same growth curve.
// - On Windows an fd is the SOCKET value itself (libev's CRT fd mapping via
//   _get_osfhandle is skipped).
// - Custom allocators and the LIBEV_FLAGS environment variable are not
//   supported.
//
unit LibEv;

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

// EV_POSIX marks the POSIX targets (Linux and macOS/Darwin) that share the
// BaseUnix platform layer; Linux-only kernel features (epoll, inotify, eventfd,
// signalfd, timerfd) stay under a plain LINUX guard.
{$IF Defined(LINUX) or Defined(DARWIN)}
  {$DEFINE EV_POSIX}
{$IFEND}

{$IF not (Defined(MSWINDOWS) or Defined(EV_POSIX))}
  {$MESSAGE ERROR 'LibEv: only Windows, Linux and macOS are supported'}
{$IFEND}

uses
{$IFDEF MSWINDOWS}
  {$IFDEF FPC}
  Windows, WinSock2,
  {$ELSE}
  Winapi.Windows, Winapi.Winsock2,
  {$ENDIF}
{$ENDIF}
{$IFDEF EV_POSIX}
  {$IFDEF FPC}
  { On FPC the platform ABI (types, structs, syscalls, and the errno / flag /
    signal-number constants) comes from the RTL, which defines them per OS and
    per architecture - this is what lets the same source run on Linux (x86-64,
    arm, aarch64) and macOS. The Linux unit adds the Linux-only kernel calls. }
  BaseUnix, UnixType, Unix,
    {$IFDEF LINUX}
    Linux,
    {$ENDIF}
  {$ENDIF}
{$ENDIF}
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF};

const
  { TLibEv's own version. This is an original Delphi / Free Pascal library,
    versioned independently of the libev C sources it is ported from. }
  TLIBEV_VERSION_MAJOR = 1;
  TLIBEV_VERSION_MINOR = 0;
  TLIBEV_VERSION       = '1.0';

  { the upstream libev release this port follows line by line (ev.h EV_VERSION_*) }
  LIBEV_UPSTREAM_VERSION = '4.33';

type
  { ev.h:157 ev_tstamp }
  TEvTstamp = Double;

  { ev.h:221 event mask enum. Ordinal values are the C bit numbers. }
  TEvEvent = (
    evRead     = 0,   { EV_READ     0x00000001 }
    evWrite    = 1,   { EV_WRITE    0x00000002 }
    evIoFdSet  = 7,   { EV__IOFDSET 0x00000080 (internal) }
    evTimer    = 8,   { EV_TIMER    0x00000100 }
    evPeriodic = 9,   { EV_PERIODIC 0x00000200 }
    evSignal   = 10,  { EV_SIGNAL   0x00000400 }
    evChild    = 11,  { EV_CHILD    0x00000800 }
    evStat     = 12,  { EV_STAT     0x00001000 }
    evIdle     = 13,  { EV_IDLE     0x00002000 }
    evPrepare  = 14,  { EV_PREPARE  0x00004000 }
    evCheck    = 15,  { EV_CHECK    0x00008000 }
    evEmbed    = 16,  { EV_EMBED    0x00010000 }
    evFork     = 17,  { EV_FORK     0x00020000 }
    evCleanup  = 18,  { EV_CLEANUP  0x00040000 }
    evAsync    = 19,  { EV_ASYNC    0x00080000 }
    evCustom   = 24,  { EV_CUSTOM   0x01000000 }
    evError    = 31   { EV_ERROR    0x80000000 }
  );
  TEvEvents = set of TEvEvent;

  { ev.h:501 flags for ev_default_loop / ev_loop_new }
  TEvFlag = (
    evflagNoInotify = 20,  { EVFLAG_NOINOTIFY  0x00100000 }
    evflagSignalFd  = 21,  { EVFLAG_SIGNALFD   0x00200000 (Linux) }
    evflagNoTimerFd = 23,  { EVFLAG_NOTIMERFD  0x00800000 (Linux) }
    evflagNoEnv     = 24,  { EVFLAG_NOENV      0x01000000 (unused, kept for parity) }
    evflagForkCheck = 25   { EVFLAG_FORKCHECK  0x02000000 }
    { EVFLAG_NOSIGMASK: not ported (this port never modifies the signal mask
      outside signalfd) }
  );
  TEvFlags = set of TEvFlag;

  { ev.h:518 backend bits }
  TEvBackendKind = (
    evbackendSelect = 0,  { EVBACKEND_SELECT 0x01 }
    evbackendPoll   = 1,  { EVBACKEND_POLL   0x02 }
    evbackendEpoll  = 2   { EVBACKEND_EPOLL  0x04 }
  );
  TEvBackendKinds = set of TEvBackendKind;

  { ev.h:629 ev_run flags }
  TEvRunFlag = (evrunNoWait, evrunOnce);  { EVRUN_NOWAIT=1, EVRUN_ONCE=2 }
  TEvRunFlags = set of TEvRunFlag;

  { ev.h:635 ev_break how values }
  TEvBreakHow = (evbreakCancel, evbreakOne, evbreakAll);  { 0, 1, 2 }

  EEvError = class(Exception);

const
  { ev.h:82 priority range (EV_FEATURE_CONFIG enabled) }
  EV_MINPRI = -2;
  EV_MAXPRI = +2;

  { ev.c NUMPRI = EV_MAXPRI - EV_MINPRI + 1 }
  NUMPRI = EV_MAXPRI - EV_MINPRI + 1;

{$IFDEF LINUX}
  { ev.c EV_INOTIFY_HASHSIZE (EV_FEATURE_DATA enabled) }
  EV_INOTIFY_HASHSIZE = 16;
{$ENDIF}

type
{$IFDEF LINUX}
  { struct inotify_event header (followed by len name bytes) }
  TInotifyEvent = record
    Wd: Integer;
    Mask: Cardinal;
    Cookie: Cardinal;
    Len: Cardinal;
  end;
  PInotifyEvent = ^TInotifyEvent;
{$ENDIF}
  TEvLoop = class;
  TEvWatcher = class;
  TEvPeriodic = class;

  { ev.h:253 EV_CB_DECLARE - common callback signature for all watchers }
  TEvCallback = procedure(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents) of object;

  { ev.h:346 reschedule_cb of ev_periodic }
  TEvPeriodicRescheduleCb = function(Watcher: TEvPeriodic; NowTime: TEvTstamp): TEvTstamp of object;

  { ev.h:672 ev_loop_callback - used for the invoke-pending / release / acquire
    hooks (threaded loop sharing) }
  TEvLoopCallback = procedure(Loop: TEvLoop) of object;

  { ev.h:302 ev_watcher - base class of all watchers }
  TEvWatcher = class
  private
    FActive: Integer;    { ev.h:287 active (private): 0, or an array/heap index }
    FPending: Integer;   { ev.h:288 pending (private): 0, or index+1 into pendings }
    FPriority: Integer;  { ev.h:282 EV_DECL_PRIORITY }
    FData: Pointer;      { ev.h:249 EV_COMMON void *data }
    FLoop: TEvLoop;      { OO extra: the loop bound at Start (a parameter in C) }
    function GetIsActive: Boolean;
    function GetIsPending: Boolean;
  protected
    FOnEvent: TEvCallback; { ev.h:253 cb }
  public
    constructor Create;  { ev.h:690 ev_init: active=pending=0, priority=0 }
    destructor Destroy; override;
    { Stops the watcher if active (each subclass implements its ev_TYPE_stop). }
    procedure Stop; virtual; abstract;
    { ev.h:256 EV_CB_INVOKE / ev.c:759 ev_invoke - run the callback directly
      with the given revents (loop/revents need not be otherwise valid) }
    procedure Invoke(REvents: TEvEvents); virtual;
    { ev.c:2313 ev_feed_event - queue an event as if it had happened }
    procedure FeedEvent(REvents: TEvEvents);
    { ev.c:4288 ev_clear_pending }
    function ClearPending: TEvEvents;
    property IsActive: Boolean read GetIsActive;    { ev.h:727 ev_is_active }
    property IsPending: Boolean read GetIsPending;  { ev.h:726 ev_is_pending }
    property Priority: Integer read FPriority write FPriority; { ev.h:736; do not change while active }
    property Data: Pointer read FData write FData;
    property Loop: TEvLoop read FLoop;
    property OnEvent: TEvCallback read FOnEvent write FOnEvent;
  end;

  { ev.h:308 ev_watcher_list - watchers kept in per-fd linked lists }
  TEvWatcherList = class(TEvWatcher)
  private
    FNext: TEvWatcherList;  { ev.h:295 next (private) }
  end;

  { ev.h:314 ev_watcher_time }
  TEvWatcherTime = class(TEvWatcher)
  protected
    FAt: TEvTstamp;  { ev.h:299 at (private) }
  end;

  { ev.h:321 ev_io - invoked when the fd is readable/writable }
  TEvIo = class(TEvWatcherList)
  private
    FFd: Integer;         { ev.h:325 fd (ro) - the SOCKET value on Windows }
    FEvents: TEvEvents;   { ev.h:326 events (ro) }
  public
    constructor Create(AFd: Integer; AEvents: TEvEvents);
    { ev.h:698 ev_io_set - only while stopped }
    procedure SetIo(AFd: Integer; AEvents: TEvEvents);
    { ev.h:697 ev_io_modify - change the event mask, fd must stay the same (while stopped) }
    procedure Modify(AEvents: TEvEvents);
    procedure Start(ALoop: TEvLoop);  { ev.c:4332 ev_io_start }
    procedure Stop; override;         { ev.c:4362 ev_io_stop }
    property Fd: Integer read FFd;
    property Events: TEvEvents read FEvents;
  end;

  { ev.h:331 ev_timer - relative timer based on the monotonic clock }
  TEvTimer = class(TEvWatcherTime)
  private
    FRepeat: TEvTstamp;  { ev.h:335 repeat (rw) }
    function GetRemaining: TEvTstamp;
  public
    constructor Create(AAfter, ARepeat: TEvTstamp);
    { ev.h:699 ev_timer_set - only while stopped }
    procedure SetTimer(AAfter, ARepeat: TEvTstamp);
    procedure Start(ALoop: TEvLoop);  { ev.c:4385 ev_timer_start }
    procedure Stop; override;         { ev.c:4410 ev_timer_stop }
    procedure Again;                  { ev.c:4441 ev_timer_again }
    property RepeatInterval: TEvTstamp read FRepeat write FRepeat;
    property Remaining: TEvTstamp read GetRemaining; { ev.c:4468 ev_timer_remaining }
    property OnTimeout: TEvCallback read FOnEvent write FOnEvent; { alias of OnEvent }
  end;

  { ev.h:340 ev_periodic - absolute timer based on wall-clock time (UTC),
    optionally repeating at regular intervals }
  TEvPeriodic = class(TEvWatcherTime)
  private
    FOffset: TEvTstamp;    { ev.h:344 offset (rw) }
    FInterval: TEvTstamp;  { ev.h:345 interval (rw) }
    FRescheduleCb: TEvPeriodicRescheduleCb; { ev.h:346 reschedule_cb (rw) }
  public
    constructor Create(AOffset, AInterval: TEvTstamp);
    { ev.h:700 ev_periodic_set - only while stopped }
    procedure SetPeriodic(AOffset, AInterval: TEvTstamp);
    procedure Start(ALoop: TEvLoop);  { ev.c:4476 ev_periodic_start }
    procedure Stop; override;         { ev.c:4512 ev_periodic_stop }
    procedure Again;                  { ev.c:4541 ev_periodic_again }
    property Offset: TEvTstamp read FOffset write FOffset;
    property Interval: TEvTstamp read FInterval write FInterval;
    property At: TEvTstamp read FAt;  { ev.h:740 ev_periodic_at }
    property OnReschedule: TEvPeriodicRescheduleCb read FRescheduleCb write FRescheduleCb;
  end;

  { ev.h:397 ev_idle - runs when nothing else needs to be done }
  TEvIdle = class(TEvWatcher)
  public
    procedure Start(ALoop: TEvLoop);  { ev.c ev_idle_start }
    procedure Stop; override;         { ev.c ev_idle_stop }
  end;

  { ev.h:405 ev_prepare - runs on each loop iteration, just before blocking }
  TEvPrepare = class(TEvWatcher)
  public
    procedure Start(ALoop: TEvLoop);  { ev.c ev_prepare_start }
    procedure Stop; override;         { ev.c ev_prepare_stop }
  end;

  { ev.h:412 ev_check - runs on each loop iteration, just after blocking }
  TEvCheck = class(TEvWatcher)
  public
    procedure Start(ALoop: TEvLoop);  { ev.c ev_check_start }
    procedure Stop; override;         { ev.c ev_check_stop }
  end;

  { ev.h:419 ev_fork - the callback gets invoked before check in the child
    process when a fork was detected (or after an explicit LoopFork call) }
  TEvFork = class(TEvWatcher)
  public
    procedure Start(ALoop: TEvLoop);  { ev.c:5319 ev_fork_start }
    procedure Stop; override;         { ev.c:5334 ev_fork_stop }
  end;

  { ev.h:426 ev_cleanup - invoked just before the loop gets destroyed }
  TEvCleanup = class(TEvWatcher)
  public
    procedure Start(ALoop: TEvLoop);  { ev.c:5357 ev_cleanup_start }
    procedure Stop; override;         { ev.c:5374 ev_cleanup_stop }
  end;

  { ev.h:374 ev_statdata - the subset of struct stat that libev compares;
    on Windows it is filled from GetFileAttributesEx (similar in content to
    the _stati64 libev uses there) }
  TEvStatData = record
    st_dev: UInt64;
    st_ino: UInt64;
    st_mode: Cardinal;
    st_nlink: UInt64;   { 0 means: file missing or other error }
    st_uid: Cardinal;
    st_gid: Cardinal;
    st_rdev: UInt64;
    st_size: Int64;
    st_atime: Int64;    { seconds since the Unix epoch }
    st_mtime: Int64;
    st_ctime: Int64;
  end;

  { ev.h:381 ev_stat - invoked each time the stat data of a path changes.
    This port currently uses the timer-polling implementation only; the
    inotify fast path of C is a planned addition. }
  TEvStat = class(TEvWatcherList)
  private
    FTimer: TEvTimer;      { ev.h:385 timer (private) }
    FInterval: TEvTstamp;  { ev.h:386 interval (ro) }
    FPath: string;         { ev.h:387 path (ro) }
    FPrev: TEvStatData;    { ev.h:388 prev (ro) }
    FAttr: TEvStatData;    { ev.h:389 attr (ro) }
    FWd: Integer;          { ev.h:391 wd - inotify watch descriptor (unused yet) }
    procedure TimerCb(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents); { ev.c:4983 stat_timer_cb }
  public
    constructor Create(const APath: string; AInterval: TEvTstamp);
    destructor Destroy; override;
    { ev.h:703 ev_stat_set - only while stopped }
    procedure SetStat(const APath: string; AInterval: TEvTstamp);
    { ev.c:4973 ev_stat_stat - refresh Attr from the filesystem }
    procedure StatNow;
    procedure Start(ALoop: TEvLoop);  { ev.c:5023 ev_stat_start }
    procedure Stop; override;         { ev.c:5054 ev_stat_stop }
    property Path: string read FPath;
    property Interval: TEvTstamp read FInterval;
    property Attr: TEvStatData read FAttr;   { current state }
    property Prev: TEvStatData read FPrev;   { state before the last change }
  end;

  { the OO face of ev_once's callback (the C void *arg travels in the
    object instance instead) }
  TEvOnceCallback = procedure(REvents: TEvEvents) of object;

  { ev.h:457 ev_async - invoked when somebody calls Send on the watcher;
    Send is safe to call from other threads }
  TEvAsync = class(TEvWatcher)
  private
    FSent: Integer;  { ev.h:461 sent (private, EV_ATOMIC_T) }
    function GetAsyncPending: Boolean;
  public
    procedure Start(ALoop: TEvLoop);  { ev.c:5398 ev_async_start }
    procedure Stop; override;         { ev.c:5417 ev_async_stop }
    procedure Send;                   { ev.c:5438 ev_async_send }
    property AsyncPending: Boolean read GetAsyncPending; { ev.h:464 ev_async_pending }
  end;

  { ev.h:351 ev_signal - invoked when the given signal has been received.
    Delivered synchronously via the event loop: sigaction on Linux, the CRT
    signal() function on Windows (where only a few signals such as SIGINT and
    SIGTERM are actually supported by the runtime). }
  TEvSignal = class(TEvWatcherList)
  private
    FSigNum: Integer;  { ev.h:355 signum (ro) }
  public
    constructor Create(ASigNum: Integer);
    { ev.h:701 ev_signal_set - only while stopped }
    procedure SetSignal(ASigNum: Integer);
    procedure Start(ALoop: TEvLoop);  { ev.c:4557 ev_signal_start }
    procedure Stop; override;         { ev.c:4640 ev_signal_stop }
    property SigNum: Integer read FSigNum;
  end;

{$IFDEF LINUX}
  { ev.h:361 ev_child - invoked when SIGCHLD is received and waitpid
    indicates the given pid; only supported in the default loop; does not
    support priorities. Linux-only (EV_CHILD_ENABLE is 0 on _WIN32). }
  TEvChild = class(TEvWatcherList)
  private
    FFlags: Integer;   { ev.h:365 flags (private) }
    FPid: Integer;     { ev.h:366 pid (ro) }
    FRPid: Integer;    { ev.h:367 rpid (rw) }
    FRStatus: Integer; { ev.h:368 rstatus (rw) }
  public
    constructor Create(APid: Integer; ATrace: Boolean);
    { ev.h:702 ev_child_set - only while stopped }
    procedure SetChild(APid: Integer; ATrace: Boolean);
    procedure Start(ALoop: TEvLoop);  { ev.c:4681 ev_child_start }
    procedure Stop; override;         { ev.c:4698 ev_child_stop }
    property Pid: Integer read FPid;
    property RPid: Integer read FRPid write FRPid;
    property RStatus: Integer read FRStatus write FRStatus;
  end;
{$ENDIF}

  { ev.c:2077 ANFD - per-fd information }
  TANFd = record
    Head: TEvWatcherList;  { WL head }
    Events: TEvEvents;     { the events being watched (only evRead/evWrite) }
    Reify: Byte;           { ANFD_REIFY / ANFD_IOFDSET flags }
    EMask: Byte;           { ev.c:2082 emask - actual kernel mask (epoll) }
    EGen: Cardinal;        { ev.c:2085 egen - generation counter against epoll bugs }
  end;

  { ev.c:2096 ANPENDING - a pending event record }
  TANPending = record
    W: TEvWatcher;
    Events: TEvEvents;
  end;

  { ev.c:2113 ANHE - heap element with cached "at" (EV_HEAP_CACHE_AT) }
  TANHE = record
    At: TEvTstamp;         { ANHE_at - cached copy of the watcher's at }
    W: TEvWatcherTime;     { ANHE_w }
  end;
  TANHEArray = array of TANHE;

  { OO stand-in for the backend_modify/backend_poll function pointers (ev_vars.h:66) }
  TEvBackend = class
  protected
    FLoop: TEvLoop;
    FMinTime: TEvTstamp;  { ev_vars.h:65 backend_mintime }
  public
    constructor Create(ALoop: TEvLoop);
    function Kind: TEvBackendKind; virtual; abstract;
    procedure Modify(Fd: Integer; OEv, NEv: TEvEvents); virtual; abstract;
    procedure Poll(Timeout: TEvTstamp); virtual; abstract;
    property MinTime: TEvTstamp read FMinTime;
  end;

  { ev.c:2132 struct ev_loop (subset of the ev_vars.h field list, M1+M2) }
  TEvLoop = class
  private
    class var FDefault: TEvLoop;
  private
    FRtNow: TEvTstamp;      { ev_rt_now }
    FNowFloor: TEvTstamp;   { ev_vars.h:42 now_floor }
    FMnNow: TEvTstamp;      { ev_vars.h:43 mn_now }
    FRtMnDiff: TEvTstamp;   { ev_vars.h:44 rtmn_diff }

    FRFeeds: array of TEvWatcher;  { ev_vars.h:47 rfeeds }
    FRFeedCnt: Integer;            { ev_vars.h:49 rfeedcnt }

    FPendings: array[0..NUMPRI - 1] of array of TANPending; { ev_vars.h:51 }
    FPendingCnt: array[0..NUMPRI - 1] of Integer;           { ev_vars.h:53 }
    FPendingPri: Integer;   { ev_vars.h:54 pendingpri }
    FPendingW: TEvPrepare;  { ev_vars.h:55 pending_w (dummy watcher) }

    FIoBlocktime: TEvTstamp;      { ev_vars.h:57 io_blocktime }
    FTimeoutBlocktime: TEvTstamp; { ev_vars.h:58 timeout_blocktime }

    FBackend: TEvBackend;   { ev_vars.h:60 backend (+ modify/poll pointers) }
    FActiveCnt: Integer;    { ev_vars.h:61 activecnt }
    FLoopDone: Integer;     { ev_vars.h:62 loop_done }

    FBackendFd: Integer;    { ev_vars.h:64 backend_fd (epoll fd on Linux) }

    FEvPipe: array[0..1] of Integer; { ev_vars.h:72 evpipe }
    FPipeW: TEvIo;                   { ev_vars.h:73 pipe_w }
    FPipeWriteWanted: Integer;   { ev_vars.h:74 pipe_write_wanted (EV_ATOMIC_T) }
    FPipeWriteSkipped: Integer;  { ev_vars.h:75 pipe_write_skipped (EV_ATOMIC_T) }

{$IFDEF LINUX}
    FCurPid: Integer;       { ev_vars.h:78 curpid (fork check, POSIX only) }
{$ENDIF}
    FPostFork: Byte;        { ev_vars.h:81 postfork }

    FAnFds: array of TANFd;      { ev_vars.h:69 anfds (Length = anfdmax) }

    FFdChanges: array of Integer; { ev_vars.h:168 fdchanges }
    FFdChangeCnt: Integer;        { ev_vars.h:170 fdchangecnt }

    FTimers: TANHEArray;    { ev_vars.h:172 timers }
    FTimerCnt: Integer;     { ev_vars.h:174 timercnt }

    FPeriodics: TANHEArray; { ev_vars.h:177 periodics }
    FPeriodicCnt: Integer;  { ev_vars.h:179 periodiccnt }

    FIdles: array[0..NUMPRI - 1] of array of TEvIdle; { ev_vars.h:183 idles }
    FIdleCnt: array[0..NUMPRI - 1] of Integer;        { ev_vars.h:185 idlecnt }
    FIdleAll: Integer;                                { ev_vars.h:187 idleall }

    FPrepares: array of TEvPrepare; { ev_vars.h:189 prepares }
    FPrepareCnt: Integer;           { ev_vars.h:191 preparecnt }

    FChecks: array of TEvCheck;     { ev_vars.h:193 checks }
    FCheckCnt: Integer;             { ev_vars.h:195 checkcnt }

    FForks: array of TEvFork;       { ev_vars.h:198 forks }
    FForkCnt: Integer;              { ev_vars.h:200 forkcnt }

    FCleanups: array of TEvCleanup; { ev_vars.h:204 cleanups }
    FCleanupCnt: Integer;           { ev_vars.h:206 cleanupcnt }

    FAsyncPending: Integer;         { ev_vars.h:210 async_pending (EV_ATOMIC_T) }
    FAsyncs: array of TEvAsync;     { ev_vars.h:211 asyncs }
    FAsyncCnt: Integer;             { ev_vars.h:213 asynccnt }

    FSigPending: Integer;           { ev_vars.h:223 sig_pending (EV_ATOMIC_T) }

{$IFDEF LINUX}
    FChildEv: TEvSignal;            { ev.c:2973 childev (per default loop) }

    FFsFd: Integer;                 { ev_vars.h:217 fs_fd (inotify fd; -2 = lazy init) }
    FFsW: TEvIo;                    { ev_vars.h:218 fs_w }
    FFs2625: Byte;                  { ev_vars.h:219 fs_2625 (kernel >= 2.6.25?) }
    FFsHash: array[0..EV_INOTIFY_HASHSIZE - 1] of TEvWatcherList; { ev_vars.h:220 fs_hash (ANFS heads) }

    FSigFd: Integer;                { ev_vars.h:225 sigfd (-2 = want signalfd, -1 = off) }
    FSigFdW: TEvIo;                 { ev_vars.h:226 sigfd_w }
    FSigFdSet: array[0..15] of UInt64; { ev_vars.h:227 sigfd_set (sigset_t, 128 bytes) }

    FTimerFd: Integer;              { ev_vars.h:231 timerfd (-2 = want, -1 = off) }
    FTimerFdW: TEvIo;               { ev_vars.h:232 timerfd_w (time-jump detection) }
{$ENDIF}

    FOrigFlags: TEvFlags;   { ev_vars.h:235 origflags }

    FLoopCount: Cardinal;   { ev_vars.h:238 loop_count }
    FLoopDepth: Cardinal;   { ev_vars.h:239 loop_depth }
    FUserData: Pointer;     { ev_vars.h:241 userdata }
    FReleaseCb: TEvLoopCallback; { ev_vars.h:243 release_cb }
    FAcquireCb: TEvLoopCallback; { ev_vars.h:244 acquire_cb }
    FInvokeCb: TEvLoopCallback;  { ev_vars.h:245 invoke_cb (nil = default InvokePending) }

    { --- pending / feed (ev.c:2304-2353) --- }
    procedure FeedEventW(W: TEvWatcher; REvents: TEvEvents); { ev.c:2313 ev_feed_event }
    procedure FeedReverse(W: TEvWatcher);                    { ev.c:2332 feed_reverse }
    procedure FeedReverseDone(REvents: TEvEvents);           { ev.c:2339 feed_reverse_done }
    procedure ClearPendingW(W: TEvWatcher);                  { ev.c:4278 clear_pending }

    { --- fd management (ev.c:2357-2552) --- }
    procedure FdEventNoCheck(Fd: Integer; REvents: TEvEvents); { ev.c:2358 }
    procedure FdEvent(Fd: Integer; REvents: TEvEvents);        { ev.c:2375 }
    procedure FdReify;                                         { ev.c:2393 }
    procedure FdChange(Fd: Integer; Flags: Byte);              { ev.c:2473 }
    procedure FdKill(Fd: Integer);                             { ev.c:2488 }
    procedure FdEbadf;                                         { ev.c:2513 }
    procedure FdEnomem;                                        { ev.c:2526 }
{$IFDEF LINUX}
    procedure FdRearmAll;                                      { ev.c:2541 fd_rearm_all }
{$ENDIF}

    { --- watcher start/stop core (ev.c:4304-4326) --- }
    procedure PriAdjust(W: TEvWatcher);           { ev.c:4305 pri_adjust }
    procedure EvStart(W: TEvWatcher; Active: Integer); { ev.c:4314 ev_start }
    procedure EvStop(W: TEvWatcher);              { ev.c:4322 ev_stop }

    { --- per-type start/stop implementations --- }
    procedure IoStart(W: TEvIo);            { ev.c:4332 }
    procedure IoStop(W: TEvIo);             { ev.c:4362 }
    procedure TimerStart(W: TEvTimer);      { ev.c:4385 }
    procedure TimerStop(W: TEvTimer);       { ev.c:4410 }
    procedure TimerAgain(W: TEvTimer);      { ev.c:4441 }
    procedure PeriodicStart(W: TEvPeriodic);{ ev.c:4476 }
    procedure PeriodicStop(W: TEvPeriodic); { ev.c:4512 }
    procedure IdleStart(W: TEvIdle);
    procedure IdleStop(W: TEvIdle);
    procedure PrepareStart(W: TEvPrepare);
    procedure PrepareStop(W: TEvPrepare);
    procedure CheckStart(W: TEvCheck);
    procedure CheckStop(W: TEvCheck);
    procedure ForkStart(W: TEvFork);        { ev.c:5319 }
    procedure ForkStop(W: TEvFork);         { ev.c:5334 }
    procedure CleanupStart(W: TEvCleanup);  { ev.c:5357 }
    procedure CleanupStop(W: TEvCleanup);   { ev.c:5374 }
    procedure StatStart(W: TEvStat);        { ev.c:5023 }
    procedure StatStop(W: TEvStat);         { ev.c:5054 }
    procedure AsyncStart(W: TEvAsync);      { ev.c:5398 }
    procedure AsyncStop(W: TEvAsync);       { ev.c:5417 }
    procedure AsyncSend(W: TEvAsync);       { ev.c:5438 }
    procedure SignalStart(W: TEvSignal);    { ev.c:4557 }
    procedure SignalStop(W: TEvSignal);     { ev.c:4640 }
{$IFDEF LINUX}
    procedure ChildStart(W: TEvChild);      { ev.c:4681 }
    procedure ChildStop(W: TEvChild);       { ev.c:4698 }
    procedure ChildCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents); { ev.c:3005 childcb }
    procedure ChildReap(Chain, APid, Status: Integer); { ev.c:2981 child_reap }

    { --- inotify fast path for stat watchers (ev.c:4727-4962) --- }
    procedure InfyAdd(W: TEvStat);          { ev.c:4734 infy_add }
    procedure InfyDel(W: TEvStat);          { ev.c:4809 infy_del }
    procedure InfyWd(Slot, Wd: Integer; Ev: PInotifyEvent); { ev.c:4827 infy_wd }
    procedure InfyCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);  { ev.c:4858 infy_cb }
    procedure InfyInit;                     { ev.c:4897 infy_init }
    procedure InfyFork;                     { ev.c:4919 infy_fork }

    procedure SigFdCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents); { ev.c:2947 sigfdcb }
    procedure TimerFdCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents); { ev.c:3034 timerfdcb }
    procedure EvTimerFdInit;                { ev.c:3055 evtimerfd_init }
{$ENDIF}

    { --- signal/async pipe (ev.c:2733-2890) --- }
    procedure EvPipeInit;                   { ev.c:2733 evpipe_init }
    procedure EvPipeWrite(var Flag: Integer); { ev.c:2778 evpipe_write }
    procedure PipeCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents); { ev.c:2828 pipecb }

    { --- time and loop internals (ev.c:3781-4249) --- }
    procedure PeriodicRecalc(W: TEvPeriodic);     { ev.c:3844 periodic_recalc }
    procedure TimersReify;                        { ev.c:3804 }
    procedure PeriodicsReify;                     { ev.c:3869 }
    procedure PeriodicsReschedule;                { ev.c:3913 }
    procedure TimersReschedule(Adjust: TEvTstamp);{ ev.c:3937 }
    procedure TimeUpdate(MaxBlock: TEvTstamp);    { ev.c:3952 }
    procedure IdleReify;                          { ev.c:3781 }
    procedure LoopForkInternal;                   { ev.c loop_fork }

    { threaded-loop hooks (ev.c EV_INVOKE_PENDING / EV_RELEASE_CB / EV_ACQUIRE_CB) }
    procedure DoInvokePending;  { calls FInvokeCb, or InvokePending by default }
    procedure DoRelease;        { called (in the backend) before blocking }
    procedure DoAcquire;        { called (in the backend) after blocking }

    { --- consistency checks (ev.c:3568-3691, EV_VERIFY) --- }
    procedure VerifyWatcher(W: TEvWatcher);                    { ev.c:3571 }
    procedure VerifyHeap(const Heap: TANHEArray; N: Integer);  { ev.c:3581 }
  public
    { ev.c:3253 loop_init / ev.c:3552 ev_loop_new. ABackends requests a
      specific backend (e.g. [evbackendPoll] on Linux); [] = recommended. }
    constructor Create(AFlags: TEvFlags = []; ABackends: TEvBackendKinds = []);
    destructor Destroy; override; { ev.c:3360 ev_loop_destroy (subset) }

    { ev.c:560 ev_default_loop - the default loop; the only one that will
      handle signals and child watchers once those are ported }
    class function Default: TEvLoop;

    function Run(Flags: TEvRunFlags = []): Boolean; { ev.c:4021 ev_run; returns activecnt<>0 }
    procedure BreakLoop(How: TEvBreakHow = evbreakOne); { ev.c:4209 ev_break }

    procedure Ref;    { ev.c:4215 ev_ref }
    procedure Unref;  { ev.c:4221 ev_unref }

    function Now: TEvTstamp;   { ev.c:2208 ev_now }
    procedure NowUpdate;       { ev.c:4227 ev_now_update }
    procedure Suspend;         { ev.c:4233 ev_suspend }
    procedure Resume;          { ev.c:4239 ev_resume }

    { ev.c:613 ev_loop_fork - call after fork() in the child if you want to
      reuse the loop there; the kernel state is recreated lazily on next Run }
    procedure LoopFork;

    procedure InvokePending;   { ev.c:3756 ev_invoke_pending }
    function PendingCount: Cardinal; { ev.c ev_pending_count }

    { ev.c:2384 ev_feed_fd_event - feed an event to all io watchers on this fd,
      as if the backend had reported it }
    procedure FeedFdEvent(Fd: Integer; REvents: TEvEvents);

    { ev.h:1103 ev_set_invoke_pending_cb - override how pending watchers are
      invoked (e.g. hand them to another thread). Unassign to restore default. }
    procedure SetInvokePendingCb(Cb: TEvLoopCallback);
    { ev.h:1113 ev_set_loop_release_cb - Release runs just before the loop
      blocks for events, Acquire just after (e.g. unlock/lock a mutex when the
      loop is shared between threads). }
    procedure SetLoopReleaseCb(Release, Acquire: TEvLoopCallback);

    { ev.c:5485 ev_once - wait for a single event on an fd and/or a timeout
      without registering a watcher; pass Fd=-1 for timeout-only, or a
      negative Timeout for fd-only }
    procedure Once(Fd: Integer; Events: TEvEvents; Timeout: TEvTstamp;
      ACallback: TEvOnceCallback);

    { ev.c:3609 ev_verify - raise EEvError if the loop data is corrupted.
      Compile the unit with EV_VERIFY_2 defined to run this on every loop
      iteration (the EV_VERIFY >= 2 mode of C). }
    procedure Verify;

    { ev.c:2922 ev_feed_signal_event - feed a signal event into this loop }
    procedure FeedSignalEvent(SigNum: Integer);

    { ev.h:666 ev_set_io_collect_interval / ev_set_timeout_collect_interval }
    property IoCollectInterval: TEvTstamp read FIoBlocktime write FIoBlocktime;
    property TimeoutCollectInterval: TEvTstamp read FTimeoutBlocktime write FTimeoutBlocktime;

    property Backend: TEvBackend read FBackend;
    property Iterations: Cardinal read FLoopCount;  { ev.c ev_iteration }
    property Depth: Cardinal read FLoopDepth;       { ev.c ev_depth }
    property UserData: Pointer read FUserData write FUserData;
    function IsDefaultLoop: Boolean; { ev.h:575 ev_is_default_loop }
  end;

{ ev.c:2172 ev_time - real (wall-clock) time, seconds since the Unix epoch }
function EvTime: TEvTstamp;
{ ev.c:2192 get_clock - monotonic clock }
function EvClock: TEvTstamp;
{ ev.c:2215 ev_sleep }
procedure EvSleep(Delay: TEvTstamp);

{ ev.c:535-537 - the backends compiled into this build. This port compiles a
  single backend per platform, so all three sets report the same one value. }
function EvSupportedBackends: TEvBackendKinds;
function EvRecommendedBackends: TEvBackendKinds;
function EvEmbeddableBackends: TEvBackendKinds;  { none in this port }

type
  { ev.h:554 the syserr callback: called on a retryable syscall error (failed
    select/poll/epoll_wait). If you set one it must fix the situation or abort;
    if it returns, the loop retries/continues. }
  TEvSyserrCb = procedure(const Msg: string);

{ ev.c:1994 ev_set_syserr_cb. With no callback set, the default raises EEvError
  (a catchable, Pascal-idiomatic replacement for libev's print+abort). }
procedure EvSetSyserrCb(Cb: TEvSyserrCb);

{ ev.c:2895 ev_feed_signal - safe to call from any context, including
  signal handlers; routes the signal to the loop it is attached to }
procedure EvFeedSignal(SigNum: Integer);

implementation

const
  { ev.c loop constants }
  MIN_TIMEJUMP  = 1.0;     { ev.c: minimum timejump that gets detected }
  MAX_BLOCKTIME = 59.743;  { ev.c: never wait longer than this in one poll }
  { ev.c:584 when a timerfd detects time jumps we can safely sleep much longer }
  MAX_BLOCKTIME2 = 1500001.07;
  EV_TSTAMP_HUGE = 1e300;

  { ev.c MIN_INTERVAL: 1/2**13, good till 4000 (periodic recalc resolution) }
  MIN_INTERVAL = 0.0001220703125;

  { ev.c:4721 stat polling intervals }
  DEF_STAT_INTERVAL = 5.0074891;
  NFS_STAT_INTERVAL = 30.1074891; { for filesystems potentially failing inotify }
  MIN_STAT_INTERVAL = 0.1074891;

  { ev.c:2074 EV_ANFD_REIFY and ev.h:226 EV__IOFDSET - anfd.reify flags }
  ANFD_REIFY   = 1;
  ANFD_IOFDSET = $80;

  { ev.c:2166 internal EVBREAK_* values }
  EVBREAK_CANCEL = 0;
  EVBREAK_ONE    = 1;

  { ev.c:2584 4-heap constants (EV_USE_4HEAP) }
  DHEAP = 4;
  HEAP0 = DHEAP - 1;  { index of the first element in the heap }

  { ev.c:275 EV_NSIG - one past the highest signal number (cross-platform;
    Windows only really uses a handful, but the table is tiny) }
  EV_NSIG = 65;
  SIG_DFL = 0;  { default signal disposition }

{ ABSPRI(w) (ev.c) }
function AbsPri(W: TEvWatcher): Integer; inline;
begin
  Result := W.FPriority - EV_MINPRI;
end;

{ assert(("libev: msg", cond)) equivalent }
procedure EvAssert(Cond: Boolean; const Msg: string);
begin
  if not Cond then
    raise EEvError.Create('libev: ' + Msg);
end;

var
  { ev.c:1992 static void (*syserr_cb)(const char *msg) }
  GSyserrCb: TEvSyserrCb = nil;

{ ev.c:1994 ev_set_syserr_cb }
procedure EvSetSyserrCb(Cb: TEvSyserrCb);
begin
  GSyserrCb := Cb;
end;

{ ev.c:2002 ev_syserr - report a retryable syscall error through the callback,
  or, by default, raise EEvError (libev's default is print + abort) }
procedure EvSysErr(const Msg: string);
begin
  if Assigned(GSyserrCb) then
    GSyserrCb(Msg)
  else
    raise EEvError.Create(Msg);
end;

function EvSupportedBackends: TEvBackendKinds;
begin
{$IFDEF MSWINDOWS}
  Result := [evbackendSelect];
{$ENDIF}
{$IFDEF LINUX}
  Result := [evbackendEpoll, evbackendPoll];
{$ENDIF}
end;

function EvRecommendedBackends: TEvBackendKinds;
begin
{$IFDEF MSWINDOWS}
  Result := [evbackendSelect];
{$ENDIF}
{$IFDEF LINUX}
  Result := [evbackendEpoll];  { epoll is the auto-detected default }
{$ENDIF}
end;

function EvEmbeddableBackends: TEvBackendKinds;
begin
  Result := [];  { no embeddable backend is compiled in this port }
end;

var
  GFenceDummy: Integer = 0;

{ ECB_MEMORY_FENCE equivalent: an interlocked operation acts as a full
  barrier on all supported targets }
procedure EvMemoryFence; inline;
begin
{$IFDEF FPC}
  InterLockedExchange(GFenceDummy, 0);
{$ELSE}
  AtomicExchange(GFenceDummy, 0);
{$ENDIF}
end;

{ atomic store for the EV_ATOMIC_T (sig_atomic_t volatile) fields that are
  touched from other threads or signal handlers }
procedure EvAtomicSet(var Target: Integer; Value: Integer); inline;
begin
{$IFDEF FPC}
  InterLockedExchange(Target, Value);
{$ELSE}
  AtomicExchange(Target, Value);
{$ENDIF}
end;

{ ev.c:2247 array_nextsize - same growth strategy as C }
function ArrayNextSize(Elem, Cur, Cnt: Integer): Integer;
const
  MALLOC_ROUND = 4096; { ev.c:2242 }
var
  NCur: Integer;
begin
  NCur := Cur + 1;
  repeat
    NCur := NCur shl 1;
  until Cnt <= NCur;

  { if size is large, round to MALLOC_ROUND - 4 * longs to accommodate malloc overhead }
  if Elem * NCur > MALLOC_ROUND - SizeOf(Pointer) * 4 then
  begin
    NCur := NCur * Elem;
    NCur := (NCur + Elem + (MALLOC_ROUND - 1) + SizeOf(Pointer) * 4) and not (MALLOC_ROUND - 1);
    NCur := NCur - SizeOf(Pointer) * 4;
    NCur := NCur div Elem;
  end;

  Result := NCur;
end;

{ EV_TS_TO_MSEC (ev.c macro): timestamp to milliseconds, rounded up }
function TsToMsec(T: TEvTstamp): Cardinal; inline;
begin
  Result := Cardinal(Trunc(T * 1e3 + 0.9999));
end;

{ Byte mask (EV_READ|EV_WRITE bits) of an event set; used where C stores the
  event mask in an unsigned char (anfd.emask) }
function EvMaskOf(Ev: TEvEvents): Byte; inline;
begin
  Result := 0;
  if evRead in Ev then Result := Result or $01;
  if evWrite in Ev then Result := Result or $02;
end;

{ ev_floor (ev.c): floor() that is correct for the timestamps we use }
function EvFloor(V: TEvTstamp): TEvTstamp;
begin
  Result := Int(V);
  if (V < 0) and (Result <> V) then
    Result := Result - 1;
end;

{ ev.c:4255 wlist_add }
procedure WListAdd(var Head: TEvWatcherList; Elem: TEvWatcherList);
begin
  Elem.FNext := Head;
  Head := Elem;
end;

{ ev.c:4262 wlist_del }
procedure WListDel(var Head: TEvWatcherList; Elem: TEvWatcherList);
var
  Cur: ^TEvWatcherList;
begin
  Cur := @Head;
  while Cur^ <> nil do
  begin
    if Cur^ = Elem then
    begin
      Cur^ := Elem.FNext;
      Break;
    end;
    Cur := @Cur^.FNext;
  end;
end;

{ ------------------------------------------------------------------ }
{ 4-heap operations (ev.c:2582-2711, EV_USE_4HEAP + EV_HEAP_CACHE_AT) }
{ ------------------------------------------------------------------ }

{ ev.c:2591 downheap - away from the root }
procedure DownHeap(var Heap: TANHEArray; N, K: Integer);
var
  He: TANHE;
  EIdx, Pos, MinPos: Integer;
  MinAt: TEvTstamp;
begin
  He := Heap[K];
  EIdx := N + HEAP0; { one past the end of the heap }

  while True do
  begin
    Pos := DHEAP * (K - HEAP0) + HEAP0 + 1;

    { find the minimum child }
    if Pos + DHEAP - 1 < EIdx then
    begin
      { fast path: all four children exist }
      MinPos := Pos;     MinAt := Heap[MinPos].At;
      if MinAt > Heap[Pos + 1].At then begin MinPos := Pos + 1; MinAt := Heap[MinPos].At; end;
      if MinAt > Heap[Pos + 2].At then begin MinPos := Pos + 2; MinAt := Heap[MinPos].At; end;
      if MinAt > Heap[Pos + 3].At then begin MinPos := Pos + 3; MinAt := Heap[MinPos].At; end;
    end
    else if Pos < EIdx then
    begin
      { slow path: bounds-checked }
      MinPos := Pos;     MinAt := Heap[MinPos].At;
      if (Pos + 1 < EIdx) and (MinAt > Heap[Pos + 1].At) then begin MinPos := Pos + 1; MinAt := Heap[MinPos].At; end;
      if (Pos + 2 < EIdx) and (MinAt > Heap[Pos + 2].At) then begin MinPos := Pos + 2; MinAt := Heap[MinPos].At; end;
      if (Pos + 3 < EIdx) and (MinAt > Heap[Pos + 3].At) then begin MinPos := Pos + 3; MinAt := Heap[MinPos].At; end;
    end
    else
      Break;

    if He.At <= MinAt then
      Break;

    Heap[K] := Heap[MinPos];
    Heap[K].W.FActive := K;

    K := MinPos;
  end;

  Heap[K] := He;
  He.W.FActive := K;
end;

{ ev.c:2671 upheap - towards the root }
procedure UpHeap(var Heap: TANHEArray; K: Integer);
var
  He: TANHE;
  P: Integer;
begin
  He := Heap[K];

  while True do
  begin
    P := ((K - HEAP0 - 1) div DHEAP) + HEAP0; { ev.c:2586 HPARENT }

    if (P = K) or (Heap[P].At <= He.At) then  { ev.c:2587 UPHEAP_DONE }
      Break;

    Heap[K] := Heap[P];
    Heap[K].W.FActive := K;
    K := P;
  end;

  Heap[K] := He;
  He.W.FActive := K;
end;

{ ev.c:2693 adjustheap - move an element to its correct place }
procedure AdjustHeap(var Heap: TANHEArray; N, K: Integer);
begin
  if (K > HEAP0) and (Heap[K].At <= Heap[((K - HEAP0 - 1) div DHEAP) + HEAP0].At) then
    UpHeap(Heap, K)
  else
    DownHeap(Heap, N, K);
end;

{ ev.c:2703 reheap - rebuild the heap, used rarely (after time jumps) }
procedure ReHeap(var Heap: TANHEArray; N: Integer);
var
  I: Integer;
begin
  { we don't use floyds algorithm, upheap is simpler and is more cache-efficient }
  for I := 0 to N - 1 do
    UpHeap(Heap, I + HEAP0);
end;

{ ------------------------------------------------------------------ }
{ Platform layer: clocks, sleep, fd validity and the backends         }
{ ------------------------------------------------------------------ }

{$IFDEF MSWINDOWS}

var
  QpcFrequency: Int64;

{ Precise system clock (Win8+); not always declared in Delphi/FPC headers,
  so we import it ourselves }
procedure GetSystemTimePreciseAsFileTime(var lpSystemTimeAsFileTime: TFileTime); stdcall;
  external 'kernel32.dll' name 'GetSystemTimePreciseAsFileTime';

{ ev.c:2172 ev_time - via FILETIME on Windows (100ns units, epoch 1601) }
function EvTime: TEvTstamp;
const
  FILETIME_TO_UNIX_EPOCH: UInt64 = 116444736000000000; { 1601 -> 1970 offset in 100ns }
var
  Ft: TFileTime;
  U: UInt64;
begin
  GetSystemTimePreciseAsFileTime(Ft);
  U := (UInt64(Ft.dwHighDateTime) shl 32) or Ft.dwLowDateTime;
  Result := (U - FILETIME_TO_UNIX_EPOCH) * 1e-7;
end;

{ ev.c:2192 get_clock - QueryPerformanceCounter on Windows (monotonic) }
function EvClock: TEvTstamp;
var
  C: Int64;
begin
  QueryPerformanceCounter(C);
  Result := C / QpcFrequency;
end;

{ ev.c:2215 ev_sleep - Windows branch: Sleep(ms) }
procedure EvSleep(Delay: TEvTstamp);
begin
  if Delay > 0 then
    Sleep(TsToMsec(Delay));
end;

const
  { Our own fd_set capacity; winsock select() accepts any size }
  EV_FD_SETSIZE = 1024;

  { errno equivalents used by the ev_select.c error mapping }
  ERRNO_EINTR  = 4;
  ERRNO_EBADF  = 9;
  ERRNO_ENOMEM = 12;
  ERRNO_EINVAL = 22;

type
  { winsock fd_set layout: u_int count + array of SOCKETs }
  TEvFdSet = record
    Count: Cardinal;
    Sockets: array[0..EV_FD_SETSIZE - 1] of TSocket;
  end;

  TEvTimeVal = record
    tv_sec: Longint;
    tv_usec: Longint;
  end;

{ we call ws2_32 select() with our own larger fd_set record }
function ws_select(nfds: Integer; readfds, writefds, exceptfds: Pointer;
  timeout: Pointer): Integer; stdcall; external 'ws2_32.dll' name 'select';

procedure EvFdSetAdd(var Fs: TEvFdSet; S: TSocket);
begin
  { no duplicates can occur because select_modify is only called on changes
    (ev_select.c:87) }
  EvAssert(Fs.Count < EV_FD_SETSIZE, 'fd >= FD_SETSIZE passed to fd_set-based select backend');
  Fs.Sockets[Fs.Count] := S;
  Inc(Fs.Count);
end;

procedure EvFdSetClr(var Fs: TEvFdSet; S: TSocket);
var
  I: Cardinal;
begin
  I := 0;
  while I < Fs.Count do
  begin
    if Fs.Sockets[I] = S then
    begin
      Dec(Fs.Count);
      Fs.Sockets[I] := Fs.Sockets[Fs.Count];
      Exit;
    end;
    Inc(I);
  end;
end;

function EvFdIsSet(const Fs: TEvFdSet; S: TSocket): Boolean;
var
  I: Cardinal;
begin
  I := 0;
  while I < Fs.Count do
  begin
    if Fs.Sockets[I] = S then
      Exit(True);
    Inc(I);
  end;
  Result := False;
end;

type
  { the EV_SELECT_USE_FD_SET + EV_SELECT_IS_WINSOCKET path of ev_select.c }
  TEvSelectBackend = class(TEvBackend)
  private
    FVecRi, FVecRo: TEvFdSet;  { ev_vars.h:84-85 vec_ri/vec_ro }
    FVecWi, FVecWo: TEvFdSet;  { ev_vars.h:86-87 vec_wi/vec_wo }
    FVecEo: TEvFdSet;          { ev_vars.h:89 vec_eo (Windows only) }
  public
    constructor Create(ALoop: TEvLoop); { ev_select.c:276 select_init }
    function Kind: TEvBackendKind; override;
    procedure Modify(Fd: Integer; OEv, NEv: TEvEvents); override; { ev_select.c:71 }
    procedure Poll(Timeout: TEvTstamp); override;                 { ev_select.c:140 }
  end;

constructor TEvSelectBackend.Create(ALoop: TEvLoop);
begin
  inherited Create(ALoop);
  FMinTime := 1e-6;  { ev_select.c:278 backend_mintime }
  FVecRi.Count := 0; { FD_ZERO }
  FVecWi.Count := 0;
end;

function TEvSelectBackend.Kind: TEvBackendKind;
begin
  Result := evbackendSelect;
end;

{ ev_select.c:71 select_modify }
procedure TEvSelectBackend.Modify(Fd: Integer; OEv, NEv: TEvEvents);
var
  Handle: TSocket;
begin
  if OEv = NEv then
    Exit;

  { on Windows an fd is the SOCKET itself (see the deviation note on top) }
  Handle := TSocket(Fd);

  { FD_SET is broken on windows (it adds the fd to a set twice or more,
    which eventually leads to overflows). Need to call it only on changes.
    (ev_select.c:87) }
  if (OEv * [evRead]) <> (NEv * [evRead]) then
  begin
    if evRead in NEv then
      EvFdSetAdd(FVecRi, Handle)
    else
      EvFdSetClr(FVecRi, Handle);
  end;

  if (OEv * [evWrite]) <> (NEv * [evWrite]) then
  begin
    if evWrite in NEv then
      EvFdSetAdd(FVecWi, Handle)
    else
      EvFdSetClr(FVecWi, Handle);
  end;
end;

{ ev_select.c:140 select_poll }
procedure TEvSelectBackend.Poll(Timeout: TEvTstamp);
var
  Tv: TEvTimeVal;
  Res, Err, Fd: Integer;
  Ms: Cardinal;
  Events: TEvEvents;
  Handle: TSocket;
begin
  { EV_TV_SET (ev.c macro) }
  Tv.tv_sec := Trunc(Timeout);
  Tv.tv_usec := Trunc((Timeout - Tv.tv_sec) * 1e6);

  FVecRo := FVecRi; { memcpy (vec_ro, vec_ri, fd_setsize) }
  FVecWo := FVecWi;
  { pass in the write set as except set: the idea behind this is to work
    around a windows bug that causes errors to be reported as an exception
    and not by setting the writable bit (ev_select.c:159) }
  FVecEo := FVecWi;

  FLoop.DoRelease;  { EV_RELEASE_CB - release the loop before blocking }
  Res := ws_select(0, @FVecRo, @FVecWo, @FVecEo, @Tv);
  FLoop.DoAcquire;  { EV_ACQUIRE_CB - reacquire after the blocking call }

  if Res < 0 then
  begin
    Err := WSAGetLastError; { ev_select.c:177 }

    { on windows, select returns incompatible error codes, fix this
      (ev_select.c:180) }
    if Err = WSAENOTSOCK then
      Err := ERRNO_EBADF
    else if (Err >= WSABASEERR) and (Err < WSABASEERR + 1000) then
      Err := Err - WSABASEERR;

    { select on windows erroneously returns EINVAL when no fd sets have
      been provided; emulate the wait by sleeping manually (ev_select.c:188) }
    if Err = ERRNO_EINVAL then
    begin
      if Timeout > 0 then
      begin
        Ms := TsToMsec(Timeout);
        if Ms = 0 then
          Ms := 1;
        Sleep(Ms);
      end;
      Exit;
    end;

    if Err = ERRNO_EBADF then
      FLoop.FdEbadf
    else if Err = ERRNO_ENOMEM then
      FLoop.FdEnomem
    else if Err <> ERRNO_EINTR then
      EvSysErr(Format('(libev) select error: %d', [Err]));

    Exit;
  end;

  { ev_select.c:218 EV_SELECT_USE_FD_SET result scan }
  for Fd := 0 to Length(FLoop.FAnFds) - 1 do
    if FLoop.FAnFds[Fd].Events <> [] then
    begin
      Events := [];
      Handle := TSocket(Fd);

      if EvFdIsSet(FVecRo, Handle) then Include(Events, evRead);
      if EvFdIsSet(FVecWo, Handle) then Include(Events, evWrite);
      if EvFdIsSet(FVecEo, Handle) then Include(Events, evWrite); { ev_select.c:236 }

      if Events <> [] then
        FLoop.FdEvent(Fd, Events);
    end;
end;

{ ev.c:2501 fd_valid - Windows branch: is this a valid socket? }
function FdValid(Fd: Integer): Boolean;
var
  OptVal: Integer;
  OptLen: Integer;
begin
  OptLen := SizeOf(OptVal);
  Result := getsockopt(TSocket(Fd), SOL_SOCKET, SO_TYPE, PAnsiChar(@OptVal), OptLen) = 0;
end;

const
  { FIONBIO; declared locally because the winsock header constant triggers
    a subrange warning when passed to ioctlsocket }
  EV_FIONBIO = Integer($8004667E);

{ ev.c:2556 fd_intern - Windows branch: make the socket non-blocking }
procedure FdIntern(Fd: Integer);
var
  Arg: u_long;
begin
  Arg := 1;
  ioctlsocket(TSocket(Fd), EV_FIONBIO, Arg);
end;

{ ev_win32.c:48 ev_tcp_socket }
function EvTcpSocket: TSocket;
begin
  Result := socket(AF_INET, SOCK_STREAM, 0);
end;

{ ev_win32.c:59 ev_pipe - "oh, the humanity!": emulate a pipe with a pair
  of interconnected loopback TCP sockets }
function EvPipe(out Fd0, Fd1: Integer): Integer;
var
  Addr, Adr2: TSockAddrIn;
  AddrSize, Adr2Size: Integer;
  Listener: TSocket;
  Sock0, Sock1: TSocket;
label
  Fail;
begin
  Sock0 := INVALID_SOCKET;
  Sock1 := INVALID_SOCKET;
  AddrSize := SizeOf(Addr);
  Adr2Size := SizeOf(Adr2);

  Listener := EvTcpSocket;
  if Listener = INVALID_SOCKET then
    Exit(-1);

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_addr.S_addr := htonl(INADDR_LOOPBACK);
  Addr.sin_port := 0;

  if bind(Listener, PSockAddr(@Addr)^, AddrSize) <> 0 then goto Fail;
  if getsockname(Listener, PSockAddr(@Addr)^, AddrSize) <> 0 then goto Fail;
  if listen(Listener, 1) <> 0 then goto Fail;

  Sock0 := EvTcpSocket;
  if Sock0 = INVALID_SOCKET then goto Fail;
  if connect(Sock0, PSockAddr(@Addr)^, AddrSize) <> 0 then goto Fail;

  Sock1 := accept(Listener, nil, nil);
  if Sock1 = INVALID_SOCKET then goto Fail;

  { windows vista returns fantasy port numbers for sockets; checking the
    ports this way seems to work (ev_win32.c:96) }
  if getpeername(Sock0, PSockAddr(@Addr)^, AddrSize) <> 0 then goto Fail;
  if getsockname(Sock1, PSockAddr(@Adr2)^, Adr2Size) <> 0 then goto Fail;

  if (AddrSize <> Adr2Size)
    or (Addr.sin_addr.S_addr <> Adr2.sin_addr.S_addr) { just to be sure, I mean, it's windows }
    or (Addr.sin_port <> Adr2.sin_port) then
    goto Fail;

  closesocket(Listener);

  { when select is winsocket-based we also expect socket etc. to work on fds }
  Fd0 := Integer(Sock0);
  Fd1 := Integer(Sock1);

  Exit(0);

Fail:
  closesocket(Listener);
  if Sock0 <> INVALID_SOCKET then closesocket(Sock0);
  if Sock1 <> INVALID_SOCKET then closesocket(Sock1);
  Result := -1;
end;

{ EV_WIN32_CLOSE_FD }
procedure EvCloseFd(Fd: Integer);
begin
  closesocket(TSocket(Fd));
end;

const
  { <sys/stat.h> mode bits used for the Windows mapping }
  S_IFDIR = $4000;
  S_IFREG = $8000;

{ EV_LSTAT (ev.c:4967): on Windows libev uses _stati64; we fill the same
  information from GetFileAttributesEx instead of pulling in the CRT }
function DoLStat(const Path: string; out Data: TEvStatData): Boolean;
const
  FILETIME_TO_UNIX_EPOCH: UInt64 = 116444736000000000;
  function FtToUnix(const Ft: TFileTime): Int64;
  var
    U: UInt64;
  begin
    U := (UInt64(Ft.dwHighDateTime) shl 32) or Ft.dwLowDateTime;
    if U < FILETIME_TO_UNIX_EPOCH then
      Result := 0
    else
      Result := Int64((U - FILETIME_TO_UNIX_EPOCH) div 10000000);
  end;
var
  Fa: TWin32FileAttributeData;
begin
  FillChar(Data, SizeOf(Data), 0);

  if not GetFileAttributesEx(PChar(Path), GetFileExInfoStandard, @Fa) then
    Exit(False);

  if (Fa.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
    Data.st_mode := S_IFDIR
  else
    Data.st_mode := S_IFREG;
  if (Fa.dwFileAttributes and FILE_ATTRIBUTE_READONLY) <> 0 then
    Data.st_mode := Data.st_mode or $124  { r--r--r-- }
  else
    Data.st_mode := Data.st_mode or $1B6; { rw-rw-rw- }

  Data.st_nlink := 1;
  Data.st_size := (Int64(Fa.nFileSizeHigh) shl 32) or Fa.nFileSizeLow;
  Data.st_atime := FtToUnix(Fa.ftLastAccessTime);
  Data.st_mtime := FtToUnix(Fa.ftLastWriteTime);
  Data.st_ctime := FtToUnix(Fa.ftCreationTime);

  Result := True;
end;

{$ENDIF MSWINDOWS}

{$IFDEF EV_POSIX}

const
  CLibName = {$IFDEF FPC}'c'{$ELSE}'libc.so'{$ENDIF};

{$IFDEF FPC}
  { errno taken from the RTL, so it is correct per OS and architecture
    (e.g. EAGAIN is 11 on Linux but 35 on macOS) }
  ERRNO_EPERM  = ESysEPERM;
  ERRNO_ENOENT = ESysENOENT;
  ERRNO_EINTR  = ESysEINTR;
  ERRNO_EBADF  = ESysEBADF;
  ERRNO_ENOMEM = ESysENOMEM;
  ERRNO_EACCES = ESysEACCES;
  ERRNO_EEXIST = ESysEEXIST;
  ERRNO_EINVAL = ESysEINVAL;
  ERRNO_ENOSYS = ESysENOSYS;
  ERRNO_ELOOP  = ESysELOOP;
{$ELSE}
  { Delphi/Linux is x86-64 (asm-generic errno) }
  ERRNO_EPERM  = 1;
  ERRNO_ENOENT = 2;
  ERRNO_EINTR  = 4;
  ERRNO_EBADF  = 9;
  ERRNO_ENOMEM = 12;
  ERRNO_EACCES = 13;
  ERRNO_EEXIST = 17;
  ERRNO_EINVAL = 22;
  ERRNO_ENOSYS = 38;
  ERRNO_ELOOP  = 40;
{$ENDIF}

  { shared POSIX constants whose value differs on macOS }
{$IFDEF DARWIN}
  CLOCK_REALTIME  = 0;
  CLOCK_MONOTONIC = 6;
  O_NONBLOCK      = 4;
  SIGCHLD         = 20;
  SA_RESTART      = $002;
  WCONTINUED      = $10;
{$ELSE}
  CLOCK_REALTIME  = 0;
  CLOCK_MONOTONIC = 1;
  O_NONBLOCK      = $800;
  SIGCHLD         = 17;
  SA_RESTART      = $10000000;
  WCONTINUED      = 8;
{$ENDIF}

  { shared POSIX constants with the same value everywhere }
  F_GETFD    = 1;
  F_SETFD    = 2;
  F_SETFL    = 4;
  FD_CLOEXEC = 1;
  POLLIN   = $001;
  POLLOUT  = $004;
  POLLERR  = $008;
  POLLHUP  = $010;
  POLLNVAL = $020;
  WNOHANG    = 1;
  WUNTRACED  = 2;
  EV_PID_HASHSIZE = 16;  { ev.c:372 EV_PID_HASHSIZE (EV_FEATURE_DATA) }

{$IFDEF LINUX}
  { --- Linux-only kernel interfaces --- }

  { sys/epoll.h }
  EPOLLIN  = $001;
  EPOLLOUT = $004;
  EPOLLERR = $008;
  EPOLLHUP = $010;
  EPOLL_CTL_ADD = 1;
  EPOLL_CTL_DEL = 2;
  EPOLL_CTL_MOD = 3;
  EPOLL_CLOEXEC = $80000; { O_CLOEXEC }

  { sys/eventfd.h }
  EFD_NONBLOCK = O_NONBLOCK;
  EFD_CLOEXEC  = $80000;

  { sys/signalfd.h and sigprocmask }
  SFD_NONBLOCK = O_NONBLOCK;
  SFD_CLOEXEC  = $80000;
  SIG_BLOCK    = 0;
  SIG_UNBLOCK  = 1;

  { sys/timerfd.h }
  TFD_NONBLOCK = O_NONBLOCK;
  TFD_CLOEXEC  = $80000;
  TFD_TIMER_ABSTIME      = 1;
  TFD_TIMER_CANCEL_ON_SET = 2;

  { sys/inotify.h }
  IN_MODIFY      = $00000002;
  IN_ATTRIB      = $00000004;
  IN_MOVED_FROM  = $00000040;
  IN_MOVED_TO    = $00000080;
  IN_CREATE      = $00000100;
  IN_DELETE      = $00000200;
  IN_DELETE_SELF = $00000400;
  IN_MOVE_SELF   = $00000800;
  IN_UNMOUNT     = $00002000;
  IN_IGNORED     = $00008000;
  IN_DONT_FOLLOW = $02000000;
  IN_MASK_ADD    = $20000000;
  IN_CLOEXEC     = $80000;
  IN_NONBLOCK    = O_NONBLOCK;

  { ev.c:4730 EV_INOTIFY_BUFSIZE: sizeof (struct inotify_event) * 2 + NAME_MAX }
  EV_INOTIFY_BUFSIZE = 16 * 2 + 255;
{$ENDIF}

type
{$IFDEF FPC}
  { the RTL's per-architecture struct timespec (tv_sec, tv_nsec) }
  TEvTimeSpec = UnixType.timespec;
{$ELSE}
  { struct timespec on 64-bit Linux (Delphi/Linux is x86-64 only) }
  TEvTimeSpec = record
    tv_sec: Int64;
    tv_nsec: Int64;
  end;
{$ENDIF}

{$IFDEF LINUX}
  {$IFDEF FPC}
  { the RTL's struct epoll_event; it packs the record only on x86-64, which is
    exactly what makes the FPC build correct on arm/aarch64 as well. Its Data
    field is a union - we use its u64 member. }
  TEpollEvent = Linux.TEPoll_Event;
  PEpollEvent = Linux.PEpoll_Event;
  {$ELSE}
  { struct epoll_event; packed on x86-64 (12 bytes) - Delphi/Linux is x86-64 }
  TEpollEvent = packed record
    Events: Cardinal;
    Data: UInt64; { we store fd in the low 32 bits, egen in the high 32 bits }
  end;
  PEpollEvent = ^TEpollEvent;
  {$ENDIF}
{$ENDIF}

  { struct pollfd: int fd; short events; short revents (8 bytes) }
  TPollFd = record
    Fd: Integer;
    Events: SmallInt;
    Revents: SmallInt;
  end;
  TPollFdArray = array of TPollFd;

  { sigset_t: 1024 bits on Linux }
  TEvSigSet = array[0..15] of UInt64;

{$IFDEF LINUX}
  { struct statfs - only f_type is read (ev.c style, for the inotify fs check).
    f_type is __fsword_t, i.e. a C long, so it is pointer-sized: 8 bytes on
    x86-64/aarch64, 4 on arm32. The trailing bytes are just a landing area
    large enough for the kernel to write the whole struct on any architecture. }
  TLinuxStatFs = record
    f_type: NativeInt;
    __rest: array[0..119] of Byte;
  end;

  { struct signalfd_siginfo (128 bytes); we only read ssi_signo at offset 0 }
  TSignalFdSiginfo = record
    ssi_signo: Cardinal;
    _pad: array[0..123] of Byte;
  end;

  { struct itimerspec: timespec it_interval; timespec it_value (32 bytes) }
  TItimerSpec = record
    it_interval: TEvTimeSpec;
    it_value: TEvTimeSpec;
  end;
{$ENDIF}

{$IFDEF FPC}
  { the RTL's per-architecture struct sigaction; its field order is the kernel
    one and is matched by Fpsigaction (the rt_sigaction syscall). Using the two
    together is what keeps signals correct on arm/aarch64. }
  TEvSigAction = BaseUnix.SigActionRec;
{$ELSE}
  { struct sigaction (glibc layout on x86-64): handler, mask, flags, restorer }
  TEvSigAction = record
    sa_handler: Pointer;
    sa_mask: TEvSigSet;
    sa_flags: Integer;
    sa_restorer: Pointer; { natural alignment inserts the 4-byte pad before this }
  end;
{$ENDIF}

{ note: on the Delphi/Linux (x86-64) path, struct arguments are declared as
  raw pointers on purpose - a "const Rec: TRecord" parameter does not reliably
  map to C's "const struct *" under the SysV x86-64 ABI (large records may be
  passed by value), which crashes inside libc. On FPC these bindings come from
  the RTL instead (arch-correct). }
{$IFDEF FPC}
  {$IFDEF LINUX}
function c_clock_gettime(ClockId: Integer; Tp: Pointer): Integer; inline;
begin
  Result := Linux.clock_gettime(clockid_t(ClockId), ptimespec(Tp));
end;
  {$ELSE}
  { macOS has clock_gettime in libc (10.12+); the RTL Linux unit is absent }
function c_clock_gettime(ClockId: Integer; Tp: Pointer): Integer; cdecl;
  external CLibName name 'clock_gettime';
  {$ENDIF}
function c_nanosleep(Req, Rem: Pointer): Integer; inline;
begin
  Result := BaseUnix.FpNanoSleep(ptimespec(Req), ptimespec(Rem));
end;
{$ELSE}
function c_clock_gettime(ClockId: Integer; Tp: Pointer): Integer; cdecl;
  external CLibName name 'clock_gettime';
function c_nanosleep(Req, Rem: Pointer): Integer; cdecl;
  external CLibName name 'nanosleep';
{$ENDIF}
{$IFDEF FPC}
function c_getpid: Integer; inline;
begin
  Result := fpGetPID;
end;
function c_close(Fd: Integer): Integer; inline;
begin
  Result := fpClose(Fd);
end;
function c_fcntl_get(Fd, Cmd: Integer): Integer; inline;
begin
  Result := fpFcntl(Fd, Cmd);
end;
function c_fcntl_set(Fd, Cmd, Arg: Integer): Integer; inline;
begin
  Result := fpFcntl(Fd, Cmd, Arg);
end;
{$ELSE}
function c_getpid: Integer; cdecl; external CLibName name 'getpid';
function c_close(Fd: Integer): Integer; cdecl; external CLibName name 'close';
function c_fcntl_get(Fd, Cmd: Integer): Integer; cdecl; external CLibName name 'fcntl';
function c_fcntl_set(Fd, Cmd, Arg: Integer): Integer; cdecl; external CLibName name 'fcntl';
{$ENDIF}
{$IFDEF LINUX}
  {$IFDEF FPC}
function c_epoll_create(Size: Integer): Integer; inline;
begin
  Result := Linux.epoll_create(Size);
end;
function c_epoll_ctl(EpFd, Op, Fd: Integer; Event: PEpollEvent): Integer; inline;
begin
  Result := Linux.epoll_ctl(EpFd, Op, Fd, Event);
end;
function c_epoll_wait(EpFd: Integer; Events: PEpollEvent; MaxEvents, TimeoutMs: Integer): Integer; inline;
begin
  Result := Linux.epoll_wait(EpFd, Events, MaxEvents, TimeoutMs);
end;
  {$ELSE}
function c_epoll_create(Size: Integer): Integer; cdecl; external CLibName name 'epoll_create';
function c_epoll_ctl(EpFd, Op, Fd: Integer; Event: PEpollEvent): Integer; cdecl;
  external CLibName name 'epoll_ctl';
function c_epoll_wait(EpFd: Integer; Events: PEpollEvent; MaxEvents, TimeoutMs: Integer): Integer; cdecl;
  external CLibName name 'epoll_wait';
  {$ENDIF}
{ epoll_create1 is not exposed by the FPC RTL, so it stays a libc binding on
  both compilers (its errno is read with GetErrno, i.e. the libc domain) }
function c_epoll_create1(Flags: Integer): Integer; cdecl; external CLibName name 'epoll_create1';
function c_errno_location: PInteger; cdecl; external CLibName name '__errno_location';
function c_eventfd(InitVal: Cardinal; Flags: Integer): Integer; cdecl;
  external CLibName name 'eventfd';
{$ENDIF}
{$IFDEF FPC}
function c_pipe(Fds: PInteger): Integer; inline;
begin
  Result := fpPipe(pFilDes(Fds)^);
end;
function c_write(Fd: Integer; Buf: Pointer; Count: NativeUInt): NativeInt; inline;
begin
  Result := fpWrite(Fd, PChar(Buf), Count);
end;
function c_dup2(OldFd, NewFd: Integer): Integer; inline;
begin
  Result := fpDup2(OldFd, NewFd);
end;
function c_read(Fd: Integer; Buf: Pointer; Count: NativeUInt): NativeInt; inline;
begin
  Result := fpRead(Fd, PChar(Buf), Count);
end;
{$ELSE}
function c_pipe(Fds: PInteger): Integer; cdecl; external CLibName name 'pipe';
function c_read(Fd: Integer; Buf: Pointer; Count: NativeUInt): NativeInt; cdecl;
  external CLibName name 'read';
function c_write(Fd: Integer; Buf: Pointer; Count: NativeUInt): NativeInt; cdecl;
  external CLibName name 'write';
function c_dup2(OldFd, NewFd: Integer): Integer; cdecl; external CLibName name 'dup2';
{$ENDIF}
{$IFDEF FPC}
function c_sigaction(SigNum: Integer; Act, OldAct: Pointer): Integer; inline;
begin
  Result := Fpsigaction(SigNum, psigactionrec(Act), psigactionrec(OldAct));
end;
{$ELSE}
function c_sigaction(SigNum: Integer; Act, OldAct: Pointer): Integer; cdecl;
  external CLibName name 'sigaction';
{$ENDIF}
{$IFDEF LINUX}
{ the signalfd/timerfd paths stay glibc bindings (the RTL has no signalfd or
  timerfd, and glibc's 128-byte userspace sigset_t is what these expect) }
function c_signalfd(Fd: Integer; Mask: Pointer; Flags: Integer): Integer; cdecl;
  external CLibName name 'signalfd';
function c_sigemptyset(Mask: Pointer): Integer; cdecl; external CLibName name 'sigemptyset';
function c_sigaddset(Mask: Pointer; Sig: Integer): Integer; cdecl; external CLibName name 'sigaddset';
function c_sigdelset(Mask: Pointer; Sig: Integer): Integer; cdecl; external CLibName name 'sigdelset';
function c_sigprocmask(How: Integer; Mask, OldMask: Pointer): Integer; cdecl;
  external CLibName name 'sigprocmask';
function c_timerfd_create(ClockId, Flags: Integer): Integer; cdecl;
  external CLibName name 'timerfd_create';
function c_timerfd_settime(Fd, Flags: Integer; NewValue, OldValue: Pointer): Integer; cdecl;
  external CLibName name 'timerfd_settime';
{$ENDIF}
{ signal() exists on every POSIX target }
function c_signal(SigNum: Integer; Handler: Pointer): Pointer; cdecl;
  external CLibName name 'signal';
{$IFDEF FPC}
function c_waitpid(Pid: Integer; Status: PInteger; Options: Integer): Integer; inline;
begin
  Result := fpWaitPid(Pid, pcint(Status), Options);
end;
{$ELSE}
function c_waitpid(Pid: Integer; Status: PInteger; Options: Integer): Integer; cdecl;
  external CLibName name 'waitpid';
{$ENDIF}
{$IFDEF LINUX}
  {$IFDEF FPC}
function c_inotify_init: Integer; inline;
begin
  Result := Linux.inotify_init;
end;
function c_inotify_init1(Flags: Integer): Integer; inline;
begin
  Result := Linux.inotify_init1(Flags);
end;
function c_inotify_add_watch(Fd: Integer; Path: PAnsiChar; Mask: Cardinal): Integer; inline;
begin
  Result := Linux.inotify_add_watch(Fd, PChar(Path), Mask);
end;
function c_inotify_rm_watch(Fd, Wd: Integer): Integer; inline;
begin
  Result := Linux.inotify_rm_watch(Fd, Wd);
end;
  {$ELSE}
function c_inotify_init: Integer; cdecl; external CLibName name 'inotify_init';
function c_inotify_init1(Flags: Integer): Integer; cdecl;
  external CLibName name 'inotify_init1';
function c_inotify_add_watch(Fd: Integer; Path: PAnsiChar; Mask: Cardinal): Integer; cdecl;
  external CLibName name 'inotify_add_watch';
function c_inotify_rm_watch(Fd, Wd: Integer): Integer; cdecl;
  external CLibName name 'inotify_rm_watch';
  {$ENDIF}
{ statfs (inotify fs check) and uname (kernel version for inotify) are only
  used by the Linux inotify path }
function c_statfs(Path: PAnsiChar; Buf: Pointer): Integer; cdecl;
  external CLibName name 'statfs';
function c_uname(Buf: Pointer): Integer; cdecl; external CLibName name 'uname';
{$ENDIF}
{$IFDEF FPC}
function c_poll(Fds: Pointer; NFds: NativeUInt; TimeoutMs: Integer): Integer; inline;
begin
  Result := fpPoll(ppollfd(Fds), cuint(NFds), clong(TimeoutMs));
end;
{$ELSE}
function c_poll(Fds: Pointer; NFds: NativeUInt; TimeoutMs: Integer): Integer; cdecl;
  external CLibName name 'poll';
{$ENDIF}

{$IFDEF LINUX}
{ errno from a direct libc binding - used only for the Linux libc calls
  (eventfd/signalfd/epoll_create1), which are the ones that do not go through
  the RTL. GetRtlErrno (below) is used everywhere else. }
function GetErrno: Integer; inline;
begin
  Result := c_errno_location^;
end;
{$ENDIF}

function GetRtlErrno: Integer; inline;
begin
{$IFDEF FPC}
  Result := fpGetErrno;
{$ELSE}
  Result := c_errno_location^;
{$ENDIF}
end;

{ ev.c:2172 ev_time - clock_gettime (CLOCK_REALTIME); the have_realtime
  probing of C is unnecessary on our minimum supported kernels }
function EvTime: TEvTstamp;
var
  Ts: TEvTimeSpec;
begin
  c_clock_gettime(CLOCK_REALTIME, @Ts);
  Result := Ts.tv_sec + Ts.tv_nsec * 1e-9; { EV_TS_GET }
end;

{ ev.c:2192 get_clock - clock_gettime (CLOCK_MONOTONIC) }
function EvClock: TEvTstamp;
var
  Ts: TEvTimeSpec;
begin
  c_clock_gettime(CLOCK_MONOTONIC, @Ts);
  Result := Ts.tv_sec + Ts.tv_nsec * 1e-9;
end;

{ ev.c:2215 ev_sleep - EV_USE_NANOSLEEP branch }
procedure EvSleep(Delay: TEvTstamp);
var
  Ts: TEvTimeSpec;
begin
  if Delay > 0 then
  begin
    { EV_TS_SET }
    Ts.tv_sec := Trunc(Delay);
    Ts.tv_nsec := Trunc((Delay - Ts.tv_sec) * 1e9);
    c_nanosleep(@Ts, nil);
  end;
end;

{ ev.c:2501 fd_valid - POSIX branch }
function FdValid(Fd: Integer): Boolean;
begin
  Result := c_fcntl_get(Fd, F_GETFD) <> -1;
end;

{ ev.c:2556 fd_intern - POSIX branch: close-on-exec + non-blocking }
procedure FdIntern(Fd: Integer);
begin
  c_fcntl_set(Fd, F_SETFD, FD_CLOEXEC);
  c_fcntl_set(Fd, F_SETFL, O_NONBLOCK);
end;

procedure EvCloseFd(Fd: Integer);
begin
  c_close(Fd);
end;

type
  { struct stat on x86-64 Linux (144 bytes) }
{$IFDEF FPC}
  { the RTL's per-architecture struct stat (kernel layout; timestamps are the
    scalar st_atime/st_mtime/st_ctime seconds fields, not timespec members) }
  TLinuxStat = BaseUnix.Stat;
{$ELSE}
  { struct stat, x86-64 layout (Delphi/Linux is x86-64 only) }
  TLinuxStat = record
    st_dev: UInt64;
    st_ino: UInt64;
    st_nlink: UInt64;
    st_mode: Cardinal;
    st_uid: Cardinal;
    st_gid: Cardinal;
    __pad0: Cardinal;
    st_rdev: UInt64;
    st_size: Int64;
    st_blksize: Int64;
    st_blocks: Int64;
    st_atim: TEvTimeSpec;
    st_mtim: TEvTimeSpec;
    st_ctim: TEvTimeSpec;
    __unused: array[0..2] of Int64;
  end;
{$ENDIF}

{$IFDEF FPC}
function c_lstat(Path: PAnsiChar; Buf: Pointer): Integer; inline;
begin
  Result := fpLstat(PChar(Path), pStat(Buf));
end;
{$ELSE}
{ direct lstat symbol; exported by glibc 2.33+, which covers our supported
  distributions (older glibc only had __lxstat) }
function c_lstat(Path: PAnsiChar; Buf: Pointer): Integer; cdecl;
  external CLibName name 'lstat';
{$ENDIF}

{ EV_LSTAT (ev.c:4969): lstat on POSIX }
function DoLStat(const Path: string; out Data: TEvStatData): Boolean;
var
  U8: UTF8String;
  St: TLinuxStat;
begin
  U8 := UTF8String(Path);
  if c_lstat(PAnsiChar(U8), @St) < 0 then
  begin
    FillChar(Data, SizeOf(Data), 0);
    Exit(False);
  end;

  Data.st_dev := St.st_dev;
  Data.st_ino := St.st_ino;
  Data.st_mode := St.st_mode;
  Data.st_nlink := St.st_nlink;
  Data.st_uid := St.st_uid;
  Data.st_gid := St.st_gid;
  Data.st_rdev := St.st_rdev;
  Data.st_size := St.st_size;
{$IFDEF FPC}
  { the RTL's stat exposes the seconds as scalar fields }
  Data.st_atime := St.st_atime;
  Data.st_mtime := St.st_mtime;
  Data.st_ctime := St.st_ctime;
{$ELSE}
  Data.st_atime := St.st_atim.tv_sec;
  Data.st_mtime := St.st_mtim.tv_sec;
  Data.st_ctime := St.st_ctim.tv_sec;
{$ENDIF}

  Result := True;
end;

{$IFDEF LINUX}
var
  { ev.c:2971 static WL childs [EV_PID_HASHSIZE] (Linux child watchers) }
  GChilds: array[0..EV_PID_HASHSIZE - 1] of TEvWatcherList;

{ ev.c:4885 infy_newfd }
function InfyNewFd: Integer;
begin
  Result := c_inotify_init1(IN_CLOEXEC or IN_NONBLOCK);
  if Result < 0 then
    Result := c_inotify_init;
end;

{ ev.c ev_linux_version - parse the running kernel version from uname
  into 0xMMmmpp form (e.g. 2.6.25 -> 0x020619) }
function EvLinuxVersion: Cardinal;
var
  Buf: array[0..389] of AnsiChar; { struct utsname: 6 fields x 65 bytes }
  P: PAnsiChar;
  V, C: Cardinal;
  I: Integer;
begin
  if c_uname(@Buf) <> 0 then
    Exit(0);

  P := @Buf[130]; { the release field (third), e.g. "6.6.87.2-microsoft..." }
  V := 0;

  for I := 1 to 3 do
  begin
    C := 0;
    while (P^ >= '0') and (P^ <= '9') do
    begin
      C := C * 10 + Cardinal(Ord(P^) - Ord('0'));
      Inc(P);
    end;
    if P^ = '.' then
      Inc(P);
    V := (V shl 8) or C;
  end;

  Result := V;
end;

{ sys/wait.h status macros }
function WIfStopped(Status: Integer): Boolean; inline;
begin
  Result := (Status and $FF) = $7F;
end;

function WIfContinued(Status: Integer): Boolean; inline;
begin
  Result := Status = $FFFF;
end;
{$ENDIF}

const
  { ev_epoll.c:68 EV_EMASK_EPERM }
  EV_EMASK_EPERM = $80;

{$IFDEF LINUX}
type
  { the epoll backend of ev_epoll.c; see that file's header comment for the
    long list of epoll design problems all this code has to work around }
  TEvEpollBackend = class(TEvBackend)
  private
    FEvents: array of TEpollEvent;  { ev_vars.h:103 epoll_events/epoll_eventmax }
    FEperms: array of Integer;      { ev_vars.h:105 epoll_eperms }
    FEpermCnt: Integer;             { ev_vars.h:106 epoll_epermcnt }
    class function EpollCreateFd: Integer; { ev_epoll.c:243 epoll_epoll_create }
  public
    constructor Create(ALoop: TEvLoop); { ev_epoll.c:264 epoll_init }
    destructor Destroy; override;       { ev_epoll.c:281 epoll_destroy }
    function Kind: TEvBackendKind; override;
    procedure Modify(Fd: Integer; OEv, NEv: TEvEvents); override; { ev_epoll.c:70 }
    procedure Poll(Timeout: TEvTstamp); override;                 { ev_epoll.c:143 }
    procedure ForkReinit; { ev_epoll.c:289 epoll_fork }
  end;

{ ev_epoll.c:243 epoll_epoll_create }
class function TEvEpollBackend.EpollCreateFd: Integer;
var
  Fd, Err: Integer;
begin
  Fd := c_epoll_create1(EPOLL_CLOEXEC);

  if Fd < 0 then
  begin
    Err := GetErrno;
    if (Err = ERRNO_EINVAL) or (Err = ERRNO_ENOSYS) then
    begin
      Fd := c_epoll_create(256);
      if Fd >= 0 then
        c_fcntl_set(Fd, F_SETFD, FD_CLOEXEC);
    end;
  end;

  Result := Fd;
end;

{ ev_epoll.c:264 epoll_init; C returns 0 to fall back to another backend,
  we raise instead because no POSIX select/poll port exists yet }
constructor TEvEpollBackend.Create(ALoop: TEvLoop);
begin
  inherited Create(ALoop);

  FLoop.FBackendFd := EpollCreateFd;
  if FLoop.FBackendFd < 0 then
    EvSysErr('(libev) epoll_create failed');

  FMinTime := 1e-3; { epoll does sometimes return early, this is just to avoid the worst }
  SetLength(FEvents, 64); { initial number of events receivable per poll }
end;

{ ev_epoll.c:281 epoll_destroy (+ the backend_fd close of ev_loop_destroy) }
destructor TEvEpollBackend.Destroy;
begin
  if FLoop.FBackendFd >= 0 then
    c_close(FLoop.FBackendFd);
  inherited Destroy;
end;

function TEvEpollBackend.Kind: TEvBackendKind;
begin
  Result := evbackendEpoll;
end;

{ ev_epoll.c:70 epoll_modify }
procedure TEvEpollBackend.Modify(Fd: Integer; OEv, NEv: TEvEvents);
var
  Ev: TEpollEvent;
  OldMask, NMask: Byte;
  Op, Err: Integer;
begin
  { we handle EPOLL_CTL_DEL by ignoring it here on the assumption that the
    fd is gone anyways; if that is wrong, we handle the spurious event in
    Poll. If the fd is added again, we try ADD and, if that fails, we assume
    it still has the same eventmask (ev_epoll.c:76) }
  if NEv = [] then
    Exit;

  OldMask := FLoop.FAnFds[Fd].EMask;
  NMask := EvMaskOf(NEv);
  FLoop.FAnFds[Fd].EMask := NMask;

  { store the generation counter in the upper 32 bits, the fd in the lower
    32 bits (ev_epoll.c:90) }
  Inc(FLoop.FAnFds[Fd].EGen);
{$IFDEF FPC}
  Ev.Data.u64 := UInt64(Cardinal(Fd)) or (UInt64(FLoop.FAnFds[Fd].EGen) shl 32);
{$ELSE}
  Ev.Data := UInt64(Cardinal(Fd)) or (UInt64(FLoop.FAnFds[Fd].EGen) shl 32);
{$ENDIF}
  Ev.Events := 0;
  if evRead in NEv then Ev.Events := Ev.Events or EPOLLIN;
  if evWrite in NEv then Ev.Events := Ev.Events or EPOLLOUT;

  if (OEv <> []) and (OldMask <> NMask) then
    Op := EPOLL_CTL_MOD
  else
    Op := EPOLL_CTL_ADD;

  if c_epoll_ctl(FLoop.FBackendFd, Op, Fd, @Ev) = 0 then
    Exit;

  Err := GetRtlErrno;  { c_epoll_ctl is an RTL binding on FPC }

  if Err = ERRNO_ENOENT then
  begin
    { ENOENT means the fd went away, so try to do the right thing;
      NEv is known non-empty here, so retry with ADD (ev_epoll.c:99) }
    if c_epoll_ctl(FLoop.FBackendFd, EPOLL_CTL_ADD, Fd, @Ev) = 0 then
      Exit;
  end
  else if Err = ERRNO_EEXIST then
  begin
    { EEXIST means we ignored a previous DEL, but the fd is still active;
      if the kernel mask is the same as the new mask, assume it hasn't
      changed (ev_epoll.c:108) }
    if OldMask = NMask then
    begin
      Dec(FLoop.FAnFds[Fd].EGen); { dec_egen }
      Exit;
    end;

    if c_epoll_ctl(FLoop.FBackendFd, EPOLL_CTL_MOD, Fd, @Ev) = 0 then
      Exit;
  end
  else if Err = ERRNO_EPERM then
  begin
    { EPERM means the fd is always ready, but epoll is too snobbish to
      handle it, unlike select or poll (ev_epoll.c:118) }
    FLoop.FAnFds[Fd].EMask := EV_EMASK_EPERM;

    { add fd to epoll_eperms, if not already inside }
    if (OldMask and EV_EMASK_EPERM) = 0 then
    begin
      if FEpermCnt + 1 > Length(FEperms) then
        SetLength(FEperms, ArrayNextSize(SizeOf(Integer), Length(FEperms), FEpermCnt + 1));
      FEperms[FEpermCnt] := Fd;
      Inc(FEpermCnt);
    end;

    Exit;
  end
  else
    EvAssert((Err <> ERRNO_EBADF) and (Err <> ERRNO_ELOOP) and (Err <> ERRNO_EINVAL),
      'I/O watcher with invalid fd found in epoll_ctl');

  FLoop.FdKill(Fd);

  { we didn't successfully call epoll_ctl, so decrement the generation
    counter again (ev_epoll.c:138 dec_egen) }
  Dec(FLoop.FAnFds[Fd].EGen);
end;

{ ev_epoll.c:143 epoll_poll }
procedure TEvEpollBackend.Poll(Timeout: TEvTstamp);
var
  I, EventCnt, Fd, Op: Integer;
  Ev: PEpollEvent;
  Want, Got: TEvEvents;
begin
  { fds reported via eperms must be polled with timeout 0 (ev_epoll.c:149) }
  if FEpermCnt > 0 then
    Timeout := 0;

  FLoop.DoRelease;  { EV_RELEASE_CB - release the loop before blocking }
  EventCnt := c_epoll_wait(FLoop.FBackendFd, @FEvents[0], Length(FEvents),
    Integer(TsToMsec(Timeout)));
  FLoop.DoAcquire;  { EV_ACQUIRE_CB - reacquire after the blocking call }

  if EventCnt < 0 then
  begin
    if GetRtlErrno <> ERRNO_EINTR then  { c_epoll_wait is an RTL binding on FPC }
      EvSysErr(Format('(libev) epoll_wait error: %d', [GetRtlErrno]));
    Exit;
  end;

  for I := 0 to EventCnt - 1 do
  begin
    Ev := @FEvents[I];

{$IFDEF FPC}
    Fd := Integer(Cardinal(Ev^.Data.u64)); { mask out the lower 32 bits }
{$ELSE}
    Fd := Integer(Cardinal(Ev^.Data)); { mask out the lower 32 bits }
{$ENDIF}
    Want := FLoop.FAnFds[Fd].Events;
    Got := [];
    if Ev^.Events and (EPOLLOUT or EPOLLERR or EPOLLHUP) <> 0 then Include(Got, evWrite);
    if Ev^.Events and (EPOLLIN or EPOLLERR or EPOLLHUP) <> 0 then Include(Got, evRead);

    { check for spurious notification: this only finds spurious
      notifications on egen updates, others are found by epoll_ctl below
      (ev_epoll.c:175) }
{$IFDEF FPC}
    if FLoop.FAnFds[Fd].EGen <> Cardinal(Ev^.Data.u64 shr 32) then
{$ELSE}
    if FLoop.FAnFds[Fd].EGen <> Cardinal(Ev^.Data shr 32) then
{$ENDIF}
    begin
      { recreate kernel state }
      FLoop.FPostFork := FLoop.FPostFork or 2;
      Continue;
    end;

    if Got - Want <> [] then
    begin
      FLoop.FAnFds[Fd].EMask := EvMaskOf(Want);

      { we received an event but are not interested in it, try mod or del;
        this often happens because we optimistically do not unregister fds
        when we are no longer interested in them (ev_epoll.c:192) }
      Ev^.Events := 0;
      if evRead in Want then Ev^.Events := Ev^.Events or EPOLLIN;
      if evWrite in Want then Ev^.Events := Ev^.Events or EPOLLOUT;

      if Want <> [] then
        Op := EPOLL_CTL_MOD
      else
        Op := EPOLL_CTL_DEL;

      if c_epoll_ctl(FLoop.FBackendFd, Op, Fd, Ev) <> 0 then
      begin
        FLoop.FPostFork := FLoop.FPostFork or 2; { an error occurred, recreate kernel state }
        Continue;
      end;
    end;

    FLoop.FdEvent(Fd, Got);
  end;

  { if the receive array was full, increase its size (ev_epoll.c:218) }
  if EventCnt = Length(FEvents) then
    SetLength(FEvents,
      ArrayNextSize(SizeOf(TEpollEvent), Length(FEvents), Length(FEvents) + 1));

  { now synthesize events for all fds where epoll fails, while select
    works... (ev_epoll.c:226) }
  for I := FEpermCnt - 1 downto 0 do
  begin
    Fd := FEperms[I];
    Want := FLoop.FAnFds[Fd].Events * [evRead, evWrite];

    if ((FLoop.FAnFds[Fd].EMask and EV_EMASK_EPERM) <> 0) and (Want <> []) then
      FLoop.FdEvent(Fd, Want)
    else
    begin
      Dec(FEpermCnt);
      FEperms[I] := FEperms[FEpermCnt];
      FLoop.FAnFds[Fd].EMask := 0;
    end;
  end;
end;

{ ev_epoll.c:289 epoll_fork - recreate the epoll fd after a fork }
procedure TEvEpollBackend.ForkReinit;
begin
  c_close(FLoop.FBackendFd);

  FLoop.FBackendFd := EpollCreateFd;
  if FLoop.FBackendFd < 0 then
    EvSysErr('(libev) epoll_create failed');

  FLoop.FdRearmAll;
end;
{$ENDIF}

type
  { the poll(2) backend of ev_poll.c: portable, scales like O(total_fds) }
  TEvPollBackend = class(TEvBackend)
  private
    FPolls: TPollFdArray;         { ev_vars.h:95 polls (FPollCnt entries used) }
    FPollCnt: Integer;            { ev_vars.h:97 pollcnt }
    FPollIdxs: array of Integer;  { ev_vars.h:98 pollidxs - fd -> index, -1 if absent }
  public
    constructor Create(ALoop: TEvLoop); { ev_poll.c:137 poll_init }
    function Kind: TEvBackendKind; override;
    procedure Modify(Fd: Integer; OEv, NEv: TEvEvents); override; { ev_poll.c:55 }
    procedure Poll(Timeout: TEvTstamp); override;                 { ev_poll.c:92 }
  end;

constructor TEvPollBackend.Create(ALoop: TEvLoop);
begin
  inherited Create(ALoop);
  FMinTime := 1e-3;  { ev_poll.c:139 backend_mintime }
end;

function TEvPollBackend.Kind: TEvBackendKind;
begin
  Result := evbackendPoll;
end;

{ ev_poll.c:55 poll_modify }
procedure TEvPollBackend.Modify(Fd: Integer; OEv, NEv: TEvEvents);
var
  Idx, OldLen, I: Integer;
begin
  if OEv = NEv then
    Exit;

  { grow the fd->index map, new slots start empty (-1) }
  if Fd + 1 > Length(FPollIdxs) then
  begin
    OldLen := Length(FPollIdxs);
    SetLength(FPollIdxs, ArrayNextSize(SizeOf(Integer), OldLen, Fd + 1));
    for I := OldLen to Length(FPollIdxs) - 1 do
      FPollIdxs[I] := -1;
  end;

  Idx := FPollIdxs[Fd];

  if Idx < 0 then  { need to allocate a new pollfd }
  begin
    Idx := FPollCnt;
    FPollIdxs[Fd] := Idx;
    Inc(FPollCnt);
    if FPollCnt > Length(FPolls) then
      SetLength(FPolls, ArrayNextSize(SizeOf(TPollFd), Length(FPolls), FPollCnt));
    FPolls[Idx].Fd := Fd;
  end;

  if NEv <> [] then
  begin
    FPolls[Idx].Events := 0;
    if evRead in NEv then FPolls[Idx].Events := FPolls[Idx].Events or POLLIN;
    if evWrite in NEv then FPolls[Idx].Events := FPolls[Idx].Events or POLLOUT;
  end
  else  { remove pollfd: move the last entry into this slot }
  begin
    FPollIdxs[Fd] := -1;
    Dec(FPollCnt);
    if Idx < FPollCnt then
    begin
      FPolls[Idx] := FPolls[FPollCnt];
      FPollIdxs[FPolls[Idx].Fd] := Idx;
    end;
  end;
end;

{ ev_poll.c:92 poll_poll }
procedure TEvPollBackend.Poll(Timeout: TEvTstamp);
var
  Res, I, Err: Integer;
  RV: SmallInt;
  Ev: TEvEvents;
begin
  FLoop.DoRelease;
  if FPollCnt > 0 then
    Res := c_poll(@FPolls[0], FPollCnt, Integer(TsToMsec(Timeout)))
  else
    Res := c_poll(nil, 0, Integer(TsToMsec(Timeout)));  { just a sleep }
  FLoop.DoAcquire;

  if Res < 0 then
  begin
    Err := GetRtlErrno;  { c_poll is an RTL binding on FPC }
    if Err = ERRNO_EBADF then
      FLoop.FdEbadf
    else if Err = ERRNO_ENOMEM then
      FLoop.FdEnomem
    else if Err <> ERRNO_EINTR then
      EvSysErr('(libev) poll');
    Exit;
  end;

  I := 0;
  while (Res > 0) and (I < FPollCnt) do
  begin
    RV := FPolls[I].Revents;
    if RV <> 0 then
    begin
      Dec(Res);
      if (RV and POLLNVAL) <> 0 then
        FLoop.FdKill(FPolls[I].Fd)
      else
      begin
        Ev := [];
        if (RV and (POLLOUT or POLLERR or POLLHUP)) <> 0 then Include(Ev, evWrite);
        if (RV and (POLLIN  or POLLERR or POLLHUP)) <> 0 then Include(Ev, evRead);
        FLoop.FdEvent(FPolls[I].Fd, Ev);
      end;
    end;
    Inc(I);
  end;
end;

{$ENDIF LINUX}

{ ------------------------------------------------------------------ }
{ signal machinery (cross-platform; ev_signal works on both targets)  }
{ ------------------------------------------------------------------ }

{$IFDEF MSWINDOWS}
{ the CRT signal() - the only signal facility Windows offers; returns the
  previous handler. Only SIGINT/SIGTERM/SIGABRT/SIGFPE/SIGILL/SIGSEGV are
  actually meaningful there. }
function msvcrt_signal(Sig: Integer; Handler: Pointer): Pointer; cdecl;
  external 'msvcrt.dll' name 'signal';
{$ENDIF}

type
  { ev.c:2716 ANSIG - associates signal watchers to a signal }
  TANSig = record
    Pending: Integer;      { EV_ATOMIC_T pending }
    Loop: TEvLoop;         { EV_P }
    Head: TEvWatcherList;  { WL head }
  end;

var
  { ev.c:2725 static ANSIG signals [EV_NSIG - 1] }
  GSignals: array[0..EV_NSIG - 2] of TANSig;

{ ev.c:2895 ev_feed_signal }
procedure EvFeedSignal(SigNum: Integer);
var
  L: TEvLoop;
begin
  EvMemoryFence; { ECB_MEMORY_FENCE_ACQUIRE }
  L := GSignals[SigNum - 1].Loop;
  if L = nil then
    Exit;

  EvAtomicSet(GSignals[SigNum - 1].Pending, 1);
  L.EvPipeWrite(L.FSigPending);
end;

{ ev.c:2911 ev_sighandler - the raw signal handler }
procedure EvSigHandler(SigNum: Integer); cdecl;
begin
{$IFDEF MSWINDOWS}
  { Windows resets the disposition to default after each delivery, so the
    handler must re-arm itself (ev_win32 does the same) }
  msvcrt_signal(SigNum, @EvSigHandler);
{$ENDIF}
  EvFeedSignal(SigNum);
end;

{ ------------------------------------------------------------------ }
{ TEvBackend                                                          }
{ ------------------------------------------------------------------ }

constructor TEvBackend.Create(ALoop: TEvLoop);
begin
  inherited Create;
  FLoop := ALoop;
end;

{ ------------------------------------------------------------------ }
{ TEvWatcher                                                          }
{ ------------------------------------------------------------------ }

{ ev.h:690 ev_init }
constructor TEvWatcher.Create;
begin
  inherited Create;
  FActive := 0;
  FPending := 0;
  FPriority := 0;
end;

destructor TEvWatcher.Destroy;
begin
  { OO safety net: if an active watcher is destroyed, remove it from the
    loop first (no C counterpart) }
  if (FLoop <> nil) and (FActive <> 0) then
    Stop;
  inherited Destroy;
end;

function TEvWatcher.GetIsActive: Boolean;
begin
  Result := FActive <> 0; { ev.h:727 ev_is_active }
end;

function TEvWatcher.GetIsPending: Boolean;
begin
  Result := FPending <> 0; { ev.h:726 ev_is_pending }
end;

{ ev.h:256 EV_CB_INVOKE }
procedure TEvWatcher.Invoke(REvents: TEvEvents);
begin
  if Assigned(FOnEvent) then
    FOnEvent(FLoop, Self, REvents);
end;

procedure TEvWatcher.FeedEvent(REvents: TEvEvents);
begin
  EvAssert(FLoop <> nil, 'FeedEvent called on a watcher not bound to any loop');
  FLoop.FeedEventW(Self, REvents);
end;

{ ev.c:4288 ev_clear_pending }
function TEvWatcher.ClearPending: TEvEvents;
var
  Pending: Integer;
  P: ^TANPending;
begin
  Pending := FPending;
  if Pending <> 0 then
  begin
    P := @FLoop.FPendings[AbsPri(Self)][Pending - 1];
    P^.W := FLoop.FPendingW;
    FPending := 0;
    Result := P^.Events;
  end
  else
    Result := [];
end;

{ ------------------------------------------------------------------ }
{ Public watcher Start/Stop wrappers                                  }
{ ------------------------------------------------------------------ }

constructor TEvIo.Create(AFd: Integer; AEvents: TEvEvents);
begin
  inherited Create;
  SetIo(AFd, AEvents);
end;

{ ev.h:698 ev_io_set }
procedure TEvIo.SetIo(AFd: Integer; AEvents: TEvEvents);
begin
  EvAssert(FActive = 0, 'ev_io_set called while the watcher is active');
  FFd := AFd;
  FEvents := AEvents + [evIoFdSet];
end;

{ ev.h:697 ev_io_modify }
procedure TEvIo.Modify(AEvents: TEvEvents);
begin
  FEvents := (FEvents * [evIoFdSet]) + AEvents;
end;

procedure TEvIo.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.IoStart(Self);
end;

procedure TEvIo.Stop;
begin
  if FLoop <> nil then
    FLoop.IoStop(Self);
end;

constructor TEvTimer.Create(AAfter, ARepeat: TEvTstamp);
begin
  inherited Create;
  SetTimer(AAfter, ARepeat);
end;

{ ev.h:699 ev_timer_set }
procedure TEvTimer.SetTimer(AAfter, ARepeat: TEvTstamp);
begin
  EvAssert(FActive = 0, 'ev_timer_set called while the watcher is active');
  FAt := AAfter;
  FRepeat := ARepeat;
end;

procedure TEvTimer.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.TimerStart(Self);
end;

procedure TEvTimer.Stop;
begin
  if FLoop <> nil then
    FLoop.TimerStop(Self);
end;

procedure TEvTimer.Again;
begin
  EvAssert(FLoop <> nil, 'ev_timer_again: bind the watcher to a loop with Start first');
  FLoop.TimerAgain(Self);
end;

{ ev.c:4468 ev_timer_remaining }
function TEvTimer.GetRemaining: TEvTstamp;
begin
  if FActive <> 0 then
    Result := FAt - FLoop.FMnNow
  else
    Result := FAt;
end;

constructor TEvPeriodic.Create(AOffset, AInterval: TEvTstamp);
begin
  inherited Create;
  SetPeriodic(AOffset, AInterval);
end;

{ ev.h:700 ev_periodic_set }
procedure TEvPeriodic.SetPeriodic(AOffset, AInterval: TEvTstamp);
begin
  EvAssert(FActive = 0, 'ev_periodic_set called while the watcher is active');
  FOffset := AOffset;
  FInterval := AInterval;
end;

procedure TEvPeriodic.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.PeriodicStart(Self);
end;

procedure TEvPeriodic.Stop;
begin
  if FLoop <> nil then
    FLoop.PeriodicStop(Self);
end;

{ ev.c:4541 ev_periodic_again }
procedure TEvPeriodic.Again;
begin
  EvAssert(FLoop <> nil, 'ev_periodic_again: bind the watcher to a loop with Start first');
  { TODO in C as well: use adjustheap and recalculation }
  FLoop.PeriodicStop(Self);
  FLoop.PeriodicStart(Self);
end;

procedure TEvIdle.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.IdleStart(Self);
end;

procedure TEvIdle.Stop;
begin
  if FLoop <> nil then
    FLoop.IdleStop(Self);
end;

procedure TEvPrepare.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.PrepareStart(Self);
end;

procedure TEvPrepare.Stop;
begin
  if FLoop <> nil then
    FLoop.PrepareStop(Self);
end;

procedure TEvCheck.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.CheckStart(Self);
end;

procedure TEvCheck.Stop;
begin
  if FLoop <> nil then
    FLoop.CheckStop(Self);
end;

procedure TEvFork.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.ForkStart(Self);
end;

procedure TEvFork.Stop;
begin
  if FLoop <> nil then
    FLoop.ForkStop(Self);
end;

procedure TEvCleanup.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.CleanupStart(Self);
end;

procedure TEvCleanup.Stop;
begin
  if FLoop <> nil then
    FLoop.CleanupStop(Self);
end;

constructor TEvStat.Create(const APath: string; AInterval: TEvTstamp);
begin
  inherited Create;
  { the embedded "ev_timer timer" member of C becomes an owned instance }
  FTimer := TEvTimer.Create(0, 0);
  FTimer.FOnEvent := TimerCb;
  SetStat(APath, AInterval);
end;

destructor TEvStat.Destroy;
begin
  inherited Destroy; { stops the watcher (and thereby the timer) if active }
  FTimer.Free;
end;

{ ev.h:703 ev_stat_set }
procedure TEvStat.SetStat(const APath: string; AInterval: TEvTstamp);
begin
  EvAssert(FActive = 0, 'ev_stat_set called while the watcher is active');
  FPath := APath;
  FInterval := AInterval;
  FWd := -2;
end;

{ ev.c:4973 ev_stat_stat }
procedure TEvStat.StatNow;
begin
  if not DoLStat(FPath, FAttr) then
    FAttr.st_nlink := 0
  else if FAttr.st_nlink = 0 then
    FAttr.st_nlink := 1;
end;

{ ev.c:4983 stat_timer_cb }
procedure TEvStat.TimerCb(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  PrevData: TEvStatData;
begin
  PrevData := FAttr;
  StatNow;

  { memcmp doesn't work on netbsd, they.... do stuff to their struct stat }
  if (PrevData.st_dev <> FAttr.st_dev)
    or (PrevData.st_ino <> FAttr.st_ino)
    or (PrevData.st_mode <> FAttr.st_mode)
    or (PrevData.st_nlink <> FAttr.st_nlink)
    or (PrevData.st_uid <> FAttr.st_uid)
    or (PrevData.st_gid <> FAttr.st_gid)
    or (PrevData.st_rdev <> FAttr.st_rdev)
    or (PrevData.st_size <> FAttr.st_size)
    or (PrevData.st_atime <> FAttr.st_atime)
    or (PrevData.st_mtime <> FAttr.st_mtime)
    or (PrevData.st_ctime <> FAttr.st_ctime) then
  begin
    { we only update prev on actual differences, in case we test more often
      than we invoke the callback, to ensure prev stays different to attr }
    FPrev := PrevData;

    { ev.c:5009: refresh the inotify watch, the identity of the watched
      path may have changed }
{$IFDEF LINUX}
    if Loop.FFsFd >= 0 then
    begin
      Loop.InfyDel(Self);
      Loop.InfyAdd(Self);
      StatNow; { avoid race... }
    end;
{$ENDIF}

    Loop.FeedEventW(Self, [evStat]);
  end;
end;

procedure TEvStat.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.StatStart(Self);
end;

procedure TEvStat.Stop;
begin
  if FLoop <> nil then
    FLoop.StatStop(Self);
end;

function TEvAsync.GetAsyncPending: Boolean;
begin
  Result := FSent <> 0; { ev.h:464 ev_async_pending }
end;

procedure TEvAsync.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.AsyncStart(Self);
end;

procedure TEvAsync.Stop;
begin
  if FLoop <> nil then
    FLoop.AsyncStop(Self);
end;

procedure TEvAsync.Send;
begin
  EvAssert(FLoop <> nil, 'ev_async_send: bind the watcher to a loop with Start first');
  FLoop.AsyncSend(Self);
end;

constructor TEvSignal.Create(ASigNum: Integer);
begin
  inherited Create;
  SetSignal(ASigNum);
end;

{ ev.h:701 ev_signal_set }
procedure TEvSignal.SetSignal(ASigNum: Integer);
begin
  EvAssert(FActive = 0, 'ev_signal_set called while the watcher is active');
  FSigNum := ASigNum;
end;

procedure TEvSignal.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.SignalStart(Self);
end;

procedure TEvSignal.Stop;
begin
  if FLoop <> nil then
    FLoop.SignalStop(Self);
end;

{$IFDEF LINUX}
constructor TEvChild.Create(APid: Integer; ATrace: Boolean);
begin
  inherited Create;
  SetChild(APid, ATrace);
end;

{ ev.h:702 ev_child_set }
procedure TEvChild.SetChild(APid: Integer; ATrace: Boolean);
begin
  EvAssert(FActive = 0, 'ev_child_set called while the watcher is active');
  FPid := APid;
  FFlags := Ord(ATrace);
end;

procedure TEvChild.Start(ALoop: TEvLoop);
begin
  EvAssert((FActive = 0) or (FLoop = ALoop), 'watcher is active on another loop');
  FLoop := ALoop;
  ALoop.ChildStart(Self);
end;

procedure TEvChild.Stop;
begin
  if FLoop <> nil then
    FLoop.ChildStop(Self);
end;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ TEvLoop                                                             }
{ ------------------------------------------------------------------ }

{ ev.c:3253 loop_init (backend selection per platform) }
constructor TEvLoop.Create(AFlags: TEvFlags; ABackends: TEvBackendKinds);
begin
  inherited Create;

  FOrigFlags := AFlags;

{$IFDEF LINUX}
  { pid check not overridable via env (ev.c:3280) }
  if evflagForkCheck in AFlags then
    FCurPid := c_getpid;
{$ENDIF}

  FRtNow := EvTime;
  FMnNow := EvClock;
  FNowFloor := FMnNow;
  FRtMnDiff := FRtNow - FMnNow;

  FIoBlocktime := 0;
  FTimeoutBlocktime := 0;
  FBackendFd := -1;
  FSigPending := 0;
  FAsyncPending := 0;
  FPipeWriteSkipped := 0;
  FPipeWriteWanted := 0;
  FEvPipe[0] := -1;
  FEvPipe[1] := -1;
{$IFDEF LINUX}
  { ev.c:3311: fs_fd = flags & EVFLAG_NOINOTIFY ? -1 : -2 }
  if evflagNoInotify in AFlags then
    FFsFd := -1
  else
    FFsFd := -2;

  { ev.c:3313: sigfd = flags & EVFLAG_SIGNALFD ? -2 : -1 }
  if evflagSignalFd in AFlags then
    FSigFd := -2
  else
    FSigFd := -1;

  { ev.c:3316: timerfd = flags & EVFLAG_NOTIMERFD ? -1 : -2 (on by default) }
  if evflagNoTimerFd in AFlags then
    FTimerFd := -1
  else
    FTimerFd := -2;
{$ENDIF}

  { ev.c:3320 backend selection. An empty ABackends means "recommended":
    epoll on Linux, poll on macOS, select on Windows. }
{$IFDEF MSWINDOWS}
  FBackend := TEvSelectBackend.Create(Self);
{$ENDIF}
{$IFDEF LINUX}
  if (evbackendPoll in ABackends) and not (evbackendEpoll in ABackends) then
    FBackend := TEvPollBackend.Create(Self)
  else
    FBackend := TEvEpollBackend.Create(Self);  { recommended }
{$ENDIF}
{$IFDEF DARWIN}
  { macOS has no epoll; use poll (kqueue is not ported yet) }
  FBackend := TEvPollBackend.Create(Self);
{$ENDIF}

  { ev.c:3348 ev_prepare_init (&pending_w, pendingcb) - a dummy watcher
    without a callback; its Invoke is naturally a no-op }
  FPendingW := TEvPrepare.Create;

  { ev.c:3351 ev_init (&pipe_w, pipecb) + ev_set_priority (&pipe_w, EV_MAXPRI) }
  FPipeW := TEvIo.Create(-1, []);
  FPipeW.FLoop := Self;
  FPipeW.FOnEvent := PipeCb;
  FPipeW.FPriority := EV_MAXPRI;

{$IFDEF LINUX}
  { the fs_w inotify watcher (embedded in the C loop struct); the fd and
    priority are assigned in InfyInit (ev.c:4911) }
  FFsW := TEvIo.Create(-1, []);
  FFsW.FLoop := Self;
  FFsW.FOnEvent := InfyCb;

  { the sigfd_w signalfd watcher; fd/priority assigned in SignalStart }
  FSigFdW := TEvIo.Create(-1, []);
  FSigFdW.FLoop := Self;
  FSigFdW.FOnEvent := SigFdCb;

  { the timerfd_w time-jump watcher; fd/priority assigned in EvTimerFdInit }
  FTimerFdW := TEvIo.Create(-1, []);
  FTimerFdW.FLoop := Self;
  FTimerFdW.FOnEvent := TimerFdCb;
{$ENDIF}
end;

{ ev.c:3360 ev_loop_destroy (subset: user watchers are owned by the user) }
destructor TEvLoop.Destroy;
var
  I: Integer;
begin
  { queue cleanup watchers (and execute them) (ev.c:3370) }
  if FCleanupCnt > 0 then
  begin
    for I := 0 to FCleanupCnt - 1 do
      FeedEventW(FCleanups[I], [evCleanup]);
    InvokePending;
  end;

  { OO safety net (no C counterpart): detach the remaining cleanup watchers
    so that freeing them later cannot touch this dead loop }
  while FCleanupCnt > 0 do
  begin
    I := FCleanupCnt - 1;
    CleanupStop(FCleanups[I]);
    FCleanups[I].FLoop := nil;
  end;

{$IFDEF LINUX}
  { ev.c:3379 stop the internal SIGCHLD watcher of the default loop }
  if (FChildEv <> nil) and FChildEv.IsActive then
  begin
    Ref; { child watcher }
    SignalStop(FChildEv);
  end;
  FChildEv.Free;

  { ev.c:3407 close the inotify fd }
  if (FFsW <> nil) and (FFsW.FActive <> 0) then
  begin
    Ref;
    IoStop(FFsW);
  end;
  FFsW.Free;
  if FFsFd >= 0 then
    c_close(FFsFd);

  { ev.c:3396 close the signalfd }
  if (FSigFdW <> nil) and (FSigFdW.FActive <> 0) then
  begin
    Ref;
    IoStop(FSigFdW);
  end;
  FSigFdW.Free;
  if FSigFd >= 0 then
    c_close(FSigFd);

  { ev.c:3401 close the timerfd }
  if (FTimerFdW <> nil) and (FTimerFdW.FActive <> 0) then
  begin
    Ref;
    IoStop(FTimerFdW);
  end;
  FTimerFdW.Free;
  if FTimerFd >= 0 then
    c_close(FTimerFd);
{$ENDIF}

  { ev.c:3387 close the signal/async pipe }
  if (FPipeW <> nil) and (FPipeW.FActive <> 0) then
  begin
    if FEvPipe[0] >= 0 then EvCloseFd(FEvPipe[0]);
    if FEvPipe[1] >= 0 then EvCloseFd(FEvPipe[1]);
    Ref;
    IoStop(FPipeW); { keep internal state consistent before freeing }
  end;
  FPipeW.Free;

  if Self = FDefault then
    FDefault := nil;
  FPendingW.Free;
  FBackend.Free;
  inherited Destroy;
end;

{ ev.c:560 ev_default_loop }
class function TEvLoop.Default: TEvLoop;
begin
  if FDefault = nil then
  begin
    FDefault := TEvLoop.Create;

{$IFDEF LINUX}
    { ev.c ev_default_loop: the default loop reaps children via an internal
      SIGCHLD watcher with maximum priority }
    FDefault.FChildEv := TEvSignal.Create(SIGCHLD);
    FDefault.FChildEv.FOnEvent := FDefault.ChildCb;
    FDefault.FChildEv.FPriority := EV_MAXPRI;
    FDefault.FChildEv.Start(FDefault);
    FDefault.Unref; { child watcher should not keep loop alive }
{$ENDIF}
  end;
  Result := FDefault;
end;

function TEvLoop.IsDefaultLoop: Boolean;
begin
  Result := Self = FDefault;
end;

{ ev.c:2208 ev_now }
function TEvLoop.Now: TEvTstamp;
begin
  Result := FRtNow;
end;

{ ev.c:4227 ev_now_update }
procedure TEvLoop.NowUpdate;
begin
  TimeUpdate(EV_TSTAMP_HUGE);
end;

{ ev.c:4233 ev_suspend }
procedure TEvLoop.Suspend;
begin
  NowUpdate;
end;

{ ev.c:4239 ev_resume }
procedure TEvLoop.Resume;
var
  MnPrev: TEvTstamp;
begin
  MnPrev := FMnNow;
  NowUpdate;
  TimersReschedule(FMnNow - MnPrev);
  PeriodicsReschedule;
end;

{ ev.c:613 ev_loop_fork }
procedure TEvLoop.LoopFork;
begin
  FPostFork := 1;
end;

{ ev.c:3485 loop_fork - recreate kernel state after a fork }
procedure TEvLoop.LoopForkInternal;
begin
{$IFDEF LINUX}
  if FBackend is TEvEpollBackend then
    TEvEpollBackend(FBackend).ForkReinit; { epoll_fork }

  InfyFork; { ev.c:3503 }
{$ENDIF}

  { postfork = 2 means "only recreate kernel state" (set by the epoll
    backend on spurious events); the pipe stays untouched then (ev.c:3506) }
  if FPostFork <> 2 then
  begin
{$IFDEF LINUX}
    { ev.c:3512 recreate the timerfd in the child }
    if FTimerFdW.FActive <> 0 then
    begin
      Ref;
      IoStop(FTimerFdW);
      c_close(FTimerFd);
      FTimerFd := -2;
      EvTimerFdInit;
      FeedEventW(FTimerFdW, [evCustom]);
    end;
{$ENDIF}

    if FPipeW.FActive <> 0 then
    begin
      { pipe_write_wanted must be false now, so modifying fd vars should be safe }
      Ref;
      IoStop(FPipeW);

{$IFDEF LINUX}
      if FEvPipe[0] >= 0 then
        c_close(FEvPipe[0]);
{$ENDIF}

      EvPipeInit;
      { iterate over everything, in case we missed something before }
      FeedEventW(FPipeW, [evCustom]);
    end;
  end;

  FPostFork := 0;
end;

{ ------------------------------------------------------------------ }
{ signal/async pipe                                                   }
{ ------------------------------------------------------------------ }

{ ev.c:2733 evpipe_init }
procedure TEvLoop.EvPipeInit;
var
  Fd0, Fd1: Integer;
{$IFDEF EV_POSIX}
  Fds: array[0..1] of Integer;
{$ENDIF}
begin
  if FPipeW.FActive = 0 then
  begin
{$IFDEF EV_POSIX}
    Fd0 := -1;
    Fd1 := -1;
  {$IFDEF LINUX}
    { prefer an eventfd over a pipe, it needs only one fd (ev.c:2739) }
    Fd1 := c_eventfd(0, EFD_NONBLOCK or EFD_CLOEXEC);
    if (Fd1 < 0) and (GetErrno = ERRNO_EINVAL) then
      Fd1 := c_eventfd(0, 0);
  {$ENDIF}
    if Fd1 < 0 then
    begin
      { a plain pipe - always on macOS (no eventfd), the fallback on Linux }
      if c_pipe(@Fds[0]) <> 0 then
        EvSysErr('(libev) error creating signal/async pipe');
      Fd0 := Fds[0];
      Fd1 := Fds[1];
      FdIntern(Fd0);
    end;
{$ELSE}
    { on Windows a pipe is emulated with a loopback TCP socket pair }
    if EvPipe(Fd0, Fd1) <> 0 then
      raise EEvError.Create('(libev) error creating signal/async pipe');
    FdIntern(Fd0);
{$ENDIF}

    FEvPipe[0] := Fd0;

    if FEvPipe[1] < 0 then
      FEvPipe[1] := Fd1 { first call, set write fd }
    else
    begin
      { on subsequent calls (after fork), do not change evpipe [1] so that
        EvPipeWrite can always rely on its value; this branch cannot be
        reached on Windows (no fork there) (ev.c:2760) }
{$IFDEF EV_POSIX}
      c_dup2(Fd1, FEvPipe[1]);
      c_close(Fd1);
{$ELSE}
      FEvPipe[1] := Fd1;
{$ENDIF}
    end;

    FdIntern(FEvPipe[1]);

    if FEvPipe[0] < 0 then
      FPipeW.SetIo(FEvPipe[1], [evRead]) { eventfd: same fd for read and write }
    else
      FPipeW.SetIo(FEvPipe[0], [evRead]);
    IoStart(FPipeW);
    Unref; { watcher should not keep loop alive }
  end;
end;

{ ev.c:2778 evpipe_write - wake up the loop; safe from other threads and
  signal handlers }
procedure TEvLoop.EvPipeWrite(var Flag: Integer);
{$IFNDEF DARWIN}  { macOS uses the pipe path below and needs no local }
var
  {$IFDEF LINUX}
  Counter: UInt64;
  {$ELSE}
  B: Byte;
  {$ENDIF}
{$ENDIF}
begin
  EvMemoryFence; { push out the write before this function was called, acquire flag }

  if Flag <> 0 then
    Exit;

  EvAtomicSet(Flag, 1); { also acts as the release fence of C }

  EvAtomicSet(FPipeWriteSkipped, 1);

  EvMemoryFence; { make sure pipe_write_skipped is visible before we check pipe_write_wanted }

  if FPipeWriteWanted <> 0 then
  begin
    EvAtomicSet(FPipeWriteSkipped, 0);

    { the errno save/restore of C is unnecessary: we never read the global
      errno after this point }
{$IFDEF EV_POSIX}
  {$IFDEF LINUX}
    if FEvPipe[0] < 0 then
    begin
      Counter := 1;
      c_write(FEvPipe[1], @Counter, SizeOf(UInt64)); { eventfd }
    end
    else
  {$ENDIF}
      c_write(FEvPipe[1], @FEvPipe[1], 1); { pipe: one dummy byte (always on macOS) }
{$ELSE}
    { C uses WSASend here; send() on the socket is equivalent }
    B := 0;
    send(TSocket(FEvPipe[1]), B, 1, 0);
{$ENDIF}
  end;
end;

{ ev.c:2828 pipecb - called whenever the libev signal pipe got some
  events (signal, async) }
procedure TEvLoop.PipeCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  I: Integer;
{$IFDEF LINUX}
  Counter: UInt64;
{$ENDIF}
  Dummy: array[0..3] of Byte;
begin
  if evRead in REvents then
  begin
{$IFDEF EV_POSIX}
  {$IFDEF LINUX}
    if FEvPipe[0] < 0 then
      c_read(FEvPipe[1], @Counter, SizeOf(UInt64)) { eventfd }
    else
  {$ENDIF}
      c_read(FEvPipe[0], @Dummy, SizeOf(Dummy)); { pipe (always on macOS) }
{$ELSE}
    { C uses WSARecv here; recv() on the socket is equivalent }
    recv(TSocket(FEvPipe[0]), Dummy, SizeOf(Dummy), 0);
{$ENDIF}
  end;

  EvAtomicSet(FPipeWriteSkipped, 0);

  EvMemoryFence; { push out skipped, acquire flags }

  if FSigPending <> 0 then
  begin
    EvAtomicSet(FSigPending, 0);

    for I := EV_NSIG - 2 downto 0 do  { C: for (i = EV_NSIG - 1; i--; ) }
      if GSignals[I].Pending <> 0 then
        FeedSignalEvent(I + 1);
  end;

  if FAsyncPending <> 0 then
  begin
    EvAtomicSet(FAsyncPending, 0);

    for I := FAsyncCnt - 1 downto 0 do
      if FAsyncs[I].FSent <> 0 then
      begin
        EvAtomicSet(FAsyncs[I].FSent, 0);
        FeedEventW(FAsyncs[I], [evAsync]);
      end;
  end;
end;

{ ev.c:2922 ev_feed_signal_event }
procedure TEvLoop.FeedSignalEvent(SigNum: Integer);
var
  W: TEvWatcherList;
begin
  if (SigNum <= 0) or (SigNum >= EV_NSIG) then
    Exit;

  Dec(SigNum);

  { it is permissible to try to feed a signal to the wrong loop or, likely
    more useful, feeding a signal nobody is waiting for }
  if GSignals[SigNum].Loop <> Self then
    Exit;

  EvAtomicSet(GSignals[SigNum].Pending, 0);

  W := GSignals[SigNum].Head;
  while W <> nil do
  begin
    FeedEventW(W, [evSignal]);
    W := W.FNext;
  end;
end;

{$IFDEF LINUX}
{ ev.c:2947 sigfdcb - drain the signalfd, feeding each queued signal }
procedure TEvLoop.SigFdCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  Si: array[0..1] of TSignalFdSiginfo;  { these structs are big }
  Res: NativeInt;
  I: Integer;
begin
  repeat
    Res := c_read(FSigFd, @Si[0], SizeOf(Si));
    I := 0;
    while (I + 1) * SizeOf(TSignalFdSiginfo) <= Res do
    begin
      FeedSignalEvent(Integer(Si[I].ssi_signo));
      Inc(I);
    end;
  until Res < SizeOf(Si);
end;

{ ev.c:3034 timerfdcb - (re-)arm the timerfd far in the future with
  CANCEL_ON_SET; it fires only when the realtime clock jumps, letting us
  reschedule periodics }
procedure TEvLoop.TimerFdCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  Its: TItimerSpec;
begin
  FillChar(Its, SizeOf(Its), 0);
  Its.it_value.tv_sec := Trunc(FRtNow) + Trunc(MAX_BLOCKTIME2);
  c_timerfd_settime(FTimerFd, TFD_TIMER_ABSTIME or TFD_TIMER_CANCEL_ON_SET, @Its, nil);

  FRtNow := EvTime;
  PeriodicsReschedule;   { only ev_rt_now is needed }
end;

{ ev.c:3055 evtimerfd_init }
procedure TEvLoop.EvTimerFdInit;
begin
  if FTimerFdW.FActive = 0 then
  begin
    FTimerFd := c_timerfd_create(CLOCK_REALTIME, TFD_NONBLOCK or TFD_CLOEXEC);

    if FTimerFd >= 0 then
    begin
      FdIntern(FTimerFd);
      FTimerFdW.SetIo(FTimerFd, [evRead]);
      FTimerFdW.FPriority := EV_MINPRI;
      IoStart(FTimerFdW);
      Unref;  { the timerfd watcher should not keep the loop alive }
      TimerFdCb(Self, FTimerFdW, []);  { arm the timer }
    end;
  end;
end;
{$ENDIF}

{ ev.c:4215 ev_ref }
procedure TEvLoop.Ref;
begin
  Inc(FActiveCnt);
end;

{ ev.c:4221 ev_unref }
procedure TEvLoop.Unref;
begin
  Dec(FActiveCnt);
end;

{ ev.c:4209 ev_break }
procedure TEvLoop.BreakLoop(How: TEvBreakHow);
begin
  FLoopDone := Ord(How);
end;

{ ------------------------------------------------------------------ }
{ pending / feed                                                      }
{ ------------------------------------------------------------------ }

{ ev.c:2313 ev_feed_event }
procedure TEvLoop.FeedEventW(W: TEvWatcher; REvents: TEvEvents);
var
  Pri: Integer;
begin
  Pri := AbsPri(W);

  if W.FPending <> 0 then
    FPendings[Pri][W.FPending - 1].Events :=
      FPendings[Pri][W.FPending - 1].Events + REvents
  else
  begin
    Inc(FPendingCnt[Pri]);
    W.FPending := FPendingCnt[Pri];
    if W.FPending > Length(FPendings[Pri]) then
      SetLength(FPendings[Pri],
        ArrayNextSize(SizeOf(TANPending), Length(FPendings[Pri]), W.FPending));
    FPendings[Pri][W.FPending - 1].W := W;
    FPendings[Pri][W.FPending - 1].Events := REvents;
  end;

  FPendingPri := NUMPRI - 1;
end;

{ ev.c:2332 feed_reverse }
procedure TEvLoop.FeedReverse(W: TEvWatcher);
begin
  if FRFeedCnt + 1 > Length(FRFeeds) then
    SetLength(FRFeeds, ArrayNextSize(SizeOf(TEvWatcher), Length(FRFeeds), FRFeedCnt + 1));
  FRFeeds[FRFeedCnt] := W;
  Inc(FRFeedCnt);
end;

{ ev.c:2339 feed_reverse_done }
procedure TEvLoop.FeedReverseDone(REvents: TEvEvents);
begin
  repeat
    Dec(FRFeedCnt);
    FeedEventW(FRFeeds[FRFeedCnt], REvents);
  until FRFeedCnt = 0;
end;

{ ev.c:4278 clear_pending (internal, faster version) }
procedure TEvLoop.ClearPendingW(W: TEvWatcher);
begin
  if W.FPending <> 0 then
  begin
    FPendings[AbsPri(W)][W.FPending - 1].W := FPendingW;
    W.FPending := 0;
  end;
end;

{ ev.c:3756 ev_invoke_pending }
procedure TEvLoop.InvokePending;
var
  P: ^TANPending;
begin
  FPendingPri := NUMPRI;

  repeat
    Dec(FPendingPri);

    { FPendingPri possibly gets modified in the inner loop (via FeedEventW) }
    while FPendingCnt[FPendingPri] > 0 do
    begin
      Dec(FPendingCnt[FPendingPri]);
      P := @FPendings[FPendingPri][FPendingCnt[FPendingPri]];

      P^.W.FPending := 0;
      P^.W.Invoke(P^.Events);
    end;
  until FPendingPri = 0;
end;

{ EV_INVOKE_PENDING: use the override if set, else invoke pending directly }
procedure TEvLoop.DoInvokePending;
begin
  if Assigned(FInvokeCb) then
    FInvokeCb(Self)
  else
    InvokePending;
end;

{ EV_RELEASE_CB / EV_ACQUIRE_CB }
procedure TEvLoop.DoRelease;
begin
  if Assigned(FReleaseCb) then FReleaseCb(Self);
end;

procedure TEvLoop.DoAcquire;
begin
  if Assigned(FAcquireCb) then FAcquireCb(Self);
end;

{ ev.c:1103 ev_set_invoke_pending_cb }
procedure TEvLoop.SetInvokePendingCb(Cb: TEvLoopCallback);
begin
  FInvokeCb := Cb;
end;

{ ev.c:1113 ev_set_loop_release_cb }
procedure TEvLoop.SetLoopReleaseCb(Release, Acquire: TEvLoopCallback);
begin
  FReleaseCb := Release;
  FAcquireCb := Acquire;
end;

{ ev.c ev_pending_count }
function TEvLoop.PendingCount: Cardinal;
var
  Pri: Integer;
begin
  Result := 0;
  for Pri := 0 to NUMPRI - 1 do
    Inc(Result, Cardinal(FPendingCnt[Pri]));
end;

{ ------------------------------------------------------------------ }
{ fd management                                                       }
{ ------------------------------------------------------------------ }

{ ev.c:2358 fd_event_nocheck }
procedure TEvLoop.FdEventNoCheck(Fd: Integer; REvents: TEvEvents);
var
  W: TEvWatcherList;
  Ev: TEvEvents;
begin
  W := FAnFds[Fd].Head;
  while W <> nil do
  begin
    Ev := TEvIo(W).FEvents * REvents;
    if Ev <> [] then
      FeedEventW(W, Ev);
    W := W.FNext;
  end;
end;

{ ev.c:2375 fd_event - do not submit events for fds that have reify set,
  because that means they changed while we were polling for new events }
procedure TEvLoop.FdEvent(Fd: Integer; REvents: TEvEvents);
begin
  if FAnFds[Fd].Reify = 0 then
    FdEventNoCheck(Fd, REvents);
end;

{ ev.c:2384 ev_feed_fd_event }
procedure TEvLoop.FeedFdEvent(Fd: Integer; REvents: TEvEvents);
begin
  if (Fd >= 0) and (Fd < Length(FAnFds)) then
    FdEventNoCheck(Fd, REvents);
end;

{ ev.c:2393 fd_reify - make sure the external fd watch events are in-sync
  with the kernel/libev internal state }
procedure TEvLoop.FdReify;
var
  ChangeCnt, I, Fd: Integer;
  AnFd: ^TANFd;
  W: TEvWatcherList;
  OEvents: TEvEvents;
  OReify: Byte;
begin
  ChangeCnt := FFdChangeCnt;

  { the EV_SELECT_IS_WINSOCKET handle-changed block (ev.c:2409) is skipped:
    with our identity mapping (handle == fd) that case cannot occur }

  for I := 0 to ChangeCnt - 1 do
  begin
    Fd := FFdChanges[I];
    AnFd := @FAnFds[Fd];

    OEvents := AnFd^.Events;
    OReify := AnFd^.Reify;

    AnFd^.Reify := 0;

    AnFd^.Events := [];
    W := AnFd^.Head;
    while W <> nil do
    begin
      AnFd^.Events := AnFd^.Events + TEvIo(W).FEvents;
      W := W.FNext;
    end;

    if OEvents <> AnFd^.Events then
      OReify := ANFD_IOFDSET; { actually |= (ev.c:2453) }

    if (OReify and ANFD_IOFDSET) <> 0 then
      FBackend.Modify(Fd, OEvents, AnFd^.Events);
  end;

  { normally fdchangecnt hasn't changed; if it has, new fds have been added
    during poll, move them to the front (ev.c:2460) }
  if FFdChangeCnt <> ChangeCnt then
    Move(FFdChanges[ChangeCnt], FFdChanges[0],
      (FFdChangeCnt - ChangeCnt) * SizeOf(Integer));

  Dec(FFdChangeCnt, ChangeCnt);
end;

{ ev.c:2473 fd_change - something about the given fd changed }
procedure TEvLoop.FdChange(Fd: Integer; Flags: Byte);
var
  Reify: Byte;
begin
  Reify := FAnFds[Fd].Reify;
  FAnFds[Fd].Reify := Reify or Flags;

  if Reify = 0 then
  begin
    Inc(FFdChangeCnt);
    if FFdChangeCnt > Length(FFdChanges) then
      SetLength(FFdChanges,
        ArrayNextSize(SizeOf(Integer), Length(FFdChanges), FFdChangeCnt));
    FFdChanges[FFdChangeCnt - 1] := Fd;
  end;
end;

{ ev.c:2488 fd_kill - the fd is invalid/unusable, stop its watchers }
procedure TEvLoop.FdKill(Fd: Integer);
var
  W: TEvWatcherList;
begin
  while FAnFds[Fd].Head <> nil do
  begin
    W := FAnFds[Fd].Head;
    IoStop(TEvIo(W));
    FeedEventW(W, [evError, evRead, evWrite]);
  end;
end;

{ ev.c:2513 fd_ebadf - called on EBADF to verify fds }
procedure TEvLoop.FdEbadf;
var
  Fd: Integer;
begin
  for Fd := 0 to Length(FAnFds) - 1 do
    if FAnFds[Fd].Events <> [] then
      if not FdValid(Fd) then
        FdKill(Fd);
end;

{ ev.c:2526 fd_enomem - called on ENOMEM to kill some fds and retry }
procedure TEvLoop.FdEnomem;
var
  Fd: Integer;
begin
  for Fd := Length(FAnFds) - 1 downto 0 do
    if FAnFds[Fd].Events <> [] then
    begin
      FdKill(Fd);
      Break;
    end;
end;

{$IFDEF LINUX}
{ ev.c:2541 fd_rearm_all - usually called after fork if the backend needs
  to re-arm all fds from scratch }
procedure TEvLoop.FdRearmAll;
var
  Fd: Integer;
begin
  for Fd := 0 to Length(FAnFds) - 1 do
    if FAnFds[Fd].Events <> [] then
    begin
      FAnFds[Fd].Events := [];
      FAnFds[Fd].EMask := 0;
      FdChange(Fd, ANFD_IOFDSET or ANFD_REIFY);
    end;
end;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ watcher start/stop core                                             }
{ ------------------------------------------------------------------ }

{ ev.c:4305 pri_adjust }
procedure TEvLoop.PriAdjust(W: TEvWatcher);
var
  Pri: Integer;
begin
  Pri := W.FPriority;
  if Pri < EV_MINPRI then Pri := EV_MINPRI;
  if Pri > EV_MAXPRI then Pri := EV_MAXPRI;
  W.FPriority := Pri;
end;

{ ev.c:4314 ev_start }
procedure TEvLoop.EvStart(W: TEvWatcher; Active: Integer);
begin
  PriAdjust(W);
  W.FActive := Active;
  Ref;
end;

{ ev.c:4322 ev_stop }
procedure TEvLoop.EvStop(W: TEvWatcher);
begin
  Unref;
  W.FActive := 0;
end;

{ ev.c:4332 ev_io_start }
procedure TEvLoop.IoStart(W: TEvIo);
var
  Fd, OldLen: Integer;
begin
  Fd := W.FFd;

  if W.FActive <> 0 then
    Exit;

  EvAssert(Fd >= 0, 'ev_io_start called with negative fd');
  EvAssert(W.FEvents - [evIoFdSet, evRead, evWrite] = [],
    'ev_io_start called with illegal event mask');

  EvStart(W, 1);

  { array_needsize (ANFD, anfds, anfdmax, fd + 1, array_needsize_zerofill) }
  if Fd + 1 > Length(FAnFds) then
  begin
    OldLen := Length(FAnFds);
    SetLength(FAnFds, ArrayNextSize(SizeOf(TANFd), OldLen, Fd + 1));
    FillChar(FAnFds[OldLen], (Length(FAnFds) - OldLen) * SizeOf(TANFd), 0);
  end;

  WListAdd(FAnFds[Fd].Head, W);

  { common bug, apparently (ev.c:4352) }
  EvAssert(W.FNext <> W, 'ev_io_start called with corrupted watcher');

  if evIoFdSet in W.FEvents then
    FdChange(Fd, ANFD_IOFDSET or ANFD_REIFY)
  else
    FdChange(Fd, ANFD_REIFY);
  W.FEvents := W.FEvents - [evIoFdSet];
end;

{ ev.c:4362 ev_io_stop }
procedure TEvLoop.IoStop(W: TEvIo);
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  EvAssert((W.FFd >= 0) and (W.FFd < Length(FAnFds)),
    'ev_io_stop called with illegal fd (must stay constant after start!)');

  WListDel(FAnFds[W.FFd].Head, W);
  EvStop(W);

  FdChange(W.FFd, ANFD_REIFY);
end;

{ ev.c:4385 ev_timer_start }
procedure TEvLoop.TimerStart(W: TEvTimer);
begin
  if W.FActive <> 0 then
    Exit;

  W.FAt := W.FAt + FMnNow;

  EvAssert(W.FRepeat >= 0, 'ev_timer_start called with negative timer repeat value');

  Inc(FTimerCnt);
  EvStart(W, FTimerCnt + HEAP0 - 1);
  if W.FActive + 1 > Length(FTimers) then
    SetLength(FTimers, ArrayNextSize(SizeOf(TANHE), Length(FTimers), W.FActive + 1));
  FTimers[W.FActive].W := W;
  FTimers[W.FActive].At := W.FAt; { ANHE_at_cache }
  UpHeap(FTimers, W.FActive);
end;

{ ev.c:4410 ev_timer_stop }
procedure TEvLoop.TimerStop(W: TEvTimer);
var
  Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Active := W.FActive;

  EvAssert(FTimers[Active].W = W, 'internal timer heap corruption');

  Dec(FTimerCnt);

  if Active < FTimerCnt + HEAP0 then
  begin
    FTimers[Active] := FTimers[FTimerCnt + HEAP0];
    AdjustHeap(FTimers, FTimerCnt, Active);
  end;

  W.FAt := W.FAt - FMnNow;

  EvStop(W);
end;

{ ev.c:4441 ev_timer_again }
procedure TEvLoop.TimerAgain(W: TEvTimer);
begin
  ClearPendingW(W);

  if W.FActive <> 0 then
  begin
    if W.FRepeat <> 0 then
    begin
      W.FAt := FMnNow + W.FRepeat;
      FTimers[W.FActive].At := W.FAt; { ANHE_at_cache }
      AdjustHeap(FTimers, FTimerCnt, W.FActive);
    end
    else
      TimerStop(W);
  end
  else if W.FRepeat <> 0 then
  begin
    W.FAt := W.FRepeat;
    TimerStart(W);
  end;
end;

{ ev.c:4476 ev_periodic_start }
procedure TEvLoop.PeriodicStart(W: TEvPeriodic);
begin
  if W.FActive <> 0 then
    Exit;

{$IFDEF LINUX}
  { ev.c:4481 - create the timerfd for time-jump detection on first periodic }
  if FTimerFd = -2 then
    EvTimerFdInit;
{$ENDIF}

  if Assigned(W.FRescheduleCb) then
    W.FAt := W.FRescheduleCb(W, FRtNow)
  else if W.FInterval <> 0 then
  begin
    EvAssert(W.FInterval >= 0, 'ev_periodic_start called with negative interval value');
    PeriodicRecalc(W);
  end
  else
    W.FAt := W.FOffset;

  Inc(FPeriodicCnt);
  EvStart(W, FPeriodicCnt + HEAP0 - 1);
  if W.FActive + 1 > Length(FPeriodics) then
    SetLength(FPeriodics, ArrayNextSize(SizeOf(TANHE), Length(FPeriodics), W.FActive + 1));
  FPeriodics[W.FActive].W := W;
  FPeriodics[W.FActive].At := W.FAt; { ANHE_at_cache }
  UpHeap(FPeriodics, W.FActive);
end;

{ ev.c:4512 ev_periodic_stop }
procedure TEvLoop.PeriodicStop(W: TEvPeriodic);
var
  Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Active := W.FActive;

  EvAssert(FPeriodics[Active].W = W, 'internal periodic heap corruption');

  Dec(FPeriodicCnt);

  if Active < FPeriodicCnt + HEAP0 then
  begin
    FPeriodics[Active] := FPeriodics[FPeriodicCnt + HEAP0];
    AdjustHeap(FPeriodics, FPeriodicCnt, Active);
  end;

  EvStop(W);
end;

{ ev_idle_start (ev.c, EV_IDLE_ENABLE) }
procedure TEvLoop.IdleStart(W: TEvIdle);
var
  Pri: Integer;
begin
  if W.FActive <> 0 then
    Exit;

  PriAdjust(W); { clamp before entering the per-priority arrays }
  Pri := AbsPri(W);

  Inc(FIdleCnt[Pri]);
  EvStart(W, FIdleCnt[Pri]);
  if FIdleCnt[Pri] > Length(FIdles[Pri]) then
    SetLength(FIdles[Pri],
      ArrayNextSize(SizeOf(TEvIdle), Length(FIdles[Pri]), FIdleCnt[Pri]));
  FIdles[Pri][FIdleCnt[Pri] - 1] := W;
  Inc(FIdleAll);
end;

{ ev_idle_stop (ev.c) }
procedure TEvLoop.IdleStop(W: TEvIdle);
var
  Pri, Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Pri := AbsPri(W);
  Active := W.FActive;

  Dec(FIdleCnt[Pri]);
  FIdles[Pri][Active - 1] := FIdles[Pri][FIdleCnt[Pri]];
  FIdles[Pri][Active - 1].FActive := Active;

  EvStop(W);
  Dec(FIdleAll);
end;

{ ev_prepare_start (ev.c) }
procedure TEvLoop.PrepareStart(W: TEvPrepare);
begin
  if W.FActive <> 0 then
    Exit;

  Inc(FPrepareCnt);
  EvStart(W, FPrepareCnt);
  if FPrepareCnt > Length(FPrepares) then
    SetLength(FPrepares,
      ArrayNextSize(SizeOf(TEvPrepare), Length(FPrepares), FPrepareCnt));
  FPrepares[FPrepareCnt - 1] := W;
end;

{ ev_prepare_stop (ev.c) }
procedure TEvLoop.PrepareStop(W: TEvPrepare);
var
  Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Active := W.FActive;

  Dec(FPrepareCnt);
  FPrepares[Active - 1] := FPrepares[FPrepareCnt];
  FPrepares[Active - 1].FActive := Active;

  EvStop(W);
end;

{ ev_check_start (ev.c) }
procedure TEvLoop.CheckStart(W: TEvCheck);
begin
  if W.FActive <> 0 then
    Exit;

  Inc(FCheckCnt);
  EvStart(W, FCheckCnt);
  if FCheckCnt > Length(FChecks) then
    SetLength(FChecks,
      ArrayNextSize(SizeOf(TEvCheck), Length(FChecks), FCheckCnt));
  FChecks[FCheckCnt - 1] := W;
end;

{ ev_check_stop (ev.c) }
procedure TEvLoop.CheckStop(W: TEvCheck);
var
  Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Active := W.FActive;

  Dec(FCheckCnt);
  FChecks[Active - 1] := FChecks[FCheckCnt];
  FChecks[Active - 1].FActive := Active;

  EvStop(W);
end;

{ ev.c:5319 ev_fork_start }
procedure TEvLoop.ForkStart(W: TEvFork);
begin
  if W.FActive <> 0 then
    Exit;

  Inc(FForkCnt);
  EvStart(W, FForkCnt);
  if FForkCnt > Length(FForks) then
    SetLength(FForks,
      ArrayNextSize(SizeOf(TEvFork), Length(FForks), FForkCnt));
  FForks[FForkCnt - 1] := W;
end;

{ ev.c:5334 ev_fork_stop }
procedure TEvLoop.ForkStop(W: TEvFork);
var
  Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Active := W.FActive;

  Dec(FForkCnt);
  FForks[Active - 1] := FForks[FForkCnt];
  FForks[Active - 1].FActive := Active;

  EvStop(W);
end;

{ ev.c:5357 ev_cleanup_start }
procedure TEvLoop.CleanupStart(W: TEvCleanup);
begin
  if W.FActive <> 0 then
    Exit;

  Inc(FCleanupCnt);
  EvStart(W, FCleanupCnt);
  if FCleanupCnt > Length(FCleanups) then
    SetLength(FCleanups,
      ArrayNextSize(SizeOf(TEvCleanup), Length(FCleanups), FCleanupCnt));
  FCleanups[FCleanupCnt - 1] := W;

  { cleanup watchers should never keep a refcount on the loop }
  Unref;
end;

{ ev.c:5374 ev_cleanup_stop }
procedure TEvLoop.CleanupStop(W: TEvCleanup);
var
  Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Ref;

  Active := W.FActive;

  Dec(FCleanupCnt);
  FCleanups[Active - 1] := FCleanups[FCleanupCnt];
  FCleanups[Active - 1].FActive := Active;

  EvStop(W);
end;

{ ev.c:5023 ev_stat_start }
procedure TEvLoop.StatStart(W: TEvStat);
begin
  if W.FActive <> 0 then
    Exit;

  W.StatNow;

  if (W.FInterval < MIN_STAT_INTERVAL) and (W.FInterval <> 0) then
    W.FInterval := MIN_STAT_INTERVAL;

  { ev_timer_init (&w->timer, stat_timer_cb, 0., interval) }
  if W.FInterval <> 0 then
    W.FTimer.SetTimer(0, W.FInterval)
  else
    W.FTimer.SetTimer(0, DEF_STAT_INTERVAL);
  W.FTimer.FPriority := W.FPriority;
  W.FTimer.FLoop := Self;

  { ev.c:5036 infy_init / infy_add }
{$IFDEF LINUX}
  InfyInit;

  if FFsFd >= 0 then
    InfyAdd(W) { rearms the timer itself, with inotify-aware intervals }
  else
{$ENDIF}
  begin
    TimerAgain(W.FTimer);
    Unref;
  end;

  EvStart(W, 1);
end;

{ ev.c:5054 ev_stat_stop }
procedure TEvLoop.StatStop(W: TEvStat);
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

{$IFDEF LINUX}
  InfyDel(W); { ev.c:5063 }
{$ENDIF}

  if W.FTimer.IsActive then
  begin
    Ref;
    TimerStop(W.FTimer);
  end;

  EvStop(W);
end;

{ ev.c:5398 ev_async_start }
procedure TEvLoop.AsyncStart(W: TEvAsync);
begin
  if W.FActive <> 0 then
    Exit;

  W.FSent := 0;

  EvPipeInit;

  Inc(FAsyncCnt);
  EvStart(W, FAsyncCnt);
  if FAsyncCnt > Length(FAsyncs) then
    SetLength(FAsyncs,
      ArrayNextSize(SizeOf(TEvAsync), Length(FAsyncs), FAsyncCnt));
  FAsyncs[FAsyncCnt - 1] := W;
end;

{ ev.c:5417 ev_async_stop }
procedure TEvLoop.AsyncStop(W: TEvAsync);
var
  Active: Integer;
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  Active := W.FActive;

  Dec(FAsyncCnt);
  FAsyncs[Active - 1] := FAsyncs[FAsyncCnt];
  FAsyncs[Active - 1].FActive := Active;

  EvStop(W);
end;

{ ev.c:5438 ev_async_send }
procedure TEvLoop.AsyncSend(W: TEvAsync);
begin
  EvAtomicSet(W.FSent, 1);
  EvPipeWrite(FAsyncPending);
end;

{ ev.c:4557 ev_signal_start }
procedure TEvLoop.SignalStart(W: TEvSignal);
{$IFDEF EV_POSIX}
var
  Sa: TEvSigAction;
{$ENDIF}
begin
  if W.FActive <> 0 then
    Exit;

  EvAssert((W.FSigNum > 0) and (W.FSigNum < EV_NSIG),
    'ev_signal_start called with illegal signal number');

  EvAssert((GSignals[W.FSigNum - 1].Loop = nil) or (GSignals[W.FSigNum - 1].Loop = Self),
    'a signal must not be attached to two different loops');

  GSignals[W.FSigNum - 1].Loop := Self;
  EvMemoryFence; { ECB_MEMORY_FENCE_RELEASE }

{$IFDEF LINUX}
  { ev.c:4574 signalfd path (when EVFLAG_SIGNALFD is set) }
  if FSigFd = -2 then
  begin
    FSigFd := c_signalfd(-1, @FSigFdSet, SFD_NONBLOCK or SFD_CLOEXEC);
    if (FSigFd < 0) and (GetErrno = ERRNO_EINVAL) then
      FSigFd := c_signalfd(-1, @FSigFdSet, 0); { retry without flags }
    if FSigFd >= 0 then
    begin
      FdIntern(FSigFd);
      c_sigemptyset(@FSigFdSet);
      FSigFdW.SetIo(FSigFd, [evRead]);
      FSigFdW.FPriority := EV_MAXPRI;
      IoStart(FSigFdW);
      Unref;  { the signalfd watcher should not keep the loop alive }
    end;
  end;

  if FSigFd >= 0 then
  begin
    c_sigaddset(@FSigFdSet, W.FSigNum);
    c_sigprocmask(SIG_BLOCK, @FSigFdSet, nil);
    c_signalfd(FSigFd, @FSigFdSet, 0);
  end;
{$ENDIF}

  EvStart(W, 1);
  WListAdd(GSignals[W.FSigNum - 1].Head, W);

  if W.FNext = nil then
  begin
{$IFDEF EV_POSIX}
  {$IFDEF LINUX}
    if FSigFd < 0 then  { only install a sigaction handler when not using signalfd }
  {$ENDIF}
    begin
      EvPipeInit;
      { install the raw handler via sigaction (ev.c:4617) }
      FillChar(Sa, SizeOf(Sa), 0);
  {$IFDEF FPC}
      Sa.sa_handler := SigActionHandler(@EvSigHandler);
  {$ELSE}
      Sa.sa_handler := @EvSigHandler;
  {$ENDIF}
      FillChar(Sa.sa_mask, SizeOf(Sa.sa_mask), $FF); { sigfillset }
      Sa.sa_flags := SA_RESTART; { if restarting works we save one iteration }
      c_sigaction(W.FSigNum, @Sa, nil);
      { the EVFLAG_NOSIGMASK unblock (ev.c:4626) is not ported: we never
        modify the signal mask outside signalfd }
    end;
{$ELSE}
    EvPipeInit;
    { Windows has only the CRT signal() (ev.c:4615) }
    msvcrt_signal(W.FSigNum, @EvSigHandler);
{$ENDIF}
  end;
end;

{ ev.c:4640 ev_signal_stop }
procedure TEvLoop.SignalStop(W: TEvSignal);
{$IFDEF LINUX}
var
  Ss: TEvSigSet;
{$ENDIF}
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  WListDel(GSignals[W.FSigNum - 1].Head, W);
  EvStop(W);

  if GSignals[W.FSigNum - 1].Head = nil then
  begin
    GSignals[W.FSigNum - 1].Loop := nil; { unattach from signal }
{$IFDEF EV_POSIX}
  {$IFDEF LINUX}
    if FSigFd >= 0 then
    begin
      { ev.c:4656 - drop this signal from the signalfd mask and unblock it }
      c_sigemptyset(@Ss);
      c_sigaddset(@Ss, W.FSigNum);
      c_sigdelset(@FSigFdSet, W.FSigNum);
      c_signalfd(FSigFd, @FSigFdSet, 0);
      c_sigprocmask(SIG_UNBLOCK, @Ss, nil);
    end
    else
  {$ENDIF}
      c_signal(W.FSigNum, Pointer(SIG_DFL));
{$ELSE}
    msvcrt_signal(W.FSigNum, Pointer(SIG_DFL));
{$ENDIF}
  end;
end;

{$IFDEF LINUX}
{ ev.c:4681 ev_child_start }
procedure TEvLoop.ChildStart(W: TEvChild);
begin
  EvAssert(IsDefaultLoop, 'child watchers are only supported in the default loop');

  if W.FActive <> 0 then
    Exit;

  EvStart(W, 1);
  WListAdd(GChilds[W.FPid and (EV_PID_HASHSIZE - 1)], W);
end;

{ ev.c:4698 ev_child_stop }
procedure TEvLoop.ChildStop(W: TEvChild);
begin
  ClearPendingW(W);
  if W.FActive = 0 then
    Exit;

  WListDel(GChilds[W.FPid and (EV_PID_HASHSIZE - 1)], W);
  EvStop(W);
end;

{ ev.c:2981 child_reap - handle a single child status event }
procedure TEvLoop.ChildReap(Chain, APid, Status: Integer);
var
  W: TEvWatcherList;
  C: TEvChild;
  Traced: Boolean;
begin
  Traced := WIfStopped(Status) or WIfContinued(Status);

  W := GChilds[Chain and (EV_PID_HASHSIZE - 1)];
  while W <> nil do
  begin
    C := TEvChild(W);

    if ((C.FPid = APid) or (C.FPid = 0)) and ((not Traced) or ((C.FFlags and 1) <> 0)) then
    begin
      { need to do it *now*, this *must* be the same prio as the signal
        watcher itself }
      C.FPriority := EV_MAXPRI;
      C.FRPid := APid;
      C.FRStatus := Status;
      FeedEventW(C, [evChild]);
    end;

    W := W.FNext;
  end;
end;

{ ev.c:3005 childcb - called on sigchld etc., calls waitpid }
procedure TEvLoop.ChildCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  APid, Status: Integer;
begin
  { some systems define WCONTINUED but then fail to support it (linux 2.4) }
  APid := c_waitpid(-1, @Status, WNOHANG or WUNTRACED or WCONTINUED);
  if APid <= 0 then
  begin
    if GetRtlErrno <> ERRNO_EINVAL then  { c_waitpid is an RTL binding on FPC }
      Exit;
    APid := c_waitpid(-1, @Status, WNOHANG or WUNTRACED);
    if APid <= 0 then
      Exit;
  end;

  { make sure we are called again until all children have been reaped; we
    need to do it this way so that the callback gets called before we
    continue }
  FeedEventW(Watcher, [evSignal]);

  ChildReap(APid, APid, Status);
  ChildReap(0, APid, Status); { this might trigger a watcher twice, but feed_event catches that }
end;

{ ------------------------------------------------------------------ }
{ inotify fast path for stat watchers                                 }
{ ------------------------------------------------------------------ }

{ ev.c:4734 infy_add }
procedure TEvLoop.InfyAdd(W: TEvStat);
var
  Path8: UTF8String;
  Sfs: TLinuxStatFs;
  Mask: Cardinal;
  Err, Pend, I: Integer;
begin
  Path8 := UTF8String(W.FPath);

  W.FWd := c_inotify_add_watch(FFsFd, PAnsiChar(Path8),
    IN_ATTRIB or IN_DELETE_SELF or IN_MOVE_SELF or IN_MODIFY
    or IN_CREATE or IN_DELETE or IN_MOVED_FROM or IN_MOVED_TO
    or IN_DONT_FOLLOW or IN_MASK_ADD);

  if W.FWd >= 0 then
  begin
    { now local changes will be tracked by inotify, but remote changes
      won't; unless the filesystem is known to be local, we therefore
      still poll; also do poll on < 2.6.25, but with normal frequency }
    if FFs2625 = 0 then
    begin
      if W.FInterval <> 0 then
        W.FTimer.FRepeat := W.FInterval
      else
        W.FTimer.FRepeat := DEF_STAT_INTERVAL;
    end
    else if (c_statfs(PAnsiChar(Path8), @Sfs) = 0)
      and ((Sfs.f_type = $1373)      { devfs }
        or (Sfs.f_type = $4006)      { fat }
        or (Sfs.f_type = $4d44)      { msdos }
        or (Sfs.f_type = $EF53)      { ext2/3 }
        or (Sfs.f_type = $72b6)      { jffs2 }
        or (Sfs.f_type = $858458f6)  { ramfs }
        or (Sfs.f_type = $5346544e)  { ntfs }
        or (Sfs.f_type = $3153464a)  { jfs }
        or (Sfs.f_type = $9123683e)  { btrfs }
        or (Sfs.f_type = $52654973)  { reiser3 }
        or (Sfs.f_type = $01021994)  { tmpfs }
        or (Sfs.f_type = $58465342)) { xfs }
    then
      W.FTimer.FRepeat := 0 { filesystem is local, kernel new enough }
    else
    begin
      { remote fs, use reduced polling frequency }
      if W.FInterval <> 0 then
        W.FTimer.FRepeat := W.FInterval
      else
        W.FTimer.FRepeat := NFS_STAT_INTERVAL;
    end;
  end
  else
  begin
    { can't use inotify, continue to stat }
    if W.FInterval <> 0 then
      W.FTimer.FRepeat := W.FInterval
    else
      W.FTimer.FRepeat := DEF_STAT_INTERVAL;

    { if path is not there, monitor some parent directory for speedup
      hints; note that exceeding the hardcoded path limit is not a
      correctness issue in C, and no limit applies here }
    Err := GetRtlErrno;  { c_inotify_add_watch is an RTL binding on FPC }
    if (Err = ERRNO_ENOENT) or (Err = ERRNO_EACCES) then
    begin
      repeat
        if GetRtlErrno = ERRNO_EACCES then
          Mask := IN_MASK_ADD or IN_DELETE_SELF or IN_MOVE_SELF or IN_ATTRIB
        else
          Mask := IN_MASK_ADD or IN_DELETE_SELF or IN_MOVE_SELF
            or IN_CREATE or IN_MOVED_TO;

        { char *pend = strrchr (path, '/') }
        Pend := 0;
        for I := Length(Path8) downto 1 do
          if Path8[I] = '/' then
          begin
            Pend := I;
            Break;
          end;

        if Pend <= 1 then { no '/' at all, or only the root slash }
          Break;

        SetLength(Path8, Pend - 1);
        W.FWd := c_inotify_add_watch(FFsFd, PAnsiChar(Path8), Mask);

        Err := GetRtlErrno;
      until not ((W.FWd < 0) and ((Err = ERRNO_ENOENT) or (Err = ERRNO_EACCES)));
    end;
  end;

  if W.FWd >= 0 then
    WListAdd(FFsHash[W.FWd and (EV_INOTIFY_HASHSIZE - 1)], W);

  { now re-arm timer, if required }
  if W.FTimer.IsActive then Ref;
  TimerAgain(W.FTimer);
  if W.FTimer.IsActive then Unref;
end;

{ ev.c:4809 infy_del }
procedure TEvLoop.InfyDel(W: TEvStat);
var
  Slot, Wd: Integer;
begin
  Wd := W.FWd;
  if Wd < 0 then
    Exit;

  W.FWd := -2;
  Slot := Wd and (EV_INOTIFY_HASHSIZE - 1);
  WListDel(FFsHash[Slot], W);

  { remove this watcher, if others are watching it, they will rearm }
  c_inotify_rm_watch(FFsFd, Wd);
end;

{ ev.c:4827 infy_wd }
procedure TEvLoop.InfyWd(Slot, Wd: Integer; Ev: PInotifyEvent);
var
  S: Integer;
  WL: TEvWatcherList;
  W: TEvStat;
begin
  if Slot < 0 then
  begin
    { overflow, need to check for all hash slots }
    for S := 0 to EV_INOTIFY_HASHSIZE - 1 do
      InfyWd(S, Wd, Ev);
  end
  else
  begin
    WL := FFsHash[Slot and (EV_INOTIFY_HASHSIZE - 1)];
    while WL <> nil do
    begin
      W := TEvStat(WL);
      WL := WL.FNext; { lets us remove this watcher and all before it }

      if (W.FWd = Wd) or (Wd = -1) then
      begin
        if (Ev^.Mask and (IN_IGNORED or IN_UNMOUNT or IN_DELETE_SELF)) <> 0 then
        begin
          WListDel(FFsHash[Slot and (EV_INOTIFY_HASHSIZE - 1)], W);
          W.FWd := -1;
          InfyAdd(W); { re-add, no matter what }
        end;

        { stat_timer_cb (EV_A_ &w->timer, 0) }
        W.TimerCb(Self, W.FTimer, []);
      end;
    end;
  end;
end;

{ ev.c:4858 infy_cb }
procedure TEvLoop.InfyCb(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  Buf: array[0..EV_INOTIFY_BUFSIZE - 1] of Byte;
  Ofs, Len: Integer;
  Ev: PInotifyEvent;
begin
  Len := c_read(FFsFd, @Buf, SizeOf(Buf));

  Ofs := 0;
  while Ofs < Len do
  begin
    Ev := PInotifyEvent(@Buf[Ofs]);
    InfyWd(Ev^.Wd, Ev^.Wd, Ev);
    Ofs := Ofs + SizeOf(TInotifyEvent) + Integer(Ev^.Len);
  end;
end;

{ ev.c:4897 infy_init }
procedure TEvLoop.InfyInit;
begin
  if FFsFd <> -2 then
    Exit;

  FFsFd := -1;

  { ev.c:4874 ev_check_2625: kernels < 2.6.25 are borked }
  if EvLinuxVersion >= $020619 then
    FFs2625 := 1;

  FFsFd := InfyNewFd;

  if FFsFd >= 0 then
  begin
    FdIntern(FFsFd);
    FFsW.SetIo(FFsFd, [evRead]);
    FFsW.FPriority := EV_MAXPRI;
    IoStart(FFsW);
    Unref;
  end;
end;

{ ev.c:4919 infy_fork }
procedure TEvLoop.InfyFork;
var
  Slot: Integer;
  WL: TEvWatcherList;
  W: TEvStat;
begin
  if FFsFd < 0 then
    Exit;

  Ref;
  IoStop(FFsW);
  c_close(FFsFd);
  FFsFd := InfyNewFd;

  if FFsFd >= 0 then
  begin
    FdIntern(FFsFd);
    FFsW.SetIo(FFsFd, [evRead]);
    IoStart(FFsW);
    Unref;
  end;

  for Slot := 0 to EV_INOTIFY_HASHSIZE - 1 do
  begin
    WL := FFsHash[Slot];
    FFsHash[Slot] := nil;

    while WL <> nil do
    begin
      W := TEvStat(WL);
      WL := WL.FNext; { lets us add this watcher }

      W.FWd := -1;

      if FFsFd >= 0 then
        InfyAdd(W) { re-add, no matter what }
      else
      begin
        if W.FInterval <> 0 then
          W.FTimer.FRepeat := W.FInterval
        else
          W.FTimer.FRepeat := DEF_STAT_INTERVAL;
        if W.FTimer.IsActive then Ref;
        TimerAgain(W.FTimer);
        if W.FTimer.IsActive then Unref;
      end;
    end;
  end;
end;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ consistency checks (EV_VERIFY)                                      }
{ ------------------------------------------------------------------ }

{ ev.c:3571 verify_watcher }
procedure TEvLoop.VerifyWatcher(W: TEvWatcher);
begin
  EvAssert((AbsPri(W) >= 0) and (AbsPri(W) < NUMPRI),
    'watcher has invalid priority');

  if W.FPending <> 0 then
    EvAssert(FPendings[AbsPri(W)][W.FPending - 1].W = W,
      'pending watcher not on pending queue');
end;

{ ev.c:3581 verify_heap }
procedure TEvLoop.VerifyHeap(const Heap: TANHEArray; N: Integer);
var
  I: Integer;
begin
  for I := HEAP0 to N + HEAP0 - 1 do
  begin
    EvAssert(Heap[I].W.FActive = I, 'active index mismatch in heap');
    EvAssert((I = HEAP0)
      or (Heap[((I - HEAP0 - 1) div DHEAP) + HEAP0].At <= Heap[I].At),
      'heap condition violated');
    EvAssert(Heap[I].At = Heap[I].W.FAt, 'heap at cache mismatch');

    VerifyWatcher(Heap[I].W);
  end;
end;

{ ev.c:3609 ev_verify; the "max >= cnt" asserts of C map to Length(arr)
  checks here; array_verify (ev.c:3597) is inlined per typed array }
procedure TEvLoop.Verify;
var
  I, J: Integer;
  W, W2: TEvWatcherList;
begin
  EvAssert(FActiveCnt >= -1, 'activecnt out of range');

  EvAssert(Length(FFdChanges) >= FFdChangeCnt, 'fdchanges overflow');
  for I := 0 to FFdChangeCnt - 1 do
    EvAssert(FFdChanges[I] >= 0, 'negative fd in fdchanges');

  for I := 0 to Length(FAnFds) - 1 do
  begin
    J := 0;
    W := FAnFds[I].Head;
    W2 := W;
    while W <> nil do
    begin
      VerifyWatcher(W);

      if (J and 1) <> 0 then
      begin
        EvAssert(W <> W2, 'io watcher list contains a loop');
        W2 := W2.FNext;
      end;
      Inc(J);

      EvAssert(W.FActive = 1, 'inactive fd watcher on anfd list');
      EvAssert(TEvIo(W).FFd = I, 'fd mismatch between watcher and anfd');

      W := W.FNext;
    end;
  end;

  EvAssert((Length(FTimers) = 0) or (Length(FTimers) >= FTimerCnt + HEAP0),
    'timer heap overflow');
  VerifyHeap(FTimers, FTimerCnt);

  EvAssert((Length(FPeriodics) = 0) or (Length(FPeriodics) >= FPeriodicCnt + HEAP0),
    'periodic heap overflow');
  VerifyHeap(FPeriodics, FPeriodicCnt);

  for I := NUMPRI - 1 downto 0 do
  begin
    EvAssert(Length(FPendings[I]) >= FPendingCnt[I], 'pendings overflow');
    EvAssert(FIdleAll >= 0, 'negative idleall');
    EvAssert(Length(FIdles[I]) >= FIdleCnt[I], 'idles overflow');
    for J := FIdleCnt[I] - 1 downto 0 do
    begin
      EvAssert(FIdles[I][J].FActive = J + 1, 'active index mismatch');
      VerifyWatcher(FIdles[I][J]);
    end;
  end;

  EvAssert(Length(FForks) >= FForkCnt, 'forks overflow');
  for J := FForkCnt - 1 downto 0 do
  begin
    EvAssert(FForks[J].FActive = J + 1, 'active index mismatch');
    VerifyWatcher(FForks[J]);
  end;

  EvAssert(Length(FCleanups) >= FCleanupCnt, 'cleanups overflow');
  for J := FCleanupCnt - 1 downto 0 do
  begin
    EvAssert(FCleanups[J].FActive = J + 1, 'active index mismatch');
    VerifyWatcher(FCleanups[J]);
  end;

  EvAssert(Length(FAsyncs) >= FAsyncCnt, 'asyncs overflow');
  for J := FAsyncCnt - 1 downto 0 do
  begin
    EvAssert(FAsyncs[J].FActive = J + 1, 'active index mismatch');
    VerifyWatcher(FAsyncs[J]);
  end;

  EvAssert(Length(FPrepares) >= FPrepareCnt, 'prepares overflow');
  for J := FPrepareCnt - 1 downto 0 do
  begin
    EvAssert(FPrepares[J].FActive = J + 1, 'active index mismatch');
    VerifyWatcher(FPrepares[J]);
  end;

  EvAssert(Length(FChecks) >= FCheckCnt, 'checks overflow');
  for J := FCheckCnt - 1 downto 0 do
  begin
    EvAssert(FChecks[J].FActive = J + 1, 'active index mismatch');
    VerifyWatcher(FChecks[J]);
  end;
end;

{ ------------------------------------------------------------------ }
{ ev_once (ev.c:5447-5505)                                            }
{ ------------------------------------------------------------------ }

type
  { ev.c:5447 struct ev_once - owns an io and a timer watcher; whichever
    fires first cancels the other, then the object frees itself }
  TEvOnce = class
  private
    FLoop: TEvLoop;
    FIo: TEvIo;
    FTimer: TEvTimer;
    FCb: TEvOnceCallback;
    procedure Done(REvents: TEvEvents);  { ev.c:5456 once_cb }
    procedure IoCb(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);    { ev.c:5469 once_cb_io }
    procedure TimerCb(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents); { ev.c:5477 once_cb_to }
  end;

{ ev.c:5456 once_cb }
procedure TEvOnce.Done(REvents: TEvEvents);
var
  Cb: TEvOnceCallback;
begin
  Cb := FCb; { grab the callback before freeing ourselves }

  FIo.Stop;
  FTimer.Stop;
  FIo.Free;
  FTimer.Free;
  Free;

  Cb(REvents);
end;

procedure TEvOnce.IoCb(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Done(REvents + FTimer.ClearPending);
end;

procedure TEvOnce.TimerCb(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Done(REvents + FIo.ClearPending);
end;

{ ev.c:5485 ev_once }
procedure TEvLoop.Once(Fd: Integer; Events: TEvEvents; Timeout: TEvTstamp;
  ACallback: TEvOnceCallback);
var
  OnceObj: TEvOnce;
begin
  OnceObj := TEvOnce.Create;
  OnceObj.FLoop := Self;
  OnceObj.FCb := ACallback;

  OnceObj.FIo := TEvIo.Create(-1, []);
  OnceObj.FIo.FLoop := Self; { bind so ClearPending works even when unstarted }
  OnceObj.FIo.FOnEvent := OnceObj.IoCb;
  if Fd >= 0 then
  begin
    OnceObj.FIo.SetIo(Fd, Events);
    IoStart(OnceObj.FIo);
  end;

  OnceObj.FTimer := TEvTimer.Create(0, 0);
  OnceObj.FTimer.FLoop := Self;
  OnceObj.FTimer.FOnEvent := OnceObj.TimerCb;
  if Timeout >= 0 then
  begin
    OnceObj.FTimer.SetTimer(Timeout, 0);
    TimerStart(OnceObj.FTimer);
  end;
end;

{ ------------------------------------------------------------------ }
{ time and the main loop                                              }
{ ------------------------------------------------------------------ }

{ ev.c:3844 periodic_recalc }
procedure TEvLoop.PeriodicRecalc(W: TEvPeriodic);
var
  Interval, At, Nat: TEvTstamp;
begin
  if W.FInterval > MIN_INTERVAL then
    Interval := W.FInterval
  else
    Interval := MIN_INTERVAL;
  At := W.FOffset + Interval * EvFloor((FRtNow - W.FOffset) / Interval);

  { the above almost always errs on the low side }
  while At <= FRtNow do
  begin
    Nat := At + W.FInterval;

    { when resolution fails us, we use ev_rt_now }
    if Nat = At then
    begin
      At := FRtNow;
      Break;
    end;

    At := Nat;
  end;

  W.FAt := At;
end;

{ ev.c:3804 timers_reify - make timers pending }
procedure TEvLoop.TimersReify;
var
  W: TEvTimer;
begin
  if (FTimerCnt > 0) and (FTimers[HEAP0].At < FMnNow) then
  begin
    repeat
      W := TEvTimer(FTimers[HEAP0].W);

      { first reschedule or stop timer }
      if W.FRepeat <> 0 then
      begin
        W.FAt := W.FAt + W.FRepeat;
        if W.FAt < FMnNow then
          W.FAt := FMnNow;

        EvAssert(W.FRepeat > 0,
          'negative ev_timer repeat value found while processing timers');

        FTimers[HEAP0].At := W.FAt; { ANHE_at_cache }
        DownHeap(FTimers, FTimerCnt, HEAP0);
      end
      else
        TimerStop(W); { nonrepeating: stop timer }

      FeedReverse(W);
    until not ((FTimerCnt > 0) and (FTimers[HEAP0].At < FMnNow));

    FeedReverseDone([evTimer]);
  end;
end;

{ ev.c:3869 periodics_reify - make periodics pending }
procedure TEvLoop.PeriodicsReify;
var
  W: TEvPeriodic;
begin
  while (FPeriodicCnt > 0) and (FPeriodics[HEAP0].At < FRtNow) do
  begin
    repeat
      W := TEvPeriodic(FPeriodics[HEAP0].W);

      { first reschedule or stop timer }
      if Assigned(W.FRescheduleCb) then
      begin
        W.FAt := W.FRescheduleCb(W, FRtNow);

        EvAssert(W.FAt >= FRtNow,
          'ev_periodic reschedule callback returned time in the past');

        FPeriodics[HEAP0].At := W.FAt; { ANHE_at_cache }
        DownHeap(FPeriodics, FPeriodicCnt, HEAP0);
      end
      else if W.FInterval <> 0 then
      begin
        PeriodicRecalc(W);
        FPeriodics[HEAP0].At := W.FAt; { ANHE_at_cache }
        DownHeap(FPeriodics, FPeriodicCnt, HEAP0);
      end
      else
        PeriodicStop(W); { nonrepeating: stop timer }

      FeedReverse(W);
    until not ((FPeriodicCnt > 0) and (FPeriodics[HEAP0].At < FRtNow));

    FeedReverseDone([evPeriodic]);
  end;
end;

{ ev.c:3913 periodics_reschedule - simply recalculate all periodics
  (called after a time jump) }
procedure TEvLoop.PeriodicsReschedule;
var
  I: Integer;
  W: TEvPeriodic;
begin
  for I := HEAP0 to FPeriodicCnt + HEAP0 - 1 do
  begin
    W := TEvPeriodic(FPeriodics[I].W);

    if Assigned(W.FRescheduleCb) then
      W.FAt := W.FRescheduleCb(W, FRtNow)
    else if W.FInterval <> 0 then
      PeriodicRecalc(W);

    FPeriodics[I].At := W.FAt; { ANHE_at_cache }
  end;

  ReHeap(FPeriodics, FPeriodicCnt);
end;

{ ev.c:3937 timers_reschedule - adjust all timers by a given offset }
procedure TEvLoop.TimersReschedule(Adjust: TEvTstamp);
var
  I: Integer;
begin
  for I := 0 to FTimerCnt - 1 do
  begin
    FTimers[I + HEAP0].W.FAt := FTimers[I + HEAP0].W.FAt + Adjust;
    FTimers[I + HEAP0].At := FTimers[I + HEAP0].W.FAt; { ANHE_at_cache }
  end;
end;

{ ev.c:3952 time_update - fetch new monotonic and realtime times, also
  detect a timejump and act accordingly. A monotonic clock is always
  available on our targets (QPC on Windows, CLOCK_MONOTONIC on Linux), so
  the have_monotonic=false branch of C is not ported. }
procedure TEvLoop.TimeUpdate(MaxBlock: TEvTstamp);
var
  I: Integer;
  ODiff, Diff: TEvTstamp;
begin
  ODiff := FRtMnDiff;

  FMnNow := EvClock;

  { only fetch the realtime clock every 0.5*MIN_TIMEJUMP seconds,
    interpolate in the meantime }
  if FMnNow - FNowFloor < MIN_TIMEJUMP * 0.5 then
  begin
    FRtNow := FRtMnDiff + FMnNow;
    Exit;
  end;

  FNowFloor := FMnNow;
  FRtNow := EvTime;

  { loop a few times before making important decisions: we may have been
    preempted between the clock calls (ev.c:3973) }
  for I := 1 to 3 do  { C: for (i = 4; --i; ) }
  begin
    FRtMnDiff := FRtNow - FMnNow;

    Diff := ODiff - FRtMnDiff;

    if Abs(Diff) < MIN_TIMEJUMP then
      Exit; { all is well }

    FRtNow := EvTime;
    FMnNow := EvClock;
    FNowFloor := FMnNow;
  end;

  { no timer adjustment, as the monotonic clock doesn't jump;
    but periodics are absolute and must be rescheduled }
  PeriodicsReschedule;
end;

{ ev.c:3781 idle_reify - make idle watchers pending, but only when no
  higher-priority watchers are pending }
procedure TEvLoop.IdleReify;
var
  Pri, I: Integer;
begin
  if FIdleAll <> 0 then
  begin
    for Pri := NUMPRI - 1 downto 0 do
    begin
      if FPendingCnt[Pri] > 0 then
        Break;

      if FIdleCnt[Pri] > 0 then
      begin
        { queue_events (ev.c:2347) }
        for I := 0 to FIdleCnt[Pri] - 1 do
          FeedEventW(FIdles[Pri][I], [evIdle]);
        Break;
      end;
    end;
  end;
end;

{ ev.c:4021 ev_run }
function TEvLoop.Run(Flags: TEvRunFlags): Boolean;
var
  WaitTime, SleepTime, PrevMnNow, To_: TEvTstamp;
  I: Integer;
begin
  Inc(FLoopDepth);

  FLoopDone := EVBREAK_CANCEL;

  DoInvokePending; { in case we recurse, ensure ordering stays nice and clean }

  repeat
{$IFDEF EV_VERIFY_2}
    Verify; { ev.c:4035, EV_VERIFY >= 2 }
{$ENDIF}

{$IFDEF LINUX}
    { penalise the forking check even more (ev.c:4039) }
    if FCurPid <> 0 then
      if c_getpid <> FCurPid then
      begin
        FCurPid := c_getpid;
        FPostFork := 1;
      end;
{$ENDIF}

    { we might have forked, so queue fork handlers (ev.c:4048) }
    if FPostFork <> 0 then
      if FForkCnt > 0 then
      begin
        for I := 0 to FForkCnt - 1 do
          FeedEventW(FForks[I], [evFork]);
        DoInvokePending;
      end;

    { queue prepare watchers (and execute them) (ev.c:4058) }
    if FPrepareCnt > 0 then
    begin
      for I := 0 to FPrepareCnt - 1 do
        FeedEventW(FPrepares[I], [evPrepare]);
      DoInvokePending;
    end;

    if FLoopDone <> 0 then
      Break;

    { we might have forked, so reify kernel state if necessary (ev.c:4070) }
    if FPostFork <> 0 then
      LoopForkInternal;

    { update fd-related kernel structures }
    FdReify;

    { calculate blocking time (ev.c:4077) }
    begin
      WaitTime := 0;
      SleepTime := 0;

      { remember old timestamp for io_blocktime calculation }
      PrevMnNow := FMnNow;

      { update time to cancel out callback processing overhead }
      TimeUpdate(EV_TSTAMP_HUGE);

      { from now on, we want a pipe-wake-up }
      FPipeWriteWanted := 1;

      { make sure pipe_write_wanted is visible before we check for
        potential skips (ev.c:4091) }
      EvMemoryFence;

      if not ((evrunNoWait in Flags) or (FIdleAll <> 0) or
              (FActiveCnt = 0) or (FPipeWriteSkipped <> 0)) then
      begin
        WaitTime := MAX_BLOCKTIME;
{$IFDEF LINUX}
        { with a timerfd we can rely on it to catch time jumps, so we may
          sleep much longer between realtime-clock checks (ev.c:4097) }
        if FTimerFd >= 0 then
          WaitTime := MAX_BLOCKTIME2;
{$ENDIF}

        if FTimerCnt > 0 then
        begin
          To_ := FTimers[HEAP0].At - FMnNow;
          if WaitTime > To_ then
            WaitTime := To_;
        end;

        if FPeriodicCnt > 0 then
        begin
          To_ := FPeriodics[HEAP0].At - FRtNow;
          if WaitTime > To_ then
            WaitTime := To_;
        end;

        { don't let timeouts decrease the waittime below timeout_blocktime }
        if WaitTime < FTimeoutBlocktime then
          WaitTime := FTimeoutBlocktime;

        { two more special cases: either we have already-expired timers, so
          we should not sleep, or we have timers that expire very soon, in
          which case we need to wait for the backend's minimum wait time
          (ev.c:4127) }
        if WaitTime < FBackend.FMinTime then
        begin
          if WaitTime <= 0 then
            WaitTime := 0
          else
            WaitTime := FBackend.FMinTime;
        end;

        { extra check because io_blocktime is commonly 0 (ev.c:4137) }
        if FIoBlocktime <> 0 then
        begin
          SleepTime := FIoBlocktime - (FMnNow - PrevMnNow);

          if SleepTime > WaitTime - FBackend.FMinTime then
            SleepTime := WaitTime - FBackend.FMinTime;

          if SleepTime > 0 then
          begin
            EvSleep(SleepTime);
            WaitTime := WaitTime - SleepTime;
          end;
        end;
      end;

      Inc(FLoopCount);
      FBackend.Poll(WaitTime);

      FPipeWriteWanted := 0; { just an optimisation }

      EvMemoryFence; { ECB_MEMORY_FENCE_ACQUIRE }
      if FPipeWriteSkipped <> 0 then
      begin
        EvAssert(FPipeW.IsActive, 'pipe_w not active, but pipe not written');
        FeedEventW(FPipeW, [evCustom]);
      end;

      { update ev_rt_now, do magic }
      TimeUpdate(WaitTime + SleepTime);
    end;

    { queue pending timers and reschedule them }
    TimersReify;   { relative timers called last }
    PeriodicsReify; { absolute timers called first }

    { queue idle watchers unless other events are pending }
    IdleReify;

    { queue check watchers, to be executed first (ev.c:4184) }
    if FCheckCnt > 0 then
      for I := 0 to FCheckCnt - 1 do
        FeedEventW(FChecks[I], [evCheck]);

    DoInvokePending;
  until not ((FActiveCnt > 0) and (FLoopDone = 0) and
             (Flags * [evrunOnce, evrunNoWait] = []));

  if FLoopDone = EVBREAK_ONE then
    FLoopDone := EVBREAK_CANCEL;

  Dec(FLoopDepth);

  Result := FActiveCnt > 0;
end;

{$IFDEF MSWINDOWS}
var
  WsaData: TWSAData;
{$ENDIF}

initialization
{$IFDEF MSWINDOWS}
  QueryPerformanceFrequency(QpcFrequency);
  WSAStartup(MakeWord(2, 2), WsaData);
{$ENDIF}

finalization
  TEvLoop.FDefault.Free;
{$IFDEF MSWINDOWS}
  WSACleanup;
{$ENDIF}

end.
