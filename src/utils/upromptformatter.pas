unit upromptformatter;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, uchattypes;

type
  { Supported LLM Prompt Formats & Chat Templates }
  TPromptTemplateType = (
    pttChatML,     // Qwen, Yi, DeepSeek-Chat, Hermes, OpenHermes
    pttLlama3,     // Meta-Llama-3, Llama-3.1, Llama-3.2
    pttMistral,    // Mistral-Instruct, Mixtral, Zephyr
    pttAlpaca,     // Classic Alpaca, Vicuna (Standard)
    pttGemma,      // Gemma, Gemma-2 (Google)
    pttPhi3,       // Phi-3, Phi-3.5 (Microsoft)
    pttDeepSeekR1, // DeepSeek R1 / V3 Reasoning format
    pttRaw         // Plain concatenation without tags
  );

  { Prompt Formatter Helper Engine }
  TPromptFormatter = class
  private
    class function FormatChatML(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string; static;
    class function FormatLlama3(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string; static;
    class function FormatMistral(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string; static;
    class function FormatAlpaca(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string; static;
    class function FormatGemma(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string; static;
    class function FormatPhi3(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string; static;
    class function FormatDeepSeekR1(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string; static;
    class function FormatRaw(const AMessages: TChatMessageArray): string; static;
  public
    class function FormatPrompt(const AMessages: TChatMessageArray;
                                const ATemplate: TPromptTemplateType;
                                const AAddAssistantGenerationPrompt: Boolean = True): string; static;

    class function GetStopTokens(const ATemplate: TPromptTemplateType): TStringArray; static;
    class function DetectTemplateFromModelName(const AModelName: string): TPromptTemplateType; static;
    class function TemplateTypeToString(const ATemplate: TPromptTemplateType): string; static;
    class function StringToTemplateType(const AStr: string): TPromptTemplateType; static;
  end;

{ Global Helper Functions }
function FormatMessagesToPrompt(const AMessages: TChatMessageArray; const ATemplate: TPromptTemplateType): string;
function GetDefaultStopTokensForTemplate(const ATemplate: TPromptTemplateType): TStringArray;

implementation

{ TPromptFormatter }

class function TPromptFormatter.FormatChatML(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string;
var
  SB: TStringBuilder;
  i: Integer;
  RoleStr: string;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AMessages) do
    begin
      case AMessages[i].Role of
        mrSystem:    RoleStr := 'system';
        mrUser:      RoleStr := 'user';
        mrAssistant: RoleStr := 'assistant';
        mrTool:      RoleStr := 'tool';
      end;
      SB.Append('<|im_start|>').Append(RoleStr).Append(#10)
        .Append(Trim(AMessages[i].Content))
        .Append('<|im_end|>').Append(#10);
    end;

    if AAddGenPrompt then
      SB.Append('<|im_start|>assistant').Append(#10);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatLlama3(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string;
var
  SB: TStringBuilder;
  i: Integer;
  RoleStr: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('<|begin_of_text|>');
    for i := 0 to High(AMessages) do
    begin
      case AMessages[i].Role of
        mrSystem:    RoleStr := 'system';
        mrUser:      RoleStr := 'user';
        mrAssistant: RoleStr := 'assistant';
        mrTool:      RoleStr := 'tool';
      end;
      SB.Append('<|start_header_id|>').Append(RoleStr).Append('<|end_header_id|>').Append(#10#10)
        .Append(Trim(AMessages[i].Content))
        .Append('<|eot_id|>');
    end;

    if AAddGenPrompt then
      SB.Append('<|start_header_id|>assistant<|end_header_id|>').Append(#10#10);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatMistral(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string;
var
  SB: TStringBuilder;
  i: Integer;
  SystemPrompt, UserContent: string;
begin
  SB := TStringBuilder.Create;
  try
    SystemPrompt := '';
    for i := 0 to High(AMessages) do
    begin
      if AMessages[i].Role = mrSystem then
      begin
        if SystemPrompt <> '' then
          SystemPrompt := SystemPrompt + #10#10 + Trim(AMessages[i].Content)
        else
          SystemPrompt := Trim(AMessages[i].Content);
      end;
    end;

    for i := 0 to High(AMessages) do
    begin
      case AMessages[i].Role of
        mrUser:
        begin
          UserContent := Trim(AMessages[i].Content);
          if (SystemPrompt <> '') and (i = 0) or ((i = 1) and (AMessages[0].Role = mrSystem)) then
          begin
            SB.Append('<s>[INST] ').Append(SystemPrompt).Append(#10#10).Append(UserContent).Append(' [/INST]');
            SystemPrompt := ''; // Consumed
          end
          else
            SB.Append('<s>[INST] ').Append(UserContent).Append(' [/INST]');
        end;
        mrAssistant:
        begin
          SB.Append(' ').Append(Trim(AMessages[i].Content)).Append('</s>');
        end;
      end;
    end;

    if AAddGenPrompt and (SB.Length > 0) and not SB.ToString.EndsWith(' ') then
      SB.Append(' ');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatAlpaca(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string;
var
  SB: TStringBuilder;
  i: Integer;
  SystemPrompt: string;
begin
  SB := TStringBuilder.Create;
  try
    SystemPrompt := 'Below is an instruction that describes a task. Write a response that appropriately completes the request.';
    for i := 0 to High(AMessages) do
    begin
      if AMessages[i].Role = mrSystem then
        SystemPrompt := Trim(AMessages[i].Content);
    end;

    SB.Append(SystemPrompt).Append(#10#10);

    for i := 0 to High(AMessages) do
    begin
      case AMessages[i].Role of
        mrUser:
          SB.Append('### Instruction:').Append(#10).Append(Trim(AMessages[i].Content)).Append(#10#10);
        mrAssistant:
          SB.Append('### Response:').Append(#10).Append(Trim(AMessages[i].Content)).Append(#10#10);
      end;
    end;

    if AAddGenPrompt then
      SB.Append('### Response:').Append(#10);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatGemma(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AMessages) do
    begin
      case AMessages[i].Role of
        mrSystem, mrUser:
        begin
          SB.Append('<start_of_turn>user').Append(#10)
            .Append(Trim(AMessages[i].Content))
            .Append('<end_of_turn>').Append(#10);
        end;
        mrAssistant:
        begin
          SB.Append('<start_of_turn>model').Append(#10)
            .Append(Trim(AMessages[i].Content))
            .Append('<end_of_turn>').Append(#10);
        end;
      end;
    end;

    if AAddGenPrompt then
      SB.Append('<start_of_turn>model').Append(#10);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatPhi3(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string;
var
  SB: TStringBuilder;
  i: Integer;
  RoleStr: string;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AMessages) do
    begin
      case AMessages[i].Role of
        mrSystem:    RoleStr := 'system';
        mrUser:      RoleStr := 'user';
        mrAssistant: RoleStr := 'assistant';
        mrTool:      RoleStr := 'user';
      end;
      SB.Append('<|').Append(RoleStr).Append('|>').Append(#10)
        .Append(Trim(AMessages[i].Content))
        .Append('<|end|>').Append(#10);
    end;

    if AAddGenPrompt then
      SB.Append('<|assistant|>').Append(#10);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatDeepSeekR1(const AMessages: TChatMessageArray; const AAddGenPrompt: Boolean): string;
var
  SB: TStringBuilder;
  i: Integer;
  SystemPrompt: string;
begin
  SB := TStringBuilder.Create;
  try
    SystemPrompt := '';
    for i := 0 to High(AMessages) do
    begin
      if AMessages[i].Role = mrSystem then
      begin
        if SystemPrompt <> '' then
          SystemPrompt := SystemPrompt + #10#10 + Trim(AMessages[i].Content)
        else
          SystemPrompt := Trim(AMessages[i].Content);
      end;
    end;

    if SystemPrompt <> '' then
      SB.Append(SystemPrompt).Append(#10#10);

    for i := 0 to High(AMessages) do
    begin
      case AMessages[i].Role of
        mrUser:
          SB.Append('<｜User｜>').Append(Trim(AMessages[i].Content));
        mrAssistant:
          SB.Append('<｜Assistant｜>').Append(Trim(AMessages[i].Content)).Append('<｜end of sentence｜>');
      end;
    end;

    if AAddGenPrompt then
      SB.Append('<｜Assistant｜>');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatRaw(const AMessages: TChatMessageArray): string;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AMessages) do
      SB.Append(AMessages[i].Content).Append(#10#10);
    Result := TrimRight(SB.ToString);
  finally
    SB.Free;
  end;
end;

class function TPromptFormatter.FormatPrompt(const AMessages: TChatMessageArray;
  const ATemplate: TPromptTemplateType; const AAddAssistantGenerationPrompt: Boolean): string;
begin
  if Length(AMessages) = 0 then Exit('');

  case ATemplate of
    pttChatML:     Result := FormatChatML(AMessages, AAddAssistantGenerationPrompt);
    pttLlama3:     Result := FormatLlama3(AMessages, AAddAssistantGenerationPrompt);
    pttMistral:    Result := FormatMistral(AMessages, AAddAssistantGenerationPrompt);
    pttAlpaca:     Result := FormatAlpaca(AMessages, AAddAssistantGenerationPrompt);
    pttGemma:      Result := FormatGemma(AMessages, AAddAssistantGenerationPrompt);
    pttPhi3:       Result := FormatPhi3(AMessages, AAddAssistantGenerationPrompt);
    pttDeepSeekR1: Result := FormatDeepSeekR1(AMessages, AAddAssistantGenerationPrompt);
    pttRaw:        Result := FormatRaw(AMessages);
    else           Result := FormatChatML(AMessages, AAddAssistantGenerationPrompt);
  end;
end;

class function TPromptFormatter.GetStopTokens(const ATemplate: TPromptTemplateType): TStringArray;
begin
  case ATemplate of
    pttChatML:
    begin
      SetLength(Result, 2);
      Result[0] := '<|im_end|>';
      Result[1] := '<|im_start|>';
    end;
    pttLlama3:
    begin
      SetLength(Result, 3);
      Result[0] := '<|eot_id|>';
      Result[1] := '<|end_of_text|>';
      Result[2] := '<|start_header_id|>';
    end;
    pttMistral:
    begin
      SetLength(Result, 2);
      Result[0] := '</s>';
      Result[1] := '[INST]';
    end;
    pttAlpaca:
    begin
      SetLength(Result, 2);
      Result[0] := '### Instruction:';
      Result[1] := '### Response:';
    end;
    pttGemma:
    begin
      SetLength(Result, 2);
      Result[0] := '<end_of_turn>';
      Result[1] := '<start_of_turn>';
    end;
    pttPhi3:
    begin
      SetLength(Result, 2);
      Result[0] := '<|end|>';
      Result[1] := '<|user|>';
    end;
    pttDeepSeekR1:
    begin
      SetLength(Result, 2);
      Result[0] := '<｜end of sentence｜>';
      Result[1] := '<｜User｜>';
    end;
    pttRaw:
    begin
      SetLength(Result, 0);
    end;
  end;
end;

class function TPromptFormatter.DetectTemplateFromModelName(const AModelName: string): TPromptTemplateType;
var
  Lower: string;
begin
  Lower := LowerCase(AModelName);

  if Pos('llama-3', Lower) > 0 then Exit(pttLlama3);
  if Pos('llama3', Lower) > 0 then Exit(pttLlama3);
  if Pos('deepseek-r1', Lower) > 0 then Exit(pttDeepSeekR1);
  if Pos('deepseek', Lower) > 0 then Exit(pttChatML);
  if Pos('qwen', Lower) > 0 then Exit(pttChatML);
  if Pos('yi-', Lower) > 0 then Exit(pttChatML);
  if Pos('hermes', Lower) > 0 then Exit(pttChatML);
  if Pos('mistral', Lower) > 0 then Exit(pttMistral);
  if Pos('mixtral', Lower) > 0 then Exit(pttMistral);
  if Pos('zephyr', Lower) > 0 then Exit(pttMistral);
  if Pos('gemma', Lower) > 0 then Exit(pttGemma);
  if Pos('phi-3', Lower) > 0 then Exit(pttPhi3);
  if Pos('phi3', Lower) > 0 then Exit(pttPhi3);
  if Pos('alpaca', Lower) > 0 then Exit(pttAlpaca);
  if Pos('vicuna', Lower) > 0 then Exit(pttAlpaca);

  // Default fallback
  Result := pttChatML;
end;

class function TPromptFormatter.TemplateTypeToString(const ATemplate: TPromptTemplateType): string;
begin
  case ATemplate of
    pttChatML:     Result := 'ChatML';
    pttLlama3:     Result := 'Llama-3';
    pttMistral:    Result := 'Mistral';
    pttAlpaca:     Result := 'Alpaca';
    pttGemma:      Result := 'Gemma';
    pttPhi3:       Result := 'Phi-3';
    pttDeepSeekR1: Result := 'DeepSeek-R1';
    pttRaw:        Result := 'Raw';
    else           Result := 'ChatML';
  end;
end;

class function TPromptFormatter.StringToTemplateType(const AStr: string): TPromptTemplateType;
var
  Upper: string;
begin
  Upper := UpperCase(Trim(AStr));
  if (Upper = 'CHATML') or (Upper = 'QWEN') then Exit(pttChatML);
  if (Upper = 'LLAMA-3') or (Upper = 'LLAMA3') or (Upper = 'LLAMA 3') then Exit(pttLlama3);
  if (Upper = 'MISTRAL') or (Upper = 'MIXTRAL') then Exit(pttMistral);
  if Upper = 'ALPACA' then Exit(pttAlpaca);
  if (Upper = 'GEMMA') or (Upper = 'GEMMA2') then Exit(pttGemma);
  if (Upper = 'PHI-3') or (Upper = 'PHI3') then Exit(pttPhi3);
  if (Upper = 'DEEPSEEK-R1') or (Upper = 'DEEPSEEK_R1') then Exit(pttDeepSeekR1);
  if Upper = 'RAW' then Exit(pttRaw);
  Result := pttChatML;
end;

{ Global Helpers }

function FormatMessagesToPrompt(const AMessages: TChatMessageArray; const ATemplate: TPromptTemplateType): string;
begin
  Result := TPromptFormatter.FormatPrompt(AMessages, ATemplate, True);
end;

function GetDefaultStopTokensForTemplate(const ATemplate: TPromptTemplateType): TStringArray;
begin
  Result := TPromptFormatter.GetStopTokens(ATemplate);
end;

end.

