unit uhttpdownloader;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, SyncObjs, DateUtils, fphttpclient, opensslsockets,
  uformatting, ulogger;

type
  { Download State Enumeration }
  TDownloadState = (
    dsIdle,
    dsConnecting,
    dsDownloading,
    dsPaused,
    dsCompleted,
    dsError,
    dsCanceled
  );

  { Telemetry & Progress Snapshot }
  TDownloadProgress = record
    BytesReceived: Int64;
    TotalBytes: Int64;
    SpeedBytesPerSec: Double;
    ProgressPercent: Double;
    RemainingSeconds: Double;
    State: TDownloadState;
    StatusMessage: string;
  end;

  { Callback Signatures }
  TDownloadProgressCallback = procedure(Sender: TObject; const AProgress: TDownloadProgress) of object;
  TDownloadCompleteCallback = procedure(Sender: TObject; const ASuccess: Boolean; const AErrorMsg: string; const ATargetFile: string) of object;

  { Resumable Chunked Downloader Thread }
  THttpDownloaderThread = class(TThread)
  private
    FUrl: string;
    FTargetFilePath: string;
    FTempFilePath: string;
    FAuthToken: string;
    FBufferSizeKB: Integer;
    FLock: TCriticalSection;

    // Telemetry Fields
    FState: TDownloadState;
    FBytesReceived: Int64;
    FTotalBytes: Int64;
    FInitialExistingBytes: Int64;
    FSessionStartBytes: Int64;
    FSpeedBytesPerSec: Double;
    FProgressPercent: Double;
    FRemainingSeconds: Double;
    FErrorMessage: string;
    FStatusMessage: string;
    FStartTime: TDateTime;
    FLastSampleTime: TDateTime;
    FLastSampleBytes: Int64;

    // Callbacks
    FOnProgress: TDownloadProgressCallback;
    FOnComplete: TDownloadCompleteCallback;

    procedure SyncFireProgress;
    procedure SyncFireComplete;
    procedure SetState(const ANewState: TDownloadState; const AMsg: string = '');
    procedure HandleDataReceived(Sender: TObject; const AContentLength, ACurrentPos: Int64);
    function QueryContentLength(const AClient: TFPHTTPClient; const AUrl: string): Int64;
  protected
    procedure Execute; override;
  public
    constructor Create(const AUrl, ATargetFilePath: string;
                       const AAuthToken: string = '';
                       const ABufferSizeKB: Integer = 64;
                       AProgressCb: TDownloadProgressCallback = nil;
                       ACompleteCb: TDownloadCompleteCallback = nil);
    destructor Destroy; override;

    procedure PauseDownload;
    procedure CancelDownload;

    function GetProgressSnapshot: TDownloadProgress;

    property Url: string read FUrl;
    property TargetFilePath: string read FTargetFilePath;
    property State: TDownloadState read FState;
  end;

{ Helper Functions }
function DownloadStateToString(const AState: TDownloadState): string;

implementation

{ Helper Functions }

function DownloadStateToString(const AState: TDownloadState): string;
begin
  case AState of
    dsIdle:        Result := 'Idle';
    dsConnecting:  Result := 'Connecting';
    dsDownloading: Result := 'Downloading';
    dsPaused:      Result := 'Paused';
    dsCompleted:   Result := 'Completed';
    dsError:       Result := 'Error';
    dsCanceled:    Result := 'Canceled';
    else           Result := 'Unknown';
  end;
end;

{ THttpDownloaderThread }

constructor THttpDownloaderThread.Create(const AUrl, ATargetFilePath: string;
  const AAuthToken: string; const ABufferSizeKB: Integer;
  AProgressCb: TDownloadProgressCallback; ACompleteCb: TDownloadCompleteCallback);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;

  FUrl := AUrl;
  FTargetFilePath := ATargetFilePath;
  FTempFilePath := ATargetFilePath + '.part';
  FAuthToken := AAuthToken;
  FBufferSizeKB := ABufferSizeKB;
  if FBufferSizeKB < 16 then FBufferSizeKB := 16;

  FOnProgress := AProgressCb;
  FOnComplete := ACompleteCb;

  FState := dsIdle;
  FBytesReceived := 0;
  FTotalBytes := 0;
  FInitialExistingBytes := 0;
  FSessionStartBytes := 0;
  FSpeedBytesPerSec := 0.0;
  FProgressPercent := 0.0;
  FRemainingSeconds := 0.0;
  FErrorMessage := '';
  FStatusMessage := 'Initializing';
end;

