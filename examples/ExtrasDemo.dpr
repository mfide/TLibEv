{ TLibEv example: three smaller features, each a self-testing section on its
  own event loop.

  1. FeedEvent - inject an event into a watcher by hand, as if it had happened.
  2. Suspend / Resume - pause the loop's notion of time so timers are not
     charged for the suspended interval (e.g. across a game pause / SIGSTOP).
  3. TimeoutCollectInterval - deliberately delay timer callbacks to batch them
     and waste fewer wake-ups. }
program ExtrasDemo;

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
    FedRevents: TEvEvents;
    FedSeen: Boolean;
    SuspElapsed: TEvTstamp;
    CollElapsed: TEvTstamp;
    WallStart: TEvTstamp;
    procedure OnFed(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnSuspTimer(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnCollTimer(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;

procedure TApp.OnFed(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  FedSeen := True;
  FedRevents := RE;
end;

procedure TApp.OnSuspTimer(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  SuspElapsed := EvTime - WallStart;
  Loop.BreakLoop(evbreakAll);
end;

procedure TApp.OnCollTimer(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  CollElapsed := EvTime - WallStart;
  Loop.BreakLoop(evbreakAll);
end;

function BoolStr(B: Boolean): string;
begin
  if B then Result := 'OK' else Result := 'FAIL';
end;

{ ---- 1. FeedEvent ---- }
function TestFeedEvent(App: TApp): Boolean;
var
  Loop: TEvLoop;
  Tmr: TEvTimer;
begin
  Loop := TEvLoop.Create;
  try
    { a timer far in the future: it is only there to be a started (bound)
      watcher - it never fires on its own here, so the only event it ever gets
      is the custom one we inject }
    Tmr := TEvTimer.Create(100, 0);
    Tmr.OnEvent := App.OnFed;
    Tmr.Start(Loop);
    try
      App.FedSeen := False;
      App.FedRevents := [];
      Tmr.FeedEvent([evCustom]);   { queue the event by hand }
      Loop.InvokePending;          { run the pending watcher now }
    finally
      Tmr.Free;
    end;
  finally
    Loop.Free;
  end;

  Result := App.FedSeen and (evCustom in App.FedRevents);
  if Result then
    Writeln('1. FeedEvent   : OK  (callback saw evCustom)')
  else
    Writeln('1. FeedEvent   : FAIL');
end;

{ ---- 2. Suspend / Resume ---- }
function TestSuspendResume(App: TApp): Boolean;
var
  Loop: TEvLoop;
  Tmr: TEvTimer;
begin
  Loop := TEvLoop.Create;
  try
    App.WallStart := EvTime;
    Tmr := TEvTimer.Create(0.3, 0);
    Tmr.OnTimeout := App.OnSuspTimer;
    Tmr.Start(Loop);
    try
      { pretend the program is frozen for 0.3s while suspended; the timer must
        not be charged for it, so it still needs its full 0.3s afterwards }
      Loop.Suspend;
      EvSleep(0.3);
      Loop.Resume;
      Loop.Run;
    finally
      Tmr.Free;
    end;
  finally
    Loop.Free;
  end;

  { total wall time ~= 0.3 (suspended) + 0.3 (timer) }
  Result := App.SuspElapsed >= 0.5;
  Writeln(Format('2. Suspend/Res : %s  (timer fired after %.3fs wall, expected ~0.6)',
    [BoolStr(Result), App.SuspElapsed]));
end;

{ ---- 3. TimeoutCollectInterval ---- }
function TestCollectInterval(App: TApp): Boolean;
var
  Loop: TEvLoop;
  Tmr: TEvTimer;
begin
  Loop := TEvLoop.Create;
  try
    Loop.TimeoutCollectInterval := 0.2;   { do not fire timers more often than this }
    App.WallStart := EvTime;
    Tmr := TEvTimer.Create(0.02, 0);       { would like to fire at 0.02s... }
    Tmr.OnTimeout := App.OnCollTimer;
    Tmr.Start(Loop);
    try
      Loop.Run;                            { ...but is delayed to ~0.2s }
    finally
      Tmr.Free;
    end;
  finally
    Loop.Free;
  end;

  Result := App.CollElapsed >= 0.15;
  Writeln(Format('3. CollectInt  : %s  (0.02s timer delayed to %.3fs by the 0.2s interval)',
    [BoolStr(Result), App.CollElapsed]));
end;

var
  App: TApp;
  AllOk: Boolean;

begin
  App := TApp.Create;
  try
    AllOk := True;
    if not TestFeedEvent(App)      then AllOk := False;
    if not TestSuspendResume(App)  then AllOk := False;
    if not TestCollectInterval(App) then AllOk := False;

    if AllOk then
      Writeln('SUCCESS: FeedEvent, Suspend/Resume and TimeoutCollectInterval all work.')
    else
    begin
      Writeln('FAILURE: one or more sections failed.');
      ExitCode := 1;
    end;
  finally
    App.Free;
  end;
end.
