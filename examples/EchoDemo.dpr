{ TLibEv showcase: a non-blocking TCP echo server driven entirely by the
  event loop, self-testing:
  - the server accepts connections via a TEvIo watcher on the listener
  - each connection gets its own TEvIo; received bytes are echoed back
  - a worker thread acts as a blocking client, sends two messages,
    verifies the echoes and wakes the loop through a TEvAsync }
program EchoDemo;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF FPC}{$IFDEF UNIX}cthreads,{$ENDIF}{$ENDIF} { FPC needs the thread driver first }
{$IFDEF MSWINDOWS}
  {$IFDEF FPC}WinSock2,{$ELSE}Winapi.Winsock2,{$ENDIF}
{$ELSE}
  { the platform sockets API comes from the RTL: the Sockets unit on FPC,
    the Posix.* units on Delphi }
  {$IFDEF FPC}BaseUnix, Sockets,{$ELSE}Posix.SysSocket, Posix.NetinetIn, Posix.ArpaInet, Posix.Fcntl, Posix.Unistd,{$ENDIF}
{$ENDIF}
  {$IFDEF FPC}SysUtils, Classes,{$ELSE}System.SysUtils, System.Classes,{$ENDIF}
  LibEv in '..\src\LibEv.pas';

{ ------------------------------------------------------------------ }
{ minimal cross-platform socket glue                                  }
{ ------------------------------------------------------------------ }

{$IFNDEF MSWINDOWS}
{ AF_INET/SOCK_STREAM/SOL_SOCKET/SO_REUSEADDR and F_SETFL/O_NONBLOCK come from
  the RTL units; the sockaddr_in type does too, so it is laid out correctly per
  OS (the BSD sin_len byte on macOS is handled for us). }
type
  TSockAddrIn = {$IFDEF FPC}TInetSockAddr{$ELSE}sockaddr_in{$ENDIF};

function c_socket(Domain, Typ, Proto: Integer): Integer; inline;
begin
{$IFDEF FPC}Result := fpSocket(Domain, Typ, Proto);{$ELSE}Result := socket(Domain, Typ, Proto);{$ENDIF}
end;
function c_bind(Fd: Integer; Addr: Pointer; Len: Cardinal): Integer; inline;
begin
{$IFDEF FPC}Result := fpBind(Fd, psockaddr(Addr), Len);{$ELSE}Result := bind(Fd, sockaddr(Addr^), Len);{$ENDIF}
end;
function c_listen(Fd, Backlog: Integer): Integer; inline;
begin
{$IFDEF FPC}Result := fpListen(Fd, Backlog);{$ELSE}Result := listen(Fd, Backlog);{$ENDIF}
end;
function c_accept(Fd: Integer; Addr, Len: Pointer): Integer; inline;
begin
{$IFDEF FPC}Result := fpAccept(Fd, psockaddr(Addr), psocklen(Len));{$ELSE}Result := accept(Fd, psockaddr(Addr)^, psocklen_t(Len)^);{$ENDIF}
end;
function c_connect(Fd: Integer; Addr: Pointer; Len: Cardinal): Integer; inline;
begin
{$IFDEF FPC}Result := fpConnect(Fd, psockaddr(Addr), Len);{$ELSE}Result := connect(Fd, sockaddr(Addr^), Len);{$ENDIF}
end;
function c_recv(Fd: Integer; Buf: Pointer; Len: NativeUInt; Flags: Integer): NativeInt; inline;
begin
{$IFDEF FPC}Result := fpRecv(Fd, Buf, Len, Flags);{$ELSE}Result := recv(Fd, Buf^, Len, Flags);{$ENDIF}
end;
function c_send(Fd: Integer; Buf: Pointer; Len: NativeUInt; Flags: Integer): NativeInt; inline;
begin
{$IFDEF FPC}Result := fpSend(Fd, Buf, Len, Flags);{$ELSE}Result := send(Fd, Buf^, Len, Flags);{$ENDIF}
end;
function c_close(Fd: Integer): Integer; inline;
begin
{$IFDEF FPC}Result := fpClose(Fd);{$ELSE}Result := __close(Fd);{$ENDIF}
end;
function c_getsockname(Fd: Integer; Addr, Len: Pointer): Integer; inline;
begin
{$IFDEF FPC}Result := fpGetSockName(Fd, psockaddr(Addr), psocklen(Len));{$ELSE}Result := getsockname(Fd, psockaddr(Addr)^, psocklen_t(Len)^);{$ENDIF}
end;
function c_setsockopt(Fd, Level, OptName: Integer; OptVal: Pointer; OptLen: Cardinal): Integer; inline;
begin
{$IFDEF FPC}Result := fpSetSockOpt(Fd, Level, OptName, OptVal, OptLen);{$ELSE}Result := setsockopt(Fd, Level, OptName, OptVal, OptLen);{$ENDIF}
end;

