unit ufrmplayground;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Spin, DateUtils, fpjson, jsonparser, uchattypes, upromptformatter,
  usseclient, uformatting, uconfigtypes, ujsonhelper, ulogger;

type
  { TfrmPlayground }

  TfrmPlayground = class(TForm)
    btnClearChat: TButton;
    btnExportChat: TButton;
    btnSend: TButton;
    btnStop: TButton;
    chkJsonMode: TCheckBox;
    chkStream: TCheckBox;
    cmbTemplate: TComboBox;
    dlgSaveChat: TSaveDialog;
    edtEndpoint: TEdit;
    edtStopTokens: TEdit;
    gbMetrics: TGroupBox;
    gbSampling: TGroupBox;
    gbSystemPrompt: TGroupBox;
    lblCompTokensMetric: TLabel;
    lblEndpoint: TLabel;
    lblFinishReason: TLabel;
    lblMaxTokens: TLabel;
    lblMinP: TLabel;
    lblPresencePenalty: TLabel;
    lblPromptTokensMetric: TLabel;
    lblRepeatPenalty: TLabel;
    lblSeed: TLabel;
    lblSpeedMetric: TLabel;
    lblStopTokens: TLabel;
    lblTemplate: TLabel;
    lblTemp: TLabel;
    lblTopK: TLabel;
    lblTopP: TLabel;
    lblTotalTimeMetric: TLabel;
    lblTotalTokensMetric: TLabel;
    lblTTFTMetric: TLabel;
    mmoChatHistory: TMemo;
    mmoSystemPrompt: TMemo;
    mmoUserInput: TMemo;
    pnlBottomInput: TPanel;
    pnlChat: TPanel;
    pnlMain: TPanel;
    pnlMessages: TPanel;
    pnlSendButtons: TPanel;
    pnlSidebar: TPanel;
    pnlTopBar: TPanel;
    sbSidebar: TScrollBox;
    seMaxTokens: TSpinEdit;
    seMinP: TFloatSpinEdit;
    sePresencePenalty: TFloatSpinEdit;
    seRepeatPenalty: TFloatSpinEdit;
    seSeed: TSpinEdit;
    seTemp: TFloatSpinEdit;
    seTopK: TSpinEdit;
    seTopP: TFloatSpinEdit;
    splSidebar: TSplitter;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnSendClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnClearChatClick(Sender: TObject);
    procedure btnExportChatClick(Sender: TObject);
    procedure mmoUserInputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FChatMessages: TChatMessageArray;
    FActiveSSEThread: TSSEClientThread;
    FIsGenerating: Boolean;
    FCurrentAssistantBuffer: string;
    FCurrentEndpointUrl: string;

    procedure SetGeneratingUIState(const AIsBusy: Boolean);
    procedure RenderChatHistoryView;
    procedure AppendAssistantToken(const AToken: string);
    procedure FinalizeAssistantResponse(const AMetrics: TInferenceMetrics; const AFinishReason: TFinishReason);
    procedure UpdateMetricsUI(const AMetrics: TInferenceMetrics; const AFinishReason: TFinishReason);
    function BuildInferencePayload(const AStream: Boolean): string;
    function ParseCustomStopTokens: TStringArray;

    // SSE Callbacks
    procedure OnSSETokenReceived(Sender: TObject; const AToken: string; const AIsDone: Boolean;
                                const AMetrics: TInferenceMetrics; const AFinishReason: TFinishReason);
    procedure OnSSEErrorReceived(Sender: TObject; const AError: string; const AStatusCode: Integer);
  public
    procedure AppendSystemMessage(const AContent: string);
    procedure SetServerEndpoint(const AEndpoint: string);
  end;

var
  frmPlayground: TfrmPlayground;

implementation

{$R *.lfm}

{ TfrmPlayground }

procedure TfrmPlayground.FormCreate(Sender: TObject);
begin
  SetLength(FChatMessages, 0);
  FActiveSSEThread := nil;
  FIsGenerating := False;
  FCurrentAssistantBuffer := '';
  FCurrentEndpointUrl := 'http://127.0.0.1:8080';
  edtEndpoint.Text := FCurrentEndpointUrl;
end;

procedure TfrmPlayground.FormDestroy(Sender: TObject);
begin
  if Assigned(FActiveSSEThread) then
  begin
    FActiveSSEThread.AbortStream;
    FActiveSSEThread.WaitFor;
    FreeAndNil(FActiveSSEThread);
  end;
  SetLength(FChatMessages, 0);
end;

procedure TfrmPlayground.FormShow(Sender: TObject);
begin
  SetGeneratingUIState(FIsGenerating);
  if mmoUserInput.CanFocus then
    mmoUserInput.SetFocus;
end;

procedure TfrmPlayground.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if FIsGenerating and Assigned(FActiveSSEThread) then
  begin
    FActiveSSEThread.AbortStream;
    FActiveSSEThread.WaitFor;
    FreeAndNil(FActiveSSEThread);
    FIsGenerating := False;
  end;
  CloseAction := caHide;
end;

procedure TfrmPlayground.SetServerEndpoint(const AEndpoint: string);
begin
  if Trim(AEndpoint) <> '' then
  begin
    FCurrentEndpointUrl := Trim(AEndpoint);
    edtEndpoint.Text := FCurrentEndpointUrl;
  end;
end;

procedure TfrmPlayground.AppendSystemMessage(const AContent: string);
begin
  mmoSystemPrompt.Text := Trim(AContent);
end;

procedure TfrmPlayground.SetGeneratingUIState(const AIsBusy: Boolean);
begin
  FIsGenerating := AIsBusy;
  btnSend.Enabled := not AIsBusy;
  btnStop.Enabled := AIsBusy;
  btnClearChat.Enabled := not AIsBusy;
  mmoUserInput.ReadOnly := AIsBusy;
  cmbTemplate.Enabled := not AIsBusy;
  edtEndpoint.ReadOnly := AIsBusy;
  gbSampling.Enabled := not AIsBusy;

  if not AIsBusy then
  begin
    if mmoUserInput.CanFocus then
      mmoUserInput.SetFocus;
  end;
end;

procedure TfrmPlayground.RenderChatHistoryView;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(FChatMessages) do
    begin
      case FChatMessages[i].Role of
        mrSystem:
        begin
          SB.AppendLine('[SYSTEM]');
          SB.AppendLine(Trim(FChatMessages[i].Content));
          SB.AppendLine('');
        end;
        mrUser:
        begin
          SB.AppendLine('USER:');
          SB.AppendLine(Trim(FChatMessages[i].Content));
          SB.AppendLine('');
        end;
        mrAssistant:
        begin
          SB.AppendLine('ASSISTANT:');
          SB.AppendLine(Trim(FChatMessages[i].Content));
          SB.AppendLine('--------------------------------------------------------------------------------');
        end;
      end;
    end;

    mmoChatHistory.Text := SB.ToString;
    mmoChatHistory.SelStart := Length(mmoChatHistory.Text);
    mmoChatHistory.SelLength := 0;
  finally
    SB.Free;
  end;
end;

procedure TfrmPlayground.AppendAssistantToken(const AToken: string);
begin
  FCurrentAssistantBuffer := FCurrentAssistantBuffer + AToken;
  mmoChatHistory.Text := mmoChatHistory.Text + AToken;
  mmoChatHistory.SelStart := Length(mmoChatHistory.Text);
  mmoChatHistory.SelLength := 0;
end;

procedure TfrmPlayground.FinalizeAssistantResponse(const AMetrics: TInferenceMetrics; const AFinishReason: TFinishReason);
var
  Len: Integer;
begin
  if Trim(FCurrentAssistantBuffer) <> '' then
  begin
    Len := Length(FChatMessages);
    SetLength(FChatMessages, Len + 1);
    FChatMessages[Len] := TChatMessage.Create(mrAssistant, Trim(FCurrentAssistantBuffer));
  end;

  mmoChatHistory.Lines.Add('');
  mmoChatHistory.Lines.Add('--------------------------------------------------------------------------------');

  UpdateMetricsUI(AMetrics, AFinishReason);
  FCurrentAssistantBuffer := '';
  SetGeneratingUIState(False);
