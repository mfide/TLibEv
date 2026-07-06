{ TLibEv example: fire an event on every keypress (no Enter needed), with
  proper Unicode handling.

  Linux:   the terminal is switched to raw (non-canonical, no echo) mode with
           termios, and stdin (fd 0) is watched with a TEvIo watcher, so every
           keystroke makes the fd readable and the callback runs. This is the
           classic libev "watch STDIN" idiom. Raw stdin delivers UTF-8 bytes
           (a letter such as 's-cedilla' arrives as two bytes), which are
           decoded to Unicode characters before being reported.

  Windows: the winsock select backend can only watch sockets, not console
           handles, so stdin cannot be watched directly. Instead a reader
           thread blocks on the CRT _getwch() - the wide console read, which
           returns UTF-16 code units - and hands each key to the loop through
           a TEvAsync watcher (which is thread-safe). This shows how a blocking
           input source is turned into ordinary loop events.

  Either way you get one callback per keypress carrying the real code point,
  so accented and non-Latin keys work. A heartbeat timer runs alongside to
  make it visible that the loop stays event-driven (it never busy-waits: it
  blocks in epoll_wait / the poll, waking only for a key or the timer).

  This program is interactive, so it is not part of the automated CI run
  (CI only compiles it). Press 'q' or ESC (or Ctrl+C) to quit. }
program KeyDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
{$IFDEF MSWINDOWS}
  {$IFDEF FPC}Classes, SyncObjs,{$ELSE}System.Classes, System.SyncObjs,{$ENDIF}
{$ENDIF}
{$IFDEF LINUX}
  { termios and read come from the RTL; only _getwch (Windows) has no binding }
  {$IFDEF FPC}BaseUnix, termio,{$ELSE}Posix.Termios, Posix.Unistd,{$ENDIF}
{$ENDIF}
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

{$IFDEF LINUX}
const
  { termios c_lflag bits }
  ISIG      = $0001;
  ICANON    = $0002;
  ECHO_FLAG = $0008;
  { tcsetattr optional_actions }
  TCSANOW   = 0;
  { c_cc indices }
  VTIME     = 5;
  VMIN      = 6;

