unit uchattypes;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes;

type
  { Message Roles }
  TMessageRole = (mrSystem, mrUser, mrAssistant, mrTool);

  { Completion Termination Reason }
  TFinishReason = (frNone, frStop, frLength, frContentFilter, frToolCalls, frError);

  { Telemetry & Generation Performance Metrics }
  TInferenceMetrics = record
    TTFTMs: Double;               // Time to First Token in milliseconds
    PromptEvalDurationMs: Double; // Time taken to process input prompt
    EvalDurationMs: Double;       // Time taken for token generation loop
    TotalDurationMs: Double;      // Overall request duration
    PromptTokens: Integer;        // Input token count
    CompletionTokens: Integer;    // Output generated token count
    TotalTokens: Integer;         // Combined token count
    PromptTokensPerSec: Double;   // Prompt processing speed (t/s)
    TokensPerSecond: Double;      // Generation speed (t/s)
    StartTime: TDateTime;
    FirstTokenTime: TDateTime;
    EndTime: TDateTime;

    class function CreateEmpty: TInferenceMetrics; static;
    procedure Reset;
    procedure MarkStart;
    procedure MarkFirstToken;
    procedure MarkEnd(const APromptTokens, ACompletionTokens: Integer);
  end;

  { Individual Chat Message }
  TChatMessage = record
    ID: string;
    Role: TMessageRole;
    Content: string;
    Timestamp: TDateTime;
    Metrics: TInferenceMetrics;
    FinishReason: TFinishReason;
    IsStreaming: Boolean;

    class function Create(const ARole: TMessageRole; const AContent: string): TChatMessage; static;
  end;
  TChatMessageArray = array of TChatMessage;

  { Chat Session / Conversation Thread }
  TChatSession = record
    ID: string;
    Title: string;
    ModelName: string;
    SystemPrompt: string;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    Messages: TChatMessageArray;

    class function CreateNew(const ATitle, AModelName, ASystemPrompt: string): TChatSession; static;
    procedure AddMessage(const AMessage: TChatMessage);
    function TotalTokenCount: Integer;
  end;
  TChatSessionArray = array of TChatSession;

  { Slot Processing State (/slots endpoint telemetry) }
  TSlotState = (ssIdle, ssProcessing, ssEvaluating, ssResetting, ssOffline);

  { llama-server Active Slot Telemetry }
  TSlotInfo = record
    ID: Integer;
    TaskID: Integer;
    State: TSlotState;
    Model: string;
    PromptTokens: Integer;
    GeneratedTokens: Integer;
    TotalTokens: Integer;
    TokensPerSecond: Double;
    ProgressPercent: Single;
    IsActive: Boolean;
    LastUpdated: TDateTime;

    class function CreateEmpty(const ASlotID: Integer): TSlotInfo; static;
  end;
  TSlotInfoArray = array of TSlotInfo;

{ String Conversion Helpers }
function MessageRoleToString(const ARole: TMessageRole): string;
function StringToMessageRole(const AStr: string): TMessageRole;
function FinishReasonToString(const AReason: TFinishReason): string;
function StringToFinishReason(const AStr: string): TFinishReason;
function SlotStateToString(const AState: TSlotState): string;
function StringToSlotState(const AStr: string): TSlotState;

implementation

uses
  DateUtils;

{ TInferenceMetrics }

class function TInferenceMetrics.CreateEmpty: TInferenceMetrics;
begin
  Result.Reset;
end;

procedure TInferenceMetrics.Reset;
begin
  TTFTMs := 0.0;
  PromptEvalDurationMs := 0.0;
  EvalDurationMs := 0.0;
  TotalDurationMs := 0.0;
  PromptTokens := 0;
  CompletionTokens := 0;
  TotalTokens := 0;
  PromptTokensPerSec := 0.0;
  TokensPerSecond := 0.0;
  StartTime := 0;
  FirstTokenTime := 0;
  EndTime := 0;
end;

procedure TInferenceMetrics.MarkStart;
begin
  Reset;
  StartTime := Now;
end;

procedure TInferenceMetrics.MarkFirstToken;
begin
  FirstTokenTime := Now;
  if StartTime > 0 then
    TTFTMs := MilliSecondsBetween(FirstTokenTime, StartTime);
end;

procedure TInferenceMetrics.MarkEnd(const APromptTokens, ACompletionTokens: Integer);
var
  GenDurationSec: Double;
begin
  EndTime := Now;
  PromptTokens := APromptTokens;
  CompletionTokens := ACompletionTokens;
  TotalTokens := PromptTokens + CompletionTokens;

  if StartTime > 0 then
    TotalDurationMs := MilliSecondsBetween(EndTime, StartTime);

  if (FirstTokenTime > 0) and (EndTime >= FirstTokenTime) then
  begin
    EvalDurationMs := MilliSecondsBetween(EndTime, FirstTokenTime);
    GenDurationSec := EvalDurationMs / 1000.0;
    if (GenDurationSec > 0.001) and (CompletionTokens > 0) then
      TokensPerSecond := CompletionTokens / GenDurationSec;
  end
  else if TotalDurationMs > 0 then
  begin
    TokensPerSecond := (CompletionTokens / TotalDurationMs) * 1000.0;
  end;

  if (TTFTMs > 0) and (PromptTokens > 0) then
    PromptTokensPerSec := (PromptTokens / TTFTMs) * 1000.0;
