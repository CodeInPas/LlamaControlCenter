unit ufrmsettings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, StdCtrls,
  ExtCtrls, Spin, fpjson, jsonparser, uconfigtypes, ujsonhelper, ulogger;

type
  { TfrmSettings }

  TfrmSettings = class(TForm)
    btnBrowseBench: TButton;
    btnBrowseCli: TButton;
    btnBrowseDownloads: TButton;
    btnBrowseLogs: TButton;
    btnBrowseModels: TButton;
    btnBrowseQuantize: TButton;
    btnBrowseServer: TButton;
    btnBrowseSplit: TButton;
    btnCancel: TButton;
    btnReset: TButton;
    btnSave: TButton;
    chkAutoDetectGPU: TCheckBox;
    chkAutoRegister: TCheckBox;
    chkAutoStart: TCheckBox;
    chkAutoVerify: TCheckBox;
    chkCheckUpdates: TCheckBox;
    chkEnableCors: TCheckBox;
    chkLogToFile: TCheckBox;
    chkMinimizeToTray: TCheckBox;
    chkParseAnsi: TCheckBox;
    chkStartMinimized: TCheckBox;
    cmbLogLevel: TComboBox;
    cmbTheme: TComboBox;
    dlgOpenBinary: TOpenDialog;
    dlgSelectFolder: TSelectDirectoryDialog;
    edtApiKey: TEdit;
    edtBenchBinary: TEdit;
    edtCliBinary: TEdit;
    edtDefaultHost: TEdit;
    edtDownloadsDir: TEdit;
    edtHFEndpoint: TEdit;
    edtHFToken: TEdit;
    edtLogsDir: TEdit;
    edtModelsDir: TEdit;
    edtQuantizeBinary: TEdit;
    edtServerBinary: TEdit;
    edtSplitBinary: TEdit;
    gbInterface: TGroupBox;
    gbTelemetry: TGroupBox;
    gbWindowBehavior: TGroupBox;
    lblApiKey: TLabel;
    lblBenchBinary: TLabel;
    lblBufferSize: TLabel;
    lblCliBinary: TLabel;
    lblDefaultHost: TLabel;
    lblDefaultPort: TLabel;
    lblDownloadsDir: TLabel;
    lblHFEndpoint: TLabel;
    lblHFToken: TLabel;
    lblLogLevel: TLabel;
    lblLogsDir: TLabel;
    lblMaxDownloads: TLabel;
    lblMaxLogLines: TLabel;
    lblModelsDir: TLabel;
    lblPollingInterval: TLabel;
    lblQuantizeBinary: TLabel;
    lblServerBinary: TLabel;
    lblSplitBinary: TLabel;
    lblTheme: TLabel;
    lblTimeout: TLabel;
    pgcSettings: TPageControl;
    pnlBottom: TPanel;
    seBufferSize: TSpinEdit;
    seDefaultPort: TSpinEdit;
    seMaxDownloads: TSpinEdit;
    seMaxLogLines: TSpinEdit;
    sePollingInterval: TSpinEdit;
    seTimeout: TSpinEdit;
    tsDownloader: TTabSheet;
    tsGeneral: TTabSheet;
    tsLogging: TTabSheet;
    tsPaths: TTabSheet;
    tsServer: TTabSheet;

    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure btnBrowseServerClick(Sender: TObject);
    procedure btnBrowseCliClick(Sender: TObject);
    procedure btnBrowseQuantizeClick(Sender: TObject);
    procedure btnBrowseBenchClick(Sender: TObject);
    procedure btnBrowseSplitClick(Sender: TObject);
    procedure btnBrowseModelsClick(Sender: TObject);
    procedure btnBrowseDownloadsClick(Sender: TObject);
    procedure btnBrowseLogsClick(Sender: TObject);
  private
    FConfigFilePath: string;
    FCurrentConfig: TAppConfig;

    procedure LoadConfigToUI(const AConfig: TAppConfig);
    procedure SaveUIToConfig(var AConfig: TAppConfig);
    function LoadConfigFile(const AFilePath: string): Boolean;
    function SaveConfigFile(const AFilePath: string; const AConfig: TAppConfig): Boolean;
  public
    function Execute(const AConfigPath: string = ''): Boolean;
    property Config: TAppConfig read FCurrentConfig write FCurrentConfig;
  end;

