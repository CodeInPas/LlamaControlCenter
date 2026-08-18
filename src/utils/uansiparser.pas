unit uansiparser;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Graphics;

type
  { ANSI Formatting Styles }
  TAnsiFontStyle = (afsBold, afsDim, afsItalic, afsUnderline, afsBlink, afsInverse, afsHidden, afsStrikethrough);
  TAnsiFontStyles = set of TAnsiFontStyle;

  { Parsed Text Fragment with Visual Attributes }
  TAnsiChunk = record
    Text: string;
    FgColor: TColor;
    BgColor: TColor;
    Styles: TAnsiFontStyles;

    class function Create(const AText: string; const AFg, ABg: TColor; const AStyles: TAnsiFontStyles): TAnsiChunk; static;
  end;
  TAnsiChunkArray = array of TAnsiChunk;

  { Parser State Machine Tracker }
  TAnsiState = record
    CurrentFg: TColor;
    CurrentBg: TColor;
    DefaultFg: TColor;
    DefaultBg: TColor;
    CurrentStyles: TAnsiFontStyles;

    procedure Reset;
    procedure ProcessSGRParams(const AParams: array of Integer);
  end;

{ Core Utilities }
function StripAnsi(const AText: string): string;
function ParseAnsi(const AText: string; const ADefaultFg: TColor = clSilver; const ADefaultBg: TColor = clNone): TAnsiChunkArray;
function AnsiToHtml(const AText: string; const ADefaultFgHex: string = '#D4D4D4'; const ADefaultBgHex: string = '#1E1E1E'): string;
function AnsiColorToTColor(const ACode: Integer; const AIsBright: Boolean = False): TColor;
function Ansi256ToTColor(const AIndex: Integer): TColor;
function ColorToHexRGB(const AColor: TColor): string;

implementation

const
  ANSI_ESC = #27;

{ Standard 16 ANSI Color Palette (RGB Mapping) }
  ANSI_COLORS: array[0..7] of TColor = (
    $000000, // Black
    $0000C0, // Red (BGR: $0000C0)
    $00C000, // Green
    $00C0C0, // Yellow
    $C00000, // Blue
    $C000C0, // Magenta
    $C0C000, // Cyan
    $C0C0C0  // White / Silver
  );

  ANSI_BRIGHT_COLORS: array[0..7] of TColor = (
    $808080, // Bright Black / Gray
    $0000FF, // Bright Red
    $00FF00, // Bright Green
    $00FFFF, // Bright Yellow
    $FF0000, // Bright Blue
    $FF00FF, // Bright Magenta
    $FFFF00, // Bright Cyan
    $FFFFFF  // Bright White
  );

{ TAnsiChunk }

class function TAnsiChunk.Create(const AText: string; const AFg, ABg: TColor; const AStyles: TAnsiFontStyles): TAnsiChunk;
begin
  Result.Text := AText;
  Result.FgColor := AFg;
  Result.BgColor := ABg;
  Result.Styles := AStyles;
end;

{ Color Helpers }

function AnsiColorToTColor(const ACode: Integer; const AIsBright: Boolean): TColor;
var
  Idx: Integer;
begin
  Idx := ACode mod 8;
  if AIsBright then
    Result := ANSI_BRIGHT_COLORS[Idx]
  else
    Result := ANSI_COLORS[Idx];
end;

function Ansi256ToTColor(const AIndex: Integer): TColor;
var
  R, G, B, Gray: Integer;
  Idx: Integer;
begin
  if (AIndex < 0) or (AIndex > 255) then
    Exit(clSilver);

  // Standard 16 Colors
  if AIndex < 8 then
    Exit(ANSI_COLORS[AIndex]);
  if AIndex < 16 then
    Exit(ANSI_BRIGHT_COLORS[AIndex - 8]);

  // 6x6x6 Color Cube (16 - 231)
  if AIndex <= 231 then
  begin
    Idx := AIndex - 16;
    R := (Idx div 36) * 51;
    G := ((Idx mod 36) div 6) * 51;
    B := (Idx mod 6) * 51;
    Exit(RGBToColor(R, G, B));
  end;

  // Grayscale Ramp (232 - 255)
  Gray := 8 + (AIndex - 232) * 10;
  Result := RGBToColor(Gray, Gray, Gray);
end;

function ColorToHexRGB(const AColor: TColor): string;
var
  RGBVal: LongInt;
  R, G, B: Byte;
