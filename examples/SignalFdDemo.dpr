{ TLibEv example (Linux only): signal delivery via signalfd, self-testing.

  Creating the loop with the evflagSignalFd flag makes signal watchers use
  the Linux signalfd(2) API instead of a sigaction handler + wakeup pipe: the
  signal is blocked and delivered synchronously by reading a file descriptor.
  This demo enables it, watches SIGUSR1, raises SIGUSR1 in this process, and
  checks the watcher fires through the signalfd. }
program SignalFdDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

{$IFNDEF LINUX}
  {$MESSAGE ERROR 'SignalFdDemo is Linux-only (signalfd is a Linux API)'}
{$ENDIF}

uses
  {$IFDEF FPC}BaseUnix, SysUtils{$ELSE}Posix.Signal, Posix.Unistd, System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

const
  SIGUSR1 = 10;

{ raise SIGUSR1 to our own process via the RTL (kill of our own pid) }
function c_raise(Sig: Integer): Integer; inline;
begin
{$IFDEF FPC}
  Result := fpKill(fpGetPID, Sig);
{$ELSE}
  Result := kill(getpid, Sig);
{$ENDIF}
end;

type
  TApp = class
  public
    Got: Boolean;
    procedure OnSignal(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnFire(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;

procedure TApp.OnSignal(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Got := True;
  Writeln('caught signal ', TEvSignal(W).SigNum, ' via signalfd');
  Loop.BreakLoop(evbreakAll);
end;

procedure TApp.OnFire(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Writeln('raising SIGUSR1 (it is blocked and routed through the signalfd)...');
  c_raise(SIGUSR1);
end;

procedure TApp.OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Writeln('timeout: the signal was not delivered');
  Loop.BreakLoop(evbreakAll);
end;

var
  App: TApp;
  Loop: TEvLoop;
  Sig: TEvSignal;
  Fire, Guard: TEvTimer;
begin
  App := TApp.Create;
  Loop := TEvLoop.Create([evflagSignalFd]);   { opt into signalfd delivery }
  try
    Sig := TEvSignal.Create(SIGUSR1);
    Sig.OnEvent := App.OnSignal;
    Sig.Start(Loop);

    Fire := TEvTimer.Create(0.2, 0);
    Fire.OnTimeout := App.OnFire;
    Fire.Start(Loop);

    Guard := TEvTimer.Create(3.0, 0);
    Guard.OnTimeout := App.OnGuard;
    Guard.Start(Loop);

    Loop.Run;

    Sig.Free;
    Fire.Free;
    Guard.Free;

    if App.Got then
      Writeln('SUCCESS: the signal was delivered through signalfd.')
    else
    begin
      Writeln('FAILURE: no signal event.');
      ExitCode := 1;
    end;
  finally
    Loop.Free;
    App.Free;
  end;
end.
