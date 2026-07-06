{ TLibEv verification example: real socket I/O through the backend.
  A UDP socket is bound to 127.0.0.1; a timer sends a datagram after 0.2s,
  the TEvIo watcher catches readability and breaks the loop. }
program IoDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

{$IFNDEF MSWINDOWS}
  {$MESSAGE ERROR 'IoDemo is Windows-only (it uses the winsock UDP API directly)'}
{$ENDIF}

uses
  {$IFDEF FPC}SysUtils, WinSock2,{$ELSE}System.SysUtils, Winapi.Winsock2,{$ENDIF}
  LibEv in '..\src\LibEv.pas';

{ Delphi's Winsock2 declares sendto with an untyped "const Buf", while FPC's
  declares a typed "Pointer", so a single portable call is impossible against
  the unit prototypes. We bind our own with an untyped const buffer (the same
  technique LibEv.pas uses for select), giving one call form on both. }
function ws_sendto(s: TSocket; const Buf; len, flags: Integer;
  toaddr: PSockAddr; tolen: Integer): Integer; stdcall;
  external 'ws2_32.dll' name 'sendto';

type
  TDemo = class
  public
    Sock: TSocket;
    Addr: TSockAddrIn;
    StartAt: TEvTstamp;
    Got: Boolean;
    procedure OnSend(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnReadable(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

procedure TDemo.OnSend(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
const
  Msg: AnsiString = 'hello libev';
begin
  Writeln(Format('t=%.3fs  sending datagram', [Loop.Now - StartAt]));
  ws_sendto(Sock, PAnsiChar(Msg)^, Length(Msg), 0, PSockAddr(@Addr), SizeOf(Addr));
end;

procedure TDemo.OnReadable(Loop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  Buf: array[0..255] of AnsiChar;
  N: Integer;
begin
  N := recv(Sock, Buf, SizeOf(Buf), 0);
  Writeln(Format('t=%.3fs  io event: read=%s  %d bytes: "%s"',
    [Loop.Now - StartAt, BoolToStr(evRead in REvents, True), N,
     string(Copy(AnsiString(Buf), 1, N))]));
  Got := True;
  Loop.BreakLoop(evbreakAll);
end;

var
  Demo: TDemo;
  Loop: TEvLoop;
  Io: TEvIo;
  SendTimer: TEvTimer;
  AddrLen: Integer;
begin
  try
    Demo := TDemo.Create;
    Loop := TEvLoop.Default;
    Demo.StartAt := Loop.Now;

    { UDP socket bound to an ephemeral port on 127.0.0.1 }
    Demo.Sock := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if Demo.Sock = INVALID_SOCKET then
      raise EEvError.CreateFmt('socket() failed: %d', [WSAGetLastError]);

    FillChar(Demo.Addr, SizeOf(Demo.Addr), 0);
    Demo.Addr.sin_family := AF_INET;
    Demo.Addr.sin_addr.S_addr := htonl($7F000001); { 127.0.0.1 }
    Demo.Addr.sin_port := 0;
    if bind(Demo.Sock, PSockAddr(@Demo.Addr)^, SizeOf(Demo.Addr)) <> 0 then
      raise EEvError.CreateFmt('bind() failed: %d', [WSAGetLastError]);

    AddrLen := SizeOf(Demo.Addr);
    getsockname(Demo.Sock, PSockAddr(@Demo.Addr)^, AddrLen);
    Writeln('UDP socket ready, port=', ntohs(Demo.Addr.sin_port),
      '  fd=', Demo.Sock);

    Io := TEvIo.Create(Integer(Demo.Sock), [evRead]);
    Io.OnEvent := Demo.OnReadable;
    Io.Start(Loop);

    SendTimer := TEvTimer.Create(0.2, 0);
    SendTimer.OnTimeout := Demo.OnSend;
    SendTimer.Start(Loop);

    Loop.Run;

    if Demo.Got then
      Writeln('SUCCESS: the io watcher received an event through the backend.')
    else
    begin
      Writeln('FAILURE: no io event arrived.');
      ExitCode := 1;
    end;

    Io.Free;
    SendTimer.Free;
    closesocket(Demo.Sock);
    Demo.Free;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
