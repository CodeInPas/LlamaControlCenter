unit usseclient;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, SyncObjs, DateUtils, fphttpclient, opensslsockets,
  fpjson, jsonparser, uchattypes, uconfigtypes, ujsonhelper, ulogger;

type
  { Forward Declaration }
  TSSEClientThread = class;

  { SSE Line Event Callback Signature }
  TSSELineProcessEvent = procedure(const ALine: string) of object;

  { SSE Stream Event Callbacks }
  TSSETokenEvent = procedure(Sender: TObject; const AToken: string; const AIsDone: Boolean;
                             const AMetrics: TInferenceMetrics; const AFinishReason: TFinishReason) of object;
  TSSEErrorEvent = procedure(Sender: TObject; const AError: string; const AStatusCode: Integer) of object;

  { Custom Streaming Buffer Stream for Real-Time Chunk Ingestion }
  TSSEStream = class(TStream)
  private
    FOwnerThread: TSSEClientThread;
    FBuffer: string;
    FOnProcessLine: TSSELineProcessEvent;
  public
    constructor Create(AOwner: TSSEClientThread; ALineHandler: TSSELineProcessEvent);
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Seek(Offset: LongInt; Origin: Word): LongInt; override;
    procedure Flush;
  end;

  { SSE Inference Stream Worker Thread }
  TSSEClientThread = class(TThread)
  private
    FEndpoint: string;
    FPayload: string;
    FApiKey: string;
    FTimeoutSeconds: Integer;

    // Telemetry & State
    FMetrics: TInferenceMetrics;
    FCurrentToken: string;
    FIsDone: Boolean;
    FFinishReason: TFinishReason;
    FErrorMessage: string;
    FStatusCode: Integer;
    FTotalPromptTokens: Integer;
    FTotalCompletionTokens: Integer;
    FHasReceivedFirstToken: Boolean;

    // Callbacks
    FOnToken: TSSETokenEvent;
    FOnError: TSSEErrorEvent;

    procedure SyncFireToken;
    procedure SyncFireError;
    procedure ProcessRawSSELine(const ALine: string);
    procedure ParseChunkJSON(const AJSONStr: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const AEndpoint: string;
                       const APayload: string;
                       const AApiKey: string = '';
                       const ATimeoutSeconds: Integer = 120;
                       const ATokenCb: TSSETokenEvent = nil;
                       const AErrorCb: TSSEErrorEvent = nil);
    destructor Destroy; override;

    procedure AbortStream;
    function IsTerminated: Boolean;
    function GetCurrentMetrics: TInferenceMetrics;

    property Endpoint: string read FEndpoint;
    property IsDone: Boolean read FIsDone;
  end;

implementation

{ TSSEStream }

constructor TSSEStream.Create(AOwner: TSSEClientThread; ALineHandler: TSSELineProcessEvent);
begin
  inherited Create;
  FOwnerThread := AOwner;
  FOnProcessLine := ALineHandler;
  FBuffer := '';
end;

function TSSEStream.Write(const Buffer; Count: LongInt): LongInt;
var
  ChunkStr: string;
  PosLF: Integer;
  Line: string;
