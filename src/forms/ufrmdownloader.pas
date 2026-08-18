unit ufrmdownloader;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Clipbrd, LCLIntf, DateUtils, uhttpdownloader, uformatting,
  uconfigtypes, ulogger;

type
  { Download Task Object Container }
  TDownloadTask = class
  private
    FID: string;
    FUrl: string;
    FTargetFilePath: string;
    FAuthToken: string;
    FWorkerThread: THttpDownloaderThread;
    FLastProgress: TDownloadProgress;
    FIsCompleted: Boolean;
    FIsError: Boolean;
    FErrorMessage: string;
  public
    constructor Create(const AUrl, ATargetFilePath, AAuthToken: string);
    destructor Destroy; override;

    procedure Start(AProgressCb: TDownloadProgressCallback; ACompleteCb: TDownloadCompleteCallback);
    procedure Pause;
    procedure Resume(AProgressCb: TDownloadProgressCallback; ACompleteCb: TDownloadCompleteCallback);
    procedure Cancel;
    procedure MarkCompleted;
    procedure MarkFailed(const AError: string);

    property ID: string read FID;
    property Url: string read FUrl;
    property TargetFilePath: string read FTargetFilePath;
    property AuthToken: string read FAuthToken;
    property WorkerThread: THttpDownloaderThread read FWorkerThread;
    property LastProgress: TDownloadProgress read FLastProgress write FLastProgress;
    property IsCompleted: Boolean read FIsCompleted write FIsCompleted;
    property IsError: Boolean read FIsError write FIsError;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
  end;

  { TfrmDownloader Form }
  TfrmDownloader = class(TForm)
    btnAddDownload: TButton;
    btnBrowseDest: TButton;
    btnCancel: TButton;
    btnClearCompleted: TButton;
    btnOpenFolder: TButton;
    btnPasteUrl: TButton;
    btnPause: TButton;
    btnResume: TButton;
    dlgSelectFolder: TSelectDirectoryDialog;
    edtDestination: TEdit;
    edtToken: TEdit;
    edtUrl: TEdit;
    gbNewDownload: TGroupBox;
    lblDestination: TLabel;
    lblQueueSummary: TLabel;
    lblToken: TLabel;
    lblTotalSpeed: TLabel;
    lblUrl: TLabel;
    lvDownloads: TListView;
    pbTotalProgress: TProgressBar;
    pnlBottomStatus: TPanel;
    pnlCenter: TPanel;
    pnlRightControls: TPanel;
    pnlTopAdd: TPanel;
    tmrUpdate: TTimer;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnPasteUrlClick(Sender: TObject);
    procedure btnBrowseDestClick(Sender: TObject);
    procedure btnAddDownloadClick(Sender: TObject);
    procedure btnPauseClick(Sender: TObject);
    procedure btnResumeClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnOpenFolderClick(Sender: TObject);
    procedure btnClearCompletedClick(Sender: TObject);
    procedure lvDownloadsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure tmrUpdateTimer(Sender: TObject);
  private
    FTasks: TFPList; // List of TDownloadTask

    function GetSelectedTask: TDownloadTask;
    function ExtractFileNameFromUrl(const AUrl: string): string;
    procedure UpdateButtonsState;
    procedure UpdateTaskListViewItem(AIndex: Integer; ATask: TDownloadTask);
    procedure RefreshEntireList;
    procedure UpdateSummaryStatusBar;

    // Downloader Thread Handlers
    procedure HandleDownloadProgress(Sender: TObject; const AProgress: TDownloadProgress);
    procedure HandleDownloadComplete(Sender: TObject; const ASuccess: Boolean; const AErrorMsg: string; const ATargetFile: string);
  public
    procedure AddDownloadTask(const AUrl: string; const ADestDir: string = ''; const AToken: string = '');
  end;

var
  frmDownloader: TfrmDownloader;

implementation

{$R *.lfm}

{ TDownloadTask }

