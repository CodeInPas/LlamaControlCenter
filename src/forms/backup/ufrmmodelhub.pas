unit ufrmmodelhub;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
  StdCtrls, Spin, ColorSpeedButton, fphttpclient, opensslsockets, fpjson,
  jsonparser, HTTPDefs, ugguftypes, uggufparser, uconfigtypes, uhardwareinfo,
  uhttpdownloader, uformatting, ujsonhelper, ulogger, ufrmservercontrol;

type
  { Local Model Cache Item }
  TLocalModelEntry = record
    FileName: string;
    SizeBytes: Int64;
    Architecture: string;
    QuantType: string;
    TotalParams: UInt64;
    FullPath: string;
  end;
  TLocalModelEntryArray = array of TLocalModelEntry;

  { Hugging Face Model Item }
  THFModelItem = record
    ModelID: string;
    Author: string;
    Name: string;
    Downloads: Int64;
    Likes: Integer;
    LastModified: string;
    PipelineTag: string;
  end;
  THFModelItemArray = array of THFModelItem;

  { Hugging Face Repository File Item }
  THFFileItem = record
    FileName: string;
    DownloadUrl: string;
    SizeBytes: Int64;
    QuantType: string;
  end;
  THFFileItemArray = array of THFFileItem;

  { TfrmModelHub Form Class }
  TfrmModelHub = class(TForm)
    btnCancelDownload: TButton;
    btnDownloadSelected: TButton;
    btnDeleteModel: TColorSpeedButton;
    btnSendToServer: TColorSpeedButton;
    btnOpenFolder: TButton;
    btnPauseDownload: TButton;
    btnRefreshLocal: TButton;
    btnSearchHF: TButton;
    btnInspectModel: TColorSpeedButton;
    edtHFSearch: TEdit;
    gbDownloadProgress: TGroupBox;
    gbLocalDetails: TGroupBox;
    lblDownloadETA: TLabel;
    lblDownloadSpeed: TLabel;
    lblDownloadStatus: TLabel;
    lblHFSearch: TLabel;
    lblLocalFilter: TLabel;
    lblRepoFiles: TLabel;
    lvHFFiles: TListView;
    lvHFModels: TListView;
    lvLocalModels: TListView;
    mmoModelDetails: TMemo;
    pbDownload: TProgressBar;
    pgcHub: TPageControl;
    pnlBottomActions: TPanel;
    pnlDownloadsTab: TPanel;
    pnlHFLeft: TPanel;
    pnlHFMain: TPanel;
    pnlHFRight: TPanel;
    pnlHFTop: TPanel;
    pnlLocalLeft: TPanel;
    pnlLocalMain: TPanel;
    pnlLocalRight: TPanel;
    pnlLocalTop: TPanel;
    splHF: TSplitter;
    splLocal: TSplitter;
    tmrSearchDebounce: TTimer;
    tsDownloads: TTabSheet;
    tsHFHub: TTabSheet;
    tsLocalModels: TTabSheet;
    txtFilterLocal: TEdit;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnRefreshLocalClick(Sender: TObject);
    procedure btnOpenFolderClick(Sender: TObject);
    procedure btnInspectModelClick(Sender: TObject);
    procedure btnSendToServerClick(Sender: TObject);
    procedure btnDeleteModelClick(Sender: TObject);
    procedure btnSearchHFClick(Sender: TObject);
    procedure btnDownloadSelectedClick(Sender: TObject);
    procedure btnPauseDownloadClick(Sender: TObject);
    procedure btnCancelDownloadClick(Sender: TObject);
    procedure lvLocalModelsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvHFModelsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure txtFilterLocalChange(Sender: TObject);
    procedure edtHFSearchKeyPress(Sender: TObject; var Key: Char);
  private
    FModelsDir: string;
    FHFEndpoint: string;
    FHFToken: string;
    FActiveDownloader: THttpDownloaderThread;
    FLocalModels: TLocalModelEntryArray;
    FHFModels: THFModelItemArray;
    FHFFiles: THFFileItemArray;

    procedure ScanLocalDirectory;
    procedure FilterLocalList;
    procedure DisplayLocalModelDetails(const AFilePath: string);
    procedure SearchHuggingFaceHub(const AQuery: string);
    procedure FetchRepoGGUFFiles(const AModelID: string);
    procedure StartModelDownload(const AUrl, ATargetFileName: string);

    // Downloader Callbacks
    procedure OnDownloadProgress(Sender: TObject; const AProgress: TDownloadProgress);
    procedure OnDownloadComplete(Sender: TObject; const ASuccess: Boolean; const AErrorMsg: string; const ATargetFile: string);
  public
    procedure SetModelsDirectory(const APath: string);
    function GetSelectedLocalModelPath: string;
  end;