type
  { the RTL's termios (same field names - c_lflag, c_cc - on FPC and Delphi) }
  TTermios = {$IFDEF FPC}termio.TermIOS{$ELSE}Posix.Termios.termios{$ENDIF};

{ tcgetattr/tcsetattr are called directly below (their name and (fd, var
  termios) shape line up on FPC and Delphi); only the keypress read needs a
  small wrapper over the RTL read }
function key_read(fd: Integer; buf: Pointer; count: NativeUInt): NativeInt; inline;
begin
{$IFDEF FPC}Result := fpRead(fd, PChar(buf), count);{$ELSE}Result := __read(fd, buf, count);{$ENDIF}
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
{ _getwch reads one keypress as a wide (UTF-16) character, without echo and
  without waiting for Enter }
function _getwch: Integer; cdecl; external 'msvcrt.dll' name '_getwch';
{ make the console print UTF-8 so the reported glyphs display correctly }
function SetConsoleOutputCP(wCodePageID: Cardinal): LongBool; stdcall;
  external 'kernel32.dll' name 'SetConsoleOutputCP';
{$ENDIF}

type
  TKeyApp = class
  private
    FLoop: TEvLoop;
    FCount: Integer;
{$IFDEF LINUX}
    FIo: TEvIo;
    FSaved: TTermios;
    FRawActive: Boolean;
    procedure OnStdin(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure EnterRawMode;
    procedure LeaveRawMode;
{$ENDIF}
{$IFDEF MSWINDOWS}
    FAsync: TEvAsync;
    FLock: TCriticalSection;
    FPending: UnicodeString;   { keys queued by the reader thread, drained in the loop }
    procedure OnAsyncKey(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
{$ENDIF}
    function HandleKey(Ch: WideChar): Boolean;  { returns True when it is a quit key }
    procedure OnHeartbeat(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
  public
    procedure Run;
  end;

{$IFDEF MSWINDOWS}
type
  { blocks on _getwch and feeds every key to the loop via TEvAsync }
  TKeyReader = class(TThread)
  private
    FApp: TKeyApp;
  protected
    procedure Execute; override;
  public
    constructor Create(AApp: TKeyApp);
  end;

constructor TKeyReader.Create(AApp: TKeyApp);
begin
  FApp := AApp;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TKeyReader.Execute;
var
  Code: Integer;
begin
  while not Terminated do
  begin
    Code := _getwch;

    FApp.FLock.Enter;
    FApp.FPending := FApp.FPending + WideChar(Code and $FFFF);
    FApp.FLock.Leave;

    FApp.FAsync.Send; { wake the loop; multiple sends may coalesce, hence the queue }

    { quit keys: 'q', ESC, Ctrl+C - stop reading so the thread can end cleanly }
    if (Code = Ord('q')) or (Code = 27) or (Code = 3) then
      Break;
  end;
end;
{$ENDIF}

{ ---- shared key handling ---- }

function TKeyApp.HandleKey(Ch: WideChar): Boolean;
var
  Cp: Integer;
  Glyph: UTF8String;
begin
  Inc(FCount);
  Cp := Ord(Ch);

  if (Cp >= 32) and (Cp <> 127) then
  begin
    { print the actual character as UTF-8, plus its code point }
    Glyph := UTF8Encode(UnicodeString(Ch));
    Write(Format('key #%d: ', [FCount]));
    Write(Glyph);
    Writeln(Format('  (U+%.4X)', [Cp]));
  end
  else
    Writeln(Format('key #%d: <control>  (U+%.4X)', [FCount, Cp]));

  Result := (Cp = Ord('q')) or (Cp = 27) or (Cp = 3); { q, ESC, Ctrl+C }
  if Result then
    Writeln('quit key pressed - leaving the loop');
end;

procedure TKeyApp.OnHeartbeat(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Writeln('  ...loop alive, waiting for keys (q or ESC to quit)');
end;

{$IFDEF LINUX}
procedure TKeyApp.EnterRawMode;
var
  Raw: TTermios;
begin
  { if stdin is not a terminal (e.g. piped input) tcgetattr fails; then we
    simply leave it alone and still read whatever arrives }
  if tcgetattr(0, FSaved) <> 0 then
    Exit;

  Raw := FSaved;
  Raw.c_lflag := Raw.c_lflag and not Cardinal(ISIG or ICANON or ECHO_FLAG);
  Raw.c_cc[VMIN] := 1;   { return as soon as one byte is available }
  Raw.c_cc[VTIME] := 0;
  tcsetattr(0, TCSANOW, Raw);
  FRawActive := True;
end;

procedure TKeyApp.LeaveRawMode;
begin
  if FRawActive then
    tcsetattr(0, TCSANOW, FSaved);
  FRawActive := False;
end;

procedure TKeyApp.OnStdin(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
var
  Buf: array[0..31] of Byte;
  N, I: NativeInt;
  Chunk: RawByteString;
  Text: UnicodeString;
begin
  { the fd is readable, so a blocking read returns immediately with the
    available byte(s); one keypress delivers the whole UTF-8 sequence at once }
  N := key_read(0, @Buf, SizeOf(Buf));

  if N <= 0 then
  begin
    Loop.BreakLoop(evbreakAll); { EOF: stdin closed }
    Exit;
  end;

  { decode the raw bytes as UTF-8 explicitly (do not rely on the dynamic
    string code page, which is not reliably CP_UTF8 after SetString) }
  SetString(Chunk, PAnsiChar(@Buf[0]), N);
{$IFDEF FPC}
  Text := UTF8Decode(Chunk);
{$ELSE}
  Text := UTF8ToUnicodeString(Chunk);
{$ENDIF}

  for I := 1 to Length(Text) do
    if HandleKey(Text[I]) then
    begin
      Loop.BreakLoop(evbreakAll);
      Exit;
    end;
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
procedure TKeyApp.OnAsyncKey(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
var
  Keys: UnicodeString;
  I: Integer;
begin
  { drain everything the reader queued since the last wakeup }
  FLock.Enter;
  Keys := FPending;
  FPending := '';
  FLock.Leave;

  for I := 1 to Length(Keys) do
    if HandleKey(Keys[I]) then
    begin
      Loop.BreakLoop(evbreakAll);
      Exit;
    end;
end;
{$ENDIF}

procedure TKeyApp.Run;
var
  Heartbeat: TEvTimer;
{$IFDEF MSWINDOWS}
  Reader: TKeyReader;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  SetConsoleOutputCP(65001); { CP_UTF8 }
{$ENDIF}

  FLoop := TEvLoop.Default;

  Writeln('KeyDemo - press keys (no Enter needed).  ''q'' or ESC quits.');
  Writeln(Format('backend=%d  (0=select/Windows, 2=epoll/Linux)',
    [Ord(FLoop.Backend.Kind)]));

  Heartbeat := TEvTimer.Create(3.0, 3.0);
  Heartbeat.OnTimeout := OnHeartbeat;
  Heartbeat.Start(FLoop);

{$IFDEF LINUX}
  EnterRawMode;
  try
    FIo := TEvIo.Create(0, [evRead]);   { fd 0 = stdin }
    FIo.OnEvent := OnStdin;
    FIo.Start(FLoop);

    FLoop.Run;

    FIo.Free;
  finally
    LeaveRawMode;  { always restore the terminal }
  end;
{$ENDIF}

{$IFDEF MSWINDOWS}
  FLock := TCriticalSection.Create;
  FAsync := TEvAsync.Create;
  FAsync.OnEvent := OnAsyncKey;
  FAsync.Start(FLoop);

  Reader := TKeyReader.Create(Self);
  try
    FLoop.Run;
  finally
    Reader.WaitFor;   { the reader stops itself after a quit key }
    Reader.Free;
    FAsync.Free;
    FLock.Free;
  end;
{$ENDIF}

  Heartbeat.Free;
  Writeln('done. total keys handled: ', FCount);
end;

var
  App: TKeyApp;
begin
  App := TKeyApp.Create;
  try
    App.Run;
  finally
    App.Free;
  end;
end.