constructor TDownloadTask.Create(const AUrl, ATargetFilePath, AAuthToken: string);
var
  NewGUID: TGUID;
begin
  inherited Create;
  CreateGUID(NewGUID);
  FID := GUIDToString(NewGUID);
  FUrl := AUrl;
  FTargetFilePath := ATargetFilePath;
  FAuthToken := AAuthToken;
  FWorkerThread := nil;
  FIsCompleted := False;
  FIsError := False;
  FErrorMessage := '';

  FillChar(FLastProgress, SizeOf(FLastProgress), 0);
  FLastProgress.State := dsIdle;
  FLastProgress.StatusMessage := 'Queued';
end;

destructor TDownloadTask.Destroy;
begin
  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.CancelDownload;
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
  end;
  inherited Destroy;
end;

procedure TDownloadTask.Start(AProgressCb: TDownloadProgressCallback; ACompleteCb: TDownloadCompleteCallback);
begin
  if Assigned(FWorkerThread) then Exit;

  FIsCompleted := False;
  FIsError := False;
  FErrorMessage := '';

  FWorkerThread := THttpDownloaderThread.Create(
    FUrl,
    FTargetFilePath,
    FAuthToken,
    64,
    AProgressCb,
    ACompleteCb
  );
  FWorkerThread.Start;
end;

procedure TDownloadTask.Pause;
begin
  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.PauseDownload;
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
    FLastProgress.State := dsPaused;
    FLastProgress.StatusMessage := 'Paused';
    FLastProgress.SpeedBytesPerSec := 0.0;
  end;
end;

procedure TDownloadTask.Resume(AProgressCb: TDownloadProgressCallback; ACompleteCb: TDownloadCompleteCallback);
begin
  if Assigned(FWorkerThread) then Exit;
  Start(AProgressCb, ACompleteCb);
end;

procedure TDownloadTask.Cancel;
begin
  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.CancelDownload;
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
  end;
  FLastProgress.State := dsCanceled;
  FLastProgress.StatusMessage := 'Canceled';
  FLastProgress.SpeedBytesPerSec := 0.0;
end;

procedure TDownloadTask.MarkCompleted;
begin
  FIsCompleted := True;
  FIsError := False;
  FErrorMessage := '';
  FLastProgress.State := dsCompleted;
  FLastProgress.StatusMessage := 'Completed';
  FLastProgress.SpeedBytesPerSec := 0.0;
  FLastProgress.ProgressPercent := 100.0;
end;

procedure TDownloadTask.MarkFailed(const AError: string);
begin
  FIsCompleted := False;
  FIsError := True;
  FErrorMessage := AError;
  FLastProgress.State := dsError;
  FLastProgress.StatusMessage := 'Failed: ' + AError;
  FLastProgress.SpeedBytesPerSec := 0.0;
end;

{ TfrmDownloader }

procedure TfrmDownloader.FormCreate(Sender: TObject);
begin
  FTasks := TFPList.Create;
  edtDestination.Text := 'models';
end;

procedure TfrmDownloader.FormDestroy(Sender: TObject);
var
  i: Integer;
begin
  tmrUpdate.Enabled := False;
  for i := 0 to FTasks.Count - 1 do
    TDownloadTask(FTasks[i]).Free;
  FTasks.Free;
end;

procedure TfrmDownloader.FormShow(Sender: TObject);
begin
  if not DirectoryExists(edtDestination.Text) then
    ForceDirectories(edtDestination.Text);

  RefreshEntireList;
  UpdateButtonsState;
  tmrUpdate.Enabled := True;
end;

procedure TfrmDownloader.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

function TfrmDownloader.ExtractFileNameFromUrl(const AUrl: string): string;
var
  CleanUrl: string;
  PosQuestion: Integer;