begin
  Result := Count;
  if Count <= 0 then Exit;

  if Assigned(FOwnerThread) and FOwnerThread.IsTerminated then
    raise EAbort.Create('SSE Stream Aborted by user.');

  SetString(ChunkStr, PAnsiChar(@Buffer), Count);
  FBuffer := FBuffer + ChunkStr;

  while True do
  begin
    PosLF := Pos(#10, FBuffer);
    if PosLF > 0 then
    begin
      Line := Copy(FBuffer, 1, PosLF - 1);
      Delete(FBuffer, 1, PosLF);

      if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
        Delete(Line, Length(Line), 1);

      if Assigned(FOnProcessLine) then
        FOnProcessLine(Line);
    end
    else
      Break;
  end;
end;

function TSSEStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
end;

function TSSEStream.Seek(Offset: LongInt; Origin: Word): LongInt;
begin
  Result := 0;
end;

procedure TSSEStream.Flush;
var
  Line: string;
begin
  if Length(FBuffer) > 0 then
  begin
    Line := FBuffer;
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Delete(Line, Length(Line), 1);
    FBuffer := '';
    if Assigned(FOnProcessLine) then
      FOnProcessLine(Line);
  end;
end;

{ TSSEClientThread }

constructor TSSEClientThread.Create(const AEndpoint: string;
  const APayload: string;
  const AApiKey: string;
  const ATimeoutSeconds: Integer;
  const ATokenCb: TSSETokenEvent;
  const AErrorCb: TSSEErrorEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;

  FEndpoint := AEndpoint;
  FPayload := APayload;
  FApiKey := AApiKey;
  FTimeoutSeconds := ATimeoutSeconds;
  if FTimeoutSeconds < 10 then FTimeoutSeconds := 10;

  FOnToken := ATokenCb;
  FOnError := AErrorCb;

  FMetrics := TInferenceMetrics.CreateEmpty;
  FCurrentToken := '';
  FIsDone := False;
  FFinishReason := frNone;
  FErrorMessage := '';
  FStatusCode := 0;
  FTotalPromptTokens := 0;
  FTotalCompletionTokens := 0;
  FHasReceivedFirstToken := False;
end;

destructor TSSEClientThread.Destroy;
begin
  inherited Destroy;
end;

function TSSEClientThread.IsTerminated: Boolean;
begin
  Result := Terminated;
end;

procedure TSSEClientThread.SyncFireToken;
begin
  // Dijalankan langsung pada Main GUI Thread tanpa lock sehingga tidak terjadi deadlock
  if Assigned(FOnToken) then
    FOnToken(Self, FCurrentToken, FIsDone, FMetrics, FFinishReason);
end;

procedure TSSEClientThread.SyncFireError;
begin
  if Assigned(FOnError) then
    FOnError(Self, FErrorMessage, FStatusCode);
end;

procedure TSSEClientThread.AbortStream;
begin
  Terminate;
end;

function TSSEClientThread.GetCurrentMetrics: TInferenceMetrics;
begin
  Result := FMetrics;
end;

procedure TSSEClientThread.ParseChunkJSON(const AJSONStr: string);
var
  RootData, ChoicesData, ChoiceItem, DeltaData, UsageData, TimingsData: TJSONData;
  RootObj, DeltaObj, UsageObj, TimingsObj: TJSONObject;
  ChoicesArr: TJSONArray;
  DeltaText, FinishReasonStr: string;
  PromptToks, CompToks: Integer;
  SpeedVal: Double;
begin
  RootData := ParseJSON(AJSONStr);
  if not Assigned(RootData) then Exit;

  try
    if not (RootData is TJSONObject) then Exit;
    RootObj := TJSONObject(RootData);

    // Tandai TTFT (Time to First Token)
    if not FHasReceivedFirstToken then
    begin
      FHasReceivedFirstToken := True;
      FMetrics.MarkFirstToken;
    end;

    DeltaText := '';
    FinishReasonStr := '';

    // 1. Ekstraksi OpenAI Schema: choices[0].delta.content
    ChoicesData := RootObj.FindPath('choices');
    if Assigned(ChoicesData) and (ChoicesData is TJSONArray) then
    begin
      ChoicesArr := TJSONArray(ChoicesData);
      if ChoicesArr.Count > 0 then
      begin
        ChoiceItem := ChoicesArr.Items[0];
        if ChoiceItem is TJSONObject then
        begin
          DeltaData := TJSONObject(ChoiceItem).FindPath('delta');
          if Assigned(DeltaData) and (DeltaData is TJSONObject) then
          begin
            DeltaObj := TJSONObject(DeltaData);
            if DeltaObj.IndexOfName('content') >= 0 then
              DeltaText := DeltaObj.Get('content', '');
          end;

          if TJSONObject(ChoiceItem).IndexOfName('finish_reason') >= 0 then
            FinishReasonStr := TJSONObject(ChoiceItem).Get('finish_reason', '');
        end;
      end;
    end
    else
    begin
      // 2. Format Fallback: Native llama.cpp /completion
      if RootObj.IndexOfName('content') >= 0 then
        DeltaText := RootObj.Get('content', '');
      if RootObj.IndexOfName('stop') >= 0 then
        if RootObj.Get('stop', False) then
          FinishReasonStr := 'stop';
    end;

    if FinishReasonStr <> '' then
      FFinishReason := StringToFinishReason(FinishReasonStr);

    // 3. Ekstraksi penggunaan token & throughput
    UsageData := RootObj.FindPath('usage');
    if Assigned(UsageData) and (UsageData is TJSONObject) then
    begin
      UsageObj := TJSONObject(UsageData);
      PromptToks := UsageObj.Get('prompt_tokens', FTotalPromptTokens);
      CompToks := UsageObj.Get('completion_tokens', FTotalCompletionTokens);
      if PromptToks > 0 then FTotalPromptTokens := PromptToks;
      if CompToks > 0 then FTotalCompletionTokens := CompToks;
    end;

    TimingsData := RootObj.FindPath('timings');
    if Assigned(TimingsData) and (TimingsData is TJSONObject) then
    begin
      TimingsObj := TJSONObject(TimingsData);
      SpeedVal := TimingsObj.Get('predicted_per_second', 0.0);
      if SpeedVal > 0.001 then
        FMetrics.TokensPerSecond := SpeedVal;
    end;

    // Kirim token baru ke UI
    if DeltaText <> '' then
    begin
      Inc(FTotalCompletionTokens);
      FCurrentToken := DeltaText;
      FIsDone := False;
      Synchronize(@SyncFireToken);
    end;

    // Cek status penyelesaian respons
    if (FFinishReason in [frStop, frLength, frToolCalls]) and not FIsDone then
    begin
      FIsDone := True;
      FCurrentToken := '';
      FMetrics.MarkEnd(FTotalPromptTokens, FTotalCompletionTokens);
      Synchronize(@SyncFireToken);
    end;

  finally
    RootData.Free;
  end;
end;

procedure TSSEClientThread.ProcessRawSSELine(const ALine: string);
var
  RawData: string;
begin
  if Trim(ALine) = '' then Exit;

  // Tangani event data SSE
  if ALine.StartsWith('data: ') or ALine.StartsWith('data:') then
  begin
    if ALine.StartsWith('data: ') then
      RawData := Copy(ALine, 7, Length(ALine))
    else
      RawData := Copy(ALine, 6, Length(ALine));

    RawData := Trim(RawData);

    // Penanda akhir stream SSE
    if RawData = '[DONE]' then
    begin
      FIsDone := True;
      if FFinishReason = frNone then
        FFinishReason := frStop;
      FMetrics.MarkEnd(FTotalPromptTokens, FTotalCompletionTokens);
      FCurrentToken := '';
      Synchronize(@SyncFireToken);
      Exit;
    end;

    ParseChunkJSON(RawData);
  end;
end;

procedure TSSEClientThread.Execute;
var
  Client: TFPHTTPClient;
  StreamHandler: TSSEStream;
  ReqBody: TStringStream;
begin
  Client := TFPHTTPClient.Create(nil);
  StreamHandler := nil;
  ReqBody := nil;

  try
    try
      FMetrics.MarkStart;
      Client.AllowRedirect := True;
      Client.ConnectTimeout := 10000;
      Client.IOTimeout := FTimeoutSeconds * 1000;

      Client.AddHeader('Content-Type', 'application/json');
      Client.AddHeader('Accept', 'text/event-stream');
      Client.AddHeader('Cache-Control', 'no-cache');
      Client.AddHeader('User-Agent', 'LlamaControlCenter-SSEClient/1.0');

      if Trim(FApiKey) <> '' then
        Client.AddHeader('Authorization', 'Bearer ' + Trim(FApiKey));

      ReqBody := TStringStream.Create(FPayload);
      Client.RequestBody := ReqBody;

      StreamHandler := TSSEStream.Create(Self, @ProcessRawSSELine);

      LogDebug('Initiating SSE inference POST request to: ' + FEndpoint, 'SSE');

      try
        Client.HTTPMethod('POST', FEndpoint, StreamHandler, [200, 201]);
        FStatusCode := Client.ResponseStatusCode;
        StreamHandler.Flush;
      except
        on E: EAbort do
        begin
          LogInfo('SSE stream generation canceled by user.', 'SSE');
          Exit;
        end;
        on E: Exception do
        begin
          FStatusCode := Client.ResponseStatusCode;
          if not Terminated then
            raise;
        end;
      end;

      if not FIsDone and not Terminated then
      begin
        FIsDone := True;
        FMetrics.MarkEnd(FTotalPromptTokens, FTotalCompletionTokens);
        FCurrentToken := '';
        Synchronize(@SyncFireToken);
      end;

    except
      on E: Exception do
      begin
        if not Terminated then
        begin
          FErrorMessage := E.Message;
          if FStatusCode = 0 then
            FStatusCode := Client.ResponseStatusCode;
          LogError(Format('SSE Inference Error [%d]: %s', [FStatusCode, E.Message]), 'SSE');
          Synchronize(@SyncFireError);
        end;
      end;
    end;
  finally
    if Assigned(StreamHandler) then
      StreamHandler.Free;
    if Assigned(ReqBody) then
      ReqBody.Free;
    Client.Free;
  end;
end;

end.
