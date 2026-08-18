unit ullamaprocess;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Process, Pipes,
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  uconfigtypes, ulogger;

type
  { Process Lifecycle State }
  TLlamaProcessState = (
    lpsStopped,
    lpsStarting,
    lpsRunning,
    lpsStopping,
    lpsError
  );

  { Process Output Callback }
  TProcessOutputEvent = procedure(Sender: TObject; const ALine: string; const AIsStdErr: Boolean) of object;
  TProcessStateChangeEvent = procedure(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer) of object;

  { Internal Pipe Stream Reader Worker Thread }
  TLlamaProcessThread = class(TThread)
  private
    FProcess: TProcess;
    FState: TLlamaProcessState;
    FExitCode: Integer;
    FActiveProfile: TServerProfile;
    FExecutablePath: string;
    FCommandLineArgs: string;
    FWorkingDir: string;
    FLock: TRTLCriticalSection;
    FCurrentLine: string;
    FIsCurrentStdErr: Boolean;
    FOnOutput: TProcessOutputEvent;
    FOnStateChange: TProcessStateChangeEvent;

    procedure SyncFireOutput;
    procedure SyncFireStateChange;
    procedure ReadAvailablePipe(const APipeStream: TInputPipeStream; var ABinaryBuffer: string; const AIsStdErr: Boolean);
    procedure FlushLineBuffer(var ABinaryBuffer: string; const AIsStdErr: Boolean; const AForceAll: Boolean = False);
  protected
    procedure Execute; override;
  public
    constructor Create(const AExePath: string;
                       const AArgs: string;
                       const AWorkDir: string;
                       const AProfile: TServerProfile;
                       const AOutputCb: TProcessOutputEvent;
                       const AStateCb: TProcessStateChangeEvent);
    destructor Destroy; override;

    procedure RequestStop;
    function GetProcessID: Cardinal;
    property State: TLlamaProcessState read FState;
    property ExitCode: Integer read FExitCode;
  end;

  { Process Orchestrator & Daemon Controller }
  TLlamaProcessManager = class
  private
    FLock: TRTLCriticalSection;
    FWorkerThread: TLlamaProcessThread;
    FState: TLlamaProcessState;
    FCurrentProfile: TServerProfile;
    FExecutablePath: string;
    FOnOutput: TProcessOutputEvent;
    FOnStateChange: TProcessStateChangeEvent;

    procedure HandleThreadOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
    procedure HandleThreadStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
    procedure SetState(const AValue: TLlamaProcessState; const AExitCode: Integer = 0);
  public
    constructor Create;
    destructor Destroy; override;

    class function Instance: TLlamaProcessManager; static;

    function StartServer(const AExecutablePath: string; const AProfile: TServerProfile; const AWorkingDir: string = ''): Boolean;
    function StartCustom(const AExecutablePath: string; const AArguments: string; const AWorkingDir: string = ''): Boolean;
    procedure StopServer;
    procedure ForceKill;

    function IsRunning: Boolean;
    function GetActivePID: Cardinal;

    property State: TLlamaProcessState read FState;
    property CurrentProfile: TServerProfile read FCurrentProfile;
    property ExecutablePath: string read FExecutablePath write FExecutablePath;
    property OnOutput: TProcessOutputEvent read FOnOutput write FOnOutput;
    property OnStateChange: TProcessStateChangeEvent read FOnStateChange write FOnStateChange;
  end;

{ Helper Functions }
function ProcessStateToString(const AState: TLlamaProcessState): string;

implementation

var
  GProcessManagerInstance: TLlamaProcessManager = nil;

{ TLlamaProcessThread }

constructor TLlamaProcessThread.Create(const AExePath: string;
  const AArgs: string;
  const AWorkDir: string;
  const AProfile: TServerProfile;
  const AOutputCb: TProcessOutputEvent;
  const AStateCb: TProcessStateChangeEvent);
begin
  inherited Create(True);
  FreeOnTerminate := True; // Thread membersihkan dirinya sendiri secara otomatis saat exit
  InitCriticalSection(FLock);
  FExecutablePath := AExePath;
  FCommandLineArgs := AArgs;
  FWorkingDir := AWorkDir;
  FActiveProfile := AProfile;
  FOnOutput := AOutputCb;
  FOnStateChange := AStateCb;
  FState := lpsStarting;
  FExitCode := 0;
  FProcess := nil;