var
  frmSettings: TfrmSettings;

implementation

{$R *.lfm}

{ TfrmSettings }

procedure TfrmSettings.FormCreate(Sender: TObject);
begin
  FConfigFilePath := 'config' + PathDelim + 'app_settings.json';
  FCurrentConfig := TAppConfig.CreateDefault;
end;

procedure TfrmSettings.FormShow(Sender: TObject);
begin
  if FileExists(FConfigFilePath) then
    LoadConfigFile(FConfigFilePath)
  else
    FCurrentConfig := TAppConfig.CreateDefault;

  LoadConfigToUI(FCurrentConfig);
  pgcSettings.ActivePageIndex := 0;
end;

procedure TfrmSettings.LoadConfigToUI(const AConfig: TAppConfig);
begin
  // General Tab
  cmbTheme.Text := AppThemeToString(AConfig.Theme);
  chkCheckUpdates.Checked := AConfig.CheckUpdatesOnStartup;
  chkStartMinimized.Checked := AConfig.StartMinimizedToTray;
  chkMinimizeToTray.Checked := AConfig.MinimizeToTrayOnClose;

  // Paths Tab
  edtServerBinary.Text := AConfig.ServerBinary;
  edtCliBinary.Text := AConfig.CliBinary;
  edtQuantizeBinary.Text := AConfig.QuantizeBinary;
  edtBenchBinary.Text := AConfig.BenchBinary;
  edtSplitBinary.Text := AConfig.SplitBinary;
  edtModelsDir.Text := AConfig.ModelsDir;
  edtDownloadsDir.Text := AConfig.DownloadsDir;
  edtLogsDir.Text := AConfig.LogsDir;

  // Server Defaults Tab
  edtDefaultHost.Text := AConfig.DefaultHost;
  seDefaultPort.Value := AConfig.DefaultPort;
  seTimeout.Value := AConfig.TimeoutSeconds;
  edtApiKey.Text := AConfig.DefaultApiKey;
  chkEnableCors.Checked := AConfig.EnableCors;
  chkAutoStart.Checked := AConfig.AutoStartOnLaunch;

  // Downloader Tab
  edtHFEndpoint.Text := AConfig.HuggingFaceEndpoint;
  edtHFToken.Text := AConfig.HFToken;
  seMaxDownloads.Value := AConfig.MaxConcurrentDownloads;
  seBufferSize.Value := AConfig.BufferSizeKB;
  chkAutoVerify.Checked := AConfig.AutoVerifySHA256;
  chkAutoRegister.Checked := AConfig.AutoRegisterModel;

  // Logging & Telemetry Tab
  cmbLogLevel.Text := LogLevelToString(AConfig.LogLevel);
  seMaxLogLines.Value := AConfig.MaxLogLines;
  chkLogToFile.Checked := AConfig.LogToFile;
  chkParseAnsi.Checked := AConfig.ParseAnsiColors;
  chkAutoDetectGPU.Checked := AConfig.AutoDetectGPU;
  sePollingInterval.Value := AConfig.PollingIntervalMS;
end;

