unit uconfigtypes;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes;

type
  { Logging & Appearance Enums }
  TLogLevel = (llDebug, llInfo, llWarn, llError);
  TAppTheme = (themeSystem, themeDark, themeLight);

  { Application Configuration Record }
  TAppConfig = record
    // Application Section
    AppVersion: string;
    Theme: TAppTheme;
    StartMinimizedToTray: Boolean;
    MinimizeToTrayOnClose: Boolean;
    CheckUpdatesOnStartup: Boolean;

    // Paths Section
    LlamaBinDir: string;
    ServerBinary: string;
    CliBinary: string;
    QuantizeBinary: string;
    BenchBinary: string;
    SplitBinary: string;
    ModelsDir: string;
    DownloadsDir: string;
    LogsDir: string;

    // Server Defaults
    DefaultHost: string;
    DefaultPort: Word;
    TimeoutSeconds: Integer;
    DefaultApiKey: string;
    EnableCors: Boolean;
    AutoStartOnLaunch: Boolean;
    LastUsedProfile: string;

    // Downloader Section
    HuggingFaceEndpoint: string;
    HFToken: string;
    MaxConcurrentDownloads: Integer;
    BufferSizeKB: Integer;
    AutoVerifySHA256: Boolean;
    AutoRegisterModel: Boolean;

    // Logging Section
    LogLevel: TLogLevel;
    MaxLogLines: Integer;
    LogToFile: Boolean;
    ParseAnsiColors: Boolean;

    // Hardware Telemetry
    AutoDetectGPU: Boolean;
    PollingIntervalMS: Cardinal;

    class function CreateDefault: TAppConfig; static;
  end;

  { Server Profile Record for llama-server Executions }
  TServerProfile = record
    ID: string;
    Name: string;
    Description: string;
    ModelFile: string;
    NGpuLayers: Integer;
    CtxSize: Cardinal;
    BatchSize: Cardinal;
    UBatchSize: Cardinal;
    Threads: Integer;
    ThreadsBatch: Integer;
    NPredict: Integer;
    NParallel: Integer;
    FlashAttn: Boolean;
    MLock: Boolean;
    NoMMap: Boolean;
    ContBatching: Boolean;
    Embedding: Boolean;
    Host: string;
    Port: Word;
    ApiKey: string;
    CustomArgs: string;

    class function CreateDefault(const AID, AName: string): TServerProfile; static;
    function BuildCommandLineArgs(const ABinaryPath: string): string;
  end;
  TServerProfileArray = array of TServerProfile;

  { Hardware Preset Record for Sizing & Recommendations }
  THardwarePreset = record
    ID: string;
    Name: string;
    MinRamGB: Integer;
    MaxVramGB: Integer;
    RecommendedQuant: string;
    MaxModelParams: string;
    DefaultCtx: Cardinal;
    BatchSize: Cardinal;
    UBatchSize: Cardinal;
    NGpuLayers7B: Integer;
    NGpuLayers14B: Integer;
    NGpuLayers70B: Integer;
    FlashAttn: Boolean;
    KVCacheTypeK: string;
    KVCacheTypeV: string;
  end;
  THardwarePresetArray = array of THardwarePreset;

  { Sampler Configuration for Playground & Inference API }
  TSamplerConfig = record
    Temperature: Single;
    TopP: Single;
    TopK: Integer;
    MinP: Single;
    RepeatPenalty: Single;
    PresencePenalty: Single;
    FrequencyPenalty: Single;
    Seed: Int64;
    MaxTokens: Integer;
    Stream: Boolean;
    StopTokens: TStringArray;
    CustomTemplateName: string;

    class function CreateDefault: TSamplerConfig; static;
  end;

{ Helper String Conversion Functions }
function LogLevelToString(const ALevel: TLogLevel): string;
function StringToLogLevel(const AStr: string): TLogLevel;
function AppThemeToString(const ATheme: TAppTheme): string;
function StringToAppTheme(const AStr: string): TAppTheme;

implementation

{ TAppConfig }

class function TAppConfig.CreateDefault: TAppConfig;
begin
  Result.AppVersion := '1.0.0';
  Result.Theme := themeSystem;
  Result.StartMinimizedToTray := False;
  Result.MinimizeToTrayOnClose := True;
  Result.CheckUpdatesOnStartup := False;

  Result.LlamaBinDir := 'bin' + PathDelim + 'llama-bin';
  Result.ServerBinary := Result.LlamaBinDir + PathDelim + 'llama-server' + {$IFDEF WINDOWS}'.exe'{$ELSE}''{$ENDIF};
  Result.CliBinary := Result.LlamaBinDir + PathDelim + 'llama-cli' + {$IFDEF WINDOWS}'.exe'{$ELSE}''{$ENDIF};
  Result.QuantizeBinary := Result.LlamaBinDir + PathDelim + 'llama-quantize' + {$IFDEF WINDOWS}'.exe'{$ELSE}''{$ENDIF};
  Result.BenchBinary := Result.LlamaBinDir + PathDelim + 'llama-bench' + {$IFDEF WINDOWS}'.exe'{$ELSE}''{$ENDIF};
  Result.SplitBinary := Result.LlamaBinDir + PathDelim + 'llama-gguf-split' + {$IFDEF WINDOWS}'.exe'{$ELSE}''{$ENDIF};
  Result.ModelsDir := 'models';
  Result.DownloadsDir := 'models';
  Result.LogsDir := 'logs';

  Result.DefaultHost := '127.0.0.1';
  Result.DefaultPort := 8080;
  Result.TimeoutSeconds := 120;
  Result.DefaultApiKey := '';
  Result.EnableCors := True;
  Result.AutoStartOnLaunch := False;
  Result.LastUsedProfile := 'prof_balanced_default';

  Result.HuggingFaceEndpoint := 'https://huggingface.co';
  Result.HFToken := '';
  Result.MaxConcurrentDownloads := 2;
  Result.BufferSizeKB := 64;
  Result.AutoVerifySHA256 := True;
  Result.AutoRegisterModel := True;

  Result.LogLevel := llDebug;
  Result.MaxLogLines := 5000;
  Result.LogToFile := True;
  Result.ParseAnsiColors := True;

  Result.AutoDetectGPU := True;
  Result.PollingIntervalMS := 1000;