end;

destructor TLlamaProcessThread.Destroy;
begin
  if Assigned(FProcess) then
  begin
    if FProcess.Running then
    begin
      try
        FProcess.Terminate(0);
      except
      end;
    end;
    FreeAndNil(FProcess);
  end;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TLlamaProcessThread.SyncFireOutput;
begin
  if Assigned(FOnOutput) then
    FOnOutput(Self, FCurrentLine, FIsCurrentStdErr);
end;

procedure TLlamaProcessThread.SyncFireStateChange;
begin
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, FState, FExitCode);
end;

procedure TLlamaProcessThread.FlushLineBuffer(var ABinaryBuffer: string; const AIsStdErr: Boolean; const AForceAll: Boolean);
var
  PosLF: Integer;
  Line: string;
begin
  while True do
  begin
    PosLF := Pos(#10, ABinaryBuffer);
    if PosLF > 0 then
    begin
      Line := Copy(ABinaryBuffer, 1, PosLF - 1);
      Delete(ABinaryBuffer, 1, PosLF);
      if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
        Delete(Line, Length(Line), 1);

      FCurrentLine := Line;
      FIsCurrentStdErr := AIsStdErr;
      Synchronize(@SyncFireOutput);
    end
    else
      Break;
  end;

  if AForceAll and (Length(ABinaryBuffer) > 0) then
  begin
    Line := ABinaryBuffer;
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Delete(Line, Length(Line), 1);
    ABinaryBuffer := '';
    FCurrentLine := Line;
    FIsCurrentStdErr := AIsStdErr;
    Synchronize(@SyncFireOutput);
  end;
end;

procedure TLlamaProcessThread.ReadAvailablePipe(const APipeStream: TInputPipeStream; var ABinaryBuffer: string; const AIsStdErr: Boolean);
var
  BytesAvailable, NumBytesRead: Integer;
  Chunk: array[0..4095] of AnsiChar;
  ChunkStr: string;
begin
  if not Assigned(APipeStream) then Exit;

  BytesAvailable := APipeStream.NumBytesAvailable;
  while BytesAvailable > 0 do
  begin
    NumBytesRead := APipeStream.Read(Chunk[0], SizeOf(Chunk));
    if NumBytesRead > 0 then
    begin
      SetString(ChunkStr, PAnsiChar(@Chunk[0]), NumBytesRead);
      ABinaryBuffer := ABinaryBuffer + ChunkStr;
      FlushLineBuffer(ABinaryBuffer, AIsStdErr, False);
    end
    else
      Break;
    BytesAvailable := APipeStream.NumBytesAvailable;
  end;
end;

procedure TLlamaProcessThread.RequestStop;
begin
  EnterCriticalSection(FLock);
  try
    if FState = lpsRunning then
    begin
      FState := lpsStopping;
    end;
    Terminate;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TLlamaProcessThread.GetProcessID: Cardinal;
begin
  Result := 0;
  EnterCriticalSection(FLock);
  try
    if Assigned(FProcess) and FProcess.Running then
      Result := FProcess.ProcessID;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLlamaProcessThread.Execute;
var
  StdOutBuffer, StdErrBuffer: string;
begin
  FProcess := TProcess.Create(nil);
  try
    FProcess.Executable := FExecutablePath;
    FProcess.CommandLine := '"' + FExecutablePath + '" ' + FCommandLineArgs;

    if FWorkingDir <> '' then
      FProcess.CurrentDirectory := FWorkingDir
    else
      FProcess.CurrentDirectory := ExtractFileDir(FExecutablePath);

    FProcess.Options := [poUsePipes, poNoConsole];
    FProcess.ShowWindow := swoNone;

    try
      FProcess.Execute;
      FState := lpsRunning;
      Synchronize(@SyncFireStateChange);
      LogInfo(Format('Process started (PID: %d): %s', [FProcess.ProcessID, FProcess.Executable]), 'PROC');
    except
      on E: Exception do
      begin
        FState := lpsError;
        FExitCode := -1;
        LogError('Failed to execute process: ' + E.Message, 'PROC');
        Synchronize(@SyncFireStateChange);
        Exit;
      end;
    end;

    StdOutBuffer := '';
    StdErrBuffer := '';

    while FProcess.Running and not Terminated do
    begin
      ReadAvailablePipe(FProcess.Output, StdOutBuffer, False);
      ReadAvailablePipe(FProcess.Stderr, StdErrBuffer, True);
      Sleep(15);
    end;

    // Graceful termination handling
    if Terminated and FProcess.Running then
    begin
      FState := lpsStopping;
      Synchronize(@SyncFireStateChange);

      {$IFDEF WINDOWS}
      GenerateConsoleCtrlEvent(0, FProcess.ProcessID); // 0 = CTRL_C_EVENT
      {$ELSE}
      FpKill(FProcess.ProcessID, SIGTERM);
      {$ENDIF}

      Sleep(200);
      if FProcess.Running then
      begin
        Sleep(800);
        if FProcess.Running then
          FProcess.Terminate(0);
      end;
    end;

    // Drain remaining output
    ReadAvailablePipe(FProcess.Output, StdOutBuffer, False);
    ReadAvailablePipe(FProcess.Stderr, StdErrBuffer, True);
    FlushLineBuffer(StdOutBuffer, False, True);
    FlushLineBuffer(StdErrBuffer, True, True);

    FExitCode := FProcess.ExitCode;
    FState := lpsStopped;
    LogInfo(Format('Process exited with code %d', [FExitCode]), 'PROC');
    Synchronize(@SyncFireStateChange);
  finally
    FreeAndNil(FProcess);
  end;
end;

{ TLlamaProcessManager }

constructor TLlamaProcessManager.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FWorkerThread := nil;
  FState := lpsStopped;
  FExecutablePath := '';
  FOnOutput := nil;
  FOnStateChange := nil;
end;

destructor TLlamaProcessManager.Destroy;
begin
  StopServer;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

class function TLlamaProcessManager.Instance: TLlamaProcessManager;
begin
  if not Assigned(GProcessManagerInstance) then
    GProcessManagerInstance := TLlamaProcessManager.Create;
  Result := GProcessManagerInstance;
end;

procedure TLlamaProcessManager.SetState(const AValue: TLlamaProcessState; const AExitCode: Integer);
begin
  EnterCriticalSection(FLock);
  try
    FState := AValue;
  finally
    LeaveCriticalSection(FLock);
  end;

  if Assigned(FOnStateChange) then
    FOnStateChange(Self, AValue, AExitCode);
end;

procedure TLlamaProcessManager.HandleThreadOutput(Sender: TObject; const ALine: string; const AIsStdErr: Boolean);
begin
  if AIsStdErr then
    LogWarn(ALine, 'LLAMA')
  else
    LogInfo(ALine, 'LLAMA');

  if Assigned(FOnOutput) then
    FOnOutput(Self, ALine, AIsStdErr);
end;

procedure TLlamaProcessManager.HandleThreadStateChange(Sender: TObject; const AState: TLlamaProcessState; const AExitCode: Integer);
begin
  SetState(AState, AExitCode);
  if AState in [lpsStopped, lpsError] then
  begin
    EnterCriticalSection(FLock);
    try
      if Assigned(FWorkerThread) and (FWorkerThread = Sender) then
      begin
        // Tanpa WaitFor di dalam Synchronize untuk mencegah deadlock
        FWorkerThread := nil;
      end;
    finally
      LeaveCriticalSection(FLock);
    end;
  end;
end;

function TLlamaProcessManager.StartServer(const AExecutablePath: string; const AProfile: TServerProfile; const AWorkingDir: string): Boolean;
var
  Args: string;
begin
  Result := False;
  EnterCriticalSection(FLock);
  try
    if IsRunning then
    begin
      LogWarn('Cannot start server: process is already running', 'PROC');
      Exit;
    end;

    if not FileExists(AExecutablePath) then
    begin
      LogError('llama-server binary not found at: ' + AExecutablePath, 'PROC');
      Exit;
    end;

    FExecutablePath := AExecutablePath;
    FCurrentProfile := AProfile;
    Args := AProfile.BuildCommandLineArgs(AExecutablePath);

    FWorkerThread := TLlamaProcessThread.Create(
      AExecutablePath,
      Args,
      AWorkingDir,
      AProfile,
      @HandleThreadOutput,
      @HandleThreadStateChange
    );
    FWorkerThread.Start;
    Result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TLlamaProcessManager.StartCustom(const AExecutablePath: string; const AArguments: string; const AWorkingDir: string): Boolean;
var
  EmptyProfile: TServerProfile;
begin
  Result := False;
  EnterCriticalSection(FLock);
  try
    if IsRunning then
    begin
      LogWarn('Process already active', 'PROC');
      Exit;
    end;

    if not FileExists(AExecutablePath) then
    begin
      LogError('Binary not found: ' + AExecutablePath, 'PROC');
      Exit;
    end;

    FExecutablePath := AExecutablePath;
    EmptyProfile := TServerProfile.CreateDefault('custom', 'Custom Task');

    FWorkerThread := TLlamaProcessThread.Create(
      AExecutablePath,
      AArguments,
      AWorkingDir,
      EmptyProfile,
      @HandleThreadOutput,
      @HandleThreadStateChange
    );
    FWorkerThread.Start;
    Result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLlamaProcessManager.StopServer;
begin
  EnterCriticalSection(FLock);
  try
    if Assigned(FWorkerThread) then
    begin
      FWorkerThread.RequestStop;

      // Paksa hentikan proses underlying agar server langsung mati di OS
      try
        if Assigned(FWorkerThread.FProcess) and FWorkerThread.FProcess.Running then
        begin
          {$IFDEF WINDOWS}
          if FWorkerThread.FProcess.ProcessID > 0 then
          begin
            var hProc := OpenProcess(PROCESS_TERMINATE, False, FWorkerThread.FProcess.ProcessID);
            if hProc <> 0 then
            begin
              TerminateProcess(hProc, 0);
              CloseHandle(hProc);
            end;
          end;
          {$ENDIF}
          FWorkerThread.FProcess.Terminate(0);
        end;
      except
      end;
      FWorkerThread := nil;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;

  // PENTING: Gunakan SetState agar UI menerima notifikasi status lpsStopped
  SetState(lpsStopped, 0);
end;

procedure TLlamaProcessManager.ForceKill;
begin
  EnterCriticalSection(FLock);
  try
    if Assigned(FWorkerThread) then
    begin
      FWorkerThread.Terminate;
      try
        if Assigned(FWorkerThread.FProcess) and FWorkerThread.FProcess.Running then
        begin
          {$IFDEF WINDOWS}
          if FWorkerThread.FProcess.ProcessID > 0 then
          begin
            var hProc := OpenProcess(PROCESS_TERMINATE, False, FWorkerThread.FProcess.ProcessID);
            if hProc <> 0 then
            begin
              TerminateProcess(hProc, 0);
              CloseHandle(hProc);
            end;
          end;
          {$ENDIF}
          FWorkerThread.FProcess.Terminate(0);
        end;
      except
      end;
      FWorkerThread := nil;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;

  // PENTING: Gunakan SetState agar UI menerima notifikasi status lpsStopped
  SetState(lpsStopped, 0);
end;

function TLlamaProcessManager.IsRunning: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := Assigned(FWorkerThread) and (FState in [lpsStarting, lpsRunning]);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TLlamaProcessManager.GetActivePID: Cardinal;
begin
  Result := 0;
  EnterCriticalSection(FLock);
  try
    if Assigned(FWorkerThread) then
      Result := FWorkerThread.GetProcessID;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function ProcessStateToString(const AState: TLlamaProcessState): string;
begin
  case AState of
    lpsStopped:  Result := 'Stopped';
    lpsStarting: Result := 'Starting';
    lpsRunning:  Result := 'Running';
    lpsStopping: Result := 'Stopping';
    lpsError:    Result := 'Error';
    else         Result := 'Unknown';
  end;
end;

initialization
  GProcessManagerInstance := nil;

finalization
  if Assigned(GProcessManagerInstance) then
    FreeAndNil(GProcessManagerInstance);

end.