begin
  CleanUrl := Trim(AUrl);
  PosQuestion := Pos('?', CleanUrl);
  if PosQuestion > 0 then
    CleanUrl := Copy(CleanUrl, 1, PosQuestion - 1);

  CleanUrl := StringReplace(CleanUrl, '/', PathDelim, [rfReplaceAll]);
  Result := ExtractFileName(CleanUrl);

  if Trim(Result) = '' then
    Result := 'model_download_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.gguf';
end;

function TfrmDownloader.GetSelectedTask: TDownloadTask;
var
  Idx: Integer;
begin
  Result := nil;
  if Assigned(lvDownloads.Selected) then
  begin
    Idx := lvDownloads.Selected.Index;
    if (Idx >= 0) and (Idx < FTasks.Count) then
      Result := TDownloadTask(FTasks[Idx]);
  end;
end;

procedure TfrmDownloader.UpdateButtonsState;
var
  Task: TDownloadTask;
begin
  Task := GetSelectedTask;
  if not Assigned(Task) then
  begin
    btnPause.Enabled := False;
    btnResume.Enabled := False;
    btnCancel.Enabled := False;
    btnOpenFolder.Enabled := False;
    Exit;
  end;

  btnOpenFolder.Enabled := True;
  btnCancel.Enabled := True;

  if Assigned(Task.WorkerThread) and (Task.LastProgress.State = dsDownloading) then
  begin
    btnPause.Enabled := True;
    btnResume.Enabled := False;
  end
  else if (Task.LastProgress.State = dsPaused) or (Task.LastProgress.State = dsError) then
  begin
    btnPause.Enabled := False;
    btnResume.Enabled := True;
  end
  else
  begin
    btnPause.Enabled := False;
    btnResume.Enabled := False;
  end;
end;

procedure TfrmDownloader.UpdateTaskListViewItem(AIndex: Integer; ATask: TDownloadTask);
var
  Item: TListItem;
begin
  if (AIndex < 0) or (AIndex >= lvDownloads.Items.Count) then Exit;

  Item := lvDownloads.Items[AIndex];
  Item.Caption := ExtractFileName(ATask.TargetFilePath);

  while Item.SubItems.Count < 7 do
    Item.SubItems.Add('');

  Item.SubItems[0] := FormatBytes(ATask.LastProgress.TotalBytes);
  Item.SubItems[1] := FormatBytes(ATask.LastProgress.BytesReceived);
  Item.SubItems[2] := Format('%.1f%%', [ATask.LastProgress.ProgressPercent]);
  Item.SubItems[3] := FormatSpeed(ATask.LastProgress.SpeedBytesPerSec);
  Item.SubItems[4] := FormatETA(ATask.LastProgress.TotalBytes - ATask.LastProgress.BytesReceived, ATask.LastProgress.SpeedBytesPerSec);
  Item.SubItems[5] := ATask.LastProgress.StatusMessage;
  Item.SubItems[6] := ATask.Url;
end;

procedure TfrmDownloader.RefreshEntireList;
var
  i: Integer;
  Item: TListItem;
  Task: TDownloadTask;
begin
  lvDownloads.Items.BeginUpdate;
  try
    lvDownloads.Items.Clear;
    for i := 0 to FTasks.Count - 1 do
    begin
      Task := TDownloadTask(FTasks[i]);
      Item := lvDownloads.Items.Add;
      Item.Caption := ExtractFileName(Task.TargetFilePath);
      Item.SubItems.Add(FormatBytes(Task.LastProgress.TotalBytes));
      Item.SubItems.Add(FormatBytes(Task.LastProgress.BytesReceived));
      Item.SubItems.Add(Format('%.1f%%', [Task.LastProgress.ProgressPercent]));
      Item.SubItems.Add(FormatSpeed(Task.LastProgress.SpeedBytesPerSec));
      Item.SubItems.Add(FormatETA(Task.LastProgress.TotalBytes - Task.LastProgress.BytesReceived, Task.LastProgress.SpeedBytesPerSec));
      Item.SubItems.Add(Task.LastProgress.StatusMessage);
      Item.SubItems.Add(Task.Url);
    end;
  finally
    lvDownloads.Items.EndUpdate;
  end;
end;

procedure TfrmDownloader.UpdateSummaryStatusBar;
var
  i, ActiveCount, PausedCount, DoneCount: Integer;
  TotalSpeed: Double;
  TotalReceived, TotalExpected: Int64;
  OverallPercent: Double;
  Task: TDownloadTask;
begin
  ActiveCount := 0;
  PausedCount := 0;
  DoneCount := 0;
  TotalSpeed := 0.0;
  TotalReceived := 0;
  TotalExpected := 0;

  for i := 0 to FTasks.Count - 1 do
  begin
    Task := TDownloadTask(FTasks[i]);
    case Task.LastProgress.State of
      dsDownloading, dsConnecting:
      begin
        Inc(ActiveCount);
        TotalSpeed := TotalSpeed + Task.LastProgress.SpeedBytesPerSec;
      end;
      dsPaused: Inc(PausedCount);
      dsCompleted: Inc(DoneCount);
    end;

    TotalReceived := TotalReceived + Task.LastProgress.BytesReceived;
    if Task.LastProgress.TotalBytes > 0 then
      TotalExpected := TotalExpected + Task.LastProgress.TotalBytes
    else
      TotalExpected := TotalExpected + Task.LastProgress.BytesReceived;
  end;

  lblQueueSummary.Caption := Format('Tasks: %d Active | %d Paused | %d Done (%d Total)', [
    ActiveCount, PausedCount, DoneCount, FTasks.Count
  ]);
  lblTotalSpeed.Caption := 'Total Speed: ' + FormatSpeed(TotalSpeed);

  if TotalExpected > 0 then
    OverallPercent := (TotalReceived / TotalExpected) * 100.0
  else
    OverallPercent := 0.0;

  pbTotalProgress.Position := Round(OverallPercent);
end;

procedure TfrmDownloader.AddDownloadTask(const AUrl, ADestDir, AToken: string);
var
  DestDirectory, TargetFile, FileName: string;
  Task: TDownloadTask;
begin
  if Trim(AUrl) = '' then Exit;

  if Trim(ADestDir) <> '' then
    DestDirectory := ADestDir
  else
    DestDirectory := Trim(edtDestination.Text);

  if (DestDirectory = '') or not DirectoryExists(DestDirectory) then
    ForceDirectories(DestDirectory);

  FileName := ExtractFileNameFromUrl(AUrl);
  TargetFile := DestDirectory + PathDelim + FileName;

  Task := TDownloadTask.Create(Trim(AUrl), TargetFile, Trim(AToken));
  FTasks.Add(Task);

  RefreshEntireList;
  Task.Start(@HandleDownloadProgress, @HandleDownloadComplete);
  LogInfo('Download task added: ' + TargetFile, 'DOWNLOAD');
end;

procedure TfrmDownloader.btnPasteUrlClick(Sender: TObject);
begin
  if Clipboard.HasFormat(CF_TEXT) then
    edtUrl.Text := Clipboard.AsText;
end;

procedure TfrmDownloader.btnBrowseDestClick(Sender: TObject);
begin
  if DirectoryExists(edtDestination.Text) then
    dlgSelectFolder.InitialDir := edtDestination.Text;

  if dlgSelectFolder.Execute then
    edtDestination.Text := dlgSelectFolder.FileName;
end;

procedure TfrmDownloader.btnAddDownloadClick(Sender: TObject);
var
  Url: string;
begin
  Url := Trim(edtUrl.Text);
  if Url = '' then
  begin
    MessageDlg('Missing URL', 'Please enter a valid HTTP/HTTPS download link.', mtWarning, [mbOK], 0);
    Exit;
  end;

  AddDownloadTask(Url, edtDestination.Text, edtToken.Text);
  edtUrl.Clear;
end;

procedure TfrmDownloader.btnPauseClick(Sender: TObject);
var
  Task: TDownloadTask;
