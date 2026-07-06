{ TLibEv example (Linux only): the poll(2) backend, self-testing.

  The default loop uses epoll on Linux; this creates a loop that explicitly
  uses the poll backend instead (TEvLoop.Create([], [evbackendPoll])), then
  proves it actually delivers fd events: it watches the read end of a pipe
  with a TEvIo watcher, writes a message into the write end, and checks the
  message arrives through the poll-driven loop.

  The poll backend is not built on Windows (Windows uses select), so this
  demo is Linux-only; CI runs it on Linux. }
program PollDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

{$IFNDEF LINUX}
  {$MESSAGE ERROR 'PollDemo is Linux-only (the poll backend is not built on Windows)'}
{$ENDIF}

uses
  {$IFDEF FPC}BaseUnix, SysUtils{$ELSE}Posix.Unistd, System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

const
  TEST_MESSAGE = 'poll backend works';

{ pipe/read/write/close come from the platform RTL (BaseUnix on FPC,
  Posix.Unistd on Delphi) rather than hand-written externals }
function c_pipe(Fds: Pointer): Integer; inline;
begin
{$IFDEF FPC}
  Result := fpPipe(PFilDes(Fds)^);
{$ELSE}
  Result := pipe(TPipeDescriptors(Pointer(Fds)^));
{$ENDIF}
end;

function c_read(Fd: Integer; Buf: Pointer; Count: NativeUInt): NativeInt; inline;
begin
{$IFDEF FPC}
  Result := fpRead(Fd, PChar(Buf), Count);
{$ELSE}
  Result := __read(Fd, Buf, Count);
{$ENDIF}
end;

function c_close(Fd: Integer): Integer; inline;
begin
{$IFDEF FPC}
  Result := fpClose(Fd);
{$ELSE}
  Result := __close(Fd);
{$ENDIF}
end;

function c_write(Fd: Integer; Buf: Pointer; Count: NativeUInt): NativeInt; inline;
begin
{$IFDEF FPC}
  Result := fpWrite(Fd, PChar(Buf), Count);
{$ELSE}
  Result := __write(Fd, Buf, Count);
{$ENDIF}
end;

type
  TApp = class
  public
    Got: Boolean;
    Received: RawByteString;
    procedure OnReadable(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  end;

procedure TApp.OnReadable(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
var
  Buf: array[0..63] of Byte;
  N: NativeInt;
begin
  N := c_read(TEvIo(W).Fd, @Buf, SizeOf(Buf));
  if N > 0 then
  begin
    SetString(Received, PAnsiChar(@Buf), N);
    Got := True;
  end;
  Loop.BreakLoop(evbreakAll);
end;

procedure TApp.OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Writeln('timeout: the poll backend did not report the pipe as readable');
  Loop.BreakLoop(evbreakAll);
end;

var
  App: TApp;
  Loop: TEvLoop;
  Io: TEvIo;
  Guard: TEvTimer;
  Fds: array[0..1] of Integer;
begin
  App := TApp.Create;
  Loop := TEvLoop.Create([], [evbackendPoll]);
  try
    Writeln('backend=', Ord(Loop.Backend.Kind), '  (1 = poll)');

    if c_pipe(@Fds[0]) <> 0 then
      raise Exception.Create('pipe() failed');

    Io := TEvIo.Create(Fds[0], [evRead]);   { watch the read end }
    Io.OnEvent := App.OnReadable;
    Io.Start(Loop);

    Guard := TEvTimer.Create(2.0, 0);
    Guard.OnTimeout := App.OnGuard;
    Guard.Start(Loop);

    c_write(Fds[1], PAnsiChar(TEST_MESSAGE), Length(TEST_MESSAGE));

    Loop.Run;

    Io.Free;
    Guard.Free;
    c_close(Fds[0]);
    c_close(Fds[1]);

    if (Loop.Backend.Kind = evbackendPoll) and App.Got and (App.Received = TEST_MESSAGE) then
      Writeln('SUCCESS: the poll backend delivered the fd event.')
    else
    begin
      Writeln('FAILURE: kind=', Ord(Loop.Backend.Kind), ' got=', App.Got);
      ExitCode := 1;
    end;
  finally
    Loop.Free;
    App.Free;
  end;
end.
