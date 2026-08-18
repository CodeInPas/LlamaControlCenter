unit uprofilemanager;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson, jsonparser,
  uconfigtypes, ujsonhelper, ulogger;

type
  { Profile Manager Engine }
  TProfileManager = class
  private
    class var FInstance: TProfileManager;
  private
    FLock: TCriticalSection;
    FConfigFilePath: string;
    FDefaultProfileID: string;
    FProfiles: TServerProfileArray;

    function ProfileToJSON(const AProfile: TServerProfile): TJSONObject;
    function JSONToProfile(const AObj: TJSONObject): TServerProfile;
    procedure PopulateDefaultPresets;
  public
    constructor Create(const AConfigFilePath: string = '');
    destructor Destroy; override;

    class function Instance: TProfileManager; static;
    class destructor ClassDestroy;

    function LoadFromFile(const AFilePath: string = ''): Boolean;
    function SaveToFile(const AFilePath: string = ''): Boolean;

    function GetCount: Integer;
    function GetAllProfiles: TServerProfileArray;
    function GetProfileByIndex(const AIndex: Integer): TServerProfile;
    function FindProfileByID(const AID: string; out AProfile: TServerProfile): Boolean;
    function FindProfileByName(const AName: string; out AProfile: TServerProfile): Boolean;

    function AddProfile(const AProfile: TServerProfile): Boolean;
    function UpdateProfile(const AProfile: TServerProfile): Boolean;
    function DeleteProfile(const AID: string): Boolean;
    function DuplicateProfile(const ASourceID: string; const ANewName: string): string;

    function GetDefaultProfile: TServerProfile;
    procedure SetDefaultProfileID(const AID: string);

    property ConfigFilePath: string read FConfigFilePath write FConfigFilePath;
    property DefaultProfileID: string read FDefaultProfileID;
  end;

implementation

{ TProfileManager }

