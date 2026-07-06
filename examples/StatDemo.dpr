{ TLibEv verification example: TEvStat (timer-polled), TEvLoop.Once and
  TEvCleanup, fully self-testing:
  - watches a temp file with a 0.15s poll interval
  - a timer appends data at t=0.3s -> the stat watcher must report a size
    change; another timer deletes the file at t=0.8s -> nlink must drop to 0
  - Once() with timeout only must fire exactly once
  - a cleanup watcher on a secondary loop must fire when that loop is freed }
program StatDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF FPC}SysUtils, Classes,{$ELSE}System.SysUtils, System.Classes,{$ENDIF}
  LibEv in '..\src\LibEv.pas';

type
  TDemo = class
  public
    StartAt: TEvTstamp;
    FileName: string;
    SawGrow: Boolean;
    SawDelete: Boolean;
    OnceFired: Integer;
    CleanupFired: Boolean;
    procedure OnStat(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnModify(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnDelete(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnGuard(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnOnce(REvents: TEvEvents);
    procedure OnCleanup(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

procedure AppendToFile(const FileName, Text: string);
var
  F: TFileStream;
  Bytes: TBytes;
  Mode: Word;
begin
  if FileExists(FileName) then
    Mode := fmOpenReadWrite or fmShareDenyNone
  else
    Mode := fmCreate or fmShareDenyNone;
  F := TFileStream.Create(FileName, Mode);
  try
    F.Seek(0, soEnd);
    Bytes := TEncoding.UTF8.GetBytes(Text);
    F.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    F.Free;
  end;
end;

procedure TDemo.OnStat(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  W: TEvStat;
begin
  W := TEvStat(Watcher);
  Writeln(Format('t=%.3fs  stat change: nlink %d->%d  size %d->%d',
    [Loop.Now - StartAt, W.Prev.st_nlink, W.Attr.st_nlink,
     W.Prev.st_size, W.Attr.st_size]));

  if (W.Attr.st_nlink > 0) and (W.Attr.st_size > W.Prev.st_size) then
    SawGrow := True;

  if W.Attr.st_nlink = 0 then
  begin
    SawDelete := True;
    Loop.BreakLoop(evbreakAll);
  end;
end;

procedure TDemo.OnModify(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Writeln(Format('t=%.3fs  appending to the watched file', [Loop.Now - StartAt]));
  AppendToFile(FileName, 'grow!');
end;

procedure TDemo.OnDelete(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Writeln(Format('t=%.3fs  deleting the watched file', [Loop.Now - StartAt]));
  DeleteFile(FileName);
end;

procedure TDemo.OnGuard(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Writeln('guard timeout hit - something did not fire');
  Loop.BreakLoop(evbreakAll);
end;

procedure TDemo.OnOnce(REvents: TEvEvents);
begin
  Inc(OnceFired);
  Writeln(Format('once callback fired (timer=%s)',
    [BoolToStr(evTimer in REvents, True)]));
end;

procedure TDemo.OnCleanup(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  CleanupFired := True;
  Writeln('cleanup watcher fired while destroying the secondary loop');
end;

var
  Demo: TDemo;
  Loop, TempLoop: TEvLoop;
  Stat: TEvStat;
  ModTimer, DelTimer, Guard: TEvTimer;
  Cleanup: TEvCleanup;
  Ok: Boolean;
begin
  try
    Demo := TDemo.Create;
    Loop := TEvLoop.Default;
    Demo.StartAt := Loop.Now;

    Demo.FileName := IncludeTrailingPathDelimiter(GetEnvironmentVariable(
      {$IFDEF MSWINDOWS}'TEMP'{$ELSE}'HOME'{$ENDIF})) + 'tlibev_stat_test.txt';
    if FileExists(Demo.FileName) then
      DeleteFile(Demo.FileName);
    AppendToFile(Demo.FileName, 'initial');
    Writeln('watching ', Demo.FileName);

    Stat := TEvStat.Create(Demo.FileName, 0.15);
    Stat.OnEvent := Demo.OnStat;
    Stat.Start(Loop);

    ModTimer := TEvTimer.Create(0.3, 0);
    ModTimer.OnTimeout := Demo.OnModify;
    ModTimer.Start(Loop);

    DelTimer := TEvTimer.Create(0.8, 0);
    DelTimer.OnTimeout := Demo.OnDelete;
    DelTimer.Start(Loop);

    Guard := TEvTimer.Create(3.0, 0);
    Guard.OnTimeout := Demo.OnGuard;
    Guard.Start(Loop);

    { timeout-only Once: must fire exactly once at t=0.1s and free itself }
    Loop.Once(-1, [], 0.1, Demo.OnOnce);

    Loop.Run;

    { cleanup watcher on a throwaway loop }
    TempLoop := TEvLoop.Create;
    Cleanup := TEvCleanup.Create;
    Cleanup.OnEvent := Demo.OnCleanup;
    Cleanup.Start(TempLoop);
    TempLoop.Free;
    Cleanup.Free;

    Ok := Demo.SawGrow and Demo.SawDelete and (Demo.OnceFired = 1)
      and Demo.CleanupFired;
    if Ok then
      Writeln('SUCCESS: stat grow+delete, once and cleanup all fired.')
    else
    begin
      Writeln(Format('FAILURE: grow=%s delete=%s once=%d cleanup=%s',
        [BoolToStr(Demo.SawGrow, True), BoolToStr(Demo.SawDelete, True),
         Demo.OnceFired, BoolToStr(Demo.CleanupFired, True)]));
      ExitCode := 1;
    end;

    Stat.Free;
    ModTimer.Free;
    DelTimer.Free;
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
