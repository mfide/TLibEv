{ TLibEv example: the "customise your event loop" watchers - TEvPrepare,
  TEvCheck and TEvIdle - shown together and self-testing.

  - a prepare watcher runs at the top of every loop iteration, just before the
    loop blocks waiting for events;
  - a check watcher runs at the bottom of every iteration, just after the
    block;
  - an idle watcher runs whenever the loop would otherwise block with nothing
    to do (while it is active the loop never sleeps).

  A repeating timer drives a few iterations. The idle watcher does a bounded
  amount of "background work" and then stops itself, so the program terminates
  instead of spinning forever. }
program LoopHooksDemo;

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
    PrepCount, CheckCount, IdleCount, TimerFires: Integer;
    procedure OnPrepare(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnCheck(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnIdle(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnTimer(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;

procedure TApp.OnPrepare(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Inc(PrepCount);
end;

procedure TApp.OnCheck(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Inc(CheckCount);
end;

procedure TApp.OnIdle(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Inc(IdleCount);
  if IdleCount >= 3 then
  begin
    Writeln('idle: did 3 units of background work, stopping the idle watcher');
    W.Stop;   { let the loop block normally from now on }
  end;
end;

procedure TApp.OnTimer(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Inc(TimerFires);
  Writeln(Format('timer fire %d  (prepares=%d, checks=%d, idles=%d)',
    [TimerFires, PrepCount, CheckCount, IdleCount]));
  if TimerFires >= 4 then
    Loop.BreakLoop(evbreakAll);
end;

var
  App: TApp;
  Loop: TEvLoop;
  Prep: TEvPrepare;
  Chk: TEvCheck;
  Idle: TEvIdle;
  Tmr: TEvTimer;
  Ok: Boolean;
begin
  App := TApp.Create;
  Loop := TEvLoop.Default;

  Prep := TEvPrepare.Create;
  Prep.OnEvent := App.OnPrepare;
  Prep.Start(Loop);

  Chk := TEvCheck.Create;
  Chk.OnEvent := App.OnCheck;
  Chk.Start(Loop);

  Idle := TEvIdle.Create;
  Idle.OnEvent := App.OnIdle;
  Idle.Start(Loop);

  Tmr := TEvTimer.Create(0.05, 0.05);
  Tmr.OnTimeout := App.OnTimer;
  Tmr.Start(Loop);

  Loop.Run;

  { prepare and check run exactly once per iteration (they bracket the poll),
    the idle watcher ran its 3 bounded units, and the timer fired 4 times }
  Ok := (App.PrepCount > 0)
    and (App.PrepCount = App.CheckCount)
    and (App.IdleCount = 3)
    and (App.TimerFires = 4);

  if Ok then
    Writeln('SUCCESS: prepare/check bracketed every iteration, idle and timer behaved.')
  else
  begin
    Writeln(Format('FAILURE: prep=%d check=%d idle=%d timer=%d',
      [App.PrepCount, App.CheckCount, App.IdleCount, App.TimerFires]));
    ExitCode := 1;
  end;

  Prep.Free;
  Chk.Free;
  Idle.Free;
  Tmr.Free;
  App.Free;
end.
