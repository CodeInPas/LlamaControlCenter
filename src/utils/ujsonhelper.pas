unit ujsonhelper;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, jsonscanner;

{ Parsing and Serialization }
function ParseJSON(const AJSONString: string): TJSONData;
function TryParseJSON(const AJSONString: string; out AData: TJSONData): Boolean;
function LoadJSONFile(const AFilePath: string): TJSONData;
function SaveJSONFile(const AData: TJSONData; const AFilePath: string; const AFormatted: Boolean = True): Boolean;
function JSONToString(const AData: TJSONData; const AFormatted: Boolean = True): string;

{ Safe Direct Object Key Getters }
function GetJSONString(const AObj: TJSONObject; const AKey: string; const ADefault: string = ''): string;
function GetJSONInt(const AObj: TJSONObject; const AKey: string; const ADefault: Integer = 0): Integer;
function GetJSONInt64(const AObj: TJSONObject; const AKey: string; const ADefault: Int64 = 0): Int64;
function GetJSONFloat(const AObj: TJSONObject; const AKey: string; const ADefault: Double = 0.0): Double;
function GetJSONBool(const AObj: TJSONObject; const AKey: string; const ADefault: Boolean = False): Boolean;
function GetJSONArray(const AObj: TJSONObject; const AKey: string): TJSONArray;
function GetJSONObject(const AObj: TJSONObject; const AKey: string): TJSONObject;

{ Safe Deep Path Finders (e.g. 'choices[0].delta.content' or 'data.model.id') }
function FindPathString(const AData: TJSONData; const APath: string; const ADefault: string = ''): string;
function FindPathInt(const AData: TJSONData; const APath: string; const ADefault: Integer = 0): Integer;
function FindPathInt64(const AData: TJSONData; const APath: string; const ADefault: Int64 = 0): Int64;
function FindPathFloat(const AData: TJSONData; const APath: string; const ADefault: Double = 0.0): Double;
function FindPathBool(const AData: TJSONData; const APath: string; const ADefault: Boolean = False): Boolean;
function FindPathArray(const AData: TJSONData; const APath: string): TJSONArray;
function FindPathObject(const AData: TJSONData; const APath: string): TJSONObject;

{ Safe Setter Utilities }
procedure SetOrAddString(const AObj: TJSONObject; const AKey, AValue: string);
procedure SetOrAddInt(const AObj: TJSONObject; const AKey: string; const AValue: Integer);
procedure SetOrAddInt64(const AObj: TJSONObject; const AKey: string; const AValue: Int64);
procedure SetOrAddFloat(const AObj: TJSONObject; const AKey: string; const AValue: Double);
procedure SetOrAddBool(const AObj: TJSONObject; const AKey: string; const AValue: Boolean);

implementation

function ParseJSON(const AJSONString: string): TJSONData;
var
  Parser: TJSONParser;
begin
  Result := nil;
  if Trim(AJSONString) = '' then Exit;

  Parser := TJSONParser.Create(AJSONString, [joUTF8, joComments]);
  try
    Result := Parser.Parse;
  finally
    Parser.Free;
  end;
end;

function TryParseJSON(const AJSONString: string; out AData: TJSONData): Boolean;
begin
  AData := nil;
  try
    AData := ParseJSON(AJSONString);
    Result := Assigned(AData);
  except
    AData := nil;
    Result := False;
  end;
end;

function LoadJSONFile(const AFilePath: string): TJSONData;
var
  FileStream: TFileStream;
  Parser: TJSONParser;
begin
  Result := nil;
  if not FileExists(AFilePath) then Exit;

  FileStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    Parser := TJSONParser.Create(FileStream, [joUTF8, joComments]);
    try
      Result := Parser.Parse;
    finally
      Parser.Free;
    end;
  finally
    FileStream.Free;
  end;
end;

function SaveJSONFile(const AData: TJSONData; const AFilePath: string; const AFormatted: Boolean): Boolean;
var
  StrList: TStringList;
  TargetDir: string;
