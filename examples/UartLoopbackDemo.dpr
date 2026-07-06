{ TLibEv example: event-driven UART / serial-port I/O, tested with a loopback.

  A serial port is one of the most natural fits for an event loop. The demo
  sends a message out the port and expects to receive the very same bytes
  back; whichever way the bytes come back, they arrive as loop events.

  Linux:   the port is a file descriptor, so it is watched directly with a
           TEvIo watcher (the classic libev idiom). To need no hardware, the
           demo builds a virtual serial pair with a PTY: the slave end is "the
           serial port" (watched with TEvIo) and the master end plays the
           loopback wire, echoing back whatever it receives (a second TEvIo).
           This runs unattended, which is what CI uses.

  Windows: the winsock select backend can only watch sockets, not COM handles,
           so a reader thread does blocking ReadFile on the port and feeds the
           bytes to the loop through a TEvAsync watcher (the same pattern as
           KeyDemo). This talks to a REAL serial port and therefore needs a
           physical loopback: connect the port's RX and TX pins together (on a
           9-pin D-sub, pins 2 and 3). Pass the port name as the first
           argument, e.g.  UartLoopbackDemo COM3   (default: COM1). COM10 and
           above work too: the "\\.\" device prefix they require is added
           automatically. Because it needs hardware, CI only compiles this half.

  Either way: send a message, receive it back, verify, done. }
program UartLoopbackDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
{$IFDEF MSWINDOWS}
  {$IFDEF FPC}Windows, Classes, SyncObjs,{$ELSE}Winapi.Windows, System.Classes, System.SyncObjs,{$ENDIF}
{$ENDIF}
{$IFDEF LINUX}
  { file I/O and termios come from the RTL; only the pty helpers below have no
    RTL binding }
  {$IFDEF FPC}BaseUnix, termio,{$ELSE}Posix.Fcntl, Posix.Unistd, Posix.Termios,{$ENDIF}
{$ENDIF}
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

const
  TEST_MESSAGE = 'TLibEv UART loopback test';

{$IFDEF LINUX}
const
  O_RDWR   = 2;
  O_NOCTTY = $100;
  TCSANOW  = 0;