begin
  RGBVal := ColorToRGB(AColor);
  R := Red(RGBVal);
  G := Green(RGBVal);
  B := Blue(RGBVal);
  Result := Format('#%.2X%.2X%.2X', [R, G, B]);
end;

{ TAnsiState }

procedure TAnsiState.Reset;
begin
  CurrentFg := DefaultFg;
  CurrentBg := DefaultBg;
  CurrentStyles := [];
end;

procedure TAnsiState.ProcessSGRParams(const AParams: array of Integer);
var
  i, Len, Code: Integer;
begin
  Len := Length(AParams);
  if Len = 0 then
  begin
    Reset;
    Exit;
  end;

  i := 0;
  while i < Len do
  begin
    Code := AParams[i];
    case Code of
      0: Reset;
      1: Include(CurrentStyles, afsBold);
      2: Include(CurrentStyles, afsDim);
      3: Include(CurrentStyles, afsItalic);
      4: Include(CurrentStyles, afsUnderline);
      5, 6: Include(CurrentStyles, afsBlink);
      7: Include(CurrentStyles, afsInverse);
      8: Include(CurrentStyles, afsHidden);
      9: Include(CurrentStyles, afsStrikethrough);
      21, 22: Exclude(CurrentStyles, afsBold);
      23: Exclude(CurrentStyles, afsItalic);
      24: Exclude(CurrentStyles, afsUnderline);
      27: Exclude(CurrentStyles, afsInverse);
      28: Exclude(CurrentStyles, afsHidden);
      29: Exclude(CurrentStyles, afsStrikethrough);

      // Standard Foreground (30-37)
      30..37:
        CurrentFg := AnsiColorToTColor(Code - 30, afsBold in CurrentStyles);
      39:
        CurrentFg := DefaultFg;

      // Standard Background (40-47)
      40..47:
        CurrentBg := AnsiColorToTColor(Code - 40, False);
      49:
        CurrentBg := DefaultBg;

      // High Intensity Foreground (90-97)
      90..97:
        CurrentFg := AnsiColorToTColor(Code - 90, True);

      // High Intensity Background (100-107)
      100..107:
        CurrentBg := AnsiColorToTColor(Code - 100, True);

      // Extended Color Mode: 38 (FG) and 48 (BG)
      38, 48:
      begin
        if (i + 2 < Len) and (AParams[i + 1] = 5) then
        begin
          // 256 Color Mode: 38;5;n or 48;5;n
          if Code = 38 then
            CurrentFg := Ansi256ToTColor(AParams[i + 2])
          else
            CurrentBg := Ansi256ToTColor(AParams[i + 2]);
          Inc(i, 2);
        end
        else if (i + 4 < Len) and (AParams[i + 1] = 2) then
        begin
          // 24-bit TrueColor: 38;2;r;g;b or 48;2;r;g;b
          if Code = 38 then
            CurrentFg := RGBToColor(AParams[i + 2], AParams[i + 3], AParams[i + 4])
          else
            CurrentBg := RGBToColor(AParams[i + 2], AParams[i + 3], AParams[i + 4]);
          Inc(i, 4);
        end;
      end;
    end;
    Inc(i);
  end;
end;

{ Parsing Algorithms }

function StripAnsi(const AText: string): string;
var
  i, Len: Integer;
  InSeq: Boolean;
begin
  Result := '';
  Len := Length(AText);
  if Len = 0 then Exit;

  SetLength(Result, Len);
  i := 1;
  InSeq := False;
  Len := 0;

  while i <= Length(AText) do
  begin
    if (AText[i] = ANSI_ESC) and (i < Length(AText)) and (AText[i + 1] = '[') then
    begin
      InSeq := True;
      Inc(i, 2);
      while (i <= Length(AText)) and InSeq do
      begin
        if AText[i] in ['A'..'Z', 'a'..'z', '~'] then
          InSeq := False;
        Inc(i);
      end;
      Continue;
    end;

    Inc(Len);
    Result[Len] := AText[i];
    Inc(i);
  end;

  SetLength(Result, Len);
end;