constructor TProfileManager.Create(const AConfigFilePath: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  SetLength(FProfiles, 0);
  FDefaultProfileID := 'prof_balanced_default';

  if AConfigFilePath <> '' then
    FConfigFilePath := AConfigFilePath
  else
    FConfigFilePath := 'config' + PathDelim + 'server_profiles.json';

  if FileExists(FConfigFilePath) then
    LoadFromFile(FConfigFilePath)
  else
  begin
    PopulateDefaultPresets;
    SaveToFile(FConfigFilePath);
  end;
end;

destructor TProfileManager.Destroy;
begin
  FLock.Free;
  SetLength(FProfiles, 0);
  inherited Destroy;
end;

class function TProfileManager.Instance: TProfileManager;
begin
  if not Assigned(FInstance) then
    FInstance := TProfileManager.Create;
  Result := FInstance;
end;

class destructor TProfileManager.ClassDestroy;
begin
  if Assigned(FInstance) then
    FreeAndNil(FInstance);
end;

function TProfileManager.ProfileToJSON(const AProfile: TServerProfile): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', AProfile.ID);
  Result.Add('name', AProfile.Name);
  Result.Add('description', AProfile.Description);
  Result.Add('model_file', AProfile.ModelFile);
  Result.Add('n_gpu_layers', AProfile.NGpuLayers);
  Result.Add('ctx_size', Int64(AProfile.CtxSize));
  Result.Add('batch_size', Int64(AProfile.BatchSize));
  Result.Add('ubatch_size', Int64(AProfile.UBatchSize));
  Result.Add('threads', AProfile.Threads);
  Result.Add('threads_batch', AProfile.ThreadsBatch);
  Result.Add('n_predict', AProfile.NPredict);
  Result.Add('n_parallel', AProfile.NParallel);
  Result.Add('flash_attn', AProfile.FlashAttn);
  Result.Add('mlock', AProfile.MLock);
  Result.Add('no_mmap', AProfile.NoMMap);
  Result.Add('cont_batching', AProfile.ContBatching);
  Result.Add('embedding', AProfile.Embedding);
  Result.Add('host', AProfile.Host);
  Result.Add('port', AProfile.Port);
  Result.Add('api_key', AProfile.ApiKey);
  Result.Add('custom_args', AProfile.CustomArgs);
end;

function TProfileManager.JSONToProfile(const AObj: TJSONObject): TServerProfile;
begin
  Result := TServerProfile.CreateDefault(
    GetJSONString(AObj, 'id', TGUID.NewGuid.ToString(True)),
    GetJSONString(AObj, 'name', 'Untitled Profile')
  );

  Result.Description := GetJSONString(AObj, 'description', '');
  Result.ModelFile := GetJSONString(AObj, 'model_file', '');
  Result.NGpuLayers := GetJSONInt(AObj, 'n_gpu_layers', 33);
  Result.CtxSize := Cardinal(GetJSONInt64(AObj, 'ctx_size', 4096));
  Result.BatchSize := Cardinal(GetJSONInt64(AObj, 'batch_size', 512));
  Result.UBatchSize := Cardinal(GetJSONInt64(AObj, 'ubatch_size', 512));
  Result.Threads := GetJSONInt(AObj, 'threads', 6);
  Result.ThreadsBatch := GetJSONInt(AObj, 'threads_batch', 6);
  Result.NPredict := GetJSONInt(AObj, 'n_predict', -1);
  Result.NParallel := GetJSONInt(AObj, 'n_parallel', 1);
  Result.FlashAttn := GetJSONBool(AObj, 'flash_attn', True);
  Result.MLock := GetJSONBool(AObj, 'mlock', False);
  Result.NoMMap := GetJSONBool(AObj, 'no_mmap', False);
  Result.ContBatching := GetJSONBool(AObj, 'cont_batching', True);
  Result.Embedding := GetJSONBool(AObj, 'embedding', False);
  Result.Host := GetJSONString(AObj, 'host', '127.0.0.1');
  Result.Port := Word(GetJSONInt(AObj, 'port', 8080));
  Result.ApiKey := GetJSONString(AObj, 'api_key', '');
  Result.CustomArgs := GetJSONString(AObj, 'custom_args', '');
end;

procedure TProfileManager.PopulateDefaultPresets;
var
  P: TServerProfile;
begin
  SetLength(FProfiles, 4);

  // 1. Balanced Hybrid
  P := TServerProfile.CreateDefault('prof_balanced_default', 'Default - Balanced (Hybrid GPU/CPU)');
  P.Description := 'Standard balanced preset for 6GB-8GB VRAM consumer GPUs.';
  P.NGpuLayers := 33;
  P.CtxSize := 4096;
  P.Threads := 6;
  P.ThreadsBatch := 6;
  FProfiles[0] := P;

  // 2. Full GPU Offload
  P := TServerProfile.CreateDefault('prof_full_gpu_fast', 'Full GPU Offload (High Speed)');
  P.Description := 'Offloads all layers to VRAM for max generation throughput.';
  P.NGpuLayers := 99;
  P.CtxSize := 8192;
  P.BatchSize := 1024;
  P.Threads := 4;
  P.ThreadsBatch := 4;
  P.NParallel := 2;
  FProfiles[1] := P;

  // 3. Coding Large Context
  P := TServerProfile.CreateDefault('prof_coding_long_ctx', 'Coding & Large Context (32k Context)');
  P.Description := 'Configured for large context window analysis with Flash Attention.';
  P.NGpuLayers := 28;
  P.CtxSize := 32768;
  P.BatchSize := 2048;
  P.Threads := 8;
  P.ThreadsBatch := 8;
  P.CustomArgs := '--cache-type-k q8_0 --cache-type-v q8_0';
  FProfiles[2] := P;

  // 4. CPU Only Low-Spec
  P := TServerProfile.CreateDefault('prof_cpu_only_low_spec', 'CPU Only (Low Spec)');
  P.Description := 'Runs entirely on system RAM using all CPU threads.';
  P.NGpuLayers := 0;
  P.CtxSize := 2048;
  P.BatchSize := 256;
  P.UBatchSize := 256;
  P.Threads := 8;
  P.ThreadsBatch := 8;
  P.FlashAttn := False;
  P.ContBatching := False;
  FProfiles[3] := P;

  FDefaultProfileID := 'prof_balanced_default';
end;

function TProfileManager.LoadFromFile(const AFilePath: string): Boolean;
var
  TargetFile: string;
  RootData, ProfilesData: TJSONData;
  RootObj: TJSONObject;
  ProfilesArr: TJSONArray;
  i: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    if AFilePath <> '' then
      TargetFile := AFilePath
    else
      TargetFile := FConfigFilePath;

    if not FileExists(TargetFile) then
    begin
      LogWarn('Profiles config not found: ' + TargetFile, 'PROFILE');
      Exit;
    end;

    RootData := LoadJSONFile(TargetFile);
    if not Assigned(RootData) or not (RootData is TJSONObject) then
    begin
      LogError('Corrupt profile JSON structure in ' + TargetFile, 'PROFILE');
      Exit;
    end;

    try
      RootObj := TJSONObject(RootData);
      FDefaultProfileID := GetJSONString(RootObj, 'default_profile_id', 'prof_balanced_default');

      ProfilesData := RootObj.Find('profiles');
      if Assigned(ProfilesData) and (ProfilesData is TJSONArray) then
      begin
        ProfilesArr := TJSONArray(ProfilesData);
        SetLength(FProfiles, ProfilesArr.Count);
        for i := 0 to ProfilesArr.Count - 1 do
        begin
          if ProfilesArr.Items[i] is TJSONObject then
            FProfiles[i] := JSONToProfile(TJSONObject(ProfilesArr.Items[i]));
        end;
        Result := True;
        LogInfo(Format('Loaded %d server profiles from %s', [Length(FProfiles), TargetFile]), 'PROFILE');
      end;
    finally
      RootData.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.SaveToFile(const AFilePath: string): Boolean;
var
  TargetFile: string;
  RootObj: TJSONObject;
  ProfilesArr: TJSONArray;
  i: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    if AFilePath <> '' then
      TargetFile := AFilePath
    else
      TargetFile := FConfigFilePath;

    RootObj := TJSONObject.Create;
    try
      RootObj.Add('default_profile_id', FDefaultProfileID);

      ProfilesArr := TJSONArray.Create;
      for i := 0 to High(FProfiles) do
        ProfilesArr.Add(ProfileToJSON(FProfiles[i]));
      RootObj.Add('profiles', ProfilesArr);

      Result := SaveJSONFile(RootObj, TargetFile, True);
      if Result then
        LogInfo('Saved server profiles to ' + TargetFile, 'PROFILE')
      else
        LogError('Failed to write profiles to ' + TargetFile, 'PROFILE');
    finally
      RootObj.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.GetCount: Integer;
begin
  FLock.Enter;
  try
    Result := Length(FProfiles);
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.GetAllProfiles: TServerProfileArray;
begin
  FLock.Enter;
  try
    Result := Copy(FProfiles, 0, Length(FProfiles));
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.GetProfileByIndex(const AIndex: Integer): TServerProfile;
begin
  FLock.Enter;
  try
    if (AIndex >= 0) and (AIndex < Length(FProfiles)) then
      Result := FProfiles[AIndex]
    else
      Result := TServerProfile.CreateDefault('', 'Invalid Profile');
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.FindProfileByID(const AID: string; out AProfile: TServerProfile): Boolean;
var
  i: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    for i := 0 to High(FProfiles) do
    begin
      if SameText(FProfiles[i].ID, AID) then
      begin
        AProfile := FProfiles[i];
        Exit(True);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.FindProfileByName(const AName: string; out AProfile: TServerProfile): Boolean;
var
  i: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    for i := 0 to High(FProfiles) do
    begin
      if SameText(FProfiles[i].Name, AName) then
      begin
        AProfile := FProfiles[i];
        Exit(True);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.AddProfile(const AProfile: TServerProfile): Boolean;
var
  Existing: TServerProfile;
  Len: Integer;
begin
  Result := False;
  if Trim(AProfile.ID) = '' then Exit;

  FLock.Enter;
  try
    if FindProfileByID(AProfile.ID, Existing) then Exit; // Duplicate ID prevention

    Len := Length(FProfiles);
    SetLength(FProfiles, Len + 1);
    FProfiles[Len] := AProfile;
    Result := SaveToFile;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.UpdateProfile(const AProfile: TServerProfile): Boolean;
var
  i: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    for i := 0 to High(FProfiles) do
    begin
      if SameText(FProfiles[i].ID, AProfile.ID) then
      begin
        FProfiles[i] := AProfile;
        Result := SaveToFile;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.DeleteProfile(const AID: string): Boolean;
var
  i, j, Len: Integer;
  Found: Boolean;
begin
  Result := False;
  FLock.Enter;
  try
    Len := Length(FProfiles);
    Found := False;
    for i := 0 to Len - 1 do
    begin
      if SameText(FProfiles[i].ID, AID) then
      begin
        for j := i to Len - 2 do
          FProfiles[j] := FProfiles[j + 1];
        SetLength(FProfiles, Len - 1);
        Found := True;
        Break;
      end;
    end;

    if Found then
    begin
      if SameText(FDefaultProfileID, AID) and (Length(FProfiles) > 0) then
        FDefaultProfileID := FProfiles[0].ID;
      Result := SaveToFile;
    end;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.DuplicateProfile(const ASourceID: string; const ANewName: string): string;
var
  SourceProfile, NewProfile: TServerProfile;
begin
  Result := '';
  FLock.Enter;
  try
    if FindProfileByID(ASourceID, SourceProfile) then
    begin
      NewProfile := SourceProfile;
      NewProfile.ID := 'prof_' + FormatDateTime('yyyymmdd_hhnnsszzz', Now);
      if Trim(ANewName) <> '' then
        NewProfile.Name := ANewName
      else
        NewProfile.Name := SourceProfile.Name + ' (Copy)';

      if AddProfile(NewProfile) then
        Result := NewProfile.ID;
    end;
  finally
    FLock.Leave;
  end;
end;

function TProfileManager.GetDefaultProfile: TServerProfile;
begin
  FLock.Enter;
  try
    if not FindProfileByID(FDefaultProfileID, Result) then
    begin
      if Length(FProfiles) > 0 then
        Result := FProfiles[0]
      else
        Result := TServerProfile.CreateDefault('prof_default', 'Default Profile');
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TProfileManager.SetDefaultProfileID(const AID: string);
var
  P: TServerProfile;
begin
  FLock.Enter;
  try
    if FindProfileByID(AID, P) then
    begin
      FDefaultProfileID := AID;
      SaveToFile;
    end;
  finally
    FLock.Leave;
  end;
end;

end.

