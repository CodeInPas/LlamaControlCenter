unit ufrmmain;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch anonymousmethods}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, LCLIntf, Buttons, ColorSpeedButton, DateUtils, process,
  uconfigtypes, uchattypes, uhardwareinfo, uprofilemanager, ullamaprocess,
  uslotmonitor, uansiparser, uformatting, ulogger, ufrmsettings,
  ufrmservercontrol, ufrmmodelhub, ufrmdownloader, ufrmquantize, ufrmbenchmark,
  ufrmplayground, usmoothbutton,fpjson,jsonparser,ujsonhelper;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    btnClearLogs: TButton;
    btnNavSettings: TColorSpeedButton;

    btnNavQuantize: TColorSpeedButton;
    btnNavPlayground: TColorSpeedButton;
    btnNavDownloader: TColorSpeedButton;
    btnNavModelHub: TColorSpeedButton;
    btnNavBench: TColorSpeedButton;


    btnOpenLogsFolder: TButton;
    btnOpenWebUI: TButton;
    btnQuickRestart: TButton;
    btnQuickStart: TButton;
    btnQuickStop: TButton;
    chkLogAutoScroll: TCheckBox;
    cmbLogLevelFilter: TComboBox;
    btnNavServer: TColorSpeedButton;
    gbHardwareOverview: TGroupBox;
    gbInferenceOverview: TGroupBox;
    gbLogViewer: TGroupBox;
    gbServerOverview: TGroupBox;
    lblCPUName: TLabel;
    lblFilterLevel: TLabel;
    lblGPUName: TLabel;
    lblMainEndpoint: TLabel;
    lblMainModel: TLabel;
    lblMainPID: TLabel;
    lblMainUptime: TLabel;
    lblPromptProcessingSpeed: TLabel;
    lblRAMUsage: TLabel;
    lblSlotCount: TLabel;
    lblThroughput: TLabel;
    lblTotalTokensProcessed: TLabel;
    lblVRAMUsage: TLabel;
    mmoMainLog: TMemo;
    mnuFile: TMenuItem;
    mnuFileExit: TMenuItem;
    mnuFileSep1: TMenuItem;
    mnuFileSettings: TMenuItem;
    mnuHelp: TMenuItem;
    mnuHelpAbout: TMenuItem;
    mnuHelpDocs: TMenuItem;
    mnuHelpSep1: TMenuItem;
    mnuMain: TMainMenu;
    mnuServer: TMenuItem;
    mnuServerRestart: TMenuItem;
    mnuServerSep1: TMenuItem;
    mnuServerStart: TMenuItem;
    mnuServerStop: TMenuItem;
    mnuServerWebUI: TMenuItem;
    mnuTools: TMenuItem;
    mnuToolsBench: TMenuItem;
    mnuToolsDownloader: TMenuItem;
    mnuToolsModelHub: TMenuItem;
    mnuToolsPlayground: TMenuItem;
    mnuToolsQuantize: TMenuItem;
    mnuToolsServerControl: TMenuItem;
    mnuTrayExit: TMenuItem;
    mnuTraySep1: TMenuItem;
    mnuTrayShow: TMenuItem;
    mnuTrayStartStop: TMenuItem;
    pbRAM: TProgressBar;
    pbVRAM: TProgressBar;
    pnlCardsTop: TPanel;
    pnlClientArea: TPanel;
    pnlLogToolbar: TPanel;
    pnlNavigation: TPanel;
    pnlStateBadge: TPanel;
    popTray: TPopupMenu;
    ProcKILL: TProcess;
    statMain: TStatusBar;
    tmrTelemetry: TTimer;
    trayMain: TTrayIcon;

    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnNavServerClick(Sender: TObject);
    procedure btnNavModelHubClick(Sender: TObject);
    procedure btnNavPlaygroundClick(Sender: TObject);
    procedure btnNavDownloaderClick(Sender: TObject);
    procedure btnNavQuantizeClick(Sender: TObject);
    procedure btnNavBenchClick(Sender: TObject);
    procedure btnNavSettingsClick(Sender: TObject);
    procedure btnQuickStartClick(Sender: TObject);
    procedure btnQuickStopClick(Sender: TObject);
    procedure btnQuickRestartClick(Sender: TObject);
    procedure btnOpenWebUIClick(Sender: TObject);
    procedure cmbLogLevelFilterChange(Sender: TObject);
    procedure btnClearLogsClick(Sender: TObject);
    procedure btnOpenLogsFolderClick(Sender: TObject);
    procedure mnuFileSettingsClick(Sender: TObject);
    procedure mnuFileExitClick(Sender: TObject);
    procedure mnuHelpDocsClick(Sender: TObject);
    procedure mnuHelpAboutClick(Sender: TObject);
    procedure tmrTelemetryTimer(Sender: TObject);
    procedure trayMainClick(Sender: TObject);
    procedure mnuTrayShowClick(Sender: TObject);
  private
    FAppConfig: TAppConfig;
    FConfigFilePath: string;
    FServerStartTime: TDateTime;
    FAllowAppClose: Boolean;
    FIsRestarting: Boolean;
    FLogHistory: array of TLogEntry;

    FNavBtnServer: TSmoothNavButton;
    FNavBtnHub: TSmoothNavButton;
    FNavBtnPlayground: TSmoothNavButton;
    FNavBtnDownloader: TSmoothNavButton;
    FNavBtnQuantize: TSmoothNavButton;
    FNavBtnBench: TSmoothNavButton;
    FNavBtnSetting :TSmoothNavButton;
    FPendingState: TLlamaProcessState;
    procedure LoadConfiguration;
    procedure ApplyAppConfig;
    procedure EnsureChildFormsCreated;
    procedure UpdateServerStatusUI(const AState: TLlamaProcessState);
    procedure UpdateHardwareTelemetry;
    procedure UpdateSlotTelemetry(const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
    procedure AppendLogEntry(const AEntry: TLogEntry);
    function FormatLogLine(const AEntry: TLogEntry): string;
    procedure ShowTrayNotification(const ATitle, AMsg: string);
    function ResolveServerBinaryPath: string;
    procedure InitSmoothNavigation;
    procedure SetActiveNavButton(AActiveBtn: TSmoothNavButton);
    procedure OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
    procedure DoUpdateStatusAsync;
    // Event Dispatchers
    procedure OnLogEntryReceived(const ATimestamp: TDateTime; const ALevel: TLogLevel; const ATag: string; const AMessage: string);
    procedure OnSlotsUpdated(Sender: TObject; const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
  public
    property AppConfig: TAppConfig read FAppConfig;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

const
  COLOR_STATUS_STOPPED  = $00454545; // Dark Gray
  COLOR_STATUS_RUNNING  = $002E7D32; // Green
  COLOR_STATUS_STARTING = $00E65100; // Deep Orange / Amber
  COLOR_STATUS_ERROR    = $00C62828; // Red

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FConfigFilePath := 'config' + PathDelim + 'app_settings.json';
  FServerStartTime := 0;
  FAllowAppClose := False;
  FIsRestarting := False;
  SetLength(FLogHistory, 0);
  //InitSmoothNavigation;
  // Inisialisasi konfigurasi
  LoadConfiguration;
  ApplyAppConfig;

  // Sambungkan event listener
  TLogger.Instance.OnLog := @OnLogEntryReceived;
  TLlamaProcessManager.Instance.OnStateChange := @OnProcessStateChange;
  UpdateServerStatusUI(TLlamaProcessManager.Instance.State);
  TSlotMonitor.Instance.OnSlotsUpdated := @OnSlotsUpdated;

  EnsureChildFormsCreated;
  LogInfo('Llama Control Center initialized successfully.', 'SYSTEM');


  // Sinkronkan status UI awal saat aplikasi dibuka


  WindowState:=wsMaximized;
end;

procedure TfrmMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  TLlamaProcessManager.Instance.StopServer;
  ProcKILL.Execute;
  Sleep(1000);
  Application.Terminate;

end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  tmrTelemetry.Enabled := False;

  TLogger.Instance.OnLog := nil;
  TLlamaProcessManager.Instance.OnStateChange := nil;
  TSlotMonitor.Instance.OnSlotsUpdated := nil;

  TSlotMonitor.Instance.StopMonitoring;
  TLlamaProcessManager.Instance.StopServer;
  SetLength(FLogHistory, 0);
end;

procedure TfrmMain.ShowTrayNotification(const ATitle, AMsg: string);
begin
  trayMain.BalloonTitle := ATitle;
  trayMain.BalloonHint := AMsg;
  trayMain.BalloonFlags := bfInfo;
  trayMain.ShowBalloonHint;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  UpdateHardwareTelemetry;
  UpdateServerStatusUI(TLlamaProcessManager.Instance.State);
  tmrTelemetry.Enabled := True;

  if FAppConfig.StartMinimizedToTray then
  begin
    Hide;
    ShowTrayNotification('Llama Control Center', 'Running minimized in system tray.');
  end;

  if FAppConfig.AutoStartOnLaunch and not TLlamaProcessManager.Instance.IsRunning then
    btnQuickStartClick(nil);
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if not FAllowAppClose and FAppConfig.MinimizeToTrayOnClose then
  begin
    CanClose := False;
    Hide;
    ShowTrayNotification('Llama Control Center', 'Application minimized to system tray.');
  end
  else
  begin
    if TLlamaProcessManager.Instance.IsRunning then
    begin
      if MessageDlg('Server Active',
        'llama-server is currently active. Terminate server and exit application?',
        mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        TLlamaProcessManager.Instance.StopServer;
        CanClose := True;
      end
      else
        CanClose := False;
    end
    else
      CanClose := True;
  end;
end;

procedure TfrmMain.LoadConfiguration;
begin
  FAppConfig := TAppConfig.CreateDefault;
  if FileExists(FConfigFilePath) then
  begin
    if Assigned(frmSettings) then
      FAppConfig := frmSettings.Config;
  end;
end;

procedure TfrmMain.ApplyAppConfig;
begin
  TLogger.Instance.MinLevel := FAppConfig.LogLevel;
  TLogger.Instance.MaxLogLines := FAppConfig.MaxLogLines;
  TLogger.Instance.LogToFileEnabled := FAppConfig.LogToFile;
  TLogger.Instance.LogFilePath := FAppConfig.LogsDir + PathDelim + 'llama_center.log';

  lblMainEndpoint.Caption := Format('Endpoint: http://%s:%d', [FAppConfig.DefaultHost, FAppConfig.DefaultPort]);
  statMain.Panels[1].Text := Format('Target: %s:%d', [FAppConfig.DefaultHost, FAppConfig.DefaultPort]);
  cmbLogLevelFilter.Text := LogLevelToString(FAppConfig.LogLevel);
end;

procedure TfrmMain.EnsureChildFormsCreated;
begin
  if not Assigned(frmServerControl) then
    Application.CreateForm(TfrmServerControl, frmServerControl);

  if not Assigned(frmModelHub) then
    Application.CreateForm(TfrmModelHub, frmModelHub);

  if not Assigned(frmPlayground) then
    Application.CreateForm(TfrmPlayground, frmPlayground);

  if not Assigned(frmDownloader) then
    Application.CreateForm(TfrmDownloader, frmDownloader);

  if not Assigned(frmQuantize) then
    Application.CreateForm(TfrmQuantize, frmQuantize);

  if not Assigned(frmBenchmark) then
    Application.CreateForm(TfrmBenchmark, frmBenchmark);

  if not Assigned(frmSettings) then
    Application.CreateForm(TfrmSettings, frmSettings);
end;

procedure TfrmMain.UpdateServerStatusUI(const AState: TLlamaProcessState);
var
  PID: Cardinal;
begin
  PID := TLlamaProcessManager.Instance.GetActivePID;

  case AState of
    lpsStopped:
    begin
      pnlStateBadge.Caption := 'STOPPED';
      pnlStateBadge.Color := COLOR_STATUS_STOPPED;
      btnQuickStart.Enabled := True;
      btnQuickStop.Enabled := False;
      btnQuickRestart.Enabled := False;
      mnuServerStart.Enabled := True;
      mnuServerStop.Enabled := False;
      mnuServerRestart.Enabled := False;
      mnuTrayStartStop.Caption := 'Start Server';
      lblMainPID.Caption := 'PID: None';
      lblMainUptime.Caption := 'Uptime: 00:00:00';
      lblMainModel.Caption := 'Model: No model loaded';
      statMain.Panels[0].Text := 'Engine: Stopped';
    end;
    lpsStarting:
    begin
      pnlStateBadge.Caption := 'STARTING';
      pnlStateBadge.Color := COLOR_STATUS_STARTING;
      btnQuickStart.Enabled := False;
      btnQuickStop.Enabled := True;
      btnQuickRestart.Enabled := False;
      mnuServerStart.Enabled := False;
      mnuServerStop.Enabled := True;
      mnuServerRestart.Enabled := False;
      mnuTrayStartStop.Caption := 'Stop Server';
      lblMainPID.Caption := Format('PID: %d (Starting)', [PID]);
      lblMainModel.Caption := 'Model: ' + ExtractFileName(TLlamaProcessManager.Instance.CurrentProfile.ModelFile);
      statMain.Panels[0].Text := 'Engine: Starting...';
    end;
    lpsRunning:
    begin
      pnlStateBadge.Caption := 'ONLINE';
      pnlStateBadge.Color := COLOR_STATUS_RUNNING;
      btnQuickStart.Enabled := False;
      btnQuickStop.Enabled := True;
      btnQuickRestart.Enabled := True;
      mnuServerStart.Enabled := False;
      mnuServerStop.Enabled := True;
      mnuServerRestart.Enabled := True;
      mnuTrayStartStop.Caption := 'Stop Server';
      lblMainPID.Caption := Format('PID: %d', [PID]);
      lblMainModel.Caption := 'Model: ' + ExtractFileName(TLlamaProcessManager.Instance.CurrentProfile.ModelFile);
      statMain.Panels[0].Text := 'Engine: Online';
    end;
    lpsStopping:
    begin
      pnlStateBadge.Caption := 'STOPPING';
      pnlStateBadge.Color := COLOR_STATUS_STARTING;
      btnQuickStart.Enabled := False;
      btnQuickStop.Enabled := False;
      btnQuickRestart.Enabled := False;
      mnuServerStart.Enabled := False;
      mnuServerStop.Enabled := False;
      mnuServerRestart.Enabled := False;
      statMain.Panels[0].Text := 'Engine: Stopping...';
    end;
    lpsError:
    begin
      pnlStateBadge.Caption := 'ERROR';
      pnlStateBadge.Color := COLOR_STATUS_ERROR;
      btnQuickStart.Enabled := True;
      btnQuickStop.Enabled := False;
      btnQuickRestart.Enabled := False;
      mnuServerStart.Enabled := True;
      mnuServerStop.Enabled := False;
      mnuServerRestart.Enabled := False;
      mnuTrayStartStop.Caption := 'Start Server';
      lblMainPID.Caption := 'PID: Crashed';
      statMain.Panels[0].Text := 'Engine: Error / Crashed';
    end;
  end;
end;

procedure TfrmMain.UpdateHardwareTelemetry;
var
  Snap: THardwareSnapshot;
  GPU: TGPUInfo;
  RAMPct, VRAMPct: Double;
begin
  Snap := THardwareInfo.GetSnapshot;
  GPU := Snap.GetPrimaryGPU;

  lblCPUName.Caption := Format('CPU: %s (%dC / %dT)', [Snap.CPUName, Snap.PhysicalCores, Snap.LogicalCores]);

  RAMPct := Snap.GetRAMUsagePercent;
  lblRAMUsage.Caption := Format('System RAM: %s / %s (%.1f%%)', [
    FormatBytes(Snap.UsedRAMBytes),
    FormatBytes(Snap.TotalRAMBytes),
    RAMPct
  ]);
  pbRAM.Position := Round(RAMPct);

  if GPU.IsDedicated and (GPU.TotalVRAMBytes > 0) then
  begin
    VRAMPct := GPU.GetVRAMUsagePercent;
    lblGPUName.Caption := Format('GPU: %s', [GPU.Name]);
    lblVRAMUsage.Caption := Format('Dedicated VRAM: %s / %s (%.1f%%)', [
      FormatBytes(GPU.UsedVRAMBytes),
      FormatBytes(GPU.TotalVRAMBytes),
      VRAMPct
    ]);
    pbVRAM.Position := Round(VRAMPct);
  end
  else
  begin
    lblGPUName.Caption := 'GPU: ' + GPU.Name;
    lblVRAMUsage.Caption := 'Dedicated VRAM: Shared / Unified Memory';
    pbVRAM.Position := 0;
  end;

  statMain.Panels[2].Text := Format('RAM: %.1f%% | VRAM: %.1f%%', [RAMPct, pbVRAM.Position * 1.0]);
end;

procedure TfrmMain.UpdateSlotTelemetry(const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
var
  i, ActiveCount: Integer;
  ThroughputSum: Double;
  TotalTokensDecoded: Int64;
begin
  ActiveCount := 0;
  ThroughputSum := 0.0;
  TotalTokensDecoded := 0;

  for i := 0 to High(ASlots) do
  begin
    if ASlots[i].IsActive or (ASlots[i].State in [ssProcessing, ssEvaluating]) then
    begin
      Inc(ActiveCount);
      ThroughputSum := ThroughputSum + ASlots[i].TokensPerSecond;
    end;
    TotalTokensDecoded := TotalTokensDecoded + ASlots[i].GeneratedTokens;
  end;

  lblSlotCount.Caption := Format('Active Slots: %d / %d', [ActiveCount, Length(ASlots)]);
  lblThroughput.Caption := Format('%.2f tokens/s', [ThroughputSum]);
  lblTotalTokensProcessed.Caption := Format('Total Tokens Decoded: %s', [FormatThousands(TotalTokensDecoded)]);

  if ThroughputSum > 0.01 then
    lblThroughput.Font.Color := clGreen
  else
    lblThroughput.Font.Color := clGray;

  statMain.Panels[3].Text := Format('Throughput: %.2f t/s', [ThroughputSum]);
end;

function TfrmMain.FormatLogLine(const AEntry: TLogEntry): string;
var
  TagStr: string;
begin
  if AEntry.Tag <> '' then
    TagStr := '[' + AEntry.Tag + '] '
  else
    TagStr := '';

  Result := Format('[%s] [%s] %s%s', [
    FormatDateTime('hh:nn:ss', AEntry.Timestamp),
    LogLevelToString(AEntry.Level),
    TagStr,
    AEntry.Message
  ]);
end;

procedure TfrmMain.AppendLogEntry(const AEntry: TLogEntry);
var
  SelectedLevel: TLogLevel;
  Line: string;
  Len: Integer;
begin
  // Simpan dalam buffer internal
  Len := Length(FLogHistory);
  SetLength(FLogHistory, Len + 1);
  FLogHistory[Len] := AEntry;

  if Length(FLogHistory) > FAppConfig.MaxLogLines then
  begin
    // Geser array untuk membatasi ukuran memori
    Move(FLogHistory[1], FLogHistory[0], (Length(FLogHistory) - 1) * SizeOf(TLogEntry));
    SetLength(FLogHistory, Length(FLogHistory) - 1);
  end;

  SelectedLevel := StringToLogLevel(cmbLogLevelFilter.Text);
  if AEntry.Level < SelectedLevel then Exit;

  Line := FormatLogLine(AEntry);
  mmoMainLog.Lines.Add(Line);

  if mmoMainLog.Lines.Count > FAppConfig.MaxLogLines then
    mmoMainLog.Lines.Delete(0);

  if chkLogAutoScroll.Checked then
  begin
    mmoMainLog.SelStart := Length(mmoMainLog.Text);
    mmoMainLog.SelLength := 0;
  end;
end;

procedure TfrmMain.btnNavServerClick(Sender: TObject);
begin
  EnsureChildFormsCreated;
  frmServerControl.Show;
  frmServerControl.BringToFront;
end;

procedure TfrmMain.btnNavModelHubClick(Sender: TObject);
begin
  EnsureChildFormsCreated;
  frmModelHub.SetModelsDirectory(FAppConfig.ModelsDir);
  frmModelHub.Show;
  frmModelHub.BringToFront;
end;

procedure TfrmMain.btnNavPlaygroundClick(Sender: TObject);
begin
  EnsureChildFormsCreated;
  frmPlayground.SetServerEndpoint(Format('http://%s:%d', [FAppConfig.DefaultHost, FAppConfig.DefaultPort]));
  frmPlayground.Show;
  frmPlayground.BringToFront;
end;

procedure TfrmMain.btnNavDownloaderClick(Sender: TObject);
begin
  EnsureChildFormsCreated;
  frmDownloader.Show;
  frmDownloader.BringToFront;
end;

procedure TfrmMain.btnNavQuantizeClick(Sender: TObject);
begin
  EnsureChildFormsCreated;
  frmQuantize.Show;
  frmQuantize.BringToFront;
end;

procedure TfrmMain.btnNavBenchClick(Sender: TObject);
begin
  EnsureChildFormsCreated;
  frmBenchmark.Show;
  frmBenchmark.BringToFront;
end;

procedure TfrmMain.btnNavSettingsClick(Sender: TObject);
begin
  EnsureChildFormsCreated;
  if frmSettings.Execute(FConfigFilePath) then
  begin
    FAppConfig := frmSettings.Config;
    ApplyAppConfig;
  end;
end;

procedure TfrmMain.btnQuickStartClick(Sender: TObject);
var
  Prof: TServerProfile;
  ServerExe: string;
begin
  if TLlamaProcessManager.Instance.IsRunning then Exit;

  Prof := TProfileManager.Instance.GetDefaultProfile;
  if (Prof.ModelFile = '') or not FileExists(Prof.ModelFile) then
  begin
    if MessageDlg('No Model Specified',
      'The active profile does not specify a valid .gguf model file.' + sLineBreak +
      'Would you like to open the Server Control dashboard to choose a model?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      btnNavServerClick(Sender);
    end;
    Exit;
  end;

  // GUNAKAN RESOLVER OTOMATIS AGAR TIDAK ERROR MESKI BELUM SAVE SETTINGS
  ServerExe := ResolveServerBinaryPath;
  if (ServerExe = '') or not FileExists(ServerExe) then
  begin
    MessageDlg('Binary Not Found',
      'llama-server executable was not found.' + sLineBreak +
      'Please configure the correct executable path in Settings -> Paths & Binaries.',
      mtError, [mbOK], 0);
    Exit;
  end;

  FServerStartTime := Now;
  if TLlamaProcessManager.Instance.StartServer(ServerExe, Prof) then
  begin
    TSlotMonitor.Instance.StartMonitoring(Prof.Host, Prof.Port, Prof.ApiKey, 1000);
    UpdateServerStatusUI(lpsStarting);
  end;
end;

procedure TfrmMain.btnQuickStopClick(Sender: TObject);
begin
  TSlotMonitor.Instance.StopMonitoring;
  TLlamaProcessManager.Instance.StopServer;
  UpdateServerStatusUI(TLlamaProcessManager.Instance.State);
end;

procedure TfrmMain.btnQuickRestartClick(Sender: TObject);
begin
  FIsRestarting := True;
  btnQuickStopClick(Sender);
end;

procedure TfrmMain.btnOpenWebUIClick(Sender: TObject);
var
  Url: string;
  Prof: TServerProfile;
begin
  Prof := TProfileManager.Instance.GetDefaultProfile;
  Url := Format('http://%s:%d', [Prof.Host, Prof.Port]);
  OpenURL(Url);
end;

procedure TfrmMain.cmbLogLevelFilterChange(Sender: TObject);
var
  SelectedLevel: TLogLevel;
  i: Integer;
begin
  SelectedLevel := StringToLogLevel(cmbLogLevelFilter.Text);
  mmoMainLog.Lines.BeginUpdate;
  try
    mmoMainLog.Clear;
    for i := 0 to High(FLogHistory) do
    begin
      if FLogHistory[i].Level >= SelectedLevel then
        mmoMainLog.Lines.Add(FormatLogLine(FLogHistory[i]));
    end;
  finally
    mmoMainLog.Lines.EndUpdate;
  end;
end;

procedure TfrmMain.btnClearLogsClick(Sender: TObject);
begin
  SetLength(FLogHistory, 0);
  mmoMainLog.Clear;
end;

procedure TfrmMain.btnOpenLogsFolderClick(Sender: TObject);
begin
  if DirectoryExists(FAppConfig.LogsDir) then
    OpenDocument(FAppConfig.LogsDir);
end;

procedure TfrmMain.mnuFileSettingsClick(Sender: TObject);
begin
  btnNavSettingsClick(Sender);
end;

procedure TfrmMain.mnuFileExitClick(Sender: TObject);
begin
  FAllowAppClose := True;
  Close;
end;

procedure TfrmMain.mnuHelpDocsClick(Sender: TObject);
begin
  OpenURL('https://github.com/ggerganov/llama.cpp');
end;

procedure TfrmMain.mnuHelpAboutClick(Sender: TObject);
begin
  ShowMessage(
    'Llama Control Center' + sLineBreak +
    'Version 1.0.0' + sLineBreak + sLineBreak +
    'A high-performance local AI management suite and GUI for llama.cpp' + sLineBreak +
    'Built with Free Pascal & Lazarus LCL.'+ sLineBreak +       sLineBreak +
    'Developer : KangOz - NKRI '
  );
end;

procedure TfrmMain.tmrTelemetryTimer(Sender: TObject);
var
  UptimeSec: Int64;
begin
  UpdateHardwareTelemetry;

  if TLlamaProcessManager.Instance.IsRunning and (FServerStartTime > 0) then
  begin
    UptimeSec := SecondsBetween(Now, FServerStartTime);
    lblMainUptime.Caption := 'Uptime: ' + FormatDurationSec(UptimeSec);
  end;
end;

procedure TfrmMain.trayMainClick(Sender: TObject);
begin
  if Visible then
  begin
    Hide;
  end
  else
  begin
    Show;
    WindowState := wsNormal;
    BringToFront;
  end;
end;

procedure TfrmMain.mnuTrayShowClick(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  BringToFront;
end;

procedure TfrmMain.OnLogEntryReceived(const ATimestamp: TDateTime; const ALevel: TLogLevel; const ATag: string; const AMessage: string);
var
  Entry: TLogEntry;
begin
  Entry.Timestamp := ATimestamp;
  Entry.Level := ALevel;
  Entry.Tag := ATag;
  Entry.Message := AMessage;
  AppendLogEntry(Entry);
end;

procedure TfrmMain.OnProcessStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
begin
  // Simpan state ke variabel privat agar aman diakses lintas thread
  FPendingState := AState;

  // Kirim ke antrean Main Thread menggunakan method pointer standar (tanpa anonymous method)
  TThread.Queue(nil, @DoUpdateStatusAsync);
end;

procedure TfrmMain.DoUpdateStatusAsync;
begin
  UpdateServerStatusUI(FPendingState);

  if (FPendingState = lpsStopped) and FIsRestarting then
  begin
    FIsRestarting := False;
    btnQuickStartClick(nil);
  end;
end;

procedure TfrmMain.OnSlotsUpdated(Sender: TObject; const ASlots: TSlotInfoArray; const AIsOnline: Boolean);
begin
  UpdateSlotTelemetry(ASlots, AIsOnline);
end;

procedure TfrmMain.InitSmoothNavigation;
  function CreateNavBtn(const ACaption: string; ALeft: Integer; AClickEv: TNotifyEvent): TSmoothNavButton;
  begin
    Result := TSmoothNavButton.Create(Self);
    Result.Parent := pnlNavigation; // Panel navbar atas
    Result.Caption := ACaption;
    Result.Left := ALeft;
    Result.Align:=alLeft;
    Result.Top := 6;
    Result.Width := 125;
    Result.Height := 34;
    Result.OnClick := AClickEv;
  end;
begin
  // Sembunyikan tombol lama
  btnNavServer.Visible := False;
  btnNavModelHub.Visible := False;
  btnNavPlayground.Visible := False;
  btnNavDownloader.Visible := False;
  btnNavQuantize.Visible := False;
  btnNavBench.Visible := False;
  btnNavSettings.Visible:=False;

  // Buat tombol baru dengan gaya halus
  FNavBtnServer     := CreateNavBtn('Server Control', 12, @btnNavServerClick);
  FNavBtnHub        := CreateNavBtn('Model Hub', 145, @btnNavModelHubClick);
  FNavBtnPlayground := CreateNavBtn('AI Playground', 278, @btnNavPlaygroundClick);
  FNavBtnDownloader := CreateNavBtn('Downloader', 411, @btnNavDownloaderClick);
  FNavBtnQuantize   := CreateNavBtn('Quantizer', 544, @btnNavQuantizeClick);
  FNavBtnBench      := CreateNavBtn('Benchmark', 677, @btnNavBenchClick);
  FNavBtnSetting    := CreateNavBtn('Setting', 700, @btnNavSettingsClick);

  SetActiveNavButton(FNavBtnServer);
end;
procedure TfrmMain.SetActiveNavButton(AActiveBtn: TSmoothNavButton);
begin
  FNavBtnServer.IsActive     := (FNavBtnServer = AActiveBtn);
  FNavBtnHub.IsActive        := (FNavBtnHub = AActiveBtn);
  FNavBtnPlayground.IsActive := (FNavBtnPlayground = AActiveBtn);
  FNavBtnDownloader.IsActive := (FNavBtnDownloader = AActiveBtn);
  FNavBtnQuantize.IsActive   := (FNavBtnQuantize = AActiveBtn);
  FNavBtnBench.IsActive      := (FNavBtnBench = AActiveBtn);
  FNavBtnSetting.IsActive    := (FNavBtnSetting = AActiveBtn);
end;

function TfrmMain.ResolveServerBinaryPath: string;
var
  ConfigPath, AppDir, TargetPath: string;
  RootData, SectionData: TJSONData;
  SecObj: TJSONObject;
begin
  Result := '';
  AppDir := ExtractFilePath(Application.ExeName);
  ConfigPath := AppDir + 'config' + PathDelim + 'app_settings.json';

  // 1. Coba baca langsung dari file konfigurasi JSON jika ada
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
          TargetPath := GetJSONString(SecObj, 'server_binary', '');

          if (TargetPath <> '') and FileExists(TargetPath) then
            Exit(TargetPath);

          if (TargetPath <> '') and FileExists(AppDir + TargetPath) then
            Exit(AppDir + TargetPath);
        end;
      finally
        RootData.Free;
      end;
    end;
  end;

  // 2. Cek dari FAppConfig jika terekam
  if (FAppConfig.ServerBinary <> '') and FileExists(FAppConfig.ServerBinary) then
    Exit(FAppConfig.ServerBinary);
  if (FAppConfig.ServerBinary <> '') and FileExists(AppDir + FAppConfig.ServerBinary) then
    Exit(AppDir + FAppConfig.ServerBinary);

  // 3. Fallback otomatis ke lokasi standar biner di folder aplikasi
  if FileExists(AppDir + 'bin' + PathDelim + 'engine' + PathDelim + 'llama-server.exe') then
    Exit(AppDir + 'bin' + PathDelim + 'engine' + PathDelim + 'llama-server.exe');

  if FileExists(AppDir + 'bin' + PathDelim + 'llama-bin' + PathDelim + 'llama-server.exe') then
    Exit(AppDir + 'bin' + PathDelim + 'llama-bin' + PathDelim + 'llama-server.exe');

  if FileExists(AppDir + 'llama-server.exe') then
    Exit(AppDir + 'llama-server.exe');
end;

end.