begin
  Task := GetSelectedTask;
  if Assigned(Task) then
  begin
    Task.Pause;
    UpdateButtonsState;
  end;
end;

procedure TfrmDownloader.btnResumeClick(Sender: TObject);
var
  Task: TDownloadTask;
begin
  Task := GetSelectedTask;
  if Assigned(Task) then
  begin
    Task.Resume(@HandleDownloadProgress, @HandleDownloadComplete);
    UpdateButtonsState;
  end;
end;

procedure TfrmDownloader.btnCancelClick(Sender: TObject);
var
  Task: TDownloadTask;
  Idx: Integer;
begin
  Task := GetSelectedTask;
  if not Assigned(Task) then Exit;

  if MessageDlg('Cancel Download', Format('Are you sure you want to remove the task for "%s"?',
    [ExtractFileName(Task.TargetFilePath)]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    Idx := FTasks.IndexOf(Task);
    Task.Cancel;
    FTasks.Remove(Task);
    Task.Free;

    RefreshEntireList;
    UpdateButtonsState;
  end;
end;

procedure TfrmDownloader.btnOpenFolderClick(Sender: TObject);
var
  Task: TDownloadTask;
  Dir: string;
begin
  Task := GetSelectedTask;
  if Assigned(Task) then
    Dir := ExtractFileDir(Task.TargetFilePath)
  else
    Dir := Trim(edtDestination.Text);

  if DirectoryExists(Dir) then
    OpenDocument(Dir);
end;

procedure TfrmDownloader.btnClearCompletedClick(Sender: TObject);
var
  i: Integer;
  Task: TDownloadTask;
begin
  for i := FTasks.Count - 1 downto 0 do
  begin
    Task := TDownloadTask(FTasks[i]);
    if Task.IsCompleted or (Task.LastProgress.State = dsCompleted) then
    begin
      FTasks.Delete(i);
      Task.Free;
    end;
  end;
  RefreshEntireList;
  UpdateButtonsState;
end;

procedure TfrmDownloader.lvDownloadsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtonsState;
end;

procedure TfrmDownloader.tmrUpdateTimer(Sender: TObject);
var
  i: Integer;
  Task: TDownloadTask;
begin
  for i := 0 to FTasks.Count - 1 do
  begin
    Task := TDownloadTask(FTasks[i]);
    if Assigned(Task.WorkerThread) then
      Task.LastProgress := Task.WorkerThread.GetProgressSnapshot;
    UpdateTaskListViewItem(i, Task);
  end;

  UpdateSummaryStatusBar;
  UpdateButtonsState;
end;

procedure TfrmDownloader.HandleDownloadProgress(Sender: TObject; const AProgress: TDownloadProgress);
var
  i: Integer;
  Task: TDownloadTask;
begin
  for i := 0 to FTasks.Count - 1 do
  begin
    Task := TDownloadTask(FTasks[i]);
    if Assigned(Task.WorkerThread) and (Task.WorkerThread = Sender) then
    begin
      Task.LastProgress := AProgress;
      Break;
    end;
  end;
end;

procedure TfrmDownloader.HandleDownloadComplete(Sender: TObject; const ASuccess: Boolean;
  const AErrorMsg: string; const ATargetFile: string);
var
  i: Integer;
  Task: TDownloadTask;
begin
  for i := 0 to FTasks.Count - 1 do
  begin
    Task := TDownloadTask(FTasks[i]);
    if SameText(Task.TargetFilePath, ATargetFile) then
    begin
      if ASuccess then
      begin
        Task.MarkCompleted;
        LogInfo('Download successfully finished: ' + ATargetFile, 'DOWNLOAD');
      end
      else
      begin
        Task.MarkFailed(AErrorMsg);
        LogError(Format('Download failed for %s: %s', [ATargetFile, AErrorMsg]), 'DOWNLOAD');
      end;
      Break;
    end;
  end;
  UpdateButtonsState;
end;

end.