end;

{ TServerProfile }

class function TServerProfile.CreateDefault(const AID, AName: string): TServerProfile;
begin
  Result.ID := AID;
  Result.Name := AName;
  Result.Description := '';
  Result.ModelFile := '';
  Result.NGpuLayers := 33;
  Result.CtxSize := 4096;
  Result.BatchSize := 512;
  Result.UBatchSize := 512;
  Result.Threads := 6;
  Result.ThreadsBatch := 6;
  Result.NPredict := -1;
  Result.NParallel := 1;
  Result.FlashAttn := True;
  Result.MLock := False;
  Result.NoMMap := False;
  Result.ContBatching := True;
  Result.Embedding := False;
  Result.Host := '127.0.0.1';
  Result.Port := 8080;
  Result.ApiKey := '';
  Result.CustomArgs := '';
end;

function TServerProfile.BuildCommandLineArgs(const ABinaryPath: string): string;
var
  Cmd: string;

  procedure AppendArg(const AFlag: string; const AVal: string = '');
  begin
    if Cmd <> '' then
      Cmd := Cmd + ' ';

    Cmd := Cmd + AFlag;

    if AVal <> '' then
    begin
      if (Pos(' ', AVal) > 0) and not (AVal.StartsWith('"') and AVal.EndsWith('"')) then
        Cmd := Cmd + ' "' + AVal + '"'
      else
        Cmd := Cmd + ' ' + AVal;
    end;
  end;

begin
  Cmd := '';

  if Trim(ModelFile) <> '' then
    AppendArg('-m', Trim(ModelFile));

  AppendArg('-ngl', IntToStr(NGpuLayers));
  AppendArg('-c', IntToStr(CtxSize));
  AppendArg('-b', IntToStr(BatchSize));
  AppendArg('-ub', IntToStr(UBatchSize));
  AppendArg('-t', IntToStr(Threads));
  AppendArg('-tb', IntToStr(ThreadsBatch));
  AppendArg('-n', IntToStr(NPredict));
  AppendArg('-np', IntToStr(NParallel));
  AppendArg('--host', Host);
  AppendArg('--port', IntToStr(Port));

  if FlashAttn then
    AppendArg('-fa');
  if MLock then
    AppendArg('--mlock');
  if NoMMap then
    AppendArg('--no-mmap');
  if ContBatching then
    AppendArg('-cb');
  if Embedding then
    AppendArg('--embedding');
  if Trim(ApiKey) <> '' then
    AppendArg('--api-key', Trim(ApiKey));
  if Trim(CustomArgs) <> '' then
    AppendArg(Trim(CustomArgs));

  Result := Cmd;
end;

{ TSamplerConfig }

class function TSamplerConfig.CreateDefault: TSamplerConfig;
begin
  Result.Temperature := 0.7;
  Result.TopP := 0.9;
  Result.TopK := 40;
  Result.MinP := 0.05;
  Result.RepeatPenalty := 1.1;
  Result.PresencePenalty := 0.0;
  Result.FrequencyPenalty := 0.0;
  Result.Seed := -1;
  Result.MaxTokens := 2048;
  Result.Stream := True;
  SetLength(Result.StopTokens, 0);
  Result.CustomTemplateName := 'ChatML';
end;

{ Conversion Helpers }

function LogLevelToString(const ALevel: TLogLevel): string;
begin
  case ALevel of
    llDebug: Result := 'DEBUG';
    llInfo:  Result := 'INFO';
    llWarn:  Result := 'WARN';
    llError: Result := 'ERROR';
    else     Result := 'INFO';
  end;
end;

function StringToLogLevel(const AStr: string): TLogLevel;
var
  Upper: string;
begin
  Upper := UpperCase(Trim(AStr));
  if Upper = 'DEBUG' then Exit(llDebug);
  if Upper = 'WARN' then Exit(llWarn);
  if Upper = 'ERROR' then Exit(llError);
  Result := llInfo;
end;

function AppThemeToString(const ATheme: TAppTheme): string;
begin
  case ATheme of
    themeSystem: Result := 'System';
    themeDark:   Result := 'Dark';
    themeLight:  Result := 'Light';
    else         Result := 'System';
  end;
end;

function StringToAppTheme(const AStr: string): TAppTheme;
var
  Upper: string;
begin
  Upper := UpperCase(Trim(AStr));
  if Upper = 'DARK' then Exit(themeDark);
  if Upper = 'LIGHT' then Exit(themeLight);
  Result := themeSystem;
end;

end.