function ParseAnsi(const AText: string; const ADefaultFg: TColor; const ADefaultBg: TColor): TAnsiChunkArray;
var
  State: TAnsiState;
  TextLen, i, SeqStart, ChunkCount: Integer;
  CurSegment: string;
  ParamStr, NumStr: string;
  Params: array of Integer;
  CmdChar: Char;

  procedure FlushChunk;
  var
    EffectiveFg, EffectiveBg: TColor;
  begin
    if CurSegment = '' then Exit;

    if afsInverse in State.CurrentStyles then
    begin
      EffectiveFg := State.CurrentBg;
      EffectiveBg := State.CurrentFg;
    end
    else
    begin
      EffectiveFg := State.CurrentFg;
      EffectiveBg := State.CurrentBg;
    end;

    Inc(ChunkCount);
    SetLength(Result, ChunkCount);
    Result[ChunkCount - 1] := TAnsiChunk.Create(CurSegment, EffectiveFg, EffectiveBg, State.CurrentStyles);
    CurSegment := '';
  end;

  procedure ParseParams(const ARawParams: string);
  var
    pIdx, Count, ParsedVal, CodeErr: Integer;
  begin
    SetLength(Params, 0);
    if ARawParams = '' then
    begin
      SetLength(Params, 1);
      Params[0] := 0;
      Exit;
    end;

    pIdx := 1;
    Count := 0;
    while pIdx <= Length(ARawParams) do
    begin
      NumStr := '';
      while (pIdx <= Length(ARawParams)) and (ARawParams[pIdx] <> ';') do
      begin
        NumStr := NumStr + ARawParams[pIdx];
        Inc(pIdx);
      end;

      Inc(Count);
      SetLength(Params, Count);
      Val(NumStr, ParsedVal, CodeErr);
      if CodeErr = 0 then
        Params[Count - 1] := ParsedVal
      else
        Params[Count - 1] := 0;

      Inc(pIdx);
    end;
  end;

begin
  SetLength(Result, 0);
  TextLen := Length(AText);
  if TextLen = 0 then Exit;

  State.DefaultFg := ADefaultFg;
  State.DefaultBg := ADefaultBg;
  State.Reset;

  CurSegment := '';
  ChunkCount := 0;
  i := 1;

  while i <= TextLen do
  begin
    if (AText[i] = ANSI_ESC) and (i < TextLen) and (AText[i + 1] = '[') then
    begin
      FlushChunk;
      Inc(i, 2);
      SeqStart := i;

      while (i <= TextLen) and not (AText[i] in ['A'..'Z', 'a'..'z', '~']) do
        Inc(i);

      if i <= TextLen then
      begin
        CmdChar := AText[i];
        ParamStr := Copy(AText, SeqStart, i - SeqStart);

        if CmdChar = 'm' then // SGR Command
        begin
          ParseParams(ParamStr);
          State.ProcessSGRParams(Params);
        end;
        Inc(i);
      end;
      Continue;
    end;

    CurSegment := CurSegment + AText[i];
    Inc(i);
  end;

  FlushChunk;
end;

function AnsiToHtml(const AText: string; const ADefaultFgHex: string; const ADefaultBgHex: string): string;
var
  Chunks: TAnsiChunkArray;
  i: Integer;
  ChunkText, StyleAttr: string;
begin
  Chunks := ParseAnsi(AText, TColor($00D4D4D4), clNone);
  if Length(Chunks) = 0 then Exit('');

  Result := '<div style="font-family: monospace; white-space: pre-wrap; background-color: ' + ADefaultBgHex + '; color: ' + ADefaultFgHex + ';">';
  for i := 0 to High(Chunks) do
  begin
    ChunkText := Chunks[i].Text;
    // Escape HTML entities
    ChunkText := StringReplace(ChunkText, '&', '&amp;', [rfReplaceAll]);
    ChunkText := StringReplace(ChunkText, '<', '&lt;', [rfReplaceAll]);
    ChunkText := StringReplace(ChunkText, '>', '&gt;', [rfReplaceAll]);
    ChunkText := StringReplace(ChunkText, '"', '&quot;', [rfReplaceAll]);

    StyleAttr := 'color: ' + ColorToHexRGB(Chunks[i].FgColor) + ';';
    if Chunks[i].BgColor <> clNone then
      StyleAttr := StyleAttr + ' background-color: ' + ColorToHexRGB(Chunks[i].BgColor) + ';';

    if afsBold in Chunks[i].Styles then
      StyleAttr := StyleAttr + ' font-weight: bold;';
    if afsItalic in Chunks[i].Styles then
      StyleAttr := StyleAttr + ' font-style: italic;';
    if afsUnderline in Chunks[i].Styles then
      StyleAttr := StyleAttr + ' text-decoration: underline;';
    if afsStrikethrough in Chunks[i].Styles then
      StyleAttr := StyleAttr + ' text-decoration: line-through;';

    Result := Result + '<span style="' + StyleAttr + '">' + ChunkText + '</span>';
  end;
  Result := Result + '</div>';
end;

end.