var
  frmModelHub: TfrmModelHub;

implementation

uses
  LCLIntf;

{$R *.lfm}

{ TfrmModelHub }

procedure TfrmModelHub.FormCreate(Sender: TObject);
begin
  FModelsDir := 'models';
  FHFEndpoint := 'https://huggingface.co';
  FHFToken := '';
  FActiveDownloader := nil;
  SetLength(FLocalModels, 0);
  SetLength(FHFModels, 0);
  SetLength(FHFFiles, 0);

  if not DirectoryExists(FModelsDir) then
    ForceDirectories(FModelsDir);
end;

procedure TfrmModelHub.FormDestroy(Sender: TObject);
begin
  if Assigned(FActiveDownloader) then
  begin
    FActiveDownloader.CancelDownload;
    FActiveDownloader.WaitFor;
    FreeAndNil(FActiveDownloader);
  end;
  SetLength(FLocalModels, 0);
  SetLength(FHFModels, 0);
  SetLength(FHFFiles, 0);
end;

procedure TfrmModelHub.FormShow(Sender: TObject);
begin
  ScanLocalDirectory;
  pgcHub.ActivePageIndex := 0;
end;

procedure TfrmModelHub.SetModelsDirectory(const APath: string);
begin
  if APath <> '' then
  begin
    FModelsDir := APath;
    if not DirectoryExists(FModelsDir) then
      ForceDirectories(FModelsDir);
    ScanLocalDirectory;
  end;
end;

function TfrmModelHub.GetSelectedLocalModelPath: string;
begin
  Result := '';
  if Assigned(lvLocalModels.Selected) and (lvLocalModels.Selected.SubItems.Count >= 5) then
    Result := lvLocalModels.Selected.SubItems[4];
end;

procedure TfrmModelHub.ScanLocalDirectory;
var
  SearchRec: TSearchRec;
  FullPath: string;
  Info: TGGUFModelInfo;
  Count: Integer;
begin
  SetLength(FLocalModels, 0);
  if not DirectoryExists(FModelsDir) then
  begin
    FilterLocalList;
    Exit;
  end;

  Count := 0;
  if FindFirst(FModelsDir + PathDelim + '*.gguf', faAnyFile and not faDirectory, SearchRec) = 0 then
  begin
    repeat
      FullPath := FModelsDir + PathDelim + SearchRec.Name;
      Info := TGGUFParser.QuickInspect(FullPath);

      Inc(Count);
      SetLength(FLocalModels, Count);
      FLocalModels[Count - 1].FileName := SearchRec.Name;
      FLocalModels[Count - 1].SizeBytes := SearchRec.Size;
      FLocalModels[Count - 1].Architecture := Info.Architecture;
      FLocalModels[Count - 1].QuantType := Info.QuantizationType;
      FLocalModels[Count - 1].TotalParams := Info.TotalParameters;
      FLocalModels[Count - 1].FullPath := FullPath;
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);
  end;

  FilterLocalList;
end;

procedure TfrmModelHub.FilterLocalList;
var
  i: Integer;
  FilterText: string;
  Item: TListItem;
  Matches: Boolean;
begin
  FilterText := LowerCase(Trim(txtFilterLocal.Text));

  lvLocalModels.Items.BeginUpdate;
  try
    lvLocalModels.Items.Clear;
    for i := 0 to High(FLocalModels) do
    begin
      if FilterText = '' then
        Matches := True
      else
        Matches := (Pos(FilterText, LowerCase(FLocalModels[i].FileName)) > 0) or
                   (Pos(FilterText, LowerCase(FLocalModels[i].Architecture)) > 0) or
                   (Pos(FilterText, LowerCase(FLocalModels[i].QuantType)) > 0);

      if Matches then
      begin
        Item := lvLocalModels.Items.Add;
        Item.Caption := FLocalModels[i].FileName;
        Item.SubItems.Add(FormatBytes(FLocalModels[i].SizeBytes));
        Item.SubItems.Add(FLocalModels[i].Architecture);
        Item.SubItems.Add(FLocalModels[i].QuantType);
        Item.SubItems.Add(FormatParameterCount(FLocalModels[i].TotalParams));
        Item.SubItems.Add(FLocalModels[i].FullPath);
      end;
    end;
  finally
    lvLocalModels.Items.EndUpdate;
  end;
end;

procedure TfrmModelHub.DisplayLocalModelDetails(const AFilePath: string);
var
  Info: TGGUFModelInfo;
  Fit: THardwareFitResult;
  SB: TStringBuilder;
  Layers: Integer;
begin
  if not FileExists(AFilePath) then
  begin
    mmoModelDetails.Clear;
    Exit;
  end;

  Info := TGGUFParser.QuickInspect(AFilePath);
  Layers := Info.BlockCount;
  if Layers <= 0 then Layers := 33;

  Fit := THardwareInfo.EvaluateModelFit(Info.FileSize, Layers, Info.ContextLength, 'f16');

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('================ GGUF METADATA ================');
    SB.AppendLine(Format('File Name:    %s', [Info.FileName]));
    SB.AppendLine(Format('File Size:    %s (%s bytes)', [FormatBytes(Info.FileSize), FormatThousands(Info.FileSize)]));
    SB.AppendLine(Format('Model Name:   %s', [Info.ModelName]));
    SB.AppendLine(Format('Architecture: %s', [Info.Architecture]));
    SB.AppendLine(Format('Quantization: %s', [Info.QuantizationType]));
    SB.AppendLine(Format('Parameters:   %s', [FormatParameterCount(Info.TotalParameters)]));
    SB.AppendLine(Format('Context Len:  %d tokens', [Info.ContextLength]));
    SB.AppendLine(Format('Layers Count: %d', [Info.BlockCount]));
    SB.AppendLine(Format('Embedding:    %d', [Info.EmbeddingLength]));
    SB.AppendLine(Format('Heads (Q/KV): %d / %d', [Info.AttentionHeadCount, Info.AttentionHeadCountKV]));
    SB.AppendLine(Format('Author:       %s', [Info.Author]));
    SB.AppendLine(Format('License:      %s', [Info.License]));
    SB.AppendLine('');
    SB.AppendLine('=============== HARDWARE FIT ASSESSMENT ===============');
    SB.AppendLine(Format('Verdict:      [%s]', [Fit.FitGrade]));
    SB.AppendLine(Format('Analysis:     %s', [Fit.Reasoning]));
    SB.AppendLine(Format('Rec GPU Layers: %d / %d', [Fit.RecommendedGPULayers, Fit.TotalModelLayers]));
    SB.AppendLine(Format('Est. VRAM Req:  %s', [FormatBytes(Fit.EstimatedVRAMUsageBytes)]));
    SB.AppendLine(Format('Est. RAM Req:   %s', [FormatBytes(Fit.EstimatedRAMUsageBytes)]));
    SB.AppendLine('========================================================');

    mmoModelDetails.Text := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TfrmModelHub.SearchHuggingFaceHub(const AQuery: string);
var
  Client: TFPHTTPClient;
  Url, ResponseStr: string;
  RootData: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  i: Integer;
  Item: TListItem;
begin
  if Trim(AQuery) = '' then Exit;

  Url := Format('%s/api/models?search=%s&filter=gguf&sort=downloads&direction=-1&limit=30', [
    FHFEndpoint,
    HTTPEncode(Trim(AQuery))
  ]);

  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := True;
    Client.ConnectTimeout := 10000;
    Client.IOTimeout := 20000;
    Client.AddHeader('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) LlamaControlCenter/1.0');
    Client.AddHeader('Accept', 'application/json');

    if Trim(FHFToken) <> '' then
      Client.AddHeader('Authorization', 'Bearer ' + Trim(FHFToken));

    try
      ResponseStr := Client.Get(Url);
    except
      on E: Exception do
      begin
        MessageDlg('Network Error', 'Failed to search Hugging Face Hub: ' + E.Message + sLineBreak +
          'Make sure OpenSSL DLLs (libssl / libcrypto) are present in the app folder.', mtError, [mbOK], 0);
        Exit;
      end;
    end;

    RootData := ParseJSON(ResponseStr);
    if not Assigned(RootData) or (RootData.JSONType <> jtArray) then Exit;

    try
      Arr := TJSONArray(RootData);
      SetLength(FHFModels, Arr.Count);

      lvHFModels.Items.BeginUpdate;
      try
        lvHFModels.Items.Clear;
        for i := 0 to Arr.Count - 1 do
        begin
          if Arr.Items[i].JSONType <> jtObject then Continue;
          Obj := TJSONObject(Arr.Items[i]);

          FHFModels[i].ModelID := GetJSONString(Obj, 'id', '');
          FHFModels[i].Author := GetJSONString(Obj, 'author', '');
          FHFModels[i].Downloads := GetJSONInt64(Obj, 'downloads', 0);
          FHFModels[i].Likes := GetJSONInt(Obj, 'likes', 0);
          FHFModels[i].LastModified := GetJSONString(Obj, 'lastModified', '');
          FHFModels[i].PipelineTag := GetJSONString(Obj, 'pipeline_tag', 'text-generation');

          Item := lvHFModels.Items.Add;
          Item.Caption := FHFModels[i].ModelID;
          Item.SubItems.Add(FormatThousands(FHFModels[i].Downloads));
          Item.SubItems.Add(FormatThousands(FHFModels[i].Likes));
          Item.SubItems.Add(FHFModels[i].PipelineTag);
        end;
      finally
        lvHFModels.Items.EndUpdate;
      end;

    finally
      RootData.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TfrmModelHub.FetchRepoGGUFFiles(const AModelID: string);
var
  Client: TFPHTTPClient;
  Url, ResponseStr, FName: string;
  RootData, SiblingsData: TJSONData;
  SiblingsArr: TJSONArray;
  FileObj: TJSONObject;
  i, GGUFCount: Integer;
  Item: TListItem;