procedure TfrmSettings.SaveUIToConfig(var AConfig: TAppConfig);
begin
  // General Tab
  AConfig.Theme := StringToAppTheme(cmbTheme.Text);
  AConfig.CheckUpdatesOnStartup := chkCheckUpdates.Checked;
  AConfig.StartMinimizedToTray := chkStartMinimized.Checked;
  AConfig.MinimizeToTrayOnClose := chkMinimizeToTray.Checked;

  // Paths Tab
  AConfig.ServerBinary := Trim(edtServerBinary.Text);
  AConfig.CliBinary := Trim(edtCliBinary.Text);
  AConfig.QuantizeBinary := Trim(edtQuantizeBinary.Text);
  AConfig.BenchBinary := Trim(edtBenchBinary.Text);
  AConfig.SplitBinary := Trim(edtSplitBinary.Text);
  AConfig.ModelsDir := Trim(edtModelsDir.Text);
  AConfig.DownloadsDir := Trim(edtDownloadsDir.Text);
  AConfig.LogsDir := Trim(edtLogsDir.Text);
  AConfig.LlamaBinDir := ExtractFileDir(AConfig.ServerBinary);

  // Server Defaults Tab
  AConfig.DefaultHost := Trim(edtDefaultHost.Text);
  AConfig.DefaultPort := Word(seDefaultPort.Value);
  AConfig.TimeoutSeconds := seTimeout.Value;
  AConfig.DefaultApiKey := Trim(edtApiKey.Text);
  AConfig.EnableCors := chkEnableCors.Checked;
  AConfig.AutoStartOnLaunch := chkAutoStart.Checked;

  // Downloader Tab
  AConfig.HuggingFaceEndpoint := Trim(edtHFEndpoint.Text);
  AConfig.HFToken := Trim(edtHFToken.Text);
  AConfig.MaxConcurrentDownloads := seMaxDownloads.Value;
  AConfig.BufferSizeKB := seBufferSize.Value;
  AConfig.AutoVerifySHA256 := chkAutoVerify.Checked;
  AConfig.AutoRegisterModel := chkAutoRegister.Checked;

  // Logging & Telemetry Tab
  AConfig.LogLevel := StringToLogLevel(cmbLogLevel.Text);
  AConfig.MaxLogLines := seMaxLogLines.Value;
  AConfig.LogToFile := chkLogToFile.Checked;
  AConfig.ParseAnsiColors := chkParseAnsi.Checked;
  AConfig.AutoDetectGPU := chkAutoDetectGPU.Checked;
  AConfig.PollingIntervalMS := Cardinal(sePollingInterval.Value);
end;

function TfrmSettings.LoadConfigFile(const AFilePath: string): Boolean;
var
  RootData, SectionData: TJSONData;
  RootObj, SecObj: TJSONObject;
