unit ulogger;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, SyncObjs, DateUtils, uconfigtypes;

type
  { Log Event Callback for UI Hook / Terminal Views }
  TLogEvent = procedure(const ATimestamp: TDateTime; const ALevel: TLogLevel;
                        const ATag, AMsg: string) of object;

  { Single Log Record }
  TLogEntry = record
    Timestamp: TDateTime;
    Level: TLogLevel;
    Tag: string;
    Message: string;
    function ToStringFormatted(const AIncludeTag: Boolean = True): string;
  end;
  TLogEntryArray = array of TLogEntry;

  { Thread-Safe Logger Engine }
  TLogger = class
  private
    class var FInstance: TLogger;
  private
    FLock: TCriticalSection;
    FLogLevel: TLogLevel;
    FLogToFile: Boolean;
    FLogFilePath: string;
    FMaxLogLines: Integer;
    FLogBuffer: TLogEntryArray;
    FBufferCount: Integer;
    FOnLog: TLogEvent;

    procedure WriteToFile(const AFormattedLine: string);
    procedure AddToBuffer(const AEntry: TLogEntry);
    procedure SetLogLevel(const AValue: TLogLevel);
    procedure SetLogToFile(const AValue: Boolean);
    procedure SetLogFilePath(const AValue: string);
  public
    constructor Create;
    destructor Destroy; override;

    class function Instance: TLogger; static;
    class destructor ClassDestroy;

    procedure Log(const ALevel: TLogLevel; const AMsg: string; const ATag: string = 'SYS');
    procedure Debug(const AMsg: string; const ATag: string = 'DEBUG');
    procedure Info(const AMsg: string; const ATag: string = 'INFO');
    procedure Warn(const AMsg: string; const ATag: string = 'WARN');
    procedure Error(const AMsg: string; const ATag: string = 'ERROR');

    procedure ClearBuffer;
    function GetBufferSnapshot: TLogEntryArray;

    property MinLevel: TLogLevel read FLogLevel write SetLogLevel;
    property LogToFileEnabled: Boolean read FLogToFile write SetLogToFile;
    property LogFilePath: string read FLogFilePath write SetLogFilePath;
    property MaxLogLines: Integer read FMaxLogLines write FMaxLogLines;
    property OnLog: TLogEvent read FOnLog write FOnLog;
  end;

{ Global Shortcut Procedures }
procedure LogDebug(const AMsg: string; const ATag: string = 'DEBUG');
procedure LogInfo(const AMsg: string; const ATag: string = 'INFO');
procedure LogWarn(const AMsg: string; const ATag: string = 'WARN');
procedure LogError(const AMsg: string; const ATag: string = 'ERROR');

implementation

{ TLogEntry }

function TLogEntry.ToStringFormatted(const AIncludeTag: Boolean): string;
var
  TimeStr, LevelStr: string;
begin
  TimeStr := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Timestamp);
  LevelStr := LogLevelToString(Level);
  if AIncludeTag and (Tag <> '') then
    Result := Format('[%s] [%-5s] [%s] %s', [TimeStr, LevelStr, Tag, Message])
  else
    Result := Format('[%s] [%-5s] %s', [TimeStr, LevelStr, Message]);
end;

{ TLogger }

constructor TLogger.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FLogLevel := llDebug;
  FLogToFile := False;
  FLogFilePath := '';
  FMaxLogLines := 5000;
  FBufferCount := 0;
  SetLength(FLogBuffer, 0);
  FOnLog := nil;
end;

destructor TLogger.Destroy;
begin
  FLock.Free;
  SetLength(FLogBuffer, 0);
  inherited Destroy;
end;

class function TLogger.Instance: TLogger;
begin
  if not Assigned(FInstance) then
    FInstance := TLogger.Create;
  Result := FInstance;
end;

class destructor TLogger.ClassDestroy;
begin
  if Assigned(FInstance) then
    FreeAndNil(FInstance);
end;

procedure TLogger.SetLogLevel(const AValue: TLogLevel);
begin
  FLock.Enter;
  try
    FLogLevel := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TLogger.SetLogToFile(const AValue: Boolean);
