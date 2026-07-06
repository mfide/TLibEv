{ TLibEv example: the extensibility hooks, self-testing.

  Covers the pieces that let you reach into the loop's machinery:
    1. Invoke        - run a watcher's callback directly (ev_invoke)
    2. FeedFdEvent   - inject an fd event by hand (ev_feed_fd_event)
    3. SetInvokePendingCb - override how pending watchers get invoked
    4. SetLoopReleaseCb   - release/acquire around the blocking poll
       (used when a loop is shared between threads) }
program HooksDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

type
  TApp = class
  public
    InvokeSeen: Boolean;
    InvokeRE: TEvEvents;
    FedSeen: Boolean;
    FedRE: TEvEvents;
    OverrideCount, ReleaseCount, AcquireCount, TickCount: Integer;
    procedure OnInvokeTarget(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnFedIo(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnTick(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure MyInvokePending(Loop: TEvLoop);
    procedure OnRelease(Loop: TEvLoop);
    procedure OnAcquire(Loop: TEvLoop);
  end;

procedure TApp.OnInvokeTarget(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  InvokeSeen := True;
  InvokeRE := RE;
end;

procedure TApp.OnFedIo(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  FedSeen := True;
  FedRE := RE;
end;

procedure TApp.OnTick(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Inc(TickCount);
  Loop.BreakLoop(evbreakAll);
end;

procedure TApp.MyInvokePending(Loop: TEvLoop);
begin
  Inc(OverrideCount);
  Loop.InvokePending;  { still do the real work }
end;

procedure TApp.OnRelease(Loop: TEvLoop);
begin
  Inc(ReleaseCount);
end;

procedure TApp.OnAcquire(Loop: TEvLoop);
begin
  Inc(AcquireCount);
end;

function BoolStr(B: Boolean): string;
begin
  if B then Result := 'OK' else Result := 'FAIL';
end;

{ 1. ev_invoke - call a watcher's callback directly }
function TestInvoke(App: TApp): Boolean;
var
  Loop: TEvLoop;
  Tmr: TEvTimer;
begin
  Loop := TEvLoop.Create;
  try
    Tmr := TEvTimer.Create(100, 0);   { never fires; only needs to be bound }
    Tmr.OnEvent := App.OnInvokeTarget;
    Tmr.Start(Loop);
    try
      App.InvokeSeen := False;
      App.InvokeRE := [];
      Tmr.Invoke([evCustom]);
    finally
      Tmr.Free;
    end;
  finally
    Loop.Free;
  end;
  Result := App.InvokeSeen and (evCustom in App.InvokeRE);
  Writeln('1. Invoke          : ', BoolStr(Result));
end;

{ 2. ev_feed_fd_event - inject an fd event without the backend }
function TestFeedFd(App: TApp): Boolean;
var
  Loop: TEvLoop;
  Io: TEvIo;
begin
  Loop := TEvLoop.Create;
  try
    Io := TEvIo.Create(0, [evRead]);  { fd 0; we never poll, so it is not touched }
    Io.OnEvent := App.OnFedIo;
    Io.Start(Loop);
    try
      App.FedSeen := False;
      App.FedRE := [];
      Loop.FeedFdEvent(0, [evRead]);
      Loop.InvokePending;
    finally
      Io.Stop;
      Io.Free;
    end;
  finally
    Loop.Free;
  end;
  Result := App.FedSeen and (evRead in App.FedRE);
  Writeln('2. FeedFdEvent     : ', BoolStr(Result));
end;

{ 3. ev_set_invoke_pending_cb - the override must run and still drive callbacks }
function TestInvokeOverride(App: TApp): Boolean;
var
  Loop: TEvLoop;
  Tmr: TEvTimer;
begin
  Loop := TEvLoop.Create;
  try
    App.OverrideCount := 0;
    App.TickCount := 0;
    Loop.SetInvokePendingCb(App.MyInvokePending);
    Tmr := TEvTimer.Create(0.02, 0);
    Tmr.OnTimeout := App.OnTick;
    Tmr.Start(Loop);
    try
      Loop.Run;
    finally
      Tmr.Free;
    end;
  finally
    Loop.Free;
  end;
  Result := (App.OverrideCount > 0) and (App.TickCount = 1);
  Writeln('3. InvokePendingCb : ', BoolStr(Result),
    Format('  (override ran %d times, tick=%d)', [App.OverrideCount, App.TickCount]));
end;

{ 4. ev_set_loop_release_cb - release/acquire must bracket each blocking poll }
function TestReleaseAcquire(App: TApp): Boolean;
var
  Loop: TEvLoop;
  Tmr: TEvTimer;
begin
  Loop := TEvLoop.Create;
  try
    App.ReleaseCount := 0;
    App.AcquireCount := 0;
    App.TickCount := 0;
    Loop.SetLoopReleaseCb(App.OnRelease, App.OnAcquire);
    Tmr := TEvTimer.Create(0.05, 0);
    Tmr.OnTimeout := App.OnTick;
    Tmr.Start(Loop);
    try
      Loop.Run;
    finally
      Tmr.Free;
    end;
  finally
    Loop.Free;
  end;
  Result := (App.ReleaseCount > 0) and (App.ReleaseCount = App.AcquireCount);
  Writeln('4. ReleaseAcquire  : ', BoolStr(Result),
    Format('  (release=%d, acquire=%d)', [App.ReleaseCount, App.AcquireCount]));
end;

var
  App: TApp;
  AllOk: Boolean;
begin
  App := TApp.Create;
  try
    AllOk := True;
    if not TestInvoke(App)          then AllOk := False;
    if not TestFeedFd(App)          then AllOk := False;
    if not TestInvokeOverride(App)  then AllOk := False;
    if not TestReleaseAcquire(App)  then AllOk := False;

    if AllOk then
      Writeln('SUCCESS: Invoke, FeedFdEvent, invoke-pending and release/acquire hooks work.')
    else
    begin
      Writeln('FAILURE: one or more hooks failed.');
      ExitCode := 1;
    end;
  finally
    App.Free;
  end;
end.
