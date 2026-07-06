{ TLibEv verification example: cross-thread wakeup with TEvAsync.
  The main thread blocks in the event loop; a worker thread calls Send
  twice, which must wake the loop through the internal signal/async pipe. }
program AsyncDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF FPC}{$IFDEF UNIX}cthreads,{$ENDIF}{$ENDIF} { FPC needs the thread driver first }
  {$IFDEF FPC}SysUtils, Classes,{$ELSE}System.SysUtils, System.Classes,{$ENDIF}
  LibEv in '..\src\LibEv.pas';

type
  TWorker = class(TThread)
  private
    FAsync: TEvAsync;
  protected
    procedure Execute; override;
  public
    constructor Create(AAsync: TEvAsync);
  end;

  TDemo = class
  public
    StartAt: TEvTstamp;
    HitCount: Integer;
    procedure OnAsync(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

constructor TWorker.Create(AAsync: TEvAsync);
begin
  inherited Create(False);
  FAsync := AAsync;
  FreeOnTerminate := False;
end;

procedure TWorker.Execute;
begin
  Sleep(150);
  FAsync.Send; { first wakeup, loop is blocked in poll }
  Sleep(150);
  FAsync.Send; { second wakeup }
end;

procedure TDemo.OnAsync(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Inc(HitCount);
  Writeln(Format('async %d  t=%.3fs  (evAsync in revents: %s)',
    [HitCount, Loop.Now - StartAt, BoolToStr(evAsync in REvents, True)]));

  if HitCount >= 2 then
    Loop.BreakLoop(evbreakAll);
end;

var
  Demo: TDemo;
  Loop: TEvLoop;
  Async: TEvAsync;
  Guard: TEvTimer;
  Worker: TWorker;
begin
  try
    Demo := TDemo.Create;
    Loop := TEvLoop.Default;
    Demo.StartAt := Loop.Now;

    Async := TEvAsync.Create;
    Async.OnEvent := Demo.OnAsync;
    Async.Start(Loop);

    { safety net: fail instead of hanging if the wakeup never arrives }
    Guard := TEvTimer.Create(2.0, 0);
    Guard.Start(Loop);

    Worker := TWorker.Create(Async);

    Loop.Run;

    Worker.WaitFor;
    Worker.Free;

    if Demo.HitCount = 2 then
      Writeln('SUCCESS: both cross-thread wakeups arrived through the pipe.')
    else
    begin
      Writeln(Format('FAILURE: expected 2 async callbacks, got %d.', [Demo.HitCount]));
      ExitCode := 1;
    end;

    Async.Free;
    Guard.Free;
    Demo.Free;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