begin
  Result := False;
  if not Assigned(AData) or (AFilePath = '') then Exit;

  TargetDir := ExtractFileDir(AFilePath);
  if (TargetDir <> '') and not DirectoryExists(TargetDir) then
    ForceDirectories(TargetDir);

  StrList := TStringList.Create;
  try
    if AFormatted then
      StrList.Text := AData.FormatJSON([foSkipWhiteSpace], 2)
    else
      StrList.Text := AData.AsJSON;

    StrList.SaveToFile(AFilePath, TEncoding.UTF8);
    Result := True;
  except
    Result := False;
  end;
  StrList.Free;
end;

function JSONToString(const AData: TJSONData; const AFormatted: Boolean): string;
begin
  if not Assigned(AData) then Exit('{}');
  if AFormatted then
    Result := AData.FormatJSON([foSkipWhiteSpace], 2)
  else
    Result := AData.AsJSON;
end;

function GetJSONString(const AObj: TJSONObject; const AKey: string; const ADefault: string): string;
var
  Item: TJSONData;
begin
  if not Assigned(AObj) then Exit(ADefault);
  Item := AObj.Find(AKey);
  if Assigned(Item) and not Item.IsNull then
    Result := Item.AsString
  else
    Result := ADefault;
end;

function GetJSONInt(const AObj: TJSONObject; const AKey: string; const ADefault: Integer): Integer;
var
  Item: TJSONData;
begin
  if not Assigned(AObj) then Exit(ADefault);
  Item := AObj.Find(AKey);
  if Assigned(Item) and not Item.IsNull then
    Result := Item.AsInteger
  else
    Result := ADefault;
end;

function GetJSONInt64(const AObj: TJSONObject; const AKey: string; const ADefault: Int64): Int64;
var
  Item: TJSONData;
begin
  if not Assigned(AObj) then Exit(ADefault);
  Item := AObj.Find(AKey);
  if Assigned(Item) and not Item.IsNull then
    Result := Item.AsInt64
  else
    Result := ADefault;
end;

function GetJSONFloat(const AObj: TJSONObject; const AKey: string; const ADefault: Double): Double;
var
  Item: TJSONData;
begin
  if not Assigned(AObj) then Exit(ADefault);
  Item := AObj.Find(AKey);
  if Assigned(Item) and not Item.IsNull then
    Result := Item.AsFloat
  else
    Result := ADefault;
end;

function GetJSONBool(const AObj: TJSONObject; const AKey: string; const ADefault: Boolean): Boolean;
var
  Item: TJSONData;
begin
  if not Assigned(AObj) then Exit(ADefault);
  Item := AObj.Find(AKey);
  if Assigned(Item) and not Item.IsNull then
    Result := Item.AsBoolean
  else
    Result := ADefault;
end;

function GetJSONArray(const AObj: TJSONObject; const AKey: string): TJSONArray;
var
  Item: TJSONData;
begin
  Result := nil;
  if not Assigned(AObj) then Exit;
  Item := AObj.Find(AKey);
  if Assigned(Item) and (Item.JSONType = jtArray) then
    Result := TJSONArray(Item);
end;

function GetJSONObject(const AObj: TJSONObject; const AKey: string): TJSONObject;
var
  Item: TJSONData;
begin
  Result := nil;
  if not Assigned(AObj) then Exit;
  Item := AObj.Find(AKey);
  if Assigned(Item) and (Item.JSONType = jtObject) then
    Result := TJSONObject(Item);
end;

function FindPathString(const AData: TJSONData; const APath: string; const ADefault: string): string;
var
  Found: TJSONData;
begin
  if not Assigned(AData) then Exit(ADefault);
  Found := AData.FindPath(APath);
  if Assigned(Found) and not Found.IsNull then
    Result := Found.AsString
  else
    Result := ADefault;
end;

function FindPathInt(const AData: TJSONData; const APath: string; const ADefault: Integer): Integer;
var
  Found: TJSONData;
