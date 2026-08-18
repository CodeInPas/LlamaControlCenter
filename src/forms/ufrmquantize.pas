unit ufrmquantize;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Spin, LCLIntf, ColorSpeedButton, DateUtils, uconfigtypes,
  ugguftypes, uggufparser, ullamaprocess, uansiparser, uformatting, ulogger;

type
  { TfrmQuantize }

  TfrmQuantize = class(TForm)
    btnAutoTarget: TButton;
    btnBrowseIMatrix: TButton;
    btnBrowseSource: TButton;
    btnBrowseTarget: TButton;
    btnOpenOutputFolder: TColorSpeedButton;
    btnClearConsole: TButton;
    btnStartQuantize: TColorSpeedButton;
    btnCancelQuantize: TColorSpeedButton;
    chkAutoScroll: TCheckBox;
    chkLeaveOutputTensor: TCheckBox;
    chkPure: TCheckBox;
    cmbQuantType: TComboBox;
    dlgOpenIMatrix: TOpenDialog;
    dlgOpenSource: TOpenDialog;
    dlgSaveTarget: TSaveDialog;
    edtExtraArgs: TEdit;
    edtIMatrix: TEdit;
    edtSourceModel: TEdit;
    edtTargetModel: TEdit;
    gbFiles: TGroupBox;
    gbOptions: TGroupBox;
    lblConsoleTitle: TLabel;
    lblExtraArgs: TLabel;
    lblIMatrix: TLabel;
    lblQuantType: TLabel;
    lblSourceInfo: TLabel;
    lblSourceModel: TLabel;
    lblStatus: TLabel;
    lblTargetModel: TLabel;
    lblThreads: TLabel;
    mmoConsole: TMemo;
    Panel1: TPanel;
    pbProgress: TProgressBar;
    pnlConsole: TPanel;
    pnlConsoleToolbar: TPanel;
    pnlMiddleActions: TPanel;
    pnlTopConfig: TPanel;
    seThreads: TSpinEdit;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnBrowseSourceClick(Sender: TObject);
    procedure btnBrowseTargetClick(Sender: TObject);
    procedure btnAutoTargetClick(Sender: TObject);
    procedure btnBrowseIMatrixClick(Sender: TObject);
    procedure edtSourceModelChange(Sender: TObject);
    procedure cmbQuantTypeChange(Sender: TObject);
    procedure btnStartQuantizeClick(Sender: TObject);
    procedure btnCancelQuantizeClick(Sender: TObject);
    procedure btnOpenOutputFolderClick(Sender: TObject);
    procedure btnClearConsoleClick(Sender: TObject);
  private
    FQuantizeProcessThread: TLlamaProcessThread;
    FIsQuantizing: Boolean;
    FStartTime: TDateTime;

    function GetSelectedQuantTypeStr: string;
    function BuildAutoTargetFileName(const ASourcePath, AQuantType: string): string;
    function BuildCommandLineArgs(const ASourcePath, ATargetPath, AQuantType: string): string;
    procedure InspectSourceModel(const APath: string);
    procedure ParseProgressFromLine(const ALine: string);
    procedure SetUIState(const AIsRunning: Boolean);
    procedure AppendConsoleLine(const AText: string; const AIsStdErr: Boolean);

    // Worker Callbacks
    procedure OnProcessOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
    procedure OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
  public
    procedure SetSourceModelPath(const APath: string);
  end;

var
  frmQuantize: TfrmQuantize;

implementation

{$R *.lfm}

{ TfrmQuantize }

procedure TfrmQuantize.FormCreate(Sender: TObject);
begin
  FQuantizeProcessThread := nil;
  FIsQuantizing := False;
  FStartTime := 0;
  seThreads.Value := GetCPUCount;
end;

procedure TfrmQuantize.FormDestroy(Sender: TObject);
begin
  if Assigned(FQuantizeProcessThread) then
  begin
    FQuantizeProcessThread.RequestStop;
    FQuantizeProcessThread.WaitFor;
    FreeAndNil(FQuantizeProcessThread);
  end;
end;

procedure TfrmQuantize.FormShow(Sender: TObject);
begin
  SetUIState(FIsQuantizing);
end;