type
  { the RTL's termios; the demo only passes it by pointer to the calls below }
  TTermios = {$IFDEF FPC}termio.TermIOS{$ELSE}Posix.Termios.termios{$ENDIF};
  PTermios = ^TTermios;

{ posix_openpt/grantpt/unlockpt/ptsname have no RTL binding, so these stay
  direct libc bindings; open/close/read/write and termios come from the RTL }
const
  CLibName = {$IFDEF FPC}'c'{$ELSE}'libc.so'{$ENDIF};
function c_posix_openpt(flags: Integer): Integer; cdecl; external CLibName name 'posix_openpt';
function c_grantpt(fd: Integer): Integer; cdecl; external CLibName name 'grantpt';
function c_unlockpt(fd: Integer): Integer; cdecl; external CLibName name 'unlockpt';
function c_ptsname(fd: Integer): PAnsiChar; cdecl; external CLibName name 'ptsname';

function c_open(path: PAnsiChar; flags: Integer): Integer; inline;
begin
{$IFDEF FPC}Result := fpOpen(path, flags, 0);{$ELSE}Result := open(path, flags);{$ENDIF}
end;
function c_close(fd: Integer): Integer; inline;
begin
{$IFDEF FPC}Result := fpClose(fd);{$ELSE}Result := __close(fd);{$ENDIF}
end;
function c_read(fd: Integer; buf: Pointer; count: NativeUInt): NativeInt; inline;
begin
{$IFDEF FPC}Result := fpRead(fd, PChar(buf), count);{$ELSE}Result := __read(fd, buf, count);{$ENDIF}
end;
function c_write(fd: Integer; buf: Pointer; count: NativeUInt): NativeInt; inline;
begin
{$IFDEF FPC}Result := fpWrite(fd, PChar(buf), count);{$ELSE}Result := __write(fd, buf, count);{$ENDIF}
end;
function c_tcgetattr(fd: Integer; termios_p: Pointer): Integer; inline;
begin
{$IFDEF FPC}Result := TCGetAttr(fd, PTermios(termios_p)^);{$ELSE}Result := tcgetattr(fd, PTermios(termios_p)^);{$ENDIF}
end;
procedure c_cfmakeraw(termios_p: Pointer); inline;
begin
{$IFDEF FPC}CFMakeRaw(PTermios(termios_p)^);{$ELSE}cfmakeraw(PTermios(termios_p)^);{$ENDIF}
end;
function c_tcsetattr(fd, optional_actions: Integer; termios_p: Pointer): Integer; inline;
begin
{$IFDEF FPC}Result := TCSetAttr(fd, optional_actions, PTermios(termios_p)^);{$ELSE}Result := tcsetattr(fd, optional_actions, PTermios(termios_p)^);{$ENDIF}
end;
{$ENDIF}

type
  TApp = class
  private
    { fields first (Delphi requires fields before methods within a section) }
    FLoop: TEvLoop;
    FSent: RawByteString;
    FReceived: RawByteString;
    FDone: Boolean;
    FOk: Boolean;
{$IFDEF LINUX}
    FMaster, FSlave: Integer;
    FPortIo, FWireIo: TEvIo;
{$ENDIF}
{$IFDEF MSWINDOWS}
    FPort: THandle;
    FAsync: TEvAsync;
    FLock: TCriticalSection;
    FQueue: RawByteString;
{$ENDIF}
    procedure GotBytes(P: Pointer; N: Integer);
    procedure OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
{$IFDEF LINUX}
    procedure OnPortReadable(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
    procedure OnWireReadable(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
{$ENDIF}
{$IFDEF MSWINDOWS}
    procedure OnAsyncRx(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
{$ENDIF}
  public
    procedure Run(const PortName: string);
  end;

{ ---- shared: collect received bytes and finish when the message is back ---- }

procedure TApp.GotBytes(P: Pointer; N: Integer);
var
  Chunk: RawByteString;
begin
  if N <= 0 then
    Exit;
  SetString(Chunk, PAnsiChar(P), N);
  FReceived := FReceived + Chunk;

  if (not FDone) and (Length(FReceived) >= Length(FSent)) then
  begin
    FDone := True;
    FOk := Copy(FReceived, 1, Length(FSent)) = FSent;
    FLoop.BreakLoop(evbreakAll);
  end;
end;

procedure TApp.OnGuard(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
begin
  Writeln('timeout: the message did not come back.');
{$IFDEF MSWINDOWS}
  Writeln('  is the port''s RX wired to its TX (physical loopback)?');
{$ENDIF}
  Loop.BreakLoop(evbreakAll);
end;

{$IFDEF LINUX}
{ the serial port (PTY slave): incoming bytes }
procedure TApp.OnPortReadable(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
var
  Buf: array[0..255] of Byte;
  N: NativeInt;
begin
  N := c_read(FSlave, @Buf, SizeOf(Buf));
  if N <= 0 then
  begin
    Loop.BreakLoop(evbreakAll);
    Exit;
  end;
  GotBytes(@Buf, N);
end;

{ the loopback wire (PTY master): echo everything straight back, so what the
  port transmits comes back on its own receive line }
procedure TApp.OnWireReadable(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
var
  Buf: array[0..255] of Byte;
  N: NativeInt;
begin
  N := c_read(FMaster, @Buf, SizeOf(Buf));
  if N > 0 then
    c_write(FMaster, @Buf, N);
end;

procedure TApp.Run(const PortName: string);
var
  SlaveName: PAnsiChar;
  Tio: TTermios;
  Guard: TEvTimer;
begin
  FLoop := TEvLoop.Default;

  FMaster := c_posix_openpt(O_RDWR or O_NOCTTY);
  if FMaster < 0 then
    raise Exception.Create('posix_openpt failed');
  c_grantpt(FMaster);
  c_unlockpt(FMaster);

  SlaveName := c_ptsname(FMaster);
  FSlave := c_open(SlaveName, O_RDWR or O_NOCTTY);
  if FSlave < 0 then
    raise Exception.Create('opening the pty slave failed');

  { put the port into raw byte mode (no echo, no line processing) }
  c_tcgetattr(FSlave, @Tio);
  c_cfmakeraw(@Tio);
  c_tcsetattr(FSlave, TCSANOW, @Tio);

  Writeln('opened virtual serial pair, port = ', string(AnsiString(SlaveName)));

  FWireIo := TEvIo.Create(FMaster, [evRead]);
  FWireIo.OnEvent := OnWireReadable;
  FWireIo.Start(FLoop);

  FPortIo := TEvIo.Create(FSlave, [evRead]);
  FPortIo.OnEvent := OnPortReadable;
  FPortIo.Start(FLoop);

  Guard := TEvTimer.Create(3.0, 0);
  Guard.OnTimeout := OnGuard;
  Guard.Start(FLoop);

  { transmit }
  c_write(FSlave, PAnsiChar(FSent), Length(FSent));
  Writeln('sent ', Length(FSent), ' bytes, waiting for the loopback...');

  FLoop.Run;

  FPortIo.Free;
  FWireIo.Free;
  Guard.Free;
  c_close(FSlave);
  c_close(FMaster);
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
type
  { blocking ReadFile on the COM port; feeds bytes to the loop via TEvAsync }
  TComReader = class(TThread)
  private
    FApp: TApp;
  protected
    procedure Execute; override;
  public
    constructor Create(AApp: TApp);
  end;

constructor TComReader.Create(AApp: TApp);
begin
  FApp := AApp;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TComReader.Execute;
var
  Buf: array[0..255] of Byte;
  Got: DWORD;
  Chunk: RawByteString;
begin
  while not Terminated do
  begin
    Got := 0;
    { ReadFile returns within the configured timeout even with no data, so the
      thread keeps checking Terminated }
    if ReadFile(FApp.FPort, Buf, SizeOf(Buf), Got, nil) and (Got > 0) then
    begin
      SetString(Chunk, PAnsiChar(@Buf), Got);
      FApp.FLock.Enter;
      FApp.FQueue := FApp.FQueue + Chunk;
      FApp.FLock.Leave;
      FApp.FAsync.Send;
    end;
  end;
end;

procedure TApp.OnAsyncRx(Loop: TEvLoop; W: TEvWatcher; RE: TEvEvents);
var
  Data: RawByteString;
begin
  FLock.Enter;
  Data := FQueue;
  FQueue := '';
  FLock.Leave;
  GotBytes(PAnsiChar(Data), Length(Data));
end;

procedure TApp.Run(const PortName: string);
var
  Dcb: TDCB;
  Timeouts: TCommTimeouts;
  Written: DWORD;
  Reader: TComReader;
  Guard: TEvTimer;
begin
  FLoop := TEvLoop.Default;

  { the "\\.\" prefix is required for COM10 and above, and is fine for COM1..9 }
  FPort := CreateFile(PChar('\\.\' + PortName),
    GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if FPort = INVALID_HANDLE_VALUE then
  begin
    Writeln('could not open ', PortName, ' (', GetLastError, ')');
    ExitCode := 1;
    Exit;
  end;

  FillChar(Dcb, SizeOf(Dcb), 0);
  Dcb.DCBlength := SizeOf(Dcb);
  GetCommState(FPort, Dcb);
  Dcb.BaudRate := 115200;
  Dcb.ByteSize := 8;
  Dcb.Parity := NOPARITY;
  Dcb.StopBits := ONESTOPBIT;
  Dcb.Flags := Dcb.Flags or 1;  { fBinary }
  SetCommState(FPort, Dcb);

  FillChar(Timeouts, SizeOf(Timeouts), 0);
  Timeouts.ReadIntervalTimeout := 50;
  Timeouts.ReadTotalTimeoutConstant := 100;
  SetCommTimeouts(FPort, Timeouts);

  Writeln('opened ', PortName, ' at 115200 8N1');

  FLock := TCriticalSection.Create;
  FAsync := TEvAsync.Create;
  FAsync.OnEvent := OnAsyncRx;
  FAsync.Start(FLoop);

  Guard := TEvTimer.Create(3.0, 0);
  Guard.OnTimeout := OnGuard;
  Guard.Start(FLoop);

  Reader := TComReader.Create(Self);

  { transmit; with RX looped back to TX it returns to us }
  WriteFile(FPort, PAnsiChar(FSent)^, Length(FSent), Written, nil);
  Writeln('sent ', Length(FSent), ' bytes, waiting for the physical loopback...');

  FLoop.Run;

  Reader.Terminate;
  Reader.WaitFor;
  Reader.Free;
  Guard.Free;
  FAsync.Free;
  FLock.Free;
  CloseHandle(FPort);
end;
{$ENDIF}

var
  App: TApp;
  PortName: string;
begin
  if ParamCount >= 1 then
    PortName := ParamStr(1)
  else
    PortName := 'COM1';   { only used on Windows; Linux makes its own pty }

  App := TApp.Create;
  try
    App.FSent := TEST_MESSAGE;
    try
      App.Run(PortName);
    except
      on E: Exception do
      begin
        Writeln('ERROR: ', E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;

    if App.FOk then
      Writeln('SUCCESS: the message came back over the serial loopback.')
    else if ExitCode = 0 then
    begin
      Writeln('FAILURE: did not receive the message back.');
      ExitCode := 1;
    end;
  finally
    App.Free;
  end;
end.