end;

{ TChatMessage }

class function TChatMessage.Create(const ARole: TMessageRole; const AContent: string): TChatMessage;
begin
  Result.ID := TGUID.NewGuid.ToString(True);
  Result.Role := ARole;
  Result.Content := AContent;
  Result.Timestamp := Now;
  Result.Metrics := TInferenceMetrics.CreateEmpty;
  Result.FinishReason := frNone;
  Result.IsStreaming := False;
end;

{ TChatSession }

class function TChatSession.CreateNew(const ATitle, AModelName, ASystemPrompt: string): TChatSession;
begin
  Result.ID := TGUID.NewGuid.ToString(True);
  Result.Title := ATitle;
  Result.ModelName := AModelName;
  Result.SystemPrompt := ASystemPrompt;
  Result.CreatedAt := Now;
  Result.UpdatedAt := Now;
  SetLength(Result.Messages, 0);

  if Trim(ASystemPrompt) <> '' then
    Result.AddMessage(TChatMessage.Create(mrSystem, ASystemPrompt));
end;

procedure TChatSession.AddMessage(const AMessage: TChatMessage);
var
  Len: Integer;
begin
  Len := Length(Messages);
  SetLength(Messages, Len + 1);
  Messages[Len] := AMessage;
  UpdatedAt := Now;
end;

function TChatSession.TotalTokenCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Messages) do
    Inc(Result, Messages[i].Metrics.TotalTokens);
end;

{ TSlotInfo }

class function TSlotInfo.CreateEmpty(const ASlotID: Integer): TSlotInfo;
begin
  Result.ID := ASlotID;
  Result.TaskID := -1;
  Result.State := ssIdle;
  Result.Model := '';
  Result.PromptTokens := 0;
  Result.GeneratedTokens := 0;
  Result.TotalTokens := 0;
  Result.TokensPerSecond := 0.0;
  Result.ProgressPercent := 0.0;
  Result.IsActive := False;
  Result.LastUpdated := Now;
end;

{ Conversions }

function MessageRoleToString(const ARole: TMessageRole): string;
begin
  case ARole of
    mrSystem:    Result := 'system';
    mrUser:      Result := 'user';
    mrAssistant: Result := 'assistant';
    mrTool:      Result := 'tool';
    else         Result := 'user';
  end;
end;

function StringToMessageRole(const AStr: string): TMessageRole;
var
  Lower: string;
begin
  Lower := LowerCase(Trim(AStr));
  if Lower = 'system' then Exit(mrSystem);
  if Lower = 'assistant' then Exit(mrAssistant);
  if Lower = 'tool' then Exit(mrTool);
  Result := mrUser;
end;

function FinishReasonToString(const AReason: TFinishReason): string;
begin
  case AReason of
    frStop:          Result := 'stop';
    frLength:        Result := 'length';
    frContentFilter: Result := 'content_filter';
    frToolCalls:     Result := 'tool_calls';
    frError:         Result := 'error';
    else             Result := 'none';
  end;
end;

function StringToFinishReason(const AStr: string): TFinishReason;
var
  Lower: string;
begin
  Lower := LowerCase(Trim(AStr));
  if Lower = 'stop' then Exit(frStop);
  if Lower = 'length' then Exit(frLength);
  if Lower = 'content_filter' then Exit(frContentFilter);
  if Lower = 'tool_calls' then Exit(frToolCalls);
  if Lower = 'error' then Exit(frError);
  Result := frNone;
end;

function SlotStateToString(const AState: TSlotState): string;
begin
  case AState of
    ssIdle:       Result := 'Idle';
    ssProcessing: Result := 'Processing';
    ssEvaluating: Result := 'Evaluating';
    ssResetting:  Result := 'Resetting';
    ssOffline:    Result := 'Offline';
    else          Result := 'Unknown';
  end;
end;

function StringToSlotState(const AStr: string): TSlotState;
var
  Upper: string;
begin
  Upper := UpperCase(Trim(AStr));
  if (Upper = 'PROCESSING') or (Upper = 'GENERATING') then Exit(ssProcessing);
  if (Upper = 'EVALUATING') or (Upper = 'PROMPT_INGEST') then Exit(ssEvaluating);
  if (Upper = 'RESETTING') or (Upper = 'CLEANING') then Exit(ssResetting);
  if Upper = 'OFFLINE' then Exit(ssOffline);
  Result := ssIdle;
end;

end.

