{ TLibEv verification example: one-shot + repeating timer and a periodic
  (wall-clock) watcher. }
program TimerDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

type
  TDemo = class
  public
    StartAt: TEvTstamp;
    TickCount: Integer;
    PeriodicCount: Integer;
    procedure OnTick(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnOneShot(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnPeriodic(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

procedure TDemo.OnTick(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Inc(TickCount);
  Writeln(Format('tick %d  t=%.3fs  (time to next repeat: %.3fs)',
    [TickCount, Loop.Now - StartAt, TEvTimer(Watcher).Remaining]));

  if TickCount >= 3 then
  begin
    Writeln('3 ticks done, breaking the loop.');
    Loop.BreakLoop(evbreakAll);
  end;
end;

procedure TDemo.OnOneShot(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Writeln(Format('one-shot timer  t=%.3fs  (still active: %s)',
    [Loop.Now - StartAt, BoolToStr(Watcher.IsActive, True)]));
end;

procedure TDemo.OnPeriodic(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Inc(PeriodicCount);
  Writeln(Format('periodic %d  t=%.3fs  (next at unix time %.3f)',
    [PeriodicCount, Loop.Now - StartAt, TEvPeriodic(Watcher).At]));
end;

var
  Demo: TDemo;
  Loop: TEvLoop;
  Ticker, OneShot: TEvTimer;
  Periodic: TEvPeriodic;
begin
  try
    Demo := TDemo.Create;
    Loop := TEvLoop.Default;
    Demo.StartAt := Loop.Now;

    Writeln(Format('TLibEv %s (libev %s)  backend=%d  (0=select, 1=poll, 2=epoll)',
      [TLIBEV_VERSION, LIBEV_UPSTREAM_VERSION, Ord(Loop.Backend.Kind)]));

    Ticker := TEvTimer.Create(0.25, 0.25);
    Ticker.OnTimeout := Demo.OnTick;
    Ticker.Start(Loop);

    OneShot := TEvTimer.Create(0.1, 0);
    OneShot.OnTimeout := Demo.OnOneShot;
    OneShot.Start(Loop);

    { fires on every multiple of 0.3 seconds of wall-clock time,
      like the "clock that ticks on the full hour" example of libev }
    Periodic := TEvPeriodic.Create(0, 0.3);
    Periodic.OnEvent := Demo.OnPeriodic;
    Periodic.Start(Loop);

    Loop.Run;

    Writeln(Format('loop finished: iterations=%d  ticker still active: %s',
      [Loop.Iterations, BoolToStr(Ticker.IsActive, True)]));

    Ticker.Free;
    OneShot.Free;
    Periodic.Free;
    Demo.Free;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
