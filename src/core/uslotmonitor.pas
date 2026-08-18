unit uslotmonitor;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, SyncObjs, DateUtils, fphttpclient, fpjson, jsonparser,
  uchattypes, uconfigtypes, ujsonhelper, ulogger;

type
  { Event Dispatch for Slot Telemetry Updates }
  TSlotUpdateEvent = procedure(Sender: TObject; const ASlots: TSlotInfoArray; const AIsOnline: Boolean) of object;

  { Background Polling Worker Thread for /slots Endpoint }
  TSlotMonitorThread = class(TThread)
  private
    FHost: string;
    FPort: Word;
    FApiKey: string;
    FIntervalMs: Cardinal;
    FLock: TCriticalSection;
    FSlots: TSlotInfoArray;
    FIsOnline: Boolean;
    FLastSyncTime: TDateTime;
    FOnUpdate: TSlotUpdateEvent;

    procedure SyncFireUpdate;
    function QuerySlotsEndpoint: string;
    procedure ParseSlotsJSON(const ARawJSON: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost: string; const APort: Word; const AApiKey: string;
                       const AIntervalMs: Cardinal; AUpdateCb: TSlotUpdateEvent);
    destructor Destroy; override;

    procedure UpdateConnectionParams(const AHost: string; const APort: Word; const AApiKey: string);
    function GetSnapshot(out AIsOnline: Boolean): TSlotInfoArray;
    property IntervalMs: Cardinal read FIntervalMs write FIntervalMs;
  end;

  { High-Level Slot Monitor Orchestrator }
  TSlotMonitor = class
  private
    class var FInstance: TSlotMonitor;
  private
    FLock: TCriticalSection;
    FWorkerThread: TSlotMonitorThread;
    FHost: string;
    FPort: Word;
    FApiKey: string;
    FIntervalMs: Cardinal;
    FLastSlots: TSlotInfoArray;
    FIsServerOnline: Boolean;
    FOnSlotsUpdated: TSlotUpdateEvent;

    procedure HandleThreadUpdate(Sender: TObject; const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
  public
    constructor Create;
    destructor Destroy; override;

    class function Instance: TSlotMonitor; static;
    class destructor ClassDestroy;

    procedure StartMonitoring(const AHost: string = '127.0.0.1'; const APort: Word = 8080;
                             const AApiKey: string = ''; const AIntervalMs: Cardinal = 1000);
    procedure StopMonitoring;
    procedure SetConnection(const AHost: string; const APort: Word; const AApiKey: string = '');

    function IsActive: Boolean;
    function IsServerOnline: Boolean;
    function GetSlotsSnapshot: TSlotInfoArray;
    function GetTotalActiveSlots: Integer;
    function GetTotalSlotCount: Integer;

    property Host: string read FHost;
    property Port: Word read FPort;
    property IntervalMs: Cardinal read FIntervalMs write FIntervalMs;
    property OnSlotsUpdated: TSlotUpdateEvent read FOnSlotsUpdated write FOnSlotsUpdated;
  end;

implementation

{ TSlotMonitorThread }

constructor TSlotMonitorThread.Create(const AHost: string; const APort: Word; const AApiKey: string;
  const AIntervalMs: Cardinal; AUpdateCb: TSlotUpdateEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FHost := AHost;
  FPort := APort;
  FApiKey := AApiKey;
  FIntervalMs := AIntervalMs;
  if FIntervalMs < 250 then
    FIntervalMs := 250;
  FOnUpdate := AUpdateCb;
  FIsOnline := False;
  FLastSyncTime := 0;
  SetLength(FSlots, 0);
end;

destructor TSlotMonitorThread.Destroy;
begin
  FLock.Free;
  SetLength(FSlots, 0);
  inherited Destroy;
end;

procedure TSlotMonitorThread.UpdateConnectionParams(const AHost: string; const APort: Word; const AApiKey: string);
begin
  FLock.Enter;
  try
    FHost := AHost;
    FPort := APort;
    FApiKey := AApiKey;
  finally
    FLock.Leave;
  end;
end;

procedure TSlotMonitorThread.SyncFireUpdate;
begin
  if Assigned(FOnUpdate) then
    FOnUpdate(Self, FSlots, FIsOnline);
end;

function TSlotMonitorThread.GetSnapshot(out AIsOnline: Boolean): TSlotInfoArray;
begin
  FLock.Enter;
  try
    AIsOnline := FIsOnline;
    Result := Copy(FSlots, 0, Length(FSlots));
  finally
    FLock.Leave;
  end;
end;

function TSlotMonitorThread.QuerySlotsEndpoint: string;
var
  Client: TFPHTTPClient;
  TargetUrl: string;
  CurHost, CurApiKey: string;
  CurPort: Word;
begin
  Result := '';
  FLock.Enter;
  try
    CurHost := FHost;
    CurPort := FPort;
    CurApiKey := FApiKey;
  finally
    FLock.Leave;
  end;

  TargetUrl := Format('http://%s:%d/slots', [CurHost, CurPort]);
  Client := TFPHTTPClient.Create(nil);
  try
    Client.IOTimeout := 1500;
    Client.ConnectTimeout := 1000;
    Client.AllowRedirect := True;

    if Trim(CurApiKey) <> '' then
      Client.AddHeader('Authorization', 'Bearer ' + CurApiKey);

    try
      Result := Client.Get(TargetUrl);
    except
      Result := '';
    end;
  finally
    Client.Free;
  end;
end;

procedure TSlotMonitorThread.ParseSlotsJSON(const ARawJSON: string);
var
  RootData, SlotsData: TJSONData;
  SlotArray: TJSONArray;
  SlotObj: TJSONObject;
  i, SlotID, TaskID: Integer;
  IsActiveFlag: Boolean;
  PromptToks, GenToks, MaxPredict: Integer;
  CurStateStr: string;
  CalcSpeed: Double;
  NowTime: TDateTime;
begin
  if Trim(ARawJSON) = '' then
  begin
    FLock.Enter;
    try
      FIsOnline := False;
      for i := 0 to High(FSlots) do
        FSlots[i].State := ssOffline;
    finally
      FLock.Leave;
    end;
    Exit;
  end;

  RootData := ParseJSON(ARawJSON);
  if not Assigned(RootData) then Exit;

  try
    SlotArray := nil;
    if RootData.JSONType = jtArray then
      SlotArray := TJSONArray(RootData)
    else if RootData.JSONType = jtObject then
    begin
      SlotsData := RootData.FindPath('slots');
      if Assigned(SlotsData) and (SlotsData.JSONType = jtArray) then
        SlotArray := TJSONArray(SlotsData);
    end;

    if not Assigned(SlotArray) then Exit;

    NowTime := Now;
    FLock.Enter;
    try
      FIsOnline := True;
      SetLength(FSlots, SlotArray.Count);

      for i := 0 to SlotArray.Count - 1 do
      begin
        if SlotArray.Items[i].JSONType <> jtObject then Continue;
        SlotObj := TJSONObject(SlotArray.Items[i]);

        SlotID := GetJSONInt(SlotObj, 'id', i);
        TaskID := GetJSONInt(SlotObj, 'id_task', -1);
        if TaskID = -1 then
          TaskID := GetJSONInt(SlotObj, 'task_id', -1);

        IsActiveFlag := GetJSONBool(SlotObj, 'is_processing', False);
        CurStateStr := GetJSONString(SlotObj, 'state', '');

        PromptToks := GetJSONInt(SlotObj, 'n_prompt_tokens', 0);
        GenToks := GetJSONInt(SlotObj, 'n_decoded', 0);
        MaxPredict := GetJSONInt(SlotObj, 'n_predict', 0);

        FSlots[i].ID := SlotID;
        FSlots[i].TaskID := TaskID;
        FSlots[i].IsActive := IsActiveFlag;
        FSlots[i].PromptTokens := PromptToks;
        FSlots[i].GeneratedTokens := GenToks;
        FSlots[i].TotalTokens := PromptToks + GenToks;
        FSlots[i].LastUpdated := NowTime;
        FSlots[i].Model := GetJSONString(SlotObj, 'model', '');

        // Decode slot state
        if CurStateStr <> '' then
          FSlots[i].State := StringToSlotState(CurStateStr)
        else if IsActiveFlag then
          FSlots[i].State := ssProcessing
        else
          FSlots[i].State := ssIdle;

        // Progress Calculation
        if (MaxPredict > 0) and (GenToks > 0) then
        begin
          FSlots[i].ProgressPercent := (GenToks / MaxPredict) * 100.0;
          if FSlots[i].ProgressPercent > 100.0 then
            FSlots[i].ProgressPercent := 100.0;
        end
        else
          FSlots[i].ProgressPercent := 0.0;

        // Approximate speed readout from payload if available
        CalcSpeed := GetJSONFloat(SlotObj, 't_per_token_ms', 0.0);
        if CalcSpeed > 0.001 then
          FSlots[i].TokensPerSecond := 1000.0 / CalcSpeed
        else
          FSlots[i].TokensPerSecond := GetJSONFloat(SlotObj, 'tokens_per_second', 0.0);
      end;
    finally
      FLock.Leave;
    end;
  finally
    RootData.Free;
  end;
end;

procedure TSlotMonitorThread.Execute;
var
  RawResponse: string;
begin
  while not Terminated do
  begin
    RawResponse := QuerySlotsEndpoint;
    ParseSlotsJSON(RawResponse);
    Synchronize(@SyncFireUpdate);

    // Sleep in small increments for responsive termination
    Sleep(FIntervalMs);
  end;
end;

{ TSlotMonitor }

constructor TSlotMonitor.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FWorkerThread := nil;
  FHost := '127.0.0.1';
  FPort := 8080;
  FApiKey := '';
  FIntervalMs := 1000;
  FIsServerOnline := False;
  SetLength(FLastSlots, 0);
  FOnSlotsUpdated := nil;
end;

destructor TSlotMonitor.Destroy;
begin
  StopMonitoring;
  FLock.Free;
  SetLength(FLastSlots, 0);
  inherited Destroy;
end;

class function TSlotMonitor.Instance: TSlotMonitor;
begin
  if not Assigned(FInstance) then
    FInstance := TSlotMonitor.Create;
  Result := FInstance;
end;

class destructor TSlotMonitor.ClassDestroy;
begin
  if Assigned(FInstance) then
    FreeAndNil(FInstance);
end;

procedure TSlotMonitor.HandleThreadUpdate(Sender: TObject; const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
begin
  FLock.Enter;
  try
    FLastSlots := Copy(ASlots, 0, Length(ASlots));
    FIsServerOnline := AIsOnline;
  finally
    FLock.Leave;
  end;

  if Assigned(FOnSlotsUpdated) then
    FOnSlotsUpdated(Self, FLastSlots, AIsOnline);
end;

procedure TSlotMonitor.StartMonitoring(const AHost: string; const APort: Word;
  const AApiKey: string; const AIntervalMs: Cardinal);
begin
  FLock.Enter;
  try
    FHost := AHost;
    FPort := APort;
    FApiKey := AApiKey;
    FIntervalMs := AIntervalMs;

    if Assigned(FWorkerThread) then
    begin
      FWorkerThread.UpdateConnectionParams(FHost, FPort, FApiKey);
      FWorkerThread.IntervalMs := FIntervalMs;
      Exit;
    end;

    FWorkerThread := TSlotMonitorThread.Create(
      FHost,
      FPort,
      FApiKey,
      FIntervalMs,
      @HandleThreadUpdate
    );
    FWorkerThread.Start;
    LogDebug(Format('Slot monitor started for %s:%d (Interval: %dms)', [FHost, FPort, FIntervalMs]), 'MONITOR');
  finally
    FLock.Leave;
  end;
end;

procedure TSlotMonitor.StopMonitoring;
begin
  FLock.Enter;
  try
    if Assigned(FWorkerThread) then
    begin
      FWorkerThread.Terminate;
      FWorkerThread.WaitFor;
      FreeAndNil(FWorkerThread);
      LogDebug('Slot monitor worker terminated', 'MONITOR');
    end;
    FIsServerOnline := False;
    SetLength(FLastSlots, 0);
  finally
    FLock.Leave;
  end;
end;

procedure TSlotMonitor.SetConnection(const AHost: string; const APort: Word; const AApiKey: string);
begin
  FLock.Enter;
  try
    FHost := AHost;
    FPort := APort;
    FApiKey := AApiKey;
    if Assigned(FWorkerThread) then
      FWorkerThread.UpdateConnectionParams(FHost, FPort, FApiKey);
  finally
    FLock.Leave;
  end;
end;

function TSlotMonitor.IsActive: Boolean;
begin
  FLock.Enter;
  try
    Result := Assigned(FWorkerThread) and not FWorkerThread.Terminated;
  finally
    FLock.Leave;
  end;
end;

function TSlotMonitor.IsServerOnline: Boolean;
begin
  FLock.Enter;
  try
    Result := FIsServerOnline;
  finally
    FLock.Leave;
  end;
end;

function TSlotMonitor.GetSlotsSnapshot: TSlotInfoArray;
begin
  FLock.Enter;
  try
    Result := Copy(FLastSlots, 0, Length(FLastSlots));
  finally
    FLock.Leave;
  end;
end;

function TSlotMonitor.GetTotalActiveSlots: Integer;
var
  i: Integer;
begin
  Result := 0;
  FLock.Enter;
  try
    for i := 0 to High(FLastSlots) do
      if FLastSlots[i].IsActive or (FLastSlots[i].State in [ssProcessing, ssEvaluating]) then
        Inc(Result);
  finally
    FLock.Leave;
  end;
end;

function TSlotMonitor.GetTotalSlotCount: Integer;
begin
  FLock.Enter;
  try
    Result := Length(FLastSlots);
  finally
    FLock.Leave;
  end;
end;

end.

