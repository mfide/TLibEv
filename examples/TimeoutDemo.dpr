{ TLibEv example: the inactivity-timeout idiom with TEvTimer.Again, self-testing.

  This is the recommended way to implement "do something if there has been no
  activity for N seconds" (e.g. drop an idle network connection). Instead of
  stopping and restarting a timer on every bit of activity, you keep one
  repeating timer and call Again to push its deadline forward. When activity
  stops, the timer finally fires once.

  Here an "activity" timer stands in for incoming traffic: it ticks a few
  times (each tick calls Again to reset the inactivity timer) and then stops.
  Roughly one inactivity window after the last tick, the timeout fires. }
program TimeoutDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

const
  ACTIVITY_INTERVAL = 0.05;  { simulated traffic period }
  INACTIVITY_WINDOW = 0.50;  { fire if no activity for this long }
  ACTIVITY_TICKS    = 3;

type
  TApp = class
  public
    Log: string;
    ActCount: Integer;
    Timeout: TEvTimer;
    Activity: TEvTimer;
    procedure OnActivity(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnTimeout(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;

procedure TApp.OnActivity(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Inc(ActCount);
  Log := Log + 'a';
  Writeln(Format('activity #%d - resetting the inactivity timer', [ActCount]));
  Timeout.Again;   { push the deadline forward }

  if ActCount >= ACTIVITY_TICKS then
  begin
    Writeln('activity stopped; now the inactivity timeout should fire once');
    Activity.Stop;
  end;
end;

procedure TApp.OnTimeout(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Log := Log + 'T';
  Writeln('inactivity timeout fired');
  Loop.BreakLoop(evbreakAll);
end;

procedure TApp.OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Log := Log + '!';
  Writeln('guard fired - something did not happen in time');
  Loop.BreakLoop(evbreakAll);
end;

var
  App: TApp;
  Loop: TEvLoop;
  Guard: TEvTimer;
begin
  App := TApp.Create;
  Loop := TEvLoop.Default;

  { the inactivity timer: repeating value = the window; first armed via Start,
    then kept alive with Again on every activity }
  App.Timeout := TEvTimer.Create(INACTIVITY_WINDOW, INACTIVITY_WINDOW);
  App.Timeout.OnTimeout := App.OnTimeout;
  App.Timeout.Start(Loop);

  App.Activity := TEvTimer.Create(ACTIVITY_INTERVAL, ACTIVITY_INTERVAL);
  App.Activity.OnTimeout := App.OnActivity;
  App.Activity.Start(Loop);

  Guard := TEvTimer.Create(3.0, 0);
  Guard.OnTimeout := App.OnGuard;
  Guard.Start(Loop);

  Loop.Run;

  { three activities kept resetting the timer, then it fired exactly once }
  if App.Log = 'aaaT' then
    Writeln('SUCCESS: Again kept the timeout at bay during activity, then it fired.')
  else
  begin
    Writeln('FAILURE: event log was "', App.Log, '", expected "aaaT"');
    ExitCode := 1;
  end;

  App.Timeout.Free;
  App.Activity.Free;
  Guard.Free;
  App.Free;
end.
