unit ufrmservercontrol;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Spin, LCLIntf, ColorSpeedButton, DateUtils, uconfigtypes,
  uchattypes, ugguftypes, uggufparser, uhardwareinfo, uprofilemanager,
  ullamaprocess, uslotmonitor, uansiparser, uformatting, ulogger;

type
  { TfrmServerControl }

  TfrmServerControl = class(TForm)
    btnClearConsole: TButton;
    btnBrowseModel: TButton;
    btnStart: TColorSpeedButton;
    btnStop: TColorSpeedButton;
    btnRestart: TColorSpeedButton;
    btnNewProfile: TButton;
    btnOpenBrowser: TButton;
    btnSaveProfile: TButton;
    chkAutoScroll: TCheckBox;
    chkContBatching: TCheckBox;
    chkFlashAttn: TCheckBox;
    chkMLock: TCheckBox;
    chkNoMMap: TCheckBox;
    cmbProfiles: TComboBox;
    dlgOpenModel: TOpenDialog;
    edtCustomArgs: TEdit;
    edtHost: TEdit;
    edtModelPath: TEdit;
    gbModel: TGroupBox;
    gbParameters: TGroupBox;
    gbProfile: TGroupBox;
    lblBatchSize: TLabel;
    lblCtxSize: TLabel;
    lblCustomArgs: TLabel;
    lblEndpoint: TLabel;
    lblGpuLayers: TLabel;
    lblHost: TLabel;
    lblModelFile: TLabel;
    lblModelFitAssessment: TLabel;
    lblParallel: TLabel;
    lblPID: TLabel;
    lblPort: TLabel;
    lblThreads: TLabel;
    lblUBatchSize: TLabel;
    lblUptime: TLabel;
    lvSlots: TListView;
    mmoConsole: TMemo;
    mmoHardwareInfo: TMemo;
    pgcRight: TPageControl;
    pnlConsoleToolbar: TPanel;
    pnlLeftConfig: TPanel;
    pnlMain: TPanel;
    pnlRightViews: TPanel;
    pnlStatusIndicator: TPanel;
    pnlTopStatus: TPanel;
    seBatchSize: TSpinEdit;
    seCtxSize: TSpinEdit;
    seGpuLayers: TSpinEdit;
    seParallel: TSpinEdit;
    sePort: TSpinEdit;
    seThreads: TSpinEdit;
    seUBatchSize: TSpinEdit;
    splMiddle: TSplitter;
    tmrStatusUpdate: TTimer;
    tsConsole: TTabSheet;
    tsHardware: TTabSheet;
    tsSlots: TTabSheet;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnRestartClick(Sender: TObject);
    procedure cmbProfilesChange(Sender: TObject);
    procedure btnSaveProfileClick(Sender: TObject);
    procedure btnNewProfileClick(Sender: TObject);
    procedure btnBrowseModelClick(Sender: TObject);
    procedure edtModelPathChange(Sender: TObject);
    procedure btnClearConsoleClick(Sender: TObject);
    procedure btnOpenBrowserClick(Sender: TObject);
    procedure tmrStatusUpdateTimer(Sender: TObject);
  private
    FServerStartTime: TDateTime;
    FIsRestarting: Boolean;
    FActiveProfileID: string;

    procedure LoadProfilesToCombo;
    procedure PopulateProfileToUI(const AProfile: TServerProfile);
    procedure SaveUIToProfile(var AProfile: TServerProfile);
    procedure EvaluateModelMemory;
    procedure RefreshHardwareOverview;
    procedure UpdateStatusUI(const AState: TLlamaProcessState);
    procedure AppendConsoleLine(const AText: string; const AIsStdErr: Boolean);

    // Callbacks
    procedure OnProcessOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
    procedure OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
    procedure OnSlotsUpdated(Sender: TObject; const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
  public
    procedure SelectModelFile(const AFilePath: string);
  end;

var
  frmServerControl: TfrmServerControl;

implementation

{$R *.lfm}

const
  COLOR_STATUS_STOPPED  = $00454545; // Dark Gray
  COLOR_STATUS_RUNNING  = $002E7D32; // Green
  COLOR_STATUS_STARTING = $00E65100; // Orange / Amber
  COLOR_STATUS_ERROR    = $00C62828; // Red

{ TfrmServerControl }

procedure TfrmServerControl.FormCreate(Sender: TObject);
begin
  FServerStartTime := 0;
  FIsRestarting := False;
  FActiveProfileID := '';

  TLlamaProcessManager.Instance.OnOutput := @OnProcessOutput;
  TLlamaProcessManager.Instance.OnStateChange := @OnProcessStateChange;
  TSlotMonitor.Instance.OnSlotsUpdated := @OnSlotsUpdated;
end;

procedure TfrmServerControl.FormDestroy(Sender: TObject);
begin
  TLlamaProcessManager.Instance.OnOutput := nil;
  TLlamaProcessManager.Instance.OnStateChange := nil;
  TSlotMonitor.Instance.OnSlotsUpdated := nil;
end;

procedure TfrmServerControl.FormShow(Sender: TObject);
begin
  LoadProfilesToCombo;
  RefreshHardwareOverview;
  UpdateStatusUI(TLlamaProcessManager.Instance.State);
  tmrStatusUpdate.Enabled := True;
end;

procedure TfrmServerControl.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  tmrStatusUpdate.Enabled := False;
  CloseAction := caHide;
end;

procedure TfrmServerControl.LoadProfilesToCombo;
var
  Profiles: TServerProfileArray;
  i, SelectedIdx: Integer;
  DefProfile: TServerProfile;
begin
  cmbProfiles.Items.BeginUpdate;
  try
    cmbProfiles.Items.Clear;
    Profiles := TProfileManager.Instance.GetAllProfiles;
    SelectedIdx := 0;

    for i := 0 to High(Profiles) do
    begin
      cmbProfiles.Items.AddObject(Profiles[i].Name, TObject(Pointer(IntPtr(i))));
      if (FActiveProfileID <> '') and SameText(Profiles[i].ID, FActiveProfileID) then
        SelectedIdx := i;
    end;

    if (FActiveProfileID = '') and (Length(Profiles) > 0) then
    begin
      DefProfile := TProfileManager.Instance.GetDefaultProfile;
      FActiveProfileID := DefProfile.ID;
      for i := 0 to High(Profiles) do
      begin
        if SameText(Profiles[i].ID, DefProfile.ID) then
        begin
          SelectedIdx := i;
          Break;
        end;
      end;
    end;

    if cmbProfiles.Items.Count > 0 then
    begin
      cmbProfiles.ItemIndex := SelectedIdx;
      cmbProfilesChange(nil);
    end;
  finally
    cmbProfiles.Items.EndUpdate;
  end;
end;

procedure TfrmServerControl.PopulateProfileToUI(const AProfile: TServerProfile);
begin
  FActiveProfileID := AProfile.ID;
  edtModelPath.Text := AProfile.ModelFile;
  seGpuLayers.Value := AProfile.NGpuLayers;
  seCtxSize.Value := AProfile.CtxSize;
  seParallel.Value := AProfile.NParallel;
  seThreads.Value := AProfile.Threads;
  seBatchSize.Value := AProfile.BatchSize;
  seUBatchSize.Value := AProfile.UBatchSize;
  edtHost.Text := AProfile.Host;
  sePort.Value := AProfile.Port;
  chkFlashAttn.Checked := AProfile.FlashAttn;
  chkContBatching.Checked := AProfile.ContBatching;
  chkNoMMap.Checked := AProfile.NoMMap;
  chkMLock.Checked := AProfile.MLock;
  edtCustomArgs.Text := AProfile.CustomArgs;

  EvaluateModelMemory;
end;

procedure TfrmServerControl.SaveUIToProfile(var AProfile: TServerProfile);
begin
  AProfile.ModelFile := Trim(edtModelPath.Text);
  AProfile.NGpuLayers := seGpuLayers.Value;
  AProfile.CtxSize := Cardinal(seCtxSize.Value);
  AProfile.NParallel := seParallel.Value;
  AProfile.Threads := seThreads.Value;
  AProfile.ThreadsBatch := seThreads.Value;
  AProfile.BatchSize := Cardinal(seBatchSize.Value);
  AProfile.UBatchSize := Cardinal(seUBatchSize.Value);
  AProfile.Host := Trim(edtHost.Text);
  AProfile.Port := Word(sePort.Value);
  AProfile.FlashAttn := chkFlashAttn.Checked;
  AProfile.ContBatching := chkContBatching.Checked;
  AProfile.NoMMap := chkNoMMap.Checked;
  AProfile.MLock := chkMLock.Checked;
  AProfile.CustomArgs := Trim(edtCustomArgs.Text);
end;

procedure TfrmServerControl.EvaluateModelMemory;
var
  ModelPath: string;
  ModelInfo: TGGUFModelInfo;
  FitResult: THardwareFitResult;
  LayerCount: Integer;
begin
  ModelPath := Trim(edtModelPath.Text);
  if (ModelPath = '') or not FileExists(ModelPath) then
  begin
    lblModelFitAssessment.Caption := 'Model Fit: Select an existing GGUF model file.';
    lblModelFitAssessment.Font.Color := clGray;
    Exit;
  end;

  ModelInfo := TGGUFParser.QuickInspect(ModelPath);
  LayerCount := ModelInfo.BlockCount;
  if LayerCount <= 0 then
    LayerCount := 33;

  FitResult := THardwareInfo.EvaluateModelFit(
    ModelInfo.FileSize,
    LayerCount,
    seCtxSize.Value,
    'f16'
  );

  lblModelFitAssessment.Caption := Format('Model Fit: [%s] %s', [FitResult.FitGrade, FitResult.Reasoning]);
  if FitResult.CanFullOffload then
    lblModelFitAssessment.Font.Color := clGreen
  else if FitResult.CanRun then
    lblModelFitAssessment.Font.Color := $00C06000 // Deep Amber
  else
    lblModelFitAssessment.Font.Color := clRed;
end;

procedure TfrmServerControl.RefreshHardwareOverview;
var
  Snap: THardwareSnapshot;
  SB: TStringBuilder;
  i: Integer;
begin
  Snap := THardwareInfo.GetSnapshot;
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('================ SYSTEM HARDWARE TELEMETRY ================');
    SB.AppendLine(Format('CPU: %s (%d Cores / %d Threads)', [Snap.CPUName, Snap.PhysicalCores, Snap.LogicalCores]));
    SB.AppendLine(Format('System RAM: Total: %s | Free: %s | Used: %s (%.1f%%)', [
      FormatBytes(Snap.TotalRAMBytes),
      FormatBytes(Snap.AvailableRAMBytes),
      FormatBytes(Snap.UsedRAMBytes),
      Snap.GetRAMUsagePercent
    ]));
    SB.AppendLine('-----------------------------------------------------------');
    SB.AppendLine(Format('Detected GPUs: %d', [Length(Snap.GPUs)]));
    for i := 0 to High(Snap.GPUs) do
    begin
      SB.AppendLine(Format(' [%d] %s (Vendor: %s)', [
        Snap.GPUs[i].Index,
        Snap.GPUs[i].Name,
        THardwareInfo.GPUVendorToString(Snap.GPUs[i].Vendor)
      ]));
      if Snap.GPUs[i].IsDedicated then
      begin
        SB.AppendLine(Format('     Dedicated VRAM: Total: %s | Free: %s', [
          FormatBytes(Snap.GPUs[i].TotalVRAMBytes),
          FormatBytes(Snap.GPUs[i].FreeVRAMBytes)
        ]));
      end
      else
        SB.AppendLine('     Architecture: Integrated / Shared Memory Graphics');
    end;
    SB.AppendLine('===========================================================');

    mmoHardwareInfo.Text := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TfrmServerControl.UpdateStatusUI(const AState: TLlamaProcessState);
var
  PID: Cardinal;
begin
  PID := TLlamaProcessManager.Instance.GetActivePID;

  case AState of
    lpsStopped:
    begin
      pnlStatusIndicator.Caption := 'STOPPED';
      pnlStatusIndicator.Color := COLOR_STATUS_STOPPED;
      btnStart.Enabled := True;
      btnStop.Enabled := False;
      btnRestart.Enabled := False;
      lblPID.Caption := 'PID: None';
      lblUptime.Caption := 'Uptime: 00:00:00';
    end;
    lpsStarting:
    begin
      pnlStatusIndicator.Caption := 'STARTING';
      pnlStatusIndicator.Color := COLOR_STATUS_STARTING;
      btnStart.Enabled := False;
      btnStop.Enabled := True;
      btnRestart.Enabled := False;
      lblPID.Caption := Format('PID: %d (Spawning)', [PID]);
    end;
    lpsRunning:
    begin
      pnlStatusIndicator.Caption := 'ONLINE';
      pnlStatusIndicator.Color := COLOR_STATUS_RUNNING;
      btnStart.Enabled := False;
      btnStop.Enabled := True;
      btnRestart.Enabled := True;
      lblPID.Caption := Format('PID: %d', [PID]);
      lblEndpoint.Caption := Format('Endpoint: http://%s:%d', [Trim(edtHost.Text), sePort.Value]);
    end;
    lpsStopping:
    begin
      pnlStatusIndicator.Caption := 'STOPPING';
      pnlStatusIndicator.Color := COLOR_STATUS_STARTING;
      btnStart.Enabled := False;
      btnStop.Enabled := False;
      btnRestart.Enabled := False;
    end;
    lpsError:
    begin
      pnlStatusIndicator.Caption := 'ERROR';
      pnlStatusIndicator.Color := COLOR_STATUS_ERROR;
      btnStart.Enabled := True;
      btnStop.Enabled := False;
      btnRestart.Enabled := False;
      lblPID.Caption := 'PID: Crashed';
    end;
  end;
end;

procedure TfrmServerControl.AppendConsoleLine(const AText: string; const AIsStdErr: Boolean);
var
  CleanText: string;
begin
  CleanText := StripAnsi(AText);
  mmoConsole.Lines.Add(CleanText);

  // Truncate console buffer if exceeding 4000 lines
  if mmoConsole.Lines.Count > 4000 then
    mmoConsole.Lines.Delete(0);

  if chkAutoScroll.Checked then
  begin
    mmoConsole.SelStart := Length(mmoConsole.Text);
    mmoConsole.SelLength := 0;
  end;
end;

procedure TfrmServerControl.btnStartClick(Sender: TObject);
var
  Config: TAppConfig;
  Profile: TServerProfile;
  ModelPath, ServerExe: string;
begin
  ModelPath := Trim(edtModelPath.Text);
  if (ModelPath = '') or not FileExists(ModelPath) then
  begin
    MessageDlg('Missing Model', 'Please select a valid .gguf model file before starting the server.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Config := TAppConfig.CreateDefault;
  ServerExe := Config.ServerBinary;
  if not FileExists(ServerExe) then
  begin
    MessageDlg('Binary Not Found', Format('llama-server binary not found at:' + sLineBreak + '%s', [ServerExe]), mtError, [mbOK], 0);
    Exit;
  end;

  if not TProfileManager.Instance.FindProfileByID(FActiveProfileID, Profile) then
    Profile := TServerProfile.CreateDefault('temp_prof', 'Active Profile');

  SaveUIToProfile(Profile);

  FServerStartTime := Now;
  mmoConsole.Lines.Add(Format('=== Starting llama-server on %s:%d ===', [Profile.Host, Profile.Port]));

  if TLlamaProcessManager.Instance.StartServer(ServerExe, Profile) then
  begin
    TSlotMonitor.Instance.StartMonitoring(Profile.Host, Profile.Port, Profile.ApiKey, 1000);
    UpdateStatusUI(lpsStarting);
  end;
end;

procedure TfrmServerControl.btnStopClick(Sender: TObject);
begin
  TSlotMonitor.Instance.StopMonitoring;
  TLlamaProcessManager.Instance.StopServer;
  UpdateStatusUI(lpsStopping);
end;

procedure TfrmServerControl.btnRestartClick(Sender: TObject);
begin
  FIsRestarting := True;
  btnStopClick(Sender);
end;

procedure TfrmServerControl.cmbProfilesChange(Sender: TObject);
var
  Profiles: TServerProfileArray;
  Idx: Integer;
begin
  Idx := cmbProfiles.ItemIndex;
  if Idx < 0 then Exit;

  Profiles := TProfileManager.Instance.GetAllProfiles;
  if (Idx >= 0) and (Idx < Length(Profiles)) then
    PopulateProfileToUI(Profiles[Idx]);
end;

procedure TfrmServerControl.btnSaveProfileClick(Sender: TObject);
var
  Profile: TServerProfile;
begin
  if TProfileManager.Instance.FindProfileByID(FActiveProfileID, Profile) then
  begin
    SaveUIToProfile(Profile);
    if TProfileManager.Instance.UpdateProfile(Profile) then
      ShowMessage('Profile updated successfully.')
    else
      MessageDlg('Error', 'Failed to save profile modifications.', mtError, [mbOK], 0);
  end;
end;

procedure TfrmServerControl.btnNewProfileClick(Sender: TObject);
var
  NewName, NewID: string;
begin
  NewName := InputBox('New Server Profile', 'Enter name for the new profile preset:', 'Custom Balanced');
  if Trim(NewName) <> '' then
  begin
    NewID := TProfileManager.Instance.DuplicateProfile(FActiveProfileID, NewName);
    if NewID <> '' then
    begin
      FActiveProfileID := NewID;
      LoadProfilesToCombo;
    end;
  end;
end;

procedure TfrmServerControl.btnBrowseModelClick(Sender: TObject);
begin
  if FileExists(edtModelPath.Text) then
    dlgOpenModel.InitialDir := ExtractFileDir(edtModelPath.Text);

  if dlgOpenModel.Execute then
    SelectModelFile(dlgOpenModel.FileName);
end;

procedure TfrmServerControl.SelectModelFile(const AFilePath: string);
begin
  edtModelPath.Text := AFilePath;
  EvaluateModelMemory;
end;

procedure TfrmServerControl.edtModelPathChange(Sender: TObject);
begin
  EvaluateModelMemory;
end;

procedure TfrmServerControl.btnClearConsoleClick(Sender: TObject);
begin
  mmoConsole.Clear;
end;

procedure TfrmServerControl.btnOpenBrowserClick(Sender: TObject);
var
  Url: string;
begin
  Url := Format('http://%s:%d', [Trim(edtHost.Text), sePort.Value]);
  OpenURL(Url);
end;

procedure TfrmServerControl.tmrStatusUpdateTimer(Sender: TObject);
var
  UptimeSec: Int64;
begin
  if TLlamaProcessManager.Instance.IsRunning and (FServerStartTime > 0) then
  begin
    UptimeSec := SecondsBetween(Now, FServerStartTime);
    lblUptime.Caption := 'Uptime: ' + FormatDurationSec(UptimeSec);
  end;
end;

procedure TfrmServerControl.OnProcessOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
begin
  AppendConsoleLine(ALine, AIsStdErr);
end;

procedure TfrmServerControl.OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
begin
  UpdateStatusUI(AState);

  if (AState = lpsStopped) and FIsRestarting then
  begin
    FIsRestarting := False;
    btnStartClick(nil);
  end;
end;

procedure TfrmServerControl.OnSlotsUpdated(Sender: TObject; const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
var
  i: Integer;
  Item: TListItem;
begin
  lvSlots.Items.BeginUpdate;
  try
    lvSlots.Items.Clear;
    for i := 0 to High(ASlots) do
    begin
      Item := lvSlots.Items.Add;
      Item.Caption := Format('Slot #%d', [ASlots[i].ID]);
      
      if ASlots[i].TaskID >= 0 then
        Item.SubItems.Add(IntToStr(ASlots[i].TaskID))
      else
        Item.SubItems.Add('-');

      Item.SubItems.Add(SlotStateToString(ASlots[i].State));
      Item.SubItems.Add(FormatTokenSpeed(ASlots[i].TokensPerSecond));
      Item.SubItems.Add(IntToStr(ASlots[i].PromptTokens));
      Item.SubItems.Add(IntToStr(ASlots[i].GeneratedTokens));
      Item.SubItems.Add(Format('%.1f%%', [ASlots[i].ProgressPercent]));
    end;
  finally
    lvSlots.Items.EndUpdate;
  end;
end;

end.