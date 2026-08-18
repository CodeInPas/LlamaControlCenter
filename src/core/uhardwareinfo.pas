unit uhardwareinfo;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  {$IFDEF LINUX}
  BaseUnix, Unix,
  {$ENDIF}
  {$IFDEF DARWIN}
  MacOSAll,
  {$ENDIF}
  uconfigtypes, uformatting;

type
  { GPU Vendor Types }
  TGPUVendor = (gvNvidia, gvAMD, gvIntel, gvApple, gvUnknown);

  { Individual GPU Device Information }
  TGPUInfo = record
    Index: Integer;
    Name: string;
    Vendor: TGPUVendor;
    TotalVRAMBytes: Int64;
    FreeVRAMBytes: Int64;
    UsedVRAMBytes: Int64;
    DriverVersion: string;
    IsDedicated: Boolean;

    function GetVRAMUsagePercent: Double;
  end;
  TGPUInfoArray = array of TGPUInfo;

  { System Hardware Resource Snapshot }
  THardwareSnapshot = record
    Timestamp: TDateTime;

    // CPU Metrics
    CPUName: string;
    LogicalCores: Integer;
    PhysicalCores: Integer;

    // RAM Metrics
    TotalRAMBytes: Int64;
    AvailableRAMBytes: Int64;
    UsedRAMBytes: Int64;

    // GPU Metrics
    GPUs: TGPUInfoArray;
    PrimaryGPUIndex: Integer;

    function GetRAMUsagePercent: Double;
    function GetPrimaryGPU: TGPUInfo;
    function GetTotalVRAMBytes: Int64;
    function GetAvailableVRAMBytes: Int64;
  end;

  { Hardware Assessment Result for Model Execution }
  THardwareFitResult = record
    CanRun: Boolean;
    CanFullOffload: Boolean;
    RecommendedGPULayers: Integer;
    TotalModelLayers: Integer;
    EstimatedVRAMUsageBytes: Int64;
    EstimatedRAMUsageBytes: Int64;
    FitGrade: string; // e.g., 'Full GPU Offload', 'Hybrid (Fast)', 'Hybrid (Slow)', 'OOM Risk'
    Reasoning: string;
  end;

  { Static Hardware Telemetry Engine }
  THardwareInfo = class
  private
    class function QuerySystemRAM(out ATotal, AAvailable: Int64): Boolean; static;
    class function QueryCPUMetrics(out AName: string; out ALogical, APhysical: Integer): Boolean; static;
    class function QueryGPUs(out AGPUs: TGPUInfoArray): Boolean; static;

    {$IFDEF WINDOWS}
    class function QueryWindowsDXGI(out AGPUs: TGPUInfoArray): Boolean; static;
    {$ENDIF}
    {$IFDEF LINUX}
    class function QueryLinuxMemInfo(out ATotal, AAvailable: Int64): Boolean; static;
    {$ENDIF}
  public
    class function GetSnapshot: THardwareSnapshot; static;
    class function EvaluateModelFit(const AModelFileSizeBytes: Int64;
                                   const ATotalLayers: Integer;
                                   const AContextTokens: Cardinal;
                                   const AKVCacheType: string = 'f16'): THardwareFitResult; static;
    class function GPUVendorToString(const AVendor: TGPUVendor): string; static;
  end;

implementation

{$IFDEF WINDOWS}
type
  { Explicit Win32/Win64 Memory Status Type Definition }
  TMemoryStatusEx = record
    dwLength: DWORD;
    dwMemoryLoad: DWORD;
    ullTotalPhys: QWORD;
    ullAvailPhys: QWORD;
    ullTotalPageFile: QWORD;
    ullAvailPageFile: QWORD;
    ullTotalVirtual: QWORD;
    ullAvailVirtual: QWORD;
    ullAvailExtendedVirtual: QWORD;
  end;

function GlobalMemoryStatusEx(var lpBuffer: TMemoryStatusEx): WINBOOL; stdcall; external 'kernel32.dll' name 'GlobalMemoryStatusEx';

{ DXGI Dynamic Definitions for Windows Zero-Dependency Detection }
type
  TCreateDXGIFactory = function(const riid: TGUID; out ppFactory: Pointer): HRESULT; stdcall;

const
  IID_IDXGIFactory: TGUID = '{7b7166ec-21c7-44ae-b21a-c9ae321ae369}';
  DXGI_ADAPTER_FLAG_SOFTWARE = 2;

type
  TDXGI_ADAPTER_DESC = record
    Description: array[0..127] of WideChar;
    VendorId: UINT;
    DeviceId: UINT;
    SubSysId: UINT;
    Revision: UINT;
    DedicatedVideoMemory: SIZE_T;
    DedicatedSystemMemory: SIZE_T;
    SharedSystemMemory: SIZE_T;
    AdapterLuid: Int64;
    Flags: UINT;
  end;

  // COM Interface VMT Layouts
  IDXGIAdapterVmt = record
    QueryInterface: Pointer;
    AddRef: function(Self: Pointer): ULONG; stdcall;
    Release: function(Self: Pointer): ULONG; stdcall;
    SetPrivateData: Pointer;
    SetPrivateDataInterface: Pointer;
    GetPrivateData: Pointer;
    GetParent: Pointer;
    EnumOutputs: Pointer;
    GetDesc: function(Self: Pointer; out pDesc: TDXGI_ADAPTER_DESC): HRESULT; stdcall;
    CheckInterfaceSupport: Pointer;
  end;
  PIDXGIAdapterVmt = ^IDXGIAdapterVmt;
  PGenericDXGIAdapter = ^PIDXGIAdapterVmt;

  IDXGIFactoryVmt = record
    QueryInterface: Pointer;
    AddRef: function(Self: Pointer): ULONG; stdcall;
    Release: function(Self: Pointer): ULONG; stdcall;
    SetPrivateData: Pointer;
    SetPrivateDataInterface: Pointer;
    GetPrivateData: Pointer;
    GetParent: Pointer;
    EnumAdapters: function(Self: Pointer; Adapter: UINT; out ppAdapter: Pointer): HRESULT; stdcall;
    MakeWindowAssociation: Pointer;
    GetWindowAssociation: Pointer;
    CreateSwapChain: Pointer;
    CreateSoftwareAdapter: Pointer;
  end;
  PIDXGIFactoryVmt = ^IDXGIFactoryVmt;
  PGenericDXGIFactory = ^PIDXGIFactoryVmt;
{$ENDIF}

{ TGPUInfo }

function TGPUInfo.GetVRAMUsagePercent: Double;
begin
  if TotalVRAMBytes <= 0 then Exit(0.0);
  Result := (UsedVRAMBytes / TotalVRAMBytes) * 100.0;
  if Result > 100.0 then Result := 100.0;
end;

{ THardwareSnapshot }

function THardwareSnapshot.GetRAMUsagePercent: Double;
begin
  if TotalRAMBytes <= 0 then Exit(0.0);
  Result := (UsedRAMBytes / TotalRAMBytes) * 100.0;
  if Result > 100.0 then Result := 100.0;
end;

function THardwareSnapshot.GetPrimaryGPU: TGPUInfo;
begin
  if (PrimaryGPUIndex >= 0) and (PrimaryGPUIndex < Length(GPUs)) then
    Result := GPUs[PrimaryGPUIndex]
  else if Length(GPUs) > 0 then
    Result := GPUs[0]
  else
  begin
    Result.Index := -1;
    Result.Name := 'No Dedicated GPU Detected';
    Result.Vendor := gvUnknown;
    Result.TotalVRAMBytes := 0;
    Result.FreeVRAMBytes := 0;
    Result.UsedVRAMBytes := 0;
    Result.DriverVersion := '';
    Result.IsDedicated := False;
  end;
end;

function THardwareSnapshot.GetTotalVRAMBytes: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(GPUs) do
    if GPUs[i].IsDedicated then
      Inc(Result, GPUs[i].TotalVRAMBytes);
end;

function THardwareSnapshot.GetAvailableVRAMBytes: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(GPUs) do
    if GPUs[i].IsDedicated then
      Inc(Result, GPUs[i].FreeVRAMBytes);
end;

{ THardwareInfo - OS Specific Implementations }

class function THardwareInfo.QuerySystemRAM(out ATotal, AAvailable: Int64): Boolean;
{$IFDEF WINDOWS}
var
  MemStatus: TMemoryStatusEx;
begin
  FillChar(MemStatus, SizeOf(MemStatus), 0);
  MemStatus.dwLength := SizeOf(MemStatus);
  if GlobalMemoryStatusEx(MemStatus) then
  begin
    ATotal := Int64(MemStatus.ullTotalPhys);
    AAvailable := Int64(MemStatus.ullAvailPhys);
    Result := True;
  end
  else
  begin
    ATotal := 0;
    AAvailable := 0;
    Result := False;
  end;
end;
{$ELSE}
  {$IFDEF LINUX}
begin
  Result := QueryLinuxMemInfo(ATotal, AAvailable);
end;
  {$ELSE}
    {$IFDEF DARWIN}
var
  MIB: array[0..1] of Integer;
  Len: size_t;
  TotalMem: UInt64;
begin
  MIB[0] := CTL_HW;
  MIB[1] := HW_MEMSIZE;
  Len := SizeOf(TotalMem);
  if fpsysctl(@MIB[0], 2, @TotalMem, @Len, nil, 0) = 0 then
  begin
    ATotal := TotalMem;
    AAvailable := TotalMem div 2;
    Result := True;
  end
  else
  begin
    ATotal := 0;
    AAvailable := 0;
    Result := False;
  end;
end;
    {$ELSE}
begin
  ATotal := 0;
  AAvailable := 0;
  Result := False;
end;
    {$ENDIF}
  {$ENDIF}
{$ENDIF}

{$IFDEF LINUX}
class function THardwareInfo.QueryLinuxMemInfo(out ATotal, AAvailable: Int64): Boolean;
var
  F: TextFile;
  Line, Key: string;
  ValKb: Int64;
  PosColon: Integer;
begin
  ATotal := 0;
  AAvailable := 0;
  Result := False;
  if not FileExists('/proc/meminfo') then Exit;

  try
    AssignFile(F, '/proc/meminfo');
    Reset(F);
    while not EOF(F) do
    begin
      ReadLn(F, Line);
      PosColon := Pos(':', Line);
      if PosColon > 0 then
      begin
        Key := Trim(Copy(Line, 1, PosColon - 1));
        Line := Trim(Copy(Line, PosColon + 1, Length(Line)));
        ValKb := StrToInt64Def(Trim(Copy(Line, 1, Pos(' ', Line))), 0);

        if Key = 'MemTotal' then
          ATotal := ValKb * 1024
        else if Key = 'MemAvailable' then
          AAvailable := ValKb * 1024;
      end;
    end;
    CloseFile(F);
    Result := (ATotal > 0);
  except
    Result := False;
  end;
end;
{$ENDIF}

class function THardwareInfo.QueryCPUMetrics(out AName: string; out ALogical, APhysical: Integer): Boolean;
begin
  ALogical := GetCPUCount;
  if ALogical <= 0 then ALogical := 1;

  if ALogical >= 4 then
    APhysical := ALogical div 2
  else
    APhysical := ALogical;

  {$IFDEF WINDOWS}
  AName := SysUtils.GetEnvironmentVariable('PROCESSOR_IDENTIFIER');
  if AName = '' then
    AName := 'Generic x86_64 Processor';
  {$ELSE}
  AName := 'Generic CPU Core Cluster';
  {$ENDIF}

  Result := True;
end;

{$IFDEF WINDOWS}
class function THardwareInfo.QueryWindowsDXGI(out AGPUs: TGPUInfoArray): Boolean;
var
  HDXGI: HMODULE;
  CreateDXGIFactoryFunc: TCreateDXGIFactory;
  Factory: PGenericDXGIFactory;
  Adapter: PGenericDXGIAdapter;
  AdapterDesc: TDXGI_ADAPTER_DESC;
  AdapterIndex: UINT;
  GPU: TGPUInfo;
  VendorUpper: string;
begin
  SetLength(AGPUs, 0);
  Result := False;

  HDXGI := LoadLibrary('dxgi.dll');
  if HDXGI = 0 then Exit;

  try
    CreateDXGIFactoryFunc := TCreateDXGIFactory(GetProcAddress(HDXGI, 'CreateDXGIFactory'));
    if not Assigned(CreateDXGIFactoryFunc) then Exit;

    if Failed(CreateDXGIFactoryFunc(IID_IDXGIFactory, Pointer(Factory))) then Exit;

    try
      AdapterIndex := 0;
      while Factory^^.EnumAdapters(Factory, AdapterIndex, Pointer(Adapter)) = S_OK do
      begin
        try
          if Adapter^^.GetDesc(Adapter, AdapterDesc) = S_OK then
          begin
            if (AdapterDesc.Flags and DXGI_ADAPTER_FLAG_SOFTWARE) = 0 then
            begin
              GPU.Index := AdapterIndex;
              GPU.Name := WideCharToString(PWideChar(@AdapterDesc.Description[0]));
              GPU.TotalVRAMBytes := Int64(AdapterDesc.DedicatedVideoMemory);
              GPU.FreeVRAMBytes := GPU.TotalVRAMBytes;
              GPU.UsedVRAMBytes := 0;
              GPU.DriverVersion := 'DirectX Video Adapter';
              GPU.IsDedicated := (AdapterDesc.DedicatedVideoMemory > 256 * 1024 * 1024);

              VendorUpper := UpperCase(GPU.Name);
              if (AdapterDesc.VendorId = $10DE) or (Pos('NVIDIA', VendorUpper) > 0) or (Pos('GEFORCE', VendorUpper) > 0) or (Pos('RTX', VendorUpper) > 0) then
                GPU.Vendor := gvNvidia
              else if (AdapterDesc.VendorId = $1002) or (Pos('AMD', VendorUpper) > 0) or (Pos('RADEON', VendorUpper) > 0) then
                GPU.Vendor := gvAMD
              else if (AdapterDesc.VendorId = $8086) or (Pos('INTEL', VendorUpper) > 0) or (Pos('ARC', VendorUpper) > 0) then
                GPU.Vendor := gvIntel
              else
                GPU.Vendor := gvUnknown;

              SetLength(AGPUs, Length(AGPUs) + 1);
              AGPUs[High(AGPUs)] := GPU;
            end;
          end;
        finally
          Adapter^^.Release(Adapter);
        end;
        Inc(AdapterIndex);
      end;
      Result := (Length(AGPUs) > 0);
    finally
      Factory^^.Release(Factory);
    end;
  finally
    FreeLibrary(HDXGI);
  end;
end;
{$ENDIF}

class function THardwareInfo.QueryGPUs(out AGPUs: TGPUInfoArray): Boolean;
begin
  SetLength(AGPUs, 0);
  {$IFDEF WINDOWS}
  Result := QueryWindowsDXGI(AGPUs);
  {$ELSE}
  Result := False;
  {$ENDIF}

  if not Result or (Length(AGPUs) = 0) then
  begin
    SetLength(AGPUs, 1);
    AGPUs[0].Index := 0;
    AGPUs[0].Name := 'Default System Graphics';
    AGPUs[0].Vendor := gvUnknown;
    AGPUs[0].TotalVRAMBytes := 0;
    AGPUs[0].FreeVRAMBytes := 0;
    AGPUs[0].UsedVRAMBytes := 0;
    AGPUs[0].DriverVersion := 'N/A';
    AGPUs[0].IsDedicated := False;
    Result := True;
  end;
end;

class function THardwareInfo.GetSnapshot: THardwareSnapshot;
var
  i: Integer;
  MaxVRAM: Int64;
begin
  Result.Timestamp := Now;
  QuerySystemRAM(Result.TotalRAMBytes, Result.AvailableRAMBytes);
  Result.UsedRAMBytes := Result.TotalRAMBytes - Result.AvailableRAMBytes;
  if Result.UsedRAMBytes < 0 then Result.UsedRAMBytes := 0;

  QueryCPUMetrics(Result.CPUName, Result.LogicalCores, Result.PhysicalCores);
  QueryGPUs(Result.GPUs);

  Result.PrimaryGPUIndex := 0;
  MaxVRAM := -1;
  for i := 0 to High(Result.GPUs) do
  begin
    if Result.GPUs[i].TotalVRAMBytes > MaxVRAM then
    begin
      MaxVRAM := Result.GPUs[i].TotalVRAMBytes;
      Result.PrimaryGPUIndex := i;
    end;
  end;
end;

class function THardwareInfo.EvaluateModelFit(const AModelFileSizeBytes: Int64;
  const ATotalLayers: Integer; const AContextTokens: Cardinal; const AKVCacheType: string): THardwareFitResult;
var
  Snapshot: THardwareSnapshot;
  PrimaryGPU: TGPUInfo;
  KVCacheBytes: Int64;
  BytesPerKVElem: Double;
  TotalRequiredBytes: Int64;
  TotalLayersSafe: Integer;
  BytesPerLayer: Int64;
  VRAMHeadroom: Int64;
  OffloadableLayers: Integer;
begin
  Snapshot := GetSnapshot;
  PrimaryGPU := Snapshot.GetPrimaryGPU;

  TotalLayersSafe := ATotalLayers;
  if TotalLayersSafe <= 0 then TotalLayersSafe := 33;

  if AKVCacheType = 'q8_0' then
    BytesPerKVElem := 1.0
  else if AKVCacheType = 'q4_0' then
    BytesPerKVElem := 0.5
  else
    BytesPerKVElem := 2.0;

  KVCacheBytes := Round(2 * TotalLayersSafe * 4096 * BytesPerKVElem * (AContextTokens / 2048.0));
  TotalRequiredBytes := AModelFileSizeBytes + KVCacheBytes + (384 * 1024 * 1024);

  BytesPerLayer := AModelFileSizeBytes div TotalLayersSafe;
  if BytesPerLayer <= 0 then BytesPerLayer := 128 * 1024 * 1024;

  Result.TotalModelLayers := TotalLayersSafe;
  Result.CanRun := (Snapshot.TotalRAMBytes + PrimaryGPU.TotalVRAMBytes) >= TotalRequiredBytes;

  if PrimaryGPU.IsDedicated and (PrimaryGPU.TotalVRAMBytes > 0) then
  begin
    VRAMHeadroom := PrimaryGPU.TotalVRAMBytes - (768 * 1024 * 1024);
    if VRAMHeadroom < 0 then VRAMHeadroom := 0;

    if VRAMHeadroom >= TotalRequiredBytes then
    begin
      Result.CanFullOffload := True;
      Result.RecommendedGPULayers := TotalLayersSafe + 1;
      Result.EstimatedVRAMUsageBytes := TotalRequiredBytes;
      Result.EstimatedRAMUsageBytes := 512 * 1024 * 1024;
      Result.FitGrade := 'Full GPU Offload';
      Result.Reasoning := Format('Model fits completely in %s (%s VRAM). Maximum generation speed.',
        [PrimaryGPU.Name, FormatBytes(PrimaryGPU.TotalVRAMBytes)]);
    end
    else
    begin
      Result.CanFullOffload := False;
      OffloadableLayers := (VRAMHeadroom - KVCacheBytes) div BytesPerLayer;
      if OffloadableLayers > TotalLayersSafe then
        OffloadableLayers := TotalLayersSafe
      else if OffloadableLayers < 0 then
        OffloadableLayers := 0;

      Result.RecommendedGPULayers := OffloadableLayers;
      Result.EstimatedVRAMUsageBytes := (OffloadableLayers * BytesPerLayer) + KVCacheBytes;
      Result.EstimatedRAMUsageBytes := ((TotalLayersSafe - OffloadableLayers) * BytesPerLayer) + (512 * 1024 * 1024);

      if OffloadableLayers > (TotalLayersSafe div 2) then
      begin
        Result.FitGrade := 'Hybrid (Fast)';
        Result.Reasoning := Format('Partial offload: %d/%d layers in GPU VRAM, remainder in RAM.',
          [OffloadableLayers, TotalLayersSafe]);
      end
      else
      begin
        Result.FitGrade := 'Hybrid (Limited VRAM)';
        Result.Reasoning := Format('Only %d/%d layers fit in VRAM. Inference speed will be RAM-bandwidth bound.',
          [OffloadableLayers, TotalLayersSafe]);
      end;
    end;
  end
  else
  begin
    Result.CanFullOffload := False;
    Result.RecommendedGPULayers := 0;
    Result.EstimatedVRAMUsageBytes := 0;
    Result.EstimatedRAMUsageBytes := TotalRequiredBytes;
    Result.FitGrade := 'CPU Only';
    Result.Reasoning := Format('No dedicated GPU detected. Model will run entirely in System RAM (%s available).',
      [FormatBytes(Snapshot.AvailableRAMBytes)]);
  end;

  if not Result.CanRun then
  begin
    Result.FitGrade := 'OOM Risk';
    Result.Reasoning := Format('Model requires ~%s but total system memory is insufficient.',
      [FormatBytes(TotalRequiredBytes)]);
  end;
end;

class function THardwareInfo.GPUVendorToString(const AVendor: TGPUVendor): string;
begin
  case AVendor of
    gvNvidia: Result := 'NVIDIA';
    gvAMD:    Result := 'AMD';
    gvIntel:  Result := 'Intel';
    gvApple:  Result := 'Apple';
    else      Result := 'Unknown';
  end;
end;

end.