begin
  Result := False;
  if not FileExists(AFilePath) then Exit;

  RootData := LoadJSONFile(AFilePath);
  if not Assigned(RootData) or not (RootData is TJSONObject) then Exit;

  try
    RootObj := TJSONObject(RootData);

    // Application
    SectionData := RootObj.Find('application');
    if Assigned(SectionData) and (SectionData is TJSONObject) then
    begin
      SecObj := TJSONObject(SectionData);
      FCurrentConfig.AppVersion := GetJSONString(SecObj, 'version', '1.0.0');
      FCurrentConfig.Theme := StringToAppTheme(GetJSONString(SecObj, 'theme', 'System'));
      FCurrentConfig.StartMinimizedToTray := GetJSONBool(SecObj, 'start_minimized_to_tray', False);
      FCurrentConfig.MinimizeToTrayOnClose := GetJSONBool(SecObj, 'minimize_to_tray_on_close', True);
      FCurrentConfig.CheckUpdatesOnStartup := GetJSONBool(SecObj, 'check_updates_on_startup', False);
    end;

    // Paths
    SectionData := RootObj.Find('paths');
    if Assigned(SectionData) and (SectionData is TJSONObject) then
    begin
      SecObj := TJSONObject(SectionData);
      FCurrentConfig.LlamaBinDir := GetJSONString(SecObj, 'llama_bin_dir', 'bin' + PathDelim + 'engine');
      FCurrentConfig.ServerBinary := GetJSONString(SecObj, 'server_binary', 'bin' + PathDelim + 'engine' + PathDelim + 'llama-server.exe');
      FCurrentConfig.CliBinary := GetJSONString(SecObj, 'cli_binary', 'bin' + PathDelim + 'engine' + PathDelim + 'llama-cli.exe');
      FCurrentConfig.QuantizeBinary := GetJSONString(SecObj, 'quantize_binary', 'bin' + PathDelim + 'engine' + PathDelim + 'llama-quantize.exe');
      FCurrentConfig.BenchBinary := GetJSONString(SecObj, 'bench_binary', 'bin' + PathDelim + 'engine' + PathDelim + 'llama-bench.exe');
      FCurrentConfig.SplitBinary := GetJSONString(SecObj, 'split_binary', 'bin' + PathDelim + 'engine' + PathDelim + 'llama-gguf-split.exe');
      FCurrentConfig.ModelsDir := GetJSONString(SecObj, 'models_dir', 'models');
      FCurrentConfig.DownloadsDir := GetJSONString(SecObj, 'downloads_dir', 'models');
      FCurrentConfig.LogsDir := GetJSONString(SecObj, 'logs_dir', 'logs');
    end;

    // Server Defaults
    SectionData := RootObj.Find('server_defaults');
    if Assigned(SectionData) and (SectionData is TJSONObject) then
    begin
      SecObj := TJSONObject(SectionData);
      FCurrentConfig.DefaultHost := GetJSONString(SecObj, 'host', '127.0.0.1');
      FCurrentConfig.DefaultPort := Word(GetJSONInt(SecObj, 'port', 8080));
      FCurrentConfig.TimeoutSeconds := GetJSONInt(SecObj, 'timeout_seconds', 120);
      FCurrentConfig.DefaultApiKey := GetJSONString(SecObj, 'api_key', '');
      FCurrentConfig.EnableCors := GetJSONBool(SecObj, 'enable_cors', True);
      FCurrentConfig.AutoStartOnLaunch := GetJSONBool(SecObj, 'auto_start_on_launch', False);
      FCurrentConfig.LastUsedProfile := GetJSONString(SecObj, 'last_used_profile', 'prof_balanced_default');
    end;

    // Downloader
    SectionData := RootObj.Find('downloader');
    if Assigned(SectionData) and (SectionData is TJSONObject) then
    begin
      SecObj := TJSONObject(SectionData);
      FCurrentConfig.HuggingFaceEndpoint := GetJSONString(SecObj, 'huggingface_endpoint', 'https://huggingface.co');
      FCurrentConfig.HFToken := GetJSONString(SecObj, 'hf_token', '');
      FCurrentConfig.MaxConcurrentDownloads := GetJSONInt(SecObj, 'max_concurrent_downloads', 2);
      FCurrentConfig.BufferSizeKB := GetJSONInt(SecObj, 'buffer_size_kb', 64);
      FCurrentConfig.AutoVerifySHA256 := GetJSONBool(SecObj, 'auto_verify_sha256', True);
      FCurrentConfig.AutoRegisterModel := GetJSONBool(SecObj, 'auto_register_model', True);
    end;

    // Logging
    SectionData := RootObj.Find('logging');
    if Assigned(SectionData) and (SectionData is TJSONObject) then
    begin
      SecObj := TJSONObject(SectionData);
      FCurrentConfig.LogLevel := StringToLogLevel(GetJSONString(SecObj, 'log_level', 'DEBUG'));
      FCurrentConfig.MaxLogLines := GetJSONInt(SecObj, 'max_log_lines', 5000);
      FCurrentConfig.LogToFile := GetJSONBool(SecObj, 'log_to_file', True);
      FCurrentConfig.ParseAnsiColors := GetJSONBool(SecObj, 'parse_ansi_colors', True);
    end;

    // Hardware
    SectionData := RootObj.Find('hardware');
    if Assigned(SectionData) and (SectionData is TJSONObject) then
    begin
      SecObj := TJSONObject(SectionData);
      FCurrentConfig.AutoDetectGPU := GetJSONBool(SecObj, 'auto_detect_gpu', True);
      FCurrentConfig.PollingIntervalMS := Cardinal(GetJSONInt(SecObj, 'polling_interval_ms', 1000));
    end;

    Result := True;
  finally
    RootData.Free;
  end;
end;