begin
  FLock.Enter;
  try
    FLogToFile := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TLogger.SetLogFilePath(const AValue: string);
var
  TargetDir: string;
begin
  FLock.Enter;
  try
    FLogFilePath := AValue;
    if FLogFilePath <> '' then
    begin
      TargetDir := ExtractFileDir(FLogFilePath);
      if (TargetDir <> '') and not DirectoryExists(TargetDir) then
        ForceDirectories(TargetDir);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TLogger.AddToBuffer(const AEntry: TLogEntry);
var
  i: Integer;
begin
  if Length(FLogBuffer) < FMaxLogLines then
  begin
    SetLength(FLogBuffer, Length(FLogBuffer) + 1);
    FLogBuffer[High(FLogBuffer)] := AEntry;
  end
  else
  begin
    // Shift left to maintain rolling buffer
    for i := 0 to FMaxLogLines - 2 do
      FLogBuffer[i] := FLogBuffer[i + 1];
    FLogBuffer[FMaxLogLines - 1] := AEntry;
  end;
  FBufferCount := Length(FLogBuffer);
end;

procedure TLogger.WriteToFile(const AFormattedLine: string);
var
  TargetFile: TextFile;
begin
  if (FLogFilePath = '') or not FLogToFile then Exit;

  try
    AssignFile(TargetFile, FLogFilePath);
    try
      if FileExists(FLogFilePath) then
        Append(TargetFile)
      else
        Rewrite(TargetFile);
      WriteLn(TargetFile, AFormattedLine);
    finally
      CloseFile(TargetFile);
    end;
  except
    // Silent fail to prevent logger crash from crashing application
  end;
end;

procedure TLogger.Log(const ALevel: TLogLevel; const AMsg: string; const ATag: string);
var
  Entry: TLogEntry;
  FormattedText: string;
  EventCallback: TLogEvent;
begin
  FLock.Enter;
  try
    if Ord(ALevel) < Ord(FLogLevel) then Exit;

    Entry.Timestamp := Now;
    Entry.Level := ALevel;
    Entry.Tag := ATag;
    Entry.Message := AMsg;

    AddToBuffer(Entry);

    if FLogToFile then
    begin
      FormattedText := Entry.ToStringFormatted(True);
      WriteToFile(FormattedText);
    end;

    EventCallback := FOnLog;
  finally
    FLock.Leave;
  end;

  // Execute UI Callback outside lock to avoid deadlocks
  if Assigned(EventCallback) then
    EventCallback(Entry.Timestamp, Entry.Level, Entry.Tag, Entry.Message);
end;

procedure TLogger.Debug(const AMsg: string; const ATag: string);
begin
  Log(llDebug, AMsg, ATag);
end;

procedure TLogger.Info(const AMsg: string; const ATag: string);
begin
  Log(llInfo, AMsg, ATag);
end;

procedure TLogger.Warn(const AMsg: string; const ATag: string);
begin
  Log(llWarn, AMsg, ATag);
end;

procedure TLogger.Error(const AMsg: string; const ATag: string);
begin
  Log(llError, AMsg, ATag);
end;

procedure TLogger.ClearBuffer;
begin
  FLock.Enter;
  try
    SetLength(FLogBuffer, 0);
    FBufferCount := 0;
  finally
    FLock.Leave;
  end;
end;

function TLogger.GetBufferSnapshot: TLogEntryArray;
begin
  FLock.Enter;
  try
    Result := Copy(FLogBuffer, 0, Length(FLogBuffer));
  finally
    FLock.Leave;
  end;
end;

{ Global Helpers }

procedure LogDebug(const AMsg: string; const ATag: string);
begin
  TLogger.Instance.Debug(AMsg, ATag);
end;

procedure LogInfo(const AMsg: string; const ATag: string);
begin
  TLogger.Instance.Info(AMsg, ATag);
end;

procedure LogWarn(const AMsg: string; const ATag: string);
begin
  TLogger.Instance.Warn(AMsg, ATag);
end;

procedure LogError(const AMsg: string; const ATag: string);
begin
  TLogger.Instance.Error(AMsg, ATag);
end;

end.