destructor THttpDownloaderThread.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure THttpDownloaderThread.SetState(const ANewState: TDownloadState; const AMsg: string);
begin
  FLock.Enter;
  try
    FState := ANewState;
    if AMsg <> '' then
      FStatusMessage := AMsg
    else
      FStatusMessage := DownloadStateToString(ANewState);
  finally
    FLock.Leave;
  end;
end;

procedure THttpDownloaderThread.SyncFireProgress;
var
  Snap: TDownloadProgress;
begin
  if Assigned(FOnProgress) then
  begin
    Snap := GetProgressSnapshot;
    FOnProgress(Self, Snap);
  end;
end;

procedure THttpDownloaderThread.SyncFireComplete;
var
  Success: Boolean;
  ErrMsg, Target: string;
begin
  FLock.Enter;
  try
    Success := (FState = dsCompleted);
    ErrMsg := FErrorMessage;
    Target := FTargetFilePath;
  finally
    FLock.Leave;
  end;

  if Assigned(FOnComplete) then
    FOnComplete(Self, Success, ErrMsg, Target);
end;

function THttpDownloaderThread.GetProgressSnapshot: TDownloadProgress;
begin
  FLock.Enter;
  try
    Result.BytesReceived := FBytesReceived;
    Result.TotalBytes := FTotalBytes;
    Result.SpeedBytesPerSec := FSpeedBytesPerSec;
    Result.ProgressPercent := FProgressPercent;
    Result.RemainingSeconds := FRemainingSeconds;
    Result.State := FState;
    Result.StatusMessage := FStatusMessage;
  finally
    FLock.Leave;
  end;
end;

procedure THttpDownloaderThread.PauseDownload;
begin
  SetState(dsPaused, 'Pausing download...');
  Terminate;
end;

procedure THttpDownloaderThread.CancelDownload;
begin
  SetState(dsCanceled, 'Canceling download...');
  Terminate;
end;

function THttpDownloaderThread.QueryContentLength(const AClient: TFPHTTPClient; const AUrl: string): Int64;
var
  HeaderVal: string;
begin
  Result := 0;
  try
    AClient.HTTPMethod('HEAD', AUrl, nil, [200, 206, 301, 302, 307, 308]);
    HeaderVal := AClient.ResponseHeaders.Values['Content-Length'];
    if HeaderVal <> '' then
      Result := StrToInt64Def(HeaderVal, 0);
  except
    Result := 0;
  end;
end;

procedure THttpDownloaderThread.HandleDataReceived(Sender: TObject; const AContentLength, ACurrentPos: Int64);
var
  NowTime: TDateTime;
  TimeDiffSec: Double;
  BytesDelta: Int64;
  CurrentTotalDownloaded: Int64;
  RemainingBytes: Int64;
begin
  CurrentTotalDownloaded := FInitialExistingBytes + ACurrentPos;
  NowTime := Now;

  FLock.Enter;
  try
    FBytesReceived := CurrentTotalDownloaded;
    if (FTotalBytes <= 0) and (AContentLength > 0) then
      FTotalBytes := FInitialExistingBytes + AContentLength;

    if FTotalBytes > 0 then
      FProgressPercent := (FBytesReceived / FTotalBytes) * 100.0
    else
      FProgressPercent := 0.0;

    // Moving average speed calculation (sampled every ~200ms)
    TimeDiffSec := MilliSecondsBetween(NowTime, FLastSampleTime) / 1000.0;
    if TimeDiffSec >= 0.20 then
    begin
      BytesDelta := FBytesReceived - FLastSampleBytes;
      if BytesDelta > 0 then
      begin
        FSpeedBytesPerSec := (BytesDelta / TimeDiffSec);
        FLastSampleBytes := FBytesReceived;
        FLastSampleTime := NowTime;

        if (FTotalBytes > FBytesReceived) and (FSpeedBytesPerSec > 1024.0) then
        begin
          RemainingBytes := FTotalBytes - FBytesReceived;
          FRemainingSeconds := RemainingBytes / FSpeedBytesPerSec;
        end
        else
          FRemainingSeconds := 0.0;
      end;
    end;
  finally
    FLock.Leave;
  end;

  Synchronize(@SyncFireProgress);

  if Terminated then
    Abort; // Raises EAbort to safely stop TFPHTTPClient stream loop
end;

procedure THttpDownloaderThread.Execute;
var
  Client: TFPHTTPClient;
  FileStream: TFileStream;
  TargetDir: string;
  IsResumed: Boolean;
  ServerSupportsRange: Boolean;
  StatusCode: Integer;
