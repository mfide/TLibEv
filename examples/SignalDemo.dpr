{ TLibEv verification example (Linux only): signal and child watchers,
  fully self-testing:
  - forks a child that exits after 0.2s with code 7 -> the child watcher
    must report it through the default loop's SIGCHLD machinery
  - a timer sends SIGTERM to the own process at t=0.8s -> the signal
    watcher must catch it and break the loop }
program SignalDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

{$IFNDEF LINUX}
  {$MESSAGE ERROR 'SignalDemo is Linux-only'}
{$ENDIF}

uses
  {$IFDEF FPC}BaseUnix, SysUtils,{$ELSE}Posix.Unistd, Posix.Signal, System.SysUtils,{$ENDIF}
  LibEv in '..\src\LibEv.pas';

const
  SIGTERM = 15;

{ fork/_exit/kill/getpid come from the RTL; the short delay uses SysUtils.Sleep }
function c_fork: Integer; inline;
begin
  {$IFDEF FPC}Result := fpFork;{$ELSE}Result := fork;{$ENDIF}
end;
procedure c_exit(Status: Integer); inline;
begin
  {$IFDEF FPC}FpExit(Status);{$ELSE}_exit(Status);{$ENDIF}
end;
function c_kill(Pid, Sig: Integer): Integer; inline;
begin
  {$IFDEF FPC}Result := fpKill(Pid, Sig);{$ELSE}Result := kill(Pid, Sig);{$ENDIF}
end;
function c_getpid: Integer; inline;
begin
  {$IFDEF FPC}Result := fpGetPID;{$ELSE}Result := getpid;{$ENDIF}
end;
procedure c_usleep(Usec: Cardinal); inline;
begin
  Sleep(Usec div 1000);
end;

type
  TDemo = class
  public
    StartAt: TEvTstamp;
    ChildPid: Integer;
    GotChild: Boolean;
    GotSignal: Boolean;
    ChildStatus: Integer;
    procedure OnSignal(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnChild(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnKillTimer(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

procedure TDemo.OnSignal(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  GotSignal := True;
  Writeln(Format('t=%.3fs  caught signal %d, breaking the loop',
    [Loop.Now - StartAt, TEvSignal(Watcher).SigNum]));
  Loop.BreakLoop(evbreakAll);
end;

procedure TDemo.OnChild(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  GotChild := True;
  ChildStatus := TEvChild(Watcher).RStatus;
  Writeln(Format('t=%.3fs  child pid %d exited, status=%d (exit code %d)',
    [Loop.Now - StartAt, TEvChild(Watcher).RPid,
     TEvChild(Watcher).RStatus, TEvChild(Watcher).RStatus shr 8]));
end;

procedure TDemo.OnKillTimer(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Writeln(Format('t=%.3fs  sending SIGTERM to self', [Loop.Now - StartAt]));
  c_kill(c_getpid, SIGTERM);
end;

var
  Demo: TDemo;
  Loop: TEvLoop;
  WatchTerm: TEvSignal;
  Child: TEvChild;
  KillTimer: TEvTimer;
begin
  Demo := TDemo.Create;
  Loop := TEvLoop.Default; { must exist before forking (installs SIGCHLD) }
  Demo.StartAt := Loop.Now;

  Demo.ChildPid := c_fork;
  if Demo.ChildPid = 0 then
  begin
    { child process: exit with a recognisable code after 0.2s }
    c_usleep(200000);
    c_exit(7);
  end;
  Writeln('forked child pid ', Demo.ChildPid);

  WatchTerm := TEvSignal.Create(SIGTERM);
  WatchTerm.OnEvent := Demo.OnSignal;
  WatchTerm.Start(Loop);

  Child := TEvChild.Create(Demo.ChildPid, False);
  Child.OnEvent := Demo.OnChild;
  Child.Start(Loop);

  KillTimer := TEvTimer.Create(0.8, 0);
  KillTimer.OnTimeout := Demo.OnKillTimer;
  KillTimer.Start(Loop);

  Loop.Run;

  if Demo.GotChild and Demo.GotSignal and (Demo.ChildStatus shr 8 = 7) then
    Writeln('SUCCESS: child watcher and signal watcher both fired.')
  else
  begin
    Writeln(Format('FAILURE: child=%s signal=%s status=%d',
      [BoolToStr(Demo.GotChild, True), BoolToStr(Demo.GotSignal, True),
       Demo.ChildStatus]));
    ExitCode := 1;
  end;

  WatchTerm.Free;
  Child.Free;
  KillTimer.Free;
  Demo.Free;
end.
