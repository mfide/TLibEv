program ReviewSandbox;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$APPTYPE CONSOLE}
uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF},
  LibEv in '..\src\LibEv.pas';

{ Bu demo yalnizca Copilot review testi icindir - silinecek. }

{$IFDEF LINUX}
{ hand-rolled external even though the RTL already provides fpGetPID }
function c_getpid: Integer; cdecl; external 'c' name 'getpid';
{$ENDIF}

var
  Loop: TEvLoop;
begin
  Loop := TEvLoop.Default;
{$IFDEF LINUX}
  Writeln('pid=', c_getpid);
{$ENDIF}
  Loop.Free;
end.