function TfrmSettings.SaveConfigFile(const AFilePath: string; const AConfig: TAppConfig): Boolean;
var
  RootObj, SecApp, SecPaths, SecServer, SecDownloader, SecLog, SecHw: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    // Application
    SecApp := TJSONObject.Create;
    SecApp.Add('version', AConfig.AppVersion);
    SecApp.Add('theme', AppThemeToString(AConfig.Theme));
    SecApp.Add('start_minimized_to_tray', AConfig.StartMinimizedToTray);
    SecApp.Add('minimize_to_tray_on_close', AConfig.MinimizeToTrayOnClose);
    SecApp.Add('check_updates_on_startup', AConfig.CheckUpdatesOnStartup);
    RootObj.Add('application', SecApp);

    // Paths
    SecPaths := TJSONObject.Create;
    SecPaths.Add('llama_bin_dir', AConfig.LlamaBinDir);
    SecPaths.Add('server_binary', AConfig.ServerBinary);
    SecPaths.Add('cli_binary', AConfig.CliBinary);
    SecPaths.Add('quantize_binary', AConfig.QuantizeBinary);
    SecPaths.Add('bench_binary', AConfig.BenchBinary);
    SecPaths.Add('split_binary', AConfig.SplitBinary);
    SecPaths.Add('models_dir', AConfig.ModelsDir);
    SecPaths.Add('downloads_dir', AConfig.DownloadsDir);
    SecPaths.Add('logs_dir', AConfig.LogsDir);
    RootObj.Add('paths', SecPaths);

    // Server Defaults
    SecServer := TJSONObject.Create;
    SecServer.Add('host', AConfig.DefaultHost);
    SecServer.Add('port', AConfig.DefaultPort);
    SecServer.Add('timeout_seconds', AConfig.TimeoutSeconds);
    SecServer.Add('api_key', AConfig.DefaultApiKey);
    SecServer.Add('enable_cors', AConfig.EnableCors);
    SecServer.Add('auto_start_on_launch', AConfig.AutoStartOnLaunch);
    SecServer.Add('last_used_profile', AConfig.LastUsedProfile);
    RootObj.Add('server_defaults', SecServer);

    // Downloader
    SecDownloader := TJSONObject.Create;
    SecDownloader.Add('huggingface_endpoint', AConfig.HuggingFaceEndpoint);
    SecDownloader.Add('hf_token', AConfig.HFToken);
    SecDownloader.Add('max_concurrent_downloads', AConfig.MaxConcurrentDownloads);
    SecDownloader.Add('buffer_size_kb', AConfig.BufferSizeKB);
    SecDownloader.Add('auto_verify_sha256', AConfig.AutoVerifySHA256);
    SecDownloader.Add('auto_register_model', AConfig.AutoRegisterModel);
    RootObj.Add('downloader', SecDownloader);

    // Logging
    SecLog := TJSONObject.Create;
    SecLog.Add('log_level', LogLevelToString(AConfig.LogLevel));
    SecLog.Add('max_log_lines', AConfig.MaxLogLines);
    SecLog.Add('log_to_file', AConfig.LogToFile);
    SecLog.Add('parse_ansi_colors', AConfig.ParseAnsiColors);
    RootObj.Add('logging', SecLog);

    // Hardware
    SecHw := TJSONObject.Create;
    SecHw.Add('auto_detect_gpu', AConfig.AutoDetectGPU);
    SecHw.Add('polling_interval_ms', Int64(AConfig.PollingIntervalMS));
    RootObj.Add('hardware', SecHw);

    Result := SaveJSONFile(RootObj, AFilePath, True);
    if Result then
      LogInfo('Application settings saved successfully to ' + AFilePath, 'SETTINGS')
    else
      LogError('Failed to write application settings to ' + AFilePath, 'SETTINGS');
  finally
    RootObj.Free;
  end;
end;

procedure TfrmSettings.btnSaveClick(Sender: TObject);
begin
  SaveUIToConfig(FCurrentConfig);
  if SaveConfigFile(FConfigFilePath, FCurrentConfig) then
  begin
    // Sync Logger runtime properties
    TLogger.Instance.MinLevel := FCurrentConfig.LogLevel;
    TLogger.Instance.MaxLogLines := FCurrentConfig.MaxLogLines;
    TLogger.Instance.LogToFileEnabled := FCurrentConfig.LogToFile;
    TLogger.Instance.LogFilePath := FCurrentConfig.LogsDir + PathDelim + 'llama_center.log';

    ModalResult := mrOk;
  end
  else
  begin
    MessageDlg('Error', 'Failed to save configuration settings to file.', mtError, [mbOK], 0);
  end;
