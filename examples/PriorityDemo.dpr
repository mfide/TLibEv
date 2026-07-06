{ TLibEv example: watcher priorities, self-testing.

  When several watchers become pending in the same loop iteration, their
  callbacks are invoked in priority order: higher priority first. Priority
  does NOT stop lower-priority watchers from running (that is what idle
  watchers are for) - it only orders callbacks within one iteration.

  Three timers are set to expire at the same instant but with different
  priorities (high, normal, low). Whatever the order they were started in,
  they must be invoked high-to-low. }
program PriorityDemo;

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
    Order: string;
    procedure OnHigh(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnNormal(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnLow(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;

procedure TApp.OnHigh(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Order := Order + 'H';
  if Length(Order) = 3 then Loop.BreakLoop(evbreakAll);
end;

procedure TApp.OnNormal(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Order := Order + 'N';
  if Length(Order) = 3 then Loop.BreakLoop(evbreakAll);
end;

procedure TApp.OnLow(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Order := Order + 'L';
  if Length(Order) = 3 then Loop.BreakLoop(evbreakAll);
end;

var
  App: TApp;
  Loop: TEvLoop;
  High, Normal, Low: TEvTimer;
begin
  App := TApp.Create;
  Loop := TEvLoop.Default;

  { all three expire together; priority must be set while the watcher is
    inactive (before Start). Started deliberately low-first to prove the
    invocation order comes from priority, not from start order. }
  Low := TEvTimer.Create(0.05, 0);
  Low.OnTimeout := App.OnLow;
  Low.Priority := EV_MINPRI;   { -2 }
  Low.Start(Loop);

  Normal := TEvTimer.Create(0.05, 0);
  Normal.OnTimeout := App.OnNormal;
  Normal.Priority := 0;
  Normal.Start(Loop);

  High := TEvTimer.Create(0.05, 0);
  High.OnTimeout := App.OnHigh;
  High.Priority := EV_MAXPRI;  { +2 }
  High.Start(Loop);

  Loop.Run;

  Writeln('invocation order: ', App.Order, '  (started low, normal, high)');
  if App.Order = 'HNL' then
    Writeln('SUCCESS: callbacks ran high-to-low regardless of start order.')
  else
  begin
    Writeln('FAILURE: expected "HNL"');
    ExitCode := 1;
  end;

  High.Free;
  Normal.Free;
  Low.Free;
  App.Free;
end.