procedure TfrmQuantize.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if FIsQuantizing then
  begin
    if MessageDlg('Quantization in Progress',
      'Quantization is currently running. Do you want to cancel the job and close?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      btnCancelQuantizeClick(nil);
      CloseAction := caHide;
    end
    else
      CloseAction := caNone;
  end
  else
    CloseAction := caHide;
end;

function TfrmQuantize.GetSelectedQuantTypeStr: string;
var
  FullText: string;
  PosSpace: Integer;
begin
  FullText := Trim(cmbQuantType.Text);
  PosSpace := Pos(' ', FullText);
  if PosSpace > 0 then
    Result := Copy(FullText, 1, PosSpace - 1)
  else
    Result := FullText;
end;

function TfrmQuantize.BuildAutoTargetFileName(const ASourcePath, AQuantType: string): string;
var
  Dir, BaseName, LowerBase: string;
begin
  if ASourcePath = '' then Exit('');

  Dir := ExtractFileDir(ASourcePath);
  BaseName := ChangeFileExt(ExtractFileName(ASourcePath), '');
  LowerBase := LowerCase(BaseName);

  // Strip existing quantization or bit-depth tags
  if LowerBase.EndsWith('-f16') or LowerBase.EndsWith('-fp16') or
     LowerBase.EndsWith('-bf16') or LowerBase.EndsWith('-f32') or
     LowerBase.EndsWith('-fp32') or LowerBase.EndsWith('-orig') then
  begin
    BaseName := Copy(BaseName, 1, Length(BaseName) - 5);
  end;

  Result := Dir + PathDelim + BaseName + '-' + AQuantType + '.gguf';
end;

function TfrmQuantize.BuildCommandLineArgs(const ASourcePath, ATargetPath, AQuantType: string): string;
var
  Args: TStringList;
begin
  Args := TStringList.Create;
  try
    Args.Delimiter := ' ';
    Args.StrictDelimiter := False;

    if Trim(edtIMatrix.Text) <> '' then
      Args.Add('--imatrix "' + Trim(edtIMatrix.Text) + '"');

    if chkLeaveOutputTensor.Checked then
      Args.Add('--leave-output-tensor');

    if chkPure.Checked then
      Args.Add('--pure');

    if Trim(edtExtraArgs.Text) <> '' then
      Args.Add(Trim(edtExtraArgs.Text));

    Args.Add('"' + ASourcePath + '"');
    Args.Add('"' + ATargetPath + '"');
    Args.Add(AQuantType);
    Args.Add(IntToStr(seThreads.Value));

    Result := Args.DelimitedText;
  finally
    Args.Free;
  end;
end;

procedure TfrmQuantize.InspectSourceModel(const APath: string);
var
  Info: TGGUFModelInfo;
begin
  if not FileExists(APath) then
  begin
    lblSourceInfo.Caption := 'Source: Select a valid GGUF model file.';
    lblSourceInfo.Font.Color := clGray;
    Exit;
  end;

  Info := TGGUFParser.QuickInspect(APath);
  lblSourceInfo.Caption := Format('Source: %s | Arch: %s | Params: %s | Original Quant: %s | Size: %s', [
    Info.ModelName,
    Info.Architecture,
    FormatParameterCount(Info.TotalParameters),
    Info.QuantizationType,
    FormatBytes(Info.FileSize)
  ]);
  lblSourceInfo.Font.Color := clNavy;
end;

procedure TfrmQuantize.SetSourceModelPath(const APath: string);
begin
  edtSourceModel.Text := APath;
  InspectSourceModel(APath);
  btnAutoTargetClick(nil);
end;

procedure TfrmQuantize.ParseProgressFromLine(const ALine: string);
var
  PosBracketOpen, PosSlash, PosBracketClose: Integer;
  CurStr, TotalStr: string;
  CurTensor, TotalTensor: Integer;
begin
  // Standard llama-quantize output pattern: [   1/ 291] or [12/291]
  PosBracketOpen := Pos('[', ALine);
  if PosBracketOpen > 0 then
  begin
    PosSlash := Pos('/', ALine);
    PosBracketClose := Pos(']', ALine);

    if (PosSlash > PosBracketOpen) and (PosBracketClose > PosSlash) then
    begin
      CurStr := Trim(Copy(ALine, PosBracketOpen + 1, PosSlash - PosBracketOpen - 1));
      TotalStr := Trim(Copy(ALine, PosSlash + 1, PosBracketClose - PosSlash - 1));

      CurTensor := StrToIntDef(CurStr, 0);
      TotalTensor := StrToIntDef(TotalStr, 0);

      if (TotalTensor > 0) and (CurTensor > 0) then
      begin
        pbProgress.Position := Round((CurTensor / TotalTensor) * 100.0);
        lblStatus.Caption := Format('Status: Quantizing tensor %d of %d (%.1f%%)...', [
          CurTensor, TotalTensor, (CurTensor / TotalTensor) * 100.0
        ]);
      end;
    end;
  end;
end;

procedure TfrmQuantize.SetUIState(const AIsRunning: Boolean);
begin
  FIsQuantizing := AIsRunning;
  btnStartQuantize.Enabled := not AIsRunning;
  btnCancelQuantize.Enabled := AIsRunning;
  btnBrowseSource.Enabled := not AIsRunning;
  btnBrowseTarget.Enabled := not AIsRunning;
  btnAutoTarget.Enabled := not AIsRunning;
  btnBrowseIMatrix.Enabled := not AIsRunning;
  edtSourceModel.ReadOnly := AIsRunning;
  edtTargetModel.ReadOnly := AIsRunning;
  cmbQuantType.Enabled := not AIsRunning;
  seThreads.Enabled := not AIsRunning;
  chkLeaveOutputTensor.Enabled := not AIsRunning;
  chkPure.Enabled := not AIsRunning;
  edtExtraArgs.ReadOnly := AIsRunning;

  if not AIsRunning then
  begin
    if pbProgress.Position >= 100 then
      lblStatus.Caption := 'Status: Quantization completed successfully.'
    else if pbProgress.Position > 0 then
      lblStatus.Caption := 'Status: Idle / Ready'
    else
      lblStatus.Caption := 'Status: Ready for quantization';
  end;
end;

procedure TfrmQuantize.AppendConsoleLine(const AText: string; const AIsStdErr: Boolean);
var
  Clean: string;
begin
  Clean := StripAnsi(AText);
  ParseProgressFromLine(Clean);

  mmoConsole.Lines.Add(Clean);
  if mmoConsole.Lines.Count > 5000 then
    mmoConsole.Lines.Delete(0);

  if chkAutoScroll.Checked then
  begin
    mmoConsole.SelStart := Length(mmoConsole.Text);
    mmoConsole.SelLength := 0;
  end;
end;

procedure TfrmQuantize.btnBrowseSourceClick(Sender: TObject);
begin
  if FileExists(edtSourceModel.Text) then
    dlgOpenSource.InitialDir := ExtractFileDir(edtSourceModel.Text);

  if dlgOpenSource.Execute then
    SetSourceModelPath(dlgOpenSource.FileName);
end;

procedure TfrmQuantize.btnBrowseTargetClick(Sender: TObject);
begin
  if edtTargetModel.Text <> '' then
  begin
    dlgSaveTarget.InitialDir := ExtractFileDir(edtTargetModel.Text);
    dlgSaveTarget.FileName := ExtractFileName(edtTargetModel.Text);
  end;

  if dlgSaveTarget.Execute then
    edtTargetModel.Text := dlgSaveTarget.FileName;
end;

procedure TfrmQuantize.btnAutoTargetClick(Sender: TObject);
begin
  edtTargetModel.Text := BuildAutoTargetFileName(Trim(edtSourceModel.Text), GetSelectedQuantTypeStr);
end;

procedure TfrmQuantize.btnBrowseIMatrixClick(Sender: TObject);
begin
  if FileExists(edtIMatrix.Text) then
    dlgOpenIMatrix.InitialDir := ExtractFileDir(edtIMatrix.Text);

  if dlgOpenIMatrix.Execute then
    edtIMatrix.Text := dlgOpenIMatrix.FileName;
end;

procedure TfrmQuantize.edtSourceModelChange(Sender: TObject);
begin
  InspectSourceModel(Trim(edtSourceModel.Text));
end;

procedure TfrmQuantize.cmbQuantTypeChange(Sender: TObject);
begin
  btnAutoTargetClick(nil);
end;

procedure TfrmQuantize.btnStartQuantizeClick(Sender: TObject);
var
  Config: TAppConfig;
  QuantizeBin: string;
  SourceFile, TargetFile, QuantType, Args: string;
  EmptyProf: TServerProfile;
begin
  SourceFile := Trim(edtSourceModel.Text);
  TargetFile := Trim(edtTargetModel.Text);
  QuantType := GetSelectedQuantTypeStr;

  if (SourceFile = '') or not FileExists(SourceFile) then
  begin
    MessageDlg('Missing Input', 'Please select a valid source GGUF model file.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if TargetFile = '' then
  begin
    MessageDlg('Missing Output', 'Please specify an output target path for the quantized model.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Config := TAppConfig.CreateDefault;
  QuantizeBin := Config.QuantizeBinary;
  if not FileExists(QuantizeBin) then
  begin
    MessageDlg('Binary Not Found', Format('llama-quantize binary was not found at:' + sLineBreak + '%s', [QuantizeBin]), mtError, [mbOK], 0);
    Exit;
  end;

  if FileExists(TargetFile) then
  begin
    if MessageDlg('Overwrite Confirmation', Format('Destination file already exists:' + sLineBreak + '%s' + sLineBreak + 'Do you wish to overwrite it?', [TargetFile]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  Args := BuildCommandLineArgs(SourceFile, TargetFile, QuantType);
  mmoConsole.Clear;
  mmoConsole.Lines.Add(Format('=== Starting Quantization: %s -> %s (%s) ===', [ExtractFileName(SourceFile), ExtractFileName(TargetFile), QuantType]));
  mmoConsole.Lines.Add(Format('Command: "%s" %s', [QuantizeBin, Args]));
  mmoConsole.Lines.Add('--------------------------------------------------------------------------------');

  pbProgress.Position := 0;
  lblStatus.Caption := 'Status: Initializing quantization engine...';
  FStartTime := Now;

  EmptyProf := TServerProfile.CreateDefault('quantize_job', 'Quantize Job');

  FQuantizeProcessThread := TLlamaProcessThread.Create(
    QuantizeBin,
    Args,
    ExtractFileDir(TargetFile),
    EmptyProf,
    @OnProcessOutput,
    @OnProcessStateChange
  );

  SetUIState(True);
  FQuantizeProcessThread.Start;
end;

procedure TfrmQuantize.btnCancelQuantizeClick(Sender: TObject);
begin
  if Assigned(FQuantizeProcessThread) then
  begin
    lblStatus.Caption := 'Status: Stopping process...';
    FQuantizeProcessThread.RequestStop;
  end;
end;

procedure TfrmQuantize.btnOpenOutputFolderClick(Sender: TObject);
var
  TargetFile, TargetDir: string;
begin
  TargetFile := Trim(edtTargetModel.Text);
  if TargetFile <> '' then
    TargetDir := ExtractFileDir(TargetFile)
  else
    TargetDir := 'models';

  if DirectoryExists(TargetDir) then
    OpenDocument(TargetDir);
end;

procedure TfrmQuantize.btnClearConsoleClick(Sender: TObject);
begin
  mmoConsole.Clear;
end;

procedure TfrmQuantize.OnProcessOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
begin
  AppendConsoleLine(ALine, AIsStdErr);
end;

procedure TfrmQuantize.OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
var
  DurationSec: Int64;
begin
  if AState in [lpsStopped, lpsError] then
  begin
    DurationSec := SecondsBetween(Now, FStartTime);
    if AExitCode = 0 then
    begin
      pbProgress.Position := 100;
      lblStatus.Caption := Format('Status: Quantization finished in %s.', [FormatDurationSec(DurationSec)]);
      mmoConsole.Lines.Add('--------------------------------------------------------------------------------');
      mmoConsole.Lines.Add(Format('=== Quantization Finished Successfully (Elapsed: %s) ===', [FormatDurationSec(DurationSec)]));
      LogInfo('Quantization completed successfully: ' + edtTargetModel.Text, 'QUANT');
      ShowMessage(Format('Model quantized successfully!' + sLineBreak + 'Output: %s' + sLineBreak + 'Time Elapsed: %s', [
        edtTargetModel.Text, FormatDurationSec(DurationSec)
      ]));
    end
    else
    begin
      lblStatus.Caption := Format('Status: Process terminated with code %d', [AExitCode]);
      mmoConsole.Lines.Add('--------------------------------------------------------------------------------');
      mmoConsole.Lines.Add(Format('=== Quantization Terminated with Exit Code %d ===', [AExitCode]));
      LogError(Format('Quantization failed or aborted with exit code %d', [AExitCode]), 'QUANT');
    end;

    SetUIState(False);
    FQuantizeProcessThread := nil;
  end;
end;

end.