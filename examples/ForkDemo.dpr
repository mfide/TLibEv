{ TLibEv verification example (Linux only): the fork watcher, self-testing.
  The process forks; the child calls LoopFork and re-enters the loop, which
  must fire the fork watcher there. The fork callback exits the child with
  code 42, which the parent verifies through a child watcher. }
program ForkDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

{$IFNDEF LINUX}
  {$MESSAGE ERROR 'ForkDemo is Linux-only'}
{$ENDIF}

uses
  {$IFDEF FPC}BaseUnix, SysUtils,{$ELSE}Posix.Unistd, System.SysUtils,{$ENDIF}
  LibEv in '..\src\LibEv.pas';

{ fork/_exit come from the RTL (BaseUnix on FPC, Posix.Unistd on Delphi) }
function c_fork: Integer; inline;
begin
  {$IFDEF FPC}Result := fpFork;{$ELSE}Result := fork;{$ENDIF}
end;
procedure c_exit(Status: Integer); inline;
begin
  {$IFDEF FPC}FpExit(Status);{$ELSE}_exit(Status);{$ENDIF}
end;

type
  TDemo = class
  public
    StartAt: TEvTstamp;
    ChildStatus: Integer;
    GotChild: Boolean;
    procedure OnFork(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnChild(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnGuard(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

procedure TDemo.OnFork(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  { runs in the child only: LoopFork is never called in the parent }
  c_exit(42);
end;

procedure TDemo.OnChild(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  GotChild := True;
  ChildStatus := TEvChild(Watcher).RStatus;
  Writeln(Format('t=%.3fs  child pid %d exited with status %d (exit code %d)',
    [Loop.Now - StartAt, TEvChild(Watcher).RPid,
     ChildStatus, ChildStatus shr 8]));
  Loop.BreakLoop(evbreakAll);
end;

procedure TDemo.OnGuard(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Writeln('guard timeout hit - the child never exited via the fork watcher');
  Loop.BreakLoop(evbreakAll);
end;

var
  Demo: TDemo;
  Loop: TEvLoop;
  ForkW: TEvFork;
  Child: TEvChild;
  Guard: TEvTimer;
  Pid: Integer;
begin
  Demo := TDemo.Create;
  Loop := TEvLoop.Default;
  Demo.StartAt := Loop.Now;

  ForkW := TEvFork.Create;
  ForkW.OnEvent := Demo.OnFork;
  ForkW.Start(Loop);

  Pid := c_fork;
  if Pid = 0 then
  begin
    { child: declare the fork to libev and re-enter the loop; the fork
      watcher must fire on the first iteration and _exit(42) }
    Loop.LoopFork;
    Loop.Run;
    c_exit(1); { not reached if the fork watcher works }
  end;

  Writeln('forked child pid ', Pid);

  Child := TEvChild.Create(Pid, False);
  Child.OnEvent := Demo.OnChild;
  Child.Start(Loop);

  Guard := TEvTimer.Create(2.0, 0);
  Guard.OnTimeout := Demo.OnGuard;
  Guard.Start(Loop);

  Loop.Run;

  if Demo.GotChild and (Demo.ChildStatus shr 8 = 42) then
    Writeln('SUCCESS: the fork watcher fired in the child (exit code 42).')
  else
  begin
    Writeln(Format('FAILURE: gotchild=%s status=%d',
      [BoolToStr(Demo.GotChild, True), Demo.ChildStatus]));
    ExitCode := 1;
  end;

  ForkW.Free;
  Child.Free;
  Guard.Free;
  Demo.Free;
end.