begin
  if not Assigned(AData) then Exit(ADefault);
  Found := AData.FindPath(APath);
  if Assigned(Found) and not Found.IsNull then
    Result := Found.AsInteger
  else
    Result := ADefault;
end;

function FindPathInt64(const AData: TJSONData; const APath: string; const ADefault: Int64): Int64;
var
  Found: TJSONData;
begin
  if not Assigned(AData) then Exit(ADefault);
  Found := AData.FindPath(APath);
  if Assigned(Found) and not Found.IsNull then
    Result := Found.AsInt64
  else
    Result := ADefault;
end;

function FindPathFloat(const AData: TJSONData; const APath: string; const ADefault: Double): Double;
var
  Found: TJSONData;
begin
  if not Assigned(AData) then Exit(ADefault);
  Found := AData.FindPath(APath);
  if Assigned(Found) and not Found.IsNull then
    Result := Found.AsFloat
  else
    Result := ADefault;
end;

function FindPathBool(const AData: TJSONData; const APath: string; const ADefault: Boolean): Boolean;
var
  Found: TJSONData;
begin
  if not Assigned(AData) then Exit(ADefault);
  Found := AData.FindPath(APath);
  if Assigned(Found) and not Found.IsNull then
    Result := Found.AsBoolean
  else
    Result := ADefault;
end;

function FindPathArray(const AData: TJSONData; const APath: string): TJSONArray;
var
  Found: TJSONData;
begin
  Result := nil;
  if not Assigned(AData) then Exit;
  Found := AData.FindPath(APath);
  if Assigned(Found) and (Found.JSONType = jtArray) then
    Result := TJSONArray(Found);
end;

function FindPathObject(const AData: TJSONData; const APath: string): TJSONObject;
var
  Found: TJSONData;
begin
  Result := nil;
  if not Assigned(AData) then Exit;
  Found := AData.FindPath(APath);
  if Assigned(Found) and (Found.JSONType = jtObject) then
    Result := TJSONObject(Found);
end;

procedure SetOrAddString(const AObj: TJSONObject; const AKey, AValue: string);
var
  Idx: Integer;
begin
  if not Assigned(AObj) then Exit;
  Idx := AObj.IndexOfName(AKey);
  if Idx >= 0 then
    AObj.Items[Idx].AsString := AValue
  else
    AObj.Add(AKey, AValue);
end;

procedure SetOrAddInt(const AObj: TJSONObject; const AKey: string; const AValue: Integer);
var
  Idx: Integer;
begin
  if not Assigned(AObj) then Exit;
  Idx := AObj.IndexOfName(AKey);
  if Idx >= 0 then
    AObj.Items[Idx].AsInteger := AValue
  else
    AObj.Add(AKey, AValue);
end;

procedure SetOrAddInt64(const AObj: TJSONObject; const AKey: string; const AValue: Int64);
var
  Idx: Integer;
begin
  if not Assigned(AObj) then Exit;
  Idx := AObj.IndexOfName(AKey);
  if Idx >= 0 then
    AObj.Items[Idx].AsInt64 := AValue
  else
    AObj.Add(AKey, AValue);
end;

procedure SetOrAddFloat(const AObj: TJSONObject; const AKey: string; const AValue: Double);
var
  Idx: Integer;
begin
  if not Assigned(AObj) then Exit;
  Idx := AObj.IndexOfName(AKey);
  if Idx >= 0 then
    AObj.Items[Idx].AsFloat := AValue
  else
    AObj.Add(AKey, AValue);
end;

procedure SetOrAddBool(const AObj: TJSONObject; const AKey: string; const AValue: Boolean);
var
  Idx: Integer;
begin
  if not Assigned(AObj) then Exit;
  Idx := AObj.IndexOfName(AKey);
  if Idx >= 0 then
    AObj.Items[Idx].AsBoolean := AValue
  else
    AObj.Add(AKey, AValue);
end;

end.