end;

procedure TfrmSettings.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfrmSettings.btnResetClick(Sender: TObject);
begin
  if MessageDlg('Restore Defaults', 'Are you sure you want to reset all settings to factory default values?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FCurrentConfig := TAppConfig.CreateDefault;
    LoadConfigToUI(FCurrentConfig);
  end;
end;

procedure TfrmSettings.btnBrowseServerClick(Sender: TObject);
begin
  dlgOpenBinary.Title := 'Select llama-server Executable';
  if FileExists(edtServerBinary.Text) then
    dlgOpenBinary.InitialDir := ExtractFileDir(edtServerBinary.Text);

  if dlgOpenBinary.Execute then
    edtServerBinary.Text := dlgOpenBinary.FileName;
end;

procedure TfrmSettings.btnBrowseCliClick(Sender: TObject);
begin
  dlgOpenBinary.Title := 'Select llama-cli Executable';
  if FileExists(edtCliBinary.Text) then
    dlgOpenBinary.InitialDir := ExtractFileDir(edtCliBinary.Text);

  if dlgOpenBinary.Execute then
    edtCliBinary.Text := dlgOpenBinary.FileName;
end;

procedure TfrmSettings.btnBrowseQuantizeClick(Sender: TObject);
begin
  dlgOpenBinary.Title := 'Select llama-quantize Executable';
  if FileExists(edtQuantizeBinary.Text) then
    dlgOpenBinary.InitialDir := ExtractFileDir(edtQuantizeBinary.Text);

  if dlgOpenBinary.Execute then
    edtQuantizeBinary.Text := dlgOpenBinary.FileName;
end;

procedure TfrmSettings.btnBrowseBenchClick(Sender: TObject);
begin
  dlgOpenBinary.Title := 'Select llama-bench Executable';
  if FileExists(edtBenchBinary.Text) then
    dlgOpenBinary.InitialDir := ExtractFileDir(edtBenchBinary.Text);

  if dlgOpenBinary.Execute then
    edtBenchBinary.Text := dlgOpenBinary.FileName;
end;

procedure TfrmSettings.btnBrowseSplitClick(Sender: TObject);
begin
  dlgOpenBinary.Title := 'Select llama-gguf-split Executable';
  if FileExists(edtSplitBinary.Text) then
    dlgOpenBinary.InitialDir := ExtractFileDir(edtSplitBinary.Text);

  if dlgOpenBinary.Execute then
    edtSplitBinary.Text := dlgOpenBinary.FileName;
end;

procedure TfrmSettings.btnBrowseModelsClick(Sender: TObject);
begin
  dlgSelectFolder.Title := 'Select Models Root Directory';
  if DirectoryExists(edtModelsDir.Text) then
    dlgSelectFolder.InitialDir := edtModelsDir.Text;

  if dlgSelectFolder.Execute then
    edtModelsDir.Text := dlgSelectFolder.FileName;
end;

procedure TfrmSettings.btnBrowseDownloadsClick(Sender: TObject);
begin
  dlgSelectFolder.Title := 'Select Downloads Directory';
  if DirectoryExists(edtDownloadsDir.Text) then
    dlgSelectFolder.InitialDir := edtDownloadsDir.Text;

  if dlgSelectFolder.Execute then
    edtDownloadsDir.Text := dlgSelectFolder.FileName;
end;

procedure TfrmSettings.btnBrowseLogsClick(Sender: TObject);
begin
  dlgSelectFolder.Title := 'Select Logs Directory';
  if DirectoryExists(edtLogsDir.Text) then
    dlgSelectFolder.InitialDir := edtLogsDir.Text;

  if dlgSelectFolder.Execute then
    edtLogsDir.Text := dlgSelectFolder.FileName;
end;

function TfrmSettings.Execute(const AConfigPath: string): Boolean;
begin
  if AConfigPath <> '' then
    FConfigFilePath := AConfigPath;
  Result := (ShowModal = mrOk);
end;

end.