begin
  if Trim(AModelID) = '' then Exit;

  Url := Format('%s/api/models/%s', [FHFEndpoint, AModelID]);
  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := True;
    Client.ConnectTimeout := 10000;
    Client.IOTimeout := 20000;
    Client.AddHeader('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) LlamaControlCenter/1.0');
    Client.AddHeader('Accept', 'application/json');

    if Trim(FHFToken) <> '' then
      Client.AddHeader('Authorization', 'Bearer ' + Trim(FHFToken));

    try
      ResponseStr := Client.Get(Url);
    except
      on E: Exception do
      begin
        LogError('Failed to fetch repository files for ' + AModelID + ': ' + E.Message, 'HUB');
        Exit;
      end;
    end;

    RootData := ParseJSON(ResponseStr);
    if not Assigned(RootData) or (RootData.JSONType <> jtObject) then Exit;

    try
      SiblingsData := RootData.FindPath('siblings');
      if not Assigned(SiblingsData) or (SiblingsData.JSONType <> jtArray) then Exit;

      SiblingsArr := TJSONArray(SiblingsData);
      SetLength(FHFFiles, 0);
      GGUFCount := 0;

      lvHFFiles.Items.BeginUpdate;
      try
        lvHFFiles.Items.Clear;
        for i := 0 to SiblingsArr.Count - 1 do
        begin
          if SiblingsArr.Items[i].JSONType <> jtObject then Continue;
          FileObj := TJSONObject(SiblingsArr.Items[i]);
          FName := GetJSONString(FileObj, 'rfilename', '');

          if FName.ToLower.EndsWith('.gguf') then
          begin
            Inc(GGUFCount);
            SetLength(FHFFiles, GGUFCount);
            FHFFiles[GGUFCount - 1].FileName := FName;
            FHFFiles[GGUFCount - 1].DownloadUrl := Format('%s/%s/resolve/main/%s', [FHFEndpoint, AModelID, FName]);
            FHFFiles[GGUFCount - 1].SizeBytes := 0;

            Item := lvHFFiles.Items.Add;
            Item.Caption := FName;
            Item.SubItems.Add(ExtractFileExt(FName));
            Item.SubItems.Add(FHFFiles[GGUFCount - 1].DownloadUrl);
          end;
        end;
      finally
        lvHFFiles.Items.EndUpdate;
      end;

    finally
      RootData.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TfrmModelHub.StartModelDownload(const AUrl, ATargetFileName: string);
var
  TargetPath: string;
begin
  if Assigned(FActiveDownloader) then
  begin
    MessageDlg('Download in Progress', 'Another download is currently running. Please pause or cancel it first.', mtWarning, [mbOK], 0);
    Exit;
  end;

  TargetPath := FModelsDir + PathDelim + ATargetFileName;
  pgcHub.ActivePage := tsDownloads;

  lblDownloadStatus.Caption := 'Connecting to ' + ATargetFileName + '...';
  pbDownload.Position := 0;
  btnPauseDownload.Enabled := True;
  btnCancelDownload.Enabled := True;

  FActiveDownloader := THttpDownloaderThread.Create(
    AUrl,
    TargetPath,
    FHFToken,
    64,
    @OnDownloadProgress,
    @OnDownloadComplete
  );
  FActiveDownloader.Start;
  LogInfo('Starting download: ' + AUrl + ' -> ' + TargetPath, 'HUB');
end;

procedure TfrmModelHub.OnDownloadProgress(Sender: TObject; const AProgress: TDownloadProgress);
begin
  pbDownload.Position := Round(AProgress.ProgressPercent);
  lblDownloadStatus.Caption := Format('%s (%s / %s - %.1f%%)', [
    AProgress.StatusMessage,
    FormatBytes(AProgress.BytesReceived),
    FormatBytes(AProgress.TotalBytes),
    AProgress.ProgressPercent
  ]);
  lblDownloadSpeed.Caption := 'Speed: ' + FormatSpeed(AProgress.SpeedBytesPerSec);
  lblDownloadETA.Caption := 'ETA: ' + FormatETA(AProgress.TotalBytes - AProgress.BytesReceived, AProgress.SpeedBytesPerSec);
end;

procedure TfrmModelHub.OnDownloadComplete(Sender: TObject; const ASuccess: Boolean; const AErrorMsg: string; const ATargetFile: string);
begin
  FActiveDownloader := nil;
  btnPauseDownload.Enabled := False;
  btnCancelDownload.Enabled := False;

  if ASuccess then
  begin
    pbDownload.Position := 100;
    lblDownloadStatus.Caption := 'Download Complete: ' + ExtractFileName(ATargetFile);
    lblDownloadSpeed.Caption := 'Speed: 0 B/s';
    lblDownloadETA.Caption := 'ETA: 00:00:00';
    ScanLocalDirectory;
    ShowMessage('Model successfully downloaded to:' + sLineBreak + ATargetFile);
  end
  else
  begin
    lblDownloadStatus.Caption := 'Download Failed / Stopped: ' + AErrorMsg;
    if AErrorMsg <> '' then
      MessageDlg('Download Notice', AErrorMsg, mtInformation, [mbOK], 0);
  end;
end;

procedure TfrmModelHub.btnRefreshLocalClick(Sender: TObject);
begin
  ScanLocalDirectory;
end;

procedure TfrmModelHub.btnOpenFolderClick(Sender: TObject);
begin
  if DirectoryExists(FModelsDir) then
    OpenDocument(FModelsDir);
end;

procedure TfrmModelHub.btnInspectModelClick(Sender: TObject);
var
  Path: string;
begin
  Path := GetSelectedLocalModelPath;
  if Path <> '' then
    DisplayLocalModelDetails(Path);
end;

procedure TfrmModelHub.btnSendToServerClick(Sender: TObject);
var
  Path: string;
begin
  Path := GetSelectedLocalModelPath;
  if Path = '' then
  begin
    MessageDlg('No Selection', 'Please select a local GGUF model from the list first.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if Assigned(frmServerControl) then
  begin
    frmServerControl.SelectModelFile(Path);
    frmServerControl.Show;
    frmServerControl.BringToFront;
  end;
end;

procedure TfrmModelHub.btnDeleteModelClick(Sender: TObject);
var
  Path: string;
begin
  Path := GetSelectedLocalModelPath;
  if (Path = '') or not FileExists(Path) then Exit;

  if MessageDlg('Confirm Delete', Format('Are you sure you want to permanently delete:' + sLineBreak + '%s', [ExtractFileName(Path)]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    if DeleteFile(Path) then
    begin
      LogInfo('Deleted model file: ' + Path, 'HUB');
      ScanLocalDirectory;
      mmoModelDetails.Clear;
    end
    else
      MessageDlg('Error', 'Unable to delete model file. It may be locked by a running process.', mtError, [mbOK], 0);
  end;
end;

procedure TfrmModelHub.btnSearchHFClick(Sender: TObject);
begin
  SearchHuggingFaceHub(edtHFSearch.Text);
end;

procedure TfrmModelHub.btnDownloadSelectedClick(Sender: TObject);
var
  Idx: Integer;
begin
  if not Assigned(lvHFFiles.Selected) then
  begin
    MessageDlg('Select File', 'Please select a specific GGUF quant file from the repository files list.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Idx := lvHFFiles.Selected.Index;
  if (Idx >= 0) and (Idx < Length(FHFFiles)) then
    StartModelDownload(FHFFiles[Idx].DownloadUrl, FHFFiles[Idx].FileName);
end;

procedure TfrmModelHub.btnPauseDownloadClick(Sender: TObject);
begin
  if Assigned(FActiveDownloader) then
    FActiveDownloader.PauseDownload;
end;

procedure TfrmModelHub.btnCancelDownloadClick(Sender: TObject);
begin
  if Assigned(FActiveDownloader) then
    FActiveDownloader.CancelDownload;
end;

procedure TfrmModelHub.lvLocalModelsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and Assigned(Item) and (Item.SubItems.Count >= 5) then
    DisplayLocalModelDetails(Item.SubItems[4]);
end;

procedure TfrmModelHub.lvHFModelsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and Assigned(Item) then
    FetchRepoGGUFFiles(Item.Caption);
end;

procedure TfrmModelHub.txtFilterLocalChange(Sender: TObject);
begin
  FilterLocalList;
end;

procedure TfrmModelHub.edtHFSearchKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    btnSearchHFClick(Sender);
  end;
end;

end.