begin
  SetState(dsConnecting, 'Establishing connection...');
  Synchronize(@SyncFireProgress);

  TargetDir := ExtractFileDir(FTargetFilePath);
  if (TargetDir <> '') and not DirectoryExists(TargetDir) then
    ForceDirectories(TargetDir);

  Client := TFPHTTPClient.Create(nil);
  FileStream := nil;
  try
    try
      Client.AllowRedirect := True;
      Client.ConnectTimeout := 15000;
      Client.IOTimeout := 30000;

      if Trim(FAuthToken) <> '' then
        Client.AddHeader('Authorization', 'Bearer ' + Trim(FAuthToken));

      Client.AddHeader('User-Agent', 'LlamaControlCenter-NativeDownloader/1.0');

      // Determine partial existence for resumption
      IsResumed := False;
      FInitialExistingBytes := 0;
      if FileExists(FTempFilePath) then
      begin
        FileStream := TFileStream.Create(FTempFilePath, fmOpenReadWrite or fmShareDenyWrite);
        FInitialExistingBytes := FileStream.Size;
        if FInitialExistingBytes > 0 then
        begin
          FileStream.Position := FInitialExistingBytes;
          Client.AddHeader('Range', Format('bytes=%d-', [FInitialExistingBytes]));
          IsResumed := True;
          LogInfo(Format('Resuming download from byte offset %d: %s', [FInitialExistingBytes, FTempFilePath]), 'DOWNLOAD');
        end;
      end;

      if not Assigned(FileStream) then
      begin
        FileStream := TFileStream.Create(FTempFilePath, fmCreate or fmShareDenyWrite);
        FInitialExistingBytes := 0;
      end;

      // Query total size if unknown
      FTotalBytes := QueryContentLength(Client, FUrl);
      if IsResumed and (FTotalBytes > 0) and (FTotalBytes < FInitialExistingBytes) then
        FTotalBytes := FTotalBytes + FInitialExistingBytes;

      FStartTime := Now;
      FLastSampleTime := FStartTime;
      FLastSampleBytes := FInitialExistingBytes;
      FBytesReceived := FInitialExistingBytes;

      SetState(dsDownloading, 'Downloading file chunks...');
      Client.OnDataReceived := @HandleDataReceived;

      // Execute HTTP GET Stream
      try
        Client.Get(FUrl, FileStream);
        StatusCode := Client.ResponseStatusCode;
      except
        on E: EAbort do
        begin
          // Caught user interruption / cancellation
          Exit;
        end;
        on E: Exception do
        begin
          StatusCode := Client.ResponseStatusCode;
          if (StatusCode <> 200) and (StatusCode <> 206) then
            raise;
        end;
      end;

      // Validate Server Response
      ServerSupportsRange := (StatusCode = 206);
      if IsResumed and not ServerSupportsRange and (StatusCode = 200) then
      begin
        // Server did not respect Range header; restarted from beginning
        LogWarn('Server did not accept HTTP Range header; restarting download from scratch.', 'DOWNLOAD');
        FInitialExistingBytes := 0;
      end;

      // Finalize File Handling
      FreeAndNil(FileStream);

      if not Terminated then
      begin
        if FileExists(FTargetFilePath) then
          DeleteFile(FTargetFilePath);

        if RenameFile(FTempFilePath, FTargetFilePath) then
        begin
          SetState(dsCompleted, 'Download complete and verified.');
          LogInfo('Successfully downloaded model to: ' + FTargetFilePath, 'DOWNLOAD');
        end
        else
        begin
          SetState(dsError, 'Failed to rename temporary .part file.');
          FErrorMessage := 'Failed to rename temporary part file.';
          LogError(FErrorMessage, 'DOWNLOAD');
        end;
      end;

    except
      on E: Exception do
      begin
        if Assigned(FileStream) then
          FreeAndNil(FileStream);

        if FState = dsPaused then
        begin
          LogInfo('Download paused by user: ' + FTempFilePath, 'DOWNLOAD');
        end
        else if FState = dsCanceled then
        begin
          if FileExists(FTempFilePath) then
            DeleteFile(FTempFilePath);
          LogInfo('Download canceled by user: ' + FTargetFilePath, 'DOWNLOAD');
        end
        else
        begin
          SetState(dsError, E.Message);
          FErrorMessage := E.Message;
          LogError(Format('Download failed [%s]: %s', [FUrl, E.Message]), 'DOWNLOAD');
        end;
      end;
    end;
  finally
    if Assigned(FileStream) then
      FileStream.Free;
    Client.Free;
    Synchronize(@SyncFireComplete);
  end;
end;

end.