end;

procedure TfrmPlayground.UpdateMetricsUI(const AMetrics: TInferenceMetrics; const AFinishReason: TFinishReason);
var
  TTFTMs: Double;
begin
  if (AMetrics.FirstTokenTime > 0) and (AMetrics.StartTime > 0) then
    TTFTMs := MilliSecondsBetween(AMetrics.FirstTokenTime, AMetrics.StartTime)
  else
    TTFTMs := 0.0;

  lblSpeedMetric.Caption := Format('Generation Speed: %s', [FormatTokenSpeed(AMetrics.TokensPerSecond)]);
  lblTTFTMetric.Caption := Format('Time to First Token: %.1f ms', [TTFTMs]);
  lblPromptTokensMetric.Caption := Format('Prompt Tokens: %d', [AMetrics.PromptTokens]);
  lblCompTokensMetric.Caption := Format('Completion Tokens: %d', [AMetrics.CompletionTokens]);
  lblTotalTokensMetric.Caption := Format('Total Tokens: %d', [AMetrics.PromptTokens + AMetrics.CompletionTokens]);
  lblTotalTimeMetric.Caption := Format('Total Duration: %.2f s', [AMetrics.TotalDurationMs / 1000.0]);
  lblFinishReason.Caption := Format('Finish Reason: %s', [FinishReasonToString(AFinishReason)]);
end;

function TfrmPlayground.ParseCustomStopTokens: TStringArray;
var
  RawList: TStringList;
  i: Integer;
begin
  SetLength(Result, 0);
  if Trim(edtStopTokens.Text) = '' then Exit;

  RawList := TStringList.Create;
  try
    RawList.Delimiter := ',';
    RawList.StrictDelimiter := True;
    RawList.DelimitedText := edtStopTokens.Text;

    SetLength(Result, RawList.Count);
    for i := 0 to RawList.Count - 1 do
      Result[i] := Trim(RawList[i]);
  finally
    RawList.Free;
  end;
end;

function TfrmPlayground.BuildInferencePayload(const AStream: Boolean): string;
var
  RootObj, MsgObj, RespFormatObj: TJSONObject;
  MessagesArr, StopArr: TJSONArray;
  i: Integer;
  StopTokens: TStringArray;
  TplType: TPromptTemplateType;
begin
  RootObj := TJSONObject.Create;
  try
    MessagesArr := TJSONArray.Create;

    // 1. System Prompt
    if Trim(mmoSystemPrompt.Text) <> '' then
    begin
      MsgObj := TJSONObject.Create;
      MsgObj.Add('role', 'system');
      MsgObj.Add('content', Trim(mmoSystemPrompt.Text));
      MessagesArr.Add(MsgObj);
    end;

    // 2. Chat history
    for i := 0 to High(FChatMessages) do
    begin
      if FChatMessages[i].Role = mrSystem then Continue;
      MsgObj := TJSONObject.Create;
      case FChatMessages[i].Role of
        mrUser:      MsgObj.Add('role', 'user');
        mrAssistant: MsgObj.Add('role', 'assistant');
        mrTool:      MsgObj.Add('role', 'tool');
      end;
      MsgObj.Add('content', FChatMessages[i].Content);
      MessagesArr.Add(MsgObj);
    end;

    RootObj.Add('messages', MessagesArr);

    // 3. Sampling Parameters
    RootObj.Add('temperature', seTemp.Value);
    RootObj.Add('top_p', seTopP.Value);
    RootObj.Add('min_p', seMinP.Value);
    RootObj.Add('top_k', seTopK.Value);
    RootObj.Add('repeat_penalty', seRepeatPenalty.Value);
    RootObj.Add('presence_penalty', sePresencePenalty.Value);

    if seMaxTokens.Value > 0 then
      RootObj.Add('max_tokens', seMaxTokens.Value);

    if seSeed.Value >= 0 then
      RootObj.Add('seed', Int64(seSeed.Value));

    RootObj.Add('stream', AStream);

    // 4. Custom & Template Stop Sequences
    TplType := TPromptFormatter.StringToTemplateType(cmbTemplate.Text);
    StopTokens := ParseCustomStopTokens;
    if Length(StopTokens) = 0 then
      StopTokens := TPromptFormatter.GetStopTokens(TplType);

    if Length(StopTokens) > 0 then
    begin
      StopArr := TJSONArray.Create;
      for i := 0 to High(StopTokens) do
        if Trim(StopTokens[i]) <> '' then
          StopArr.Add(StopTokens[i]);
      RootObj.Add('stop', StopArr);
    end;

    // 5. JSON Grammar Constraint
    if chkJsonMode.Checked then
    begin
      RespFormatObj := TJSONObject.Create;
      RespFormatObj.Add('type', 'json_object');
      RootObj.Add('response_format', RespFormatObj);
    end;

    Result := RootObj.AsJSON;
  finally
    RootObj.Free;
  end;
