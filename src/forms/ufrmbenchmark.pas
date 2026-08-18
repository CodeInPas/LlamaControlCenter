unit ufrmbenchmark;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Spin, LCLIntf, ColorSpeedButton, DateUtils, fpjson, jsonparser,
  uconfigtypes, ujsonhelper, ugguftypes, uggufparser, uhardwareinfo,
  ullamaprocess, uansiparser, uformatting, ulogger;

type
  { Parsed Benchmark Entry Record }
  TBenchmarkRow = record
    ModelName: string;
    Parameters: string;
    Backend: string;
    Threads: string;
    GpuLayers: string;
    TestType: string;
    TokensPerSec: Double;
    TokensPerSecStdDev: Double;
    RawDetails: string;
  end;
  TBenchmarkRowArray = array of TBenchmarkRow;

  { TfrmBenchmark Form }
  TfrmBenchmark = class(TForm)
    btnBrowseModel: TButton;
    btnClearLog: TButton;
    btnExportCSV1: TColorSpeedButton;
    btnRunBench: TColorSpeedButton;
    btnCancelBench: TColorSpeedButton;
    chkAutoScroll: TCheckBox;
    chkFlashAttn: TCheckBox;
    chkNoMMap: TCheckBox;
    dlgOpenModel: TOpenDialog;
    dlgSaveCSV: TSaveDialog;
    edtBatchSizes: TEdit;
    edtExtraArgs: TEdit;
    edtGenTokens: TEdit;
    edtGpuLayers: TEdit;
    edtModelPath: TEdit;
    edtPromptTokens: TEdit;
    edtThreads: TEdit;
    edtUBatchSizes: TEdit;
    gbBenchParams: TGroupBox;
    gbModelSelection: TGroupBox;
    lblBatchSizes: TLabel;
    lblExtraArgs: TLabel;
    lblGenTokens: TLabel;
    lblGpuLayers: TLabel;
    lblModelInfo: TLabel;
    lblModelPath: TLabel;
    lblPromptTokens: TLabel;
    lblReps: TLabel;
    lblStatus: TLabel;
    lblThreads: TLabel;
    lblUBatchSizes: TLabel;
    lvResults: TListView;
    mmoConsole: TMemo;
    mmoSummary: TMemo;
    Panel1: TPanel;
    pbBench: TProgressBar;
    pgcResults: TPageControl;
    pnlActions: TPanel;
    pnlConsoleToolbar: TPanel;
    pnlMainView: TPanel;
    pnlTop: TPanel;
    seReps: TSpinEdit;
    tsConsole: TTabSheet;
    tsSummary: TTabSheet;
    tsTable: TTabSheet;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnBrowseModelClick(Sender: TObject);
    procedure edtModelPathChange(Sender: TObject);
    procedure btnRunBenchClick(Sender: TObject);
    procedure btnCancelBenchClick(Sender: TObject);
    procedure btnExportCSVClick(Sender: TObject);
    procedure btnClearLogClick(Sender: TObject);
  private
    FBenchProcessThread: TLlamaProcessThread;
    FIsRunning: Boolean;
    FStartTime: TDateTime;
    FParsedRows: TBenchmarkRowArray;

    procedure InspectModel(const APath: string);
    function BuildCommandLineArgs(const AModelPath: string): string;
    procedure SetUIState(const AIsRunningBench: Boolean);
    procedure AppendConsoleLine(const AText: string; const AIsStdErr: Boolean);
    procedure ParseBenchOutputLine(const ALine: string);
    procedure GeneratePerformanceSummary;
    procedure ClearResults;
    function ResolveBenchBinaryPath: string;

    // Worker Callbacks
    procedure OnProcessOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
    procedure OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
  public
    procedure SetModelPath(const APath: string);
  end;

var
  frmBenchmark: TfrmBenchmark;

implementation

{$R *.lfm}

{ TfrmBenchmark }

procedure TfrmBenchmark.FormCreate(Sender: TObject);
begin
  FBenchProcessThread := nil;
  FIsRunning := False;
  FStartTime := 0;
  SetLength(FParsedRows, 0);

  edtThreads.Text := Format('%d, %d', [GetCPUCount div 2, GetCPUCount]);
end;

procedure TfrmBenchmark.FormDestroy(Sender: TObject);
begin
  if Assigned(FBenchProcessThread) then
  begin
    FBenchProcessThread.RequestStop;
    FBenchProcessThread.WaitFor;
    FreeAndNil(FBenchProcessThread);
  end;
  SetLength(FParsedRows, 0);
end;

procedure TfrmBenchmark.FormShow(Sender: TObject);
begin
  SetUIState(FIsRunning);
end;

procedure TfrmBenchmark.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if FIsRunning then
  begin
    if MessageDlg('Benchmark in Progress',
      'A benchmark suite is currently running. Do you wish to terminate the benchmark?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      btnCancelBenchClick(nil);
      CloseAction := caHide;
    end
    else
      CloseAction := caNone;
  end
  else
    CloseAction := caHide;
end;

procedure TfrmBenchmark.InspectModel(const APath: string);
var
  Info: TGGUFModelInfo;
begin
  if not FileExists(APath) then
  begin
    lblModelInfo.Caption := 'Model: Select an existing GGUF model file.';
    lblModelInfo.Font.Color := clGray;
    Exit;
  end;

  Info := TGGUFParser.QuickInspect(APath);
  lblModelInfo.Caption := Format('Model: %s | Architecture: %s | Params: %s | Quant: %s | Size: %s', [
    Info.ModelName,
    Info.Architecture,
    FormatParameterCount(Info.TotalParameters),
    Info.QuantizationType,
    FormatBytes(Info.FileSize)
  ]);
  lblModelInfo.Font.Color := clNavy;
end;

procedure TfrmBenchmark.SetModelPath(const APath: string);
begin
  edtModelPath.Text := APath;
  InspectModel(APath);
end;

procedure TfrmBenchmark.ClearResults;
begin
  SetLength(FParsedRows, 0);
  lvResults.Items.Clear;
  mmoSummary.Clear;
  pbBench.Position := 0;
end;

function TfrmBenchmark.ResolveBenchBinaryPath: string;
var
  ConfigPath, AppDir, TargetPath, ServerBinDir: string;
  RootData, SectionData: TJSONData;
  SecObj: TJSONObject;
begin
  Result := '';
  AppDir := ExtractFilePath(Application.ExeName);
  ConfigPath := AppDir + 'config' + PathDelim + 'app_settings.json';

  if FileExists(ConfigPath) then
  begin
    RootData := LoadJSONFile(ConfigPath);
    if Assigned(RootData) and (RootData is TJSONObject) then
    begin
      try
        SectionData := TJSONObject(RootData).Find('paths');
        if Assigned(SectionData) and (SectionData is TJSONObject) then
        begin
          SecObj := TJSONObject(SectionData);
          TargetPath := GetJSONString(SecObj, 'bench_binary', '');

          if (TargetPath <> '') and FileExists(TargetPath) then
            Exit(TargetPath);

          if (TargetPath <> '') and FileExists(AppDir + TargetPath) then
            Exit(AppDir + TargetPath);

          TargetPath := GetJSONString(SecObj, 'server_binary', '');
          if TargetPath <> '' then
          begin
            ServerBinDir := ExtractFileDir(TargetPath);
            if FileExists(ServerBinDir + PathDelim + 'llama-bench.exe') then
              Exit(ServerBinDir + PathDelim + 'llama-bench.exe');
          end;
        end;
      finally
        RootData.Free;
      end;
    end;
  end;

  if FileExists(AppDir + 'bin' + PathDelim + 'engine' + PathDelim + 'llama-bench.exe') then
    Exit(AppDir + 'bin' + PathDelim + 'engine' + PathDelim + 'llama-bench.exe');

  if FileExists(AppDir + 'bin' + PathDelim + 'llama-bin' + PathDelim + 'llama-bench.exe') then
    Exit(AppDir + 'bin' + PathDelim + 'llama-bin' + PathDelim + 'llama-bench.exe');

  if FileExists(AppDir + 'llama-bench.exe') then
    Exit(AppDir + 'llama-bench.exe');
end;

function TfrmBenchmark.BuildCommandLineArgs(const AModelPath: string): string;
var
  Args: TStringList;
  i : integer;
  procedure AddSanitizedListParam(const AFlag, ARawInput: string);
  var
    Clean: string;
  begin
    Clean := StringReplace(Trim(ARawInput), ' ', '', [rfReplaceAll]);
    if Clean <> '' then
      Args.Add(AFlag + ' ' + Clean);
  end;

begin
  Args := TStringList.Create;
  try
    // Model Path (Gunakan 1 pasang tanda kutip standar)
    Args.Add('-m');
    Args.Add('"' + Trim(AModelPath) + '"');

    // Matrix Parameters
    AddSanitizedListParam('-p', edtPromptTokens.Text);
    AddSanitizedListParam('-n', edtGenTokens.Text);
    AddSanitizedListParam('-ngl', edtGpuLayers.Text);
    AddSanitizedListParam('-t', edtThreads.Text);
    AddSanitizedListParam('-b', edtBatchSizes.Text);
    AddSanitizedListParam('-ub', edtUBatchSizes.Text);

    // Repetitions
    Args.Add('-r ' + IntToStr(seReps.Value));

    // Flash Attention: Gunakan 'on' atau 'off' sesuai spesifikasi llama-bench
    if chkFlashAttn.Checked then
      Args.Add('-fa on')
    else
      Args.Add('-fa off');

    // MMAP: Gunakan flag -mmp 0 jika chkNoMMap dicentang
    if chkNoMMap.Checked then
      Args.Add('-mmp 0')
    else
      Args.Add('-mmp 1');

    // Output Markdown Table
    Args.Add('-o md');

    // Parameter Tambahan Opsional
    if Trim(edtExtraArgs.Text) <> '' then
      Args.Add(Trim(edtExtraArgs.Text));

    // Gabungkan dengan spasi biasa tanpa pembungkusan delimiter otomatis
    Result := '';
    for  i := 0 to Args.Count - 1 do
    begin
      if Result <> '' then Result := Result + ' ';
      Result := Result + Args[i];
    end;
  finally
    Args.Free;
  end;
end;

procedure TfrmBenchmark.SetUIState(const AIsRunningBench: Boolean);
begin
  FIsRunning := AIsRunningBench;
  btnRunBench.Enabled := not AIsRunningBench;
  btnCancelBench.Enabled := AIsRunningBench;
  btnBrowseModel.Enabled := not AIsRunningBench;

  edtModelPath.ReadOnly := AIsRunningBench;
  edtPromptTokens.ReadOnly := AIsRunningBench;
  edtGenTokens.ReadOnly := AIsRunningBench;
  edtGpuLayers.ReadOnly := AIsRunningBench;
  edtThreads.ReadOnly := AIsRunningBench;
  seReps.Enabled := not AIsRunningBench;
  edtBatchSizes.ReadOnly := AIsRunningBench;
  edtUBatchSizes.ReadOnly := AIsRunningBench;
  chkFlashAttn.Enabled := not AIsRunningBench;
  chkNoMMap.Enabled := not AIsRunningBench;
  edtExtraArgs.ReadOnly := AIsRunningBench;

  if not AIsRunningBench then
  begin
    if pbBench.Position >= 100 then
      lblStatus.Caption := 'Status: Benchmark completed.'
    else
      lblStatus.Caption := 'Status: Ready for benchmarking';
  end;
end;

procedure TfrmBenchmark.ParseBenchOutputLine(const ALine: string);
var
  CleanLine: string;
  RawCols: TStringArray;
  Cols: array of string;
  Row: TBenchmarkRow;
  Item: TListItem;
  TestStr, SpeedStr, StdDevStr: string;
  PosPlusMinus, i, ValCount: Integer;
  SpeedVal, StdDevVal: Double;
  FmtSettings: TFormatSettings;
begin
  CleanLine := Trim(ALine);

  // Validasi baris tabel Markdown
  if (Length(CleanLine) < 5) or (CleanLine[1] <> '|') or (Pos('---', CleanLine) > 0) then Exit;

  // Format angka standar (menggunakan titik desimal)
  FmtSettings := DefaultFormatSettings;
  FmtSettings.DecimalSeparator := '.';

  RawCols := CleanLine.Split(['|']);
  SetLength(Cols, 0);

  // Ambil kolom yang tidak kosong
  for i := 0 to High(RawCols) do
  begin
    if Trim(RawCols[i]) <> '' then
    begin
      SetLength(Cols, Length(Cols) + 1);
      Cols[High(Cols)] := Trim(RawCols[i]);
    end;
  end;

  ValCount := Length(Cols);
  if ValCount < 5 then Exit;

  // Abaikan baris header
  if SameText(Cols[0], 'model') or SameText(Cols[0], 'build') or SameText(Cols[0], 'commit') then
    Exit;

  FillChar(Row, SizeOf(Row), 0);
  Row.ModelName := Cols[0];
  Row.Parameters := Cols[1];
  Row.Backend := Cols[2];
  Row.GpuLayers := edtGpuLayers.Text;

  // Deteksi tata letak kolom secara adaptif
  if ValCount >= 7 then
  begin
    // Format standar modern: model | size/params | backend | ngl | threads | test | t/s
    Row.Threads := Cols[ValCount - 3];
    TestStr := Cols[ValCount - 2];
    SpeedStr := Cols[ValCount - 1];
  end
  else
  begin
    // Format ringkas: model | params | backend | threads | test | t/s
    Row.Threads := Cols[3];
    TestStr := Cols[4];
    SpeedStr := Cols[ValCount - 1];
  end;

  // Parsing kecepatan & standar deviasi
  PosPlusMinus := Pos('±', SpeedStr);
  if PosPlusMinus = 0 then
    PosPlusMinus := Pos('+/-', SpeedStr);

  if PosPlusMinus > 0 then
  begin
    StdDevStr := Trim(Copy(SpeedStr, PosPlusMinus + 3, Length(SpeedStr)));
    SpeedStr := Trim(Copy(SpeedStr, 1, PosPlusMinus - 1));
  end
  else
    StdDevStr := '0.0';

  // Normalisasi pemisah desimal
  SpeedStr := StringReplace(SpeedStr, ',', '.', [rfReplaceAll]);
  StdDevStr := StringReplace(StdDevStr, ',', '.', [rfReplaceAll]);

  SpeedVal := StrToFloatDef(SpeedStr, 0.0, FmtSettings);
  StdDevVal := StrToFloatDef(StdDevStr, 0.0, FmtSettings);

  Row.TestType := TestStr;
  Row.TokensPerSec := SpeedVal;
  Row.TokensPerSecStdDev := StdDevVal;
  Row.RawDetails := CleanLine;

  SetLength(FParsedRows, Length(FParsedRows) + 1);
  FParsedRows[High(FParsedRows)] := Row;

  // Tambahkan baris baru ke ListView GUI
  Item := lvResults.Items.Add;
  Item.Caption := Row.ModelName;
  Item.SubItems.Add(Row.Parameters);
  Item.SubItems.Add(Row.Backend);
  Item.SubItems.Add(Row.Threads);
  Item.SubItems.Add(Row.GpuLayers);

  if (Pos('pp', LowerCase(TestStr)) > 0) or (Pos('prompt', LowerCase(TestStr)) > 0) then
  begin
    Item.SubItems.Add(TestStr);
    Item.SubItems.Add(Format('%.2f ± %.2f', [SpeedVal, StdDevVal], FmtSettings));
    Item.SubItems.Add('-');
    Item.SubItems.Add('-');
  end
  else
  begin
    Item.SubItems.Add('-');
    Item.SubItems.Add('-');
    Item.SubItems.Add(TestStr);
    Item.SubItems.Add(Format('%.2f ± %.2f', [SpeedVal, StdDevVal], FmtSettings));
  end;

  Item.SubItems.Add(FormatSpeed(SpeedVal));
end;

procedure TfrmBenchmark.GeneratePerformanceSummary;
var
  SB: TStringBuilder;
  i: Integer;
  MaxPP, MaxTG, MinPP, MinTG: Double;
  BestPPConfig, BestTGConfig: string;
begin
  if Length(FParsedRows) = 0 then Exit;

  MaxPP := 0.0;
  MaxTG := 0.0;
  MinPP := 999999.0;
  MinTG := 999999.0;
  BestPPConfig := 'N/A';
  BestTGConfig := 'N/A';

  for i := 0 to High(FParsedRows) do
  begin
    if (Pos('pp', LowerCase(FParsedRows[i].TestType)) > 0) or (Pos('prompt', LowerCase(FParsedRows[i].TestType)) > 0) then
    begin
      if FParsedRows[i].TokensPerSec > MaxPP then
      begin
        MaxPP := FParsedRows[i].TokensPerSec;
        BestPPConfig := Format('%s (Backend: %s, Threads: %s, Test: %s)', [
          FParsedRows[i].ModelName, FParsedRows[i].Backend, FParsedRows[i].Threads, FParsedRows[i].TestType
        ]);
      end;
      if (FParsedRows[i].TokensPerSec > 0.001) and (FParsedRows[i].TokensPerSec < MinPP) then
        MinPP := FParsedRows[i].TokensPerSec;
    end
    else
    begin
      if FParsedRows[i].TokensPerSec > MaxTG then
      begin
        MaxTG := FParsedRows[i].TokensPerSec;
        BestTGConfig := Format('%s (Backend: %s, Threads: %s, Test: %s)', [
          FParsedRows[i].ModelName, FParsedRows[i].Backend, FParsedRows[i].Threads, FParsedRows[i].TestType
        ]);
      end;
      if (FParsedRows[i].TokensPerSec > 0.001) and (FParsedRows[i].TokensPerSec < MinTG) then
        MinTG := FParsedRows[i].TokensPerSec;
    end;
  end;

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('================ BENCHMARK PERFORMANCE REPORT ================');
    SB.AppendLine(Format('Model:       %s', [ExtractFileName(edtModelPath.Text)]));
    SB.AppendLine(Format('Tests Run:   %d benchmark sample matrix executions', [Length(FParsedRows)]));
    SB.AppendLine(Format('Total Time:  %s', [FormatDurationSec(SecondsBetween(Now, FStartTime))]));
    SB.AppendLine('--------------------------------------------------------------');
    SB.AppendLine('1. PROMPT PROCESSING / PREFILL SPEED (PP):');
    SB.AppendLine(Format('   Peak Throughput:    %.2f tokens/sec', [MaxPP]));
    SB.AppendLine(Format('   Fastest Setting:    %s', [BestPPConfig]));
    if MinPP < 999999.0 then
      SB.AppendLine(Format('   Baseline / Lowest:  %.2f tokens/sec', [MinPP]));
    SB.AppendLine('');
    SB.AppendLine('2. TEXT GENERATION / DECODING SPEED (TG):');
    SB.AppendLine(Format('   Peak Throughput:    %.2f tokens/sec', [MaxTG]));
    SB.AppendLine(Format('   Fastest Setting:    %s', [BestTGConfig]));
    if MinTG < 999999.0 then
      SB.AppendLine(Format('   Baseline / Lowest:  %.2f tokens/sec', [MinTG]));
    SB.AppendLine('==============================================================');

    mmoSummary.Text := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TfrmBenchmark.AppendConsoleLine(const AText: string; const AIsStdErr: Boolean);
var
  Clean: string;
begin
  Clean := StripAnsi(AText);
  ParseBenchOutputLine(Clean);

  mmoConsole.Lines.Add(Clean);
  if mmoConsole.Lines.Count > 5000 then
    mmoConsole.Lines.Delete(0);

  if chkAutoScroll.Checked then
  begin
    mmoConsole.SelStart := Length(mmoConsole.Text);
    mmoConsole.SelLength := 0;
  end;
end;

procedure TfrmBenchmark.btnBrowseModelClick(Sender: TObject);
begin
  if FileExists(edtModelPath.Text) then
    dlgOpenModel.InitialDir := ExtractFileDir(edtModelPath.Text);

  if dlgOpenModel.Execute then
    SetModelPath(dlgOpenModel.FileName);
end;

procedure TfrmBenchmark.edtModelPathChange(Sender: TObject);
begin
  InspectModel(Trim(edtModelPath.Text));
end;

procedure TfrmBenchmark.btnRunBenchClick(Sender: TObject);
var
  BenchBin, ModelFile, Args: string;
  EmptyProf: TServerProfile;
begin
  ModelFile := Trim(edtModelPath.Text);
  if (ModelFile = '') or not FileExists(ModelFile) then
  begin
    MessageDlg('Missing Model', 'Please select a valid GGUF model file before running benchmark.', mtWarning, [mbOK], 0);
    Exit;
  end;

  BenchBin := ResolveBenchBinaryPath;
  if (BenchBin = '') or not FileExists(BenchBin) then
  begin
    MessageDlg('Binary Not Found',
      'llama-bench binary was not found.' + sLineBreak +
      'Please configure the correct executable path in Settings -> Paths & Binaries.',
      mtError, [mbOK], 0);
    Exit;
  end;

  ClearResults;
  Args := BuildCommandLineArgs(ModelFile);

  mmoConsole.Lines.Add(Format('=== Starting Benchmark Suite for %s ===', [ExtractFileName(ModelFile)]));
  mmoConsole.Lines.Add(Format('Command: "%s" %s', [BenchBin, Args]));
  mmoConsole.Lines.Add('--------------------------------------------------------------------------------');

  lblStatus.Caption := 'Status: Benchmarking in progress...';
  pbBench.Style := pbstMarquee;
  FStartTime := Now;

  EmptyProf := TServerProfile.CreateDefault('bench_job', 'Benchmark Task');

  FBenchProcessThread := TLlamaProcessThread.Create(
    BenchBin,
    Args,
    ExtractFileDir(ModelFile),
    EmptyProf,
    @OnProcessOutput,
    @OnProcessStateChange
  );

  SetUIState(True);
  FBenchProcessThread.Start;
end;

procedure TfrmBenchmark.btnCancelBenchClick(Sender: TObject);
begin
  if Assigned(FBenchProcessThread) then
  begin
    lblStatus.Caption := 'Status: Canceling benchmark...';
    FBenchProcessThread.RequestStop;
  end;
end;

procedure TfrmBenchmark.btnExportCSVClick(Sender: TObject);
var
  CSV: TStringList;
  i, j: Integer;
  Line: string;
  Item: TListItem;
begin
  if lvResults.Items.Count = 0 then
  begin
    MessageDlg('No Data', 'There are no benchmark results to export.', mtInformation, [mbOK], 0);
    Exit;
  end;

  dlgSaveCSV.FileName := 'benchmark_results_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.csv';
  if dlgSaveCSV.Execute then
  begin
    CSV := TStringList.Create;
    try
      Line := 'Model,Parameters,Backend,Threads,NGL,Prompt_Test,Prompt_Speed_tps,Gen_Test,Gen_Speed_tps,Formatted_Speed';
      CSV.Add(Line);

      for i := 0 to lvResults.Items.Count - 1 do
      begin
        Item := lvResults.Items[i];
        Line := '"' + Item.Caption + '"';
        for j := 0 to Item.SubItems.Count - 1 do
          Line := Line + ',"' + Item.SubItems[j] + '"';
        CSV.Add(Line);
      end;

      CSV.SaveToFile(dlgSaveCSV.FileName);
      LogInfo('Exported benchmark CSV: ' + dlgSaveCSV.FileName, 'BENCH');
      ShowMessage('Benchmark results successfully exported to:' + sLineBreak + dlgSaveCSV.FileName);
    finally
      CSV.Free;
    end;
  end;
end;

procedure TfrmBenchmark.btnClearLogClick(Sender: TObject);
begin
  mmoConsole.Clear;
end;

procedure TfrmBenchmark.OnProcessOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
begin
  AppendConsoleLine(ALine, AIsStdErr);
end;

procedure TfrmBenchmark.OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
var
  DurationSec: Int64;
begin
  if AState in [lpsStopped, lpsError] then
  begin
    DurationSec := SecondsBetween(Now, FStartTime);
    pbBench.Style := pbstNormal;

    if AExitCode = 0 then
    begin
      pbBench.Position := 100;
      lblStatus.Caption := Format('Status: Benchmark completed in %s.', [FormatDurationSec(DurationSec)]);
      mmoConsole.Lines.Add('--------------------------------------------------------------------------------');
      mmoConsole.Lines.Add(Format('=== Benchmark Completed Successfully (Elapsed: %s) ===', [FormatDurationSec(DurationSec)]));
      LogInfo('Benchmark completed successfully in ' + FormatDurationSec(DurationSec), 'BENCH');
      GeneratePerformanceSummary;
      pgcResults.ActivePage := tsTable; // Otomatis aktifkan tab tabel hasil
    end
    else
    begin
      lblStatus.Caption := Format('Status: Terminated with code %d', [AExitCode]);
      mmoConsole.Lines.Add('--------------------------------------------------------------------------------');
      mmoConsole.Lines.Add(Format('=== Benchmark Terminated (Exit Code %d) ===', [AExitCode]));
      LogError(Format('Benchmark failed or interrupted with exit code %d', [AExitCode]), 'BENCH');
    end;

    SetUIState(False);
    FBenchProcessThread := nil;
  end;
end;

end.