function Htons(V: Word): Word; inline;
begin
  Result := Swap(V);
end;

procedure SetNonBlocking(Fd: Integer);
begin
{$IFDEF FPC}fpFcntl(Fd, F_SETFL, O_NONBLOCK);{$ELSE}fcntl(Fd, F_SETFL, O_NONBLOCK);{$ENDIF}
end;

procedure CloseSock(Fd: Integer);
begin
  c_close(Fd);
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
procedure SetNonBlocking(Fd: Integer);
var
  Arg: u_long;
begin
  Arg := 1;
  ioctlsocket(TSocket(Fd), Integer($8004667E) { FIONBIO }, Arg);
end;

procedure CloseSock(Fd: Integer);
begin
  closesocket(TSocket(Fd));
end;
{$ENDIF}

{ creates a listening TCP socket on 127.0.0.1, returns fd and port }
function CreateListener(out Port: Word): Integer;
var
  Addr: TSockAddrIn; { winsock's on Windows, our own record on Linux }
{$IFDEF MSWINDOWS}
  AddrLen: Integer;
{$ELSE}
  AddrLen: Cardinal;
{$ENDIF}
  OptVal: Integer;
begin
{$IFDEF MSWINDOWS}
  Result := Integer(socket(AF_INET, SOCK_STREAM, 0));
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_addr.S_addr := htonl($7F000001);
  Addr.sin_port := 0;
  OptVal := 1;
  setsockopt(TSocket(Result), SOL_SOCKET, SO_REUSEADDR, PAnsiChar(@OptVal), SizeOf(OptVal));
  bind(TSocket(Result), PSockAddr(@Addr)^, SizeOf(Addr));
  listen(TSocket(Result), 8);
  AddrLen := SizeOf(Addr);
  getsockname(TSocket(Result), PSockAddr(@Addr)^, AddrLen);
  Port := ntohs(Addr.sin_port);
{$ELSE}
  Result := c_socket(AF_INET, SOCK_STREAM, 0);
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_addr.s_addr := $0100007F; { 127.0.0.1, already big-endian byte order }
  Addr.sin_port := 0;
  OptVal := 1;
  c_setsockopt(Result, SOL_SOCKET, SO_REUSEADDR, @OptVal, SizeOf(OptVal));
  c_bind(Result, @Addr, SizeOf(Addr));
  c_listen(Result, 8);
  AddrLen := SizeOf(Addr);
  c_getsockname(Result, @Addr, @AddrLen);
  Port := Swap(Addr.sin_port);
{$ENDIF}
  SetNonBlocking(Result);
end;

{ blocking client connect for the test thread }
function ConnectTo(Port: Word): Integer;
var
  Addr: TSockAddrIn;
begin
{$IFDEF MSWINDOWS}
  Result := Integer(socket(AF_INET, SOCK_STREAM, 0));
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_addr.S_addr := htonl($7F000001);
  Addr.sin_port := htons(Port);
  connect(TSocket(Result), PSockAddr(@Addr)^, SizeOf(Addr));
{$ELSE}
  Result := c_socket(AF_INET, SOCK_STREAM, 0);
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_addr.s_addr := $0100007F;
  Addr.sin_port := Htons(Port);
  c_connect(Result, @Addr, SizeOf(Addr));
{$ENDIF}
end;

function SockRecv(Fd: Integer; Buf: Pointer; Len: Integer): Integer;
begin
{$IFDEF MSWINDOWS}
  Result := recv(TSocket(Fd), PByte(Buf)^, Len, 0);
{$ELSE}
  Result := c_recv(Fd, Buf, Len, 0);
{$ENDIF}
end;

function SockSend(Fd: Integer; Buf: Pointer; Len: Integer): Integer;
begin
{$IFDEF MSWINDOWS}
  Result := send(TSocket(Fd), PByte(Buf)^, Len, 0);
{$ELSE}
  Result := c_send(Fd, Buf, Len, 0);
{$ENDIF}
end;

{ ------------------------------------------------------------------ }
{ the echo server                                                     }
{ ------------------------------------------------------------------ }

type
  TEchoServer = class
  public
    Loop: TEvLoop;
    ListenerIo: TEvIo;
    Connections: Integer;
    EchoedBytes: Integer;
    procedure OnAccept(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnReadable(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

  TClientThread = class(TThread)
  public
    Port: Word;
    Async: TEvAsync;
    AllEchoed: Boolean;
    procedure Execute; override;
  end;

procedure TEchoServer.OnAccept(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  ClientFd: Integer;
  ConnIo: TEvIo;
begin
{$IFDEF MSWINDOWS}
  ClientFd := Integer(accept(TSocket(TEvIo(Watcher).Fd), nil, nil));
  if TSocket(ClientFd) = INVALID_SOCKET then
    Exit;
{$ELSE}
  ClientFd := c_accept(TEvIo(Watcher).Fd, nil, nil);
  if ClientFd < 0 then
    Exit;
{$ENDIF}
  SetNonBlocking(ClientFd);
  Inc(Connections);
  Writeln(Format('server: accepted connection #%d (fd %d)', [Connections, ClientFd]));

  { one io watcher per connection; freed in OnReadable on close }
  ConnIo := TEvIo.Create(ClientFd, [evRead]);
  ConnIo.OnEvent := OnReadable;
  ConnIo.Start(ALoop);
end;

procedure TEchoServer.OnReadable(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
var
  Io: TEvIo;
  Buf: array[0..1023] of Byte;
  N: Integer;
begin
  Io := TEvIo(Watcher);
  N := SockRecv(Io.Fd, @Buf, SizeOf(Buf));

  if N <= 0 then
  begin
    { peer closed (or error): stop watching and clean up }
    Writeln(Format('server: connection fd %d closed', [Io.Fd]));
    Io.Stop;
    CloseSock(Io.Fd);
    Io.Free;
    Exit;
  end;

  { echo back; for this demo a single non-blocking send suffices }
  SockSend(Io.Fd, @Buf, N);
  Inc(EchoedBytes, N);
end;

procedure TClientThread.Execute;
const
  Messages: array[0..1] of AnsiString = ('merhaba dunya', 'echo me too');
var
  Fd, I, N: Integer;
  Buf: array[0..1023] of AnsiChar;
  Reply, Chunk: AnsiString;
begin
  AllEchoed := True;

  Fd := ConnectTo(Port);
  try
    for I := Low(Messages) to High(Messages) do
    begin
      SockSend(Fd, PAnsiChar(Messages[I]), Length(Messages[I]));

      { collect the full echo (may arrive in pieces) }
      Reply := '';
      while Length(Reply) < Length(Messages[I]) do
      begin
        N := SockRecv(Fd, @Buf, SizeOf(Buf));
        if N <= 0 then
          Break;
        SetString(Chunk, PAnsiChar(@Buf), N);
        Reply := Reply + Chunk;
      end;

      if Reply <> Messages[I] then
        AllEchoed := False;
    end;
  finally
    CloseSock(Fd);
    Sleep(50); { let the server observe the close before we wake the loop }
    Async.Send;
  end;
end;

type
  TMain = class
  public
    Done: Boolean;
    procedure OnClientDone(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
    procedure OnGuard(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
  end;

procedure TMain.OnClientDone(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Done := True;
  ALoop.BreakLoop(evbreakAll);
end;

procedure TMain.OnGuard(ALoop: TEvLoop; Watcher: TEvWatcher; REvents: TEvEvents);
begin
  Writeln('guard timeout hit');
  ALoop.BreakLoop(evbreakAll);
end;

var
  Server: TEchoServer;
  Main: TMain;
  Loop: TEvLoop;
  Port: Word;
  ListenFd: Integer;
  Async: TEvAsync;
  Guard: TEvTimer;
  Client: TClientThread;
begin
  try
    Server := TEchoServer.Create;
    Main := TMain.Create;
    Loop := TEvLoop.Default;
    Server.Loop := Loop;

    ListenFd := CreateListener(Port);
    Writeln('echo server listening on 127.0.0.1:', Port,
      '  backend=', Ord(Loop.Backend.Kind), ' (0=select, 2=epoll)');

    Server.ListenerIo := TEvIo.Create(ListenFd, [evRead]);
    Server.ListenerIo.OnEvent := Server.OnAccept;
    Server.ListenerIo.Start(Loop);

    Async := TEvAsync.Create;
    Async.OnEvent := Main.OnClientDone;
    Async.Start(Loop);

    Guard := TEvTimer.Create(3.0, 0);
    Guard.OnTimeout := Main.OnGuard;
    Guard.Start(Loop);

    Client := TClientThread.Create(True);
    Client.Port := Port;
    Client.Async := Async;
    Client.Start;

    Loop.Run;

    Client.WaitFor;

    Loop.Verify; { exercise the ev_verify port while everything is live }

    if Main.Done and Client.AllEchoed and (Server.Connections = 1)
      and (Server.EchoedBytes = 24) then
      Writeln('SUCCESS: all client messages were echoed through the loop.')
    else
    begin
      Writeln(Format('FAILURE: done=%s echoed=%s conns=%d bytes=%d',
        [BoolToStr(Main.Done, True), BoolToStr(Client.AllEchoed, True),
         Server.Connections, Server.EchoedBytes]));
      ExitCode := 1;
    end;

    Server.ListenerIo.Free;
    CloseSock(ListenFd);
    Async.Free;
    Guard.Free;
    Client.Free;
    Server.Free;
    Main.Free;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