end;

procedure TfrmPlayground.btnSendClick(Sender: TObject);
var
  InputText, TargetEndpoint, PayloadJSON: string;
  Len: Integer;
begin
  InputText := Trim(mmoUserInput.Text);
  if (InputText = '') or FIsGenerating then Exit;

  // Add User Message to History
  Len := Length(FChatMessages);
  SetLength(FChatMessages, Len + 1);
  FChatMessages[Len] := TChatMessage.Create(mrUser, InputText);

  mmoUserInput.Clear;
  RenderChatHistoryView;

  // Visual header for incoming Assistant response
  mmoChatHistory.Lines.Add('ASSISTANT:');
  FCurrentAssistantBuffer := '';

  TargetEndpoint := Trim(edtEndpoint.Text);
  if TargetEndpoint.EndsWith('/') then
    TargetEndpoint := Copy(TargetEndpoint, 1, Length(TargetEndpoint) - 1);

  if not TargetEndpoint.EndsWith('/v1/chat/completions') then
    TargetEndpoint := TargetEndpoint + '/v1/chat/completions';

  PayloadJSON := BuildInferencePayload(chkStream.Checked);
  SetGeneratingUIState(True);

  if Assigned(FActiveSSEThread) then
  begin
    FActiveSSEThread.AbortStream;
    FActiveSSEThread.WaitFor;
    FreeAndNil(FActiveSSEThread);
  end;

  FActiveSSEThread := TSSEClientThread.Create(
    TargetEndpoint,
    PayloadJSON,
    '', // Optional Bearer API Key
    180,
    @OnSSETokenReceived,
    @OnSSEErrorReceived
  );
  FActiveSSEThread.Start;
end;

procedure TfrmPlayground.btnStopClick(Sender: TObject);
begin
  if Assigned(FActiveSSEThread) then
  begin
    FActiveSSEThread.AbortStream;
    LogInfo('User requested stop for active inference stream.', 'PLAY');
  end;
end;

