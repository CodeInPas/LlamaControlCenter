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
    FLock: TCriticalSection;

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

  SetLength(ChunkStr, Count);
  Move(Buffer, ChunkStr[1], Count);
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
  FLock := TCriticalSection.Create;

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
  FLock.Free;
  inherited Destroy;
end;

function TSSEClientThread.IsTerminated: Boolean;
begin
  Result := Terminated;
end;

procedure TSSEClientThread.SyncFireToken;
var
  Tok: string;
  Done: Boolean;
  Met: TInferenceMetrics;
  Fin: TFinishReason;
begin
  if Assigned(FOnToken) then
  begin
    FLock.Enter;
    try
      Tok := FCurrentToken;
      Done := FIsDone;
      Met := FMetrics;
      Fin := FFinishReason;
    finally
      FLock.Leave;
    end;
    FOnToken(Self, Tok, Done, Met, Fin);
  end;
end;

procedure TSSEClientThread.SyncFireError;
var
  Err: string;
  Code: Integer;
begin
  if Assigned(FOnError) then
  begin
    FLock.Enter;
    try
      Err := FErrorMessage;
      Code := FStatusCode;
    finally
      FLock.Leave;
    end;
    FOnError(Self, Err, Code);
  end;
end;

procedure TSSEClientThread.AbortStream;
begin
  Terminate;
end;

function TSSEClientThread.GetCurrentMetrics: TInferenceMetrics;
begin
  FLock.Enter;
  try
    Result := FMetrics;
  finally
    FLock.Leave;
  end;
end;

procedure TSSEClientThread.ParseChunkJSON(const AJSONStr: string);
var
  RootData, UsageObj, TimingsObj: TJSONData;
  DeltaText, FinishReasonStr: string;
  PromptToks, CompToks: Integer;
  SpeedVal: Double;
begin
  RootData := ParseJSON(AJSONStr);
  if not Assigned(RootData) then Exit;

  try
    FLock.Enter;
    try
      // Check for first token generation timing (TTFT)
      if not FHasReceivedFirstToken then
      begin
        FHasReceivedFirstToken := True;
        FMetrics.MarkFirstToken;
      end;

      // Format 1: OpenAI /v1/chat/completions format: choices[0].delta.content
      DeltaText := FindPathString(RootData, 'choices[0].delta.content', '');
      FinishReasonStr := FindPathString(RootData, 'choices[0].finish_reason', '');

      // Format 2: Raw llama.cpp /completion format fallback: content
      if DeltaText = '' then
        DeltaText := FindPathString(RootData, 'content', '');

      if FinishReasonStr <> '' then
        FFinishReason := StringToFinishReason(FinishReasonStr);

      if DeltaText <> '' then
      begin
        Inc(FTotalCompletionTokens);
        FCurrentToken := DeltaText;
        FIsDone := False;
        Synchronize(@SyncFireToken);
      end;

      // Extract telemetry usage or timings if provided by server
      UsageObj := RootData.FindPath('usage');
      if Assigned(UsageObj) and (UsageObj is TJSONObject) then
      begin
        PromptToks := GetJSONInt(TJSONObject(UsageObj), 'prompt_tokens', FTotalPromptTokens);
        CompToks := GetJSONInt(TJSONObject(UsageObj), 'completion_tokens', FTotalCompletionTokens);
        if PromptToks > 0 then FTotalPromptTokens := PromptToks;
        if CompToks > 0 then FTotalCompletionTokens := CompToks;
      end;

      TimingsObj := RootData.FindPath('timings');
      if Assigned(TimingsObj) and (TimingsObj is TJSONObject) then
      begin
        SpeedVal := GetJSONFloat(TJSONObject(TimingsObj), 'predicted_per_second', 0.0);
        if SpeedVal > 0.001 then
          FMetrics.TokensPerSecond := SpeedVal;
      end;
    finally
      FLock.Leave;
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

  // Handle SSE data line
  if ALine.StartsWith('data: ') or ALine.StartsWith('data:') then
  begin
    if ALine.StartsWith('data: ') then
      RawData := Copy(ALine, 7, Length(ALine))
    else
      RawData := Copy(ALine, 6, Length(ALine));

    RawData := Trim(RawData);

    // End of Stream Marker
    if RawData = '[DONE]' then
    begin
      FLock.Enter;
      try
        FIsDone := True;
        if FFinishReason = frNone then
          FFinishReason := frStop;
        FMetrics.MarkEnd(FTotalPromptTokens, FTotalCompletionTokens);
        FCurrentToken := '';
      finally
        FLock.Leave;
      end;
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
        FLock.Enter;
        try
          FIsDone := True;
          FMetrics.MarkEnd(FTotalPromptTokens, FTotalCompletionTokens);
          FCurrentToken := '';
        finally
          FLock.Leave;
        end;
        Synchronize(@SyncFireToken);
      end;

    except
      on E: Exception do
      begin
        if not Terminated then
        begin
          FLock.Enter;
          try
            FErrorMessage := E.Message;
            if FStatusCode = 0 then
              FStatusCode := Client.ResponseStatusCode;
          finally
            FLock.Leave;
          end;
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
