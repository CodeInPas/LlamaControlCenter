unit uformatting;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math;

{ Byte & Transfer Rate Formats }
function FormatBytes(const ABytes: Int64; const ADecimals: Integer = 2): string;
function FormatSpeed(const ABytesPerSec: Double; const ADecimals: Integer = 2): string;
function FormatTokenSpeed(const ATokensPerSec: Double; const ADecimals: Integer = 1): string;

{ Time, Duration & ETA Formats }
function FormatDurationMs(const AMilliSeconds: Int64): string;
function FormatDurationSec(const ASeconds: Double): string;
function FormatETA(const ARemainingBytes: Int64; const ASpeedBytesPerSec: Double): string;
function FormatTimestamp(const ADateTime: TDateTime; const AIncludeDate: Boolean = False): string;

{ Numeric, Count & Parameter Formats }
function FormatPercent(const ACurrent, ATotal: Double; const ADecimals: Integer = 1): string;
function FormatThousands(const AValue: Int64): string;
function FormatParameterCount(const ATotalParams: UInt64): string;

{ String Helpers }
function TruncateString(const AStr: string; const AMaxLen: Integer; const AWithEllipsis: Boolean = True): string;
function EscapeCliArgument(const AArg: string): string;

implementation

function FormatBytes(const ABytes: Int64; const ADecimals: Integer): string;
const
  Units: array[0..5] of string = ('B', 'KB', 'MB', 'GB', 'TB', 'PB');
var
  Size: Double;
  UnitIdx: Integer;
begin
  if ABytes <= 0 then
    Exit('0 B');

  Size := Abs(ABytes);
  UnitIdx := 0;

  while (Size >= 1024.0) and (UnitIdx < High(Units)) do
  begin
    Size := Size / 1024.0;
    Inc(UnitIdx);
  end;

  if UnitIdx = 0 then
    Result := Format('%d B', [ABytes])
  else
    Result := Format('%.*f %s', [ADecimals, Size, Units[UnitIdx]]);

  if ABytes < 0 then
    Result := '-' + Result;
end;

function FormatSpeed(const ABytesPerSec: Double; const ADecimals: Integer): string;
begin
  if ABytesPerSec <= 0.0 then
    Exit('0 B/s');
  Result := FormatBytes(Round(ABytesPerSec), ADecimals) + '/s';
end;

function FormatTokenSpeed(const ATokensPerSec: Double; const ADecimals: Integer): string;
begin
  if IsNan(ATokensPerSec) or IsInfinite(ATokensPerSec) or (ATokensPerSec <= 0.0) then
    Exit('0.0 t/s');
  Result := Format('%.*f t/s', [ADecimals, ATokensPerSec]);
end;

function FormatDurationMs(const AMilliSeconds: Int64): string;
var
  TotalSec, Ms: Int64;
  Hours, Mins, Secs: Integer;
begin
  if AMilliSeconds < 0 then
    Exit('0ms');

  if AMilliSeconds < 1000 then
    Exit(Format('%dms', [AMilliSeconds]));

  TotalSec := AMilliSeconds div 1000;
  Ms := AMilliSeconds mod 1000;
  Hours := TotalSec div 3600;
  Mins := (TotalSec mod 3600) div 60;
  Secs := TotalSec mod 60;

  if Hours > 0 then
    Result := Format('%.2d:%.2d:%.2d', [Hours, Mins, Secs])
  else if Mins > 0 then
    Result := Format('%.2d:%.2d', [Mins, Secs])
  else
    Result := Format('%d.%03ds', [Secs, Ms]);
end;

function FormatDurationSec(const ASeconds: Double): string;
begin
  if IsNan(ASeconds) or IsInfinite(ASeconds) or (ASeconds <= 0.0) then
    Exit('0s');
  Result := FormatDurationMs(Round(ASeconds * 1000.0));
end;

function FormatETA(const ARemainingBytes: Int64; const ASpeedBytesPerSec: Double): string;
var
  SecondsRemaining: Double;
  Hours, Mins, Secs: Integer;
begin
  if (ARemainingBytes <= 0) or (ASpeedBytesPerSec <= 0.001) then
    Exit('--:--:--');

  SecondsRemaining := ARemainingBytes / ASpeedBytesPerSec;
  if SecondsRemaining > 864000.0 then // > 10 days
    Exit('> 10 days');

  Hours := Trunc(SecondsRemaining) div 3600;
  Mins := (Trunc(SecondsRemaining) mod 3600) div 60;
  Secs := Trunc(SecondsRemaining) mod 60;

  Result := Format('%.2d:%.2d:%.2d', [Hours, Mins, Secs]);
end;

function FormatTimestamp(const ADateTime: TDateTime; const AIncludeDate: Boolean): string;
begin
  if AIncludeDate then
    Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', ADateTime)
  else
    Result := FormatDateTime('hh:nn:ss', ADateTime);
end;

function FormatPercent(const ACurrent, ATotal: Double; const ADecimals: Integer): string;
var
  Pct: Double;
begin
  if (ATotal <= 0.0) or IsNan(ACurrent) or IsNan(ATotal) then
    Exit('0.0%');

  Pct := (ACurrent / ATotal) * 100.0;
  if Pct > 100.0 then
    Pct := 100.0
  else if Pct < 0.0 then
    Pct := 0.0;

  Result := Format('%.*f%%', [ADecimals, Pct]);
end;

function FormatThousands(const AValue: Int64): string;
var
  S, Res: string;
  Len, i, CommaCount: Integer;
begin
  S := IntToStr(Abs(AValue));
  Len := Length(S);
  if Len <= 3 then
  begin
    if AValue < 0 then
      Exit('-' + S)
    else
      Exit(S);
  end;

  Res := '';
  CommaCount := 0;
  for i := Len downto 1 do
  begin
    Res := S[i] + Res;
    Inc(CommaCount);
    if (CommaCount mod 3 = 0) and (i > 1) then
      Res := DefaultFormatSettings.ThousandSeparator + Res;
  end;

  if AValue < 0 then
    Result := '-' + Res
  else
    Result := Res;
end;

function FormatParameterCount(const ATotalParams: UInt64): string;
begin
  if ATotalParams >= 1000000000 then
    Result := Format('%.2fB', [ATotalParams / 1000000000.0])
  else if ATotalParams >= 1000000 then
    Result := Format('%.2fM', [ATotalParams / 1000000.0])
  else if ATotalParams >= 1000 then
    Result := Format('%.2fK', [ATotalParams / 1000.0])
  else
    Result := UIntToStr(ATotalParams);
end;

function TruncateString(const AStr: string; const AMaxLen: Integer; const AWithEllipsis: Boolean): string;
begin
  if Length(AStr) <= AMaxLen then
    Exit(AStr);

  if AWithEllipsis and (AMaxLen > 3) then
    Result := Copy(AStr, 1, AMaxLen - 3) + '...'
  else
    Result := Copy(AStr, 1, AMaxLen);
end;

function EscapeCliArgument(const AArg: string): string;
var
  S: string;
begin
  if (Pos(' ', AArg) = 0) and (Pos('"', AArg) = 0) and (Length(AArg) > 0) then
    Exit(AArg);

  S := StringReplace(AArg, '"', '\"', [rfReplaceAll]);
  Result := '"' + S + '"';
end;

end.