procedure TfrmPlayground.btnClearChatClick(Sender: TObject);
begin
  if MessageDlg('Clear Chat', 'Are you sure you want to clear the entire conversation history?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    SetLength(FChatMessages, 0);
    mmoChatHistory.Clear;
    FCurrentAssistantBuffer := '';

    lblSpeedMetric.Caption := 'Generation Speed: 0 t/s';
    lblTTFTMetric.Caption := 'Time to First Token: 0 ms';
    lblPromptTokensMetric.Caption := 'Prompt Tokens: 0';
    lblCompTokensMetric.Caption := 'Completion Tokens: 0';
    lblTotalTokensMetric.Caption := 'Total Tokens: 0';
    lblTotalTimeMetric.Caption := 'Total Duration: 0.00 s';
    lblFinishReason.Caption := 'Finish Reason: None';
  end;
end;

procedure TfrmPlayground.btnExportChatClick(Sender: TObject);
var
  OutList: TStringList;
  i: Integer;
  Ext: string;
  RootObj: TJSONObject;
  ItemObj: TJSONArray;
  Obj: TJSONObject;
begin
  if Length(FChatMessages) = 0 then
  begin
    MessageDlg('Empty Chat', 'There are no messages in the conversation history to export.', mtInformation, [mbOK], 0);
    Exit;
  end;

  dlgSaveChat.FileName := 'chat_transcript_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.md';
  if dlgSaveChat.Execute then
  begin
    Ext := LowerCase(ExtractFileExt(dlgSaveChat.FileName));
    OutList := TStringList.Create;
    try
      if Ext = '.json' then
      begin
        RootObj := TJSONObject.Create;
        try
          RootObj.Add('system_prompt', Trim(mmoSystemPrompt.Text));
          ItemObj := TJSONArray.Create;
          for i := 0 to High(FChatMessages) do
          begin
            Obj := TJSONObject.Create;
            Obj.Add('role', MessageRoleToString(FChatMessages[i].Role));
            Obj.Add('content', FChatMessages[i].Content);
            ItemObj.Add(Obj);
          end;
          RootObj.Add('messages', ItemObj);
          OutList.Text := RootObj.FormatJSON;
        finally
          RootObj.Free;
        end;
      end
      else if Ext = '.md' then
      begin
        OutList.Add('# Chat Conversation Transcript');
        OutList.Add('*Exported on ' + DateTimeToStr(Now) + '*');
        OutList.Add('');
        if Trim(mmoSystemPrompt.Text) <> '' then
        begin
          OutList.Add('> **System Prompt**: ' + Trim(mmoSystemPrompt.Text));
          OutList.Add('');
        end;
        for i := 0 to High(FChatMessages) do
        begin
          case FChatMessages[i].Role of
            mrUser:
            begin
              OutList.Add('### 👤 User');
              OutList.Add(FChatMessages[i].Content);
              OutList.Add('');
            end;
            mrAssistant:
            begin
              OutList.Add('### 🤖 Assistant');
              OutList.Add(FChatMessages[i].Content);
              OutList.Add('');
              OutList.Add('---');
              OutList.Add('');
            end;
          end;
        end;
      end
      else
      begin
        // Standard Text Transcript
        OutList.Add('================ CHAT CONVERSATION LOG ================');
        if Trim(mmoSystemPrompt.Text) <> '' then
        begin
          OutList.Add('[SYSTEM]: ' + Trim(mmoSystemPrompt.Text));
          OutList.Add('-------------------------------------------------------');
        end;
        for i := 0 to High(FChatMessages) do
        begin
          OutList.Add(UpperCase(MessageRoleToString(FChatMessages[i].Role)) + ':');
          OutList.Add(FChatMessages[i].Content);
          OutList.Add('');
        end;
        OutList.Add('=======================================================');
      end;

      OutList.SaveToFile(dlgSaveChat.FileName);
      LogInfo('Exported chat transcript: ' + dlgSaveChat.FileName, 'PLAY');
      ShowMessage('Chat conversation successfully exported to:' + sLineBreak + dlgSaveChat.FileName);
    finally
      OutList.Free;
    end;
  end;
end;

procedure TfrmPlayground.mmoUserInputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = 13) and (ssCtrl in Shift) then
  begin
    Key := 0;
    btnSendClick(Sender);
  end;
end;

procedure TfrmPlayground.OnSSETokenReceived(Sender: TObject; const AToken: string;
  const AIsDone: Boolean; const AMetrics: TInferenceMetrics; const AFinishReason: TFinishReason);
begin
  if AToken <> '' then
    AppendAssistantToken(AToken);

  UpdateMetricsUI(AMetrics, AFinishReason);

  if AIsDone then
    FinalizeAssistantResponse(AMetrics, AFinishReason);
end;

procedure TfrmPlayground.OnSSEErrorReceived(Sender: TObject; const AError: string; const AStatusCode: Integer);
begin
  SetGeneratingUIState(False);
  mmoChatHistory.Lines.Add('');
  mmoChatHistory.Lines.Add(Format('[ERROR %d]: %s', [AStatusCode, AError]));
  mmoChatHistory.Lines.Add('--------------------------------------------------------------------------------');
  MessageDlg('Inference Stream Error', Format('Failed to receive response (Status %d):' + sLineBreak + '%s', [AStatusCode, AError]), mtError, [mbOK], 0);
end;

end.
