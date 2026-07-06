{ TLibEv example: signal watchers, cross-platform and self-testing.

  A TEvSignal watches SIGINT; a timer then raises SIGINT in this very process
  (via the C runtime raise()), and the watcher must catch it through the loop.

  This works on both targets and shows that TEvSignal is no longer Linux-only:
  on Linux the handler is installed with sigaction, on Windows with the CRT
  signal() function. (The existing SignalDemo, which forks a child, stays
  Linux-only; this one needs no fork, so it also runs on Windows.) }
program SignalSelfDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
{$IFDEF FPC}
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  SysUtils,
{$ELSE}
  {$IFDEF POSIX}Posix.Signal, Posix.Unistd,{$ENDIF}
  System.SysUtils,
{$ENDIF}
  LibEv in '..\src\LibEv.pas';

const
  SIGINT = 2;

{ send SIGINT to our own process. On POSIX this is kill(getpid()) from the RTL,
  which triggers the sigaction handler; on Windows only the CRT raise() reaches
  the msvcrt signal() handler, and the RTL has no equivalent. }
{$IFDEF MSWINDOWS}
function c_raise(Sig: Integer): Integer; cdecl; external 'msvcrt.dll' name 'raise';
{$ELSE}
function c_raise(Sig: Integer): Integer; inline;
begin
{$IFDEF FPC}
  Result := fpKill(fpGetPID, Sig);
{$ELSE}
  Result := kill(getpid, Sig);
{$ENDIF}
end;
{$ENDIF}

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
  Writeln('caught signal ', TEvSignal(W).SigNum, ' through the loop');
  Loop.BreakLoop(evbreakAll);
end;

procedure TApp.OnFire(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Writeln('raising SIGINT to self...');
  c_raise(SIGINT);
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
  Loop := TEvLoop.Default;

  Sig := TEvSignal.Create(SIGINT);
  Sig.OnEvent := App.OnSignal;
  Sig.Start(Loop);

  Fire := TEvTimer.Create(0.2, 0);
  Fire.OnTimeout := App.OnFire;
  Fire.Start(Loop);

  Guard := TEvTimer.Create(3.0, 0);
  Guard.OnTimeout := App.OnGuard;
  Guard.Start(Loop);

  Loop.Run;

  if App.Got then
    Writeln('SUCCESS: the signal watcher fired.')
  else
  begin
    Writeln('FAILURE: no signal event.');
    ExitCode := 1;
  end;

  Sig.Free;
  Fire.Free;
  Guard.Free;
  App.Free;
end.
