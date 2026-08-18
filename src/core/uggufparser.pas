unit uggufparser;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math, ugguftypes, ulogger;

type
  { GGUF Binary File Parser Engine }
  TGGUFParser = class
  private
    class function ReadGGUFString(const AStream: TStream; const AVersion: UInt32): string; static;
    class function ReadMetadataValue(const AStream: TStream; const AValueType: TGGUFValueType;
                                     const AVersion: UInt32): TGGUFMetadataValue; static;
    class function ReadTensorInfo(const AStream: TStream; const AVersion: UInt32): TGGUFTensorInfo; static;

    class function FindMetadataKV(const AList: TGGUFMetadataKVArray; const AKey: string;
                                 out AValue: TGGUFMetadataValue): Boolean; static;
    class function GetMetadataString(const AList: TGGUFMetadataKVArray; const AKey: string;
                                    const ADefault: string = ''): string; static;
    class function GetMetadataUInt64(const AList: TGGUFMetadataKVArray; const AKey: string;
                                    const ADefault: UInt64 = 0): UInt64; static;
    class function GetMetadataSingle(const AList: TGGUFMetadataKVArray; const AKey: string;
                                    const ADefault: Single = 0.0): Single; static;
    class procedure ExtractModelSummary(var AModelInfo: TGGUFModelInfo); static;
  public
    class function ParseFile(const AFilePath: string; const AHeaderAndMetaOnly: Boolean = False): TGGUFModelInfo; static;
    class function QuickInspect(const AFilePath: string): TGGUFModelInfo; static;
    class function IsValidGGUF(const AFilePath: string): Boolean; static;
  end;

implementation

{ TGGUFParser Private Methods }

class function TGGUFParser.ReadGGUFString(const AStream: TStream; const AVersion: UInt32): string;
var
  StrLen64: UInt64;
  StrLen32: UInt32;
  LenToRead: Int64;
  RawBytes: TBytes;
begin
  Result := '';
  if AVersion = GGUF_VERSION_V1 then
  begin
    if AStream.Read(StrLen32, SizeOf(UInt32)) <> SizeOf(UInt32) then Exit;
    LenToRead := StrLen32;
  end
  else
  begin
    if AStream.Read(StrLen64, SizeOf(UInt64)) <> SizeOf(UInt64) then Exit;
    LenToRead := StrLen64;
  end;

  if (LenToRead <= 0) or (LenToRead > 10 * 1024 * 1024) then Exit; // 10MB safety bound

  SetLength(RawBytes, LenToRead);
  if AStream.Read(RawBytes[0], LenToRead) = LenToRead then
    Result := TEncoding.UTF8.GetString(RawBytes);
end;

class function TGGUFParser.ReadMetadataValue(const AStream: TStream; const AValueType: TGGUFValueType;
  const AVersion: UInt32): TGGUFMetadataValue;
var
  ArrTypeInt: UInt32;
  ArrLen: UInt64;
  ArrLen32: UInt32;
  i: Integer;
  ElemVal: TGGUFMetadataValue;
  PreviewList: TStringList;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.ValueType := AValueType;

  case AValueType of
    gvtUInt8:   AStream.Read(Result.AsUInt8, SizeOf(UInt8));
    gvtInt8:    AStream.Read(Result.AsInt8, SizeOf(Int8));
    gvtUInt16:  AStream.Read(Result.AsUInt16, SizeOf(UInt16));
    gvtInt16:   AStream.Read(Result.AsInt16, SizeOf(Int16));
    gvtUInt32:  AStream.Read(Result.AsUInt32, SizeOf(UInt32));
    gvtInt32:   AStream.Read(Result.AsInt32, SizeOf(Int32));
    gvtFloat32: AStream.Read(Result.AsFloat32, SizeOf(Single));
    gvtBool:    AStream.Read(Result.AsBool, SizeOf(Boolean));
    gvtString:  Result.AsString := ReadGGUFString(AStream, AVersion);
    gvtUInt64:  AStream.Read(Result.AsUInt64, SizeOf(UInt64));
    gvtInt64:   AStream.Read(Result.AsInt64, SizeOf(Int64));
    gvtFloat64: AStream.Read(Result.AsFloat64, SizeOf(Double));

    gvtArray:
    begin
      if AStream.Read(ArrTypeInt, SizeOf(UInt32)) <> SizeOf(UInt32) then Exit;
      Result.ArrayType := TGGUFValueType(ArrTypeInt);

      if AVersion = GGUF_VERSION_V1 then
      begin
        if AStream.Read(ArrLen32, SizeOf(UInt32)) <> SizeOf(UInt32) then Exit;
        ArrLen := ArrLen32;
      end
      else
      begin
        if AStream.Read(ArrLen, SizeOf(UInt64)) <> SizeOf(UInt64) then Exit;
      end;

      Result.ArrayLen := ArrLen;
      PreviewList := TStringList.Create;
      try
        for i := 0 to Integer(ArrLen) - 1 do
        begin
          ElemVal := ReadMetadataValue(AStream, Result.ArrayType, AVersion);
          if i < 5 then // Ambil 5 sampel pertama sebagai preview
          begin
            if Result.ArrayType = gvtString then
              PreviewList.Add('"' + ElemVal.AsString + '"')
            else if Result.ArrayType in [gvtUInt8, gvtUInt16, gvtUInt32, gvtUInt64] then
              PreviewList.Add(UIntToStr(ElemVal.AsUInt64))
            else if Result.ArrayType in [gvtInt8, gvtInt16, gvtInt32, gvtInt64] then
              PreviewList.Add(IntToStr(ElemVal.AsInt64))
            else if Result.ArrayType in [gvtFloat32, gvtFloat64] then
              PreviewList.Add(Format('%.2f', [ElemVal.AsFloat64]))
            else if Result.ArrayType = gvtBool then
              PreviewList.Add(BoolToStr(ElemVal.AsBool, True));
          end;
        end;

        if ArrLen > 5 then
          Result.ArrayStringPreview := Format('[%s, ... (+%d more)]', [PreviewList.CommaText, ArrLen - 5])
        else
          Result.ArrayStringPreview := Format('[%s]', [PreviewList.CommaText]);
      finally
        PreviewList.Free;
      end;
    end;
  end;
end;

class function TGGUFParser.ReadTensorInfo(const AStream: TStream; const AVersion: UInt32): TGGUFTensorInfo;
var
  i: Integer;
  DimVal32: UInt32;
  DimVal64: UInt64;
  TensorTypeInt: UInt32;
  ElementsCount: UInt64;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Name := ReadGGUFString(AStream, AVersion);
  if AStream.Read(Result.nDims, SizeOf(UInt32)) <> SizeOf(UInt32) then Exit;

  ElementsCount := 1;
  for i := 0 to Min(Integer(Result.nDims) - 1, 3) do
  begin
    if AVersion = GGUF_VERSION_V1 then
    begin
      if AStream.Read(DimVal32, SizeOf(UInt32)) = SizeOf(UInt32) then
        Result.Dimensions[i] := DimVal32;
    end
    else
    begin
      if AStream.Read(DimVal64, SizeOf(UInt64)) = SizeOf(UInt64) then
        Result.Dimensions[i] := DimVal64;
    end;
    ElementsCount := ElementsCount * Result.Dimensions[i];
  end;

  // Lewati dimensi di atas rank 4 jika ada
  if Result.nDims > 4 then
  begin
    for i := 4 to Integer(Result.nDims) - 1 do
    begin
      if AVersion = GGUF_VERSION_V1 then
        AStream.Read(DimVal32, SizeOf(UInt32))
      else
        AStream.Read(DimVal64, SizeOf(UInt64));
    end;
  end;

  if AStream.Read(TensorTypeInt, SizeOf(UInt32)) <> SizeOf(UInt32) then Exit;
  Result.TensorType := IntegerToGGMLType(TensorTypeInt);

  if AStream.Read(Result.Offset, SizeOf(UInt64)) <> SizeOf(UInt64) then Exit;

  // Estimasi ukuran byte tensor
  Result.SizeBytes := Round(ElementsCount * (GGMLTypeToTypeSize(Result.TensorType) / 8.0));
end;

class function TGGUFParser.FindMetadataKV(const AList: TGGUFMetadataKVArray; const AKey: string;
  out AValue: TGGUFMetadataValue): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(AList) do
  begin
    if SameText(AList[i].Key, AKey) then
    begin
      AValue := AList[i].Value;
      Exit(True);
    end;
  end;
end;

class function TGGUFParser.GetMetadataString(const AList: TGGUFMetadataKVArray; const AKey: string;
  const ADefault: string): string;
var
  Val: TGGUFMetadataValue;
begin
  if FindMetadataKV(AList, AKey, Val) then
  begin
    if Val.ValueType = gvtString then
      Exit(Val.AsString)
    else if Val.ValueType = gvtArray then
      Exit(Val.ArrayStringPreview);
  end;
  Result := ADefault;
end;

class function TGGUFParser.GetMetadataUInt64(const AList: TGGUFMetadataKVArray; const AKey: string;
  const ADefault: UInt64): UInt64;
var
  Val: TGGUFMetadataValue;
begin
  if FindMetadataKV(AList, AKey, Val) then
  begin
    case Val.ValueType of
      gvtUInt8:  Exit(Val.AsUInt8);
      gvtUInt16: Exit(Val.AsUInt16);
      gvtUInt32: Exit(Val.AsUInt32);
      gvtUInt64: Exit(Val.AsUInt64);
      gvtInt8:   if Val.AsInt8 >= 0 then Exit(Val.AsInt8);
      gvtInt16:  if Val.AsInt16 >= 0 then Exit(Val.AsInt16);
      gvtInt32:  if Val.AsInt32 >= 0 then Exit(Val.AsInt32);
      gvtInt64:  if Val.AsInt64 >= 0 then Exit(Val.AsInt64);
    end;
  end;
  Result := ADefault;
end;

class function TGGUFParser.GetMetadataSingle(const AList: TGGUFMetadataKVArray; const AKey: string;
  const ADefault: Single): Single;
var
  Val: TGGUFMetadataValue;
begin
  if FindMetadataKV(AList, AKey, Val) then
  begin
    if Val.ValueType = gvtFloat32 then
      Exit(Val.AsFloat32)
    else if Val.ValueType = gvtFloat64 then
      Exit(Single(Val.AsFloat64));
  end;
  Result := ADefault;
end;

class procedure TGGUFParser.ExtractModelSummary(var AModelInfo: TGGUFModelInfo);
var
  Arch: string;
begin
  AModelInfo.Architecture := GetMetadataString(AModelInfo.MetadataList, 'general.architecture', 'unknown');
  Arch := AModelInfo.Architecture;

  AModelInfo.ModelName := GetMetadataString(AModelInfo.MetadataList, 'general.name', ChangeFileExt(AModelInfo.FileName, ''));
  AModelInfo.Author := GetMetadataString(AModelInfo.MetadataList, 'general.author', '');
  AModelInfo.Description := GetMetadataString(AModelInfo.MetadataList, 'general.description', '');
  AModelInfo.License := GetMetadataString(AModelInfo.MetadataList, 'general.license', '');
  AModelInfo.QuantizationType := GetMetadataString(AModelInfo.MetadataList, 'general.file_type', '');

  if AModelInfo.QuantizationType = '' then
    AModelInfo.QuantizationType := GetMetadataString(AModelInfo.MetadataList, 'general.quantization_version', 'Standard GGUF');

  AModelInfo.Alignment := UInt32(GetMetadataUInt64(AModelInfo.MetadataList, 'general.alignment', GGUF_DEFAULT_ALIGNMENT));

  // Hyperparameters
  AModelInfo.ContextLength := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.context_length', 4096);
  AModelInfo.EmbeddingLength := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.embedding_length', 4096);
  AModelInfo.BlockCount := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.block_count', 32);
  AModelInfo.FeedForwardLength := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.feed_forward_length', 11008);
  AModelInfo.AttentionHeadCount := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.attention.head_count', 32);
  AModelInfo.AttentionHeadCountKV := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.attention.head_count_kv', AModelInfo.AttentionHeadCount);
  AModelInfo.RopeDimensionCount := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.rope.dimension_count', 128);
  AModelInfo.RopeFreqBase := GetMetadataSingle(AModelInfo.MetadataList, Arch + '.rope.freq_base', 10000.0);
  AModelInfo.RopeFreqScale := GetMetadataSingle(AModelInfo.MetadataList, Arch + '.rope.freq_scale', 1.0);
  AModelInfo.VocabSize := GetMetadataUInt64(AModelInfo.MetadataList, Arch + '.vocab_size', 32000);

  // Estimasi RAM & VRAM baseline
  AModelInfo.EstimatedVRAMBytes := AModelInfo.FileSize + (512 * 1024 * 1024);
  AModelInfo.EstimatedRAMBytes := Round(AModelInfo.FileSize * 0.15) + (256 * 1024 * 1024);
end;

{ TGGUFParser Public Methods }

class function TGGUFParser.IsValidGGUF(const AFilePath: string): Boolean;
var
  FS: TFileStream;
  Magic: UInt32;
begin
  Result := False;
  if not FileExists(AFilePath) then Exit;

  try
    FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size >= SizeOf(TGGUFHeader) then
      begin
        if FS.Read(Magic, SizeOf(UInt32)) = SizeOf(UInt32) then
          Result := (Magic = GGUF_MAGIC);
      end;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

class function TGGUFParser.QuickInspect(const AFilePath: string): TGGUFModelInfo;
begin
  Result := ParseFile(AFilePath, True);
end;

class function TGGUFParser.ParseFile(const AFilePath: string; const AHeaderAndMetaOnly: Boolean): TGGUFModelInfo;
var
  FS: TFileStream;
  Header: TGGUFHeader;
  i: Integer;
  MetaKey: string;
  ValTypeInt: UInt32;
  ValType: TGGUFValueType;
  TotalParamCount: UInt64;
  DimProd: UInt64;
  d: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.FilePath := AFilePath;
  Result.FileName := ExtractFileName(AFilePath);

  if not FileExists(AFilePath) then
  begin
    LogWarn('GGUF file not found: ' + AFilePath, 'GGUF');
    Exit;
  end;

  FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    Result.FileSize := FS.Size;
    if FS.Read(Header, SizeOf(TGGUFHeader)) <> SizeOf(TGGUFHeader) then
    begin
      LogError('Unable to read GGUF header from ' + AFilePath, 'GGUF');
      Exit;
    end;

    if Header.Magic <> GGUF_MAGIC then
    begin
      LogError('Invalid GGUF magic header in ' + AFilePath, 'GGUF');
      Exit;
    end;

    Result.Version := Header.Version;
    Result.TotalTensors := Header.TensorCount;
    Result.TotalMetadataKV := Header.MetadataKVCount;

    // 1. Baca Metadata Key-Value pairs
    SetLength(Result.MetadataList, Header.MetadataKVCount);
    for i := 0 to Integer(Header.MetadataKVCount) - 1 do
    begin
      MetaKey := ReadGGUFString(FS, Result.Version);
      if FS.Read(ValTypeInt, SizeOf(UInt32)) <> SizeOf(UInt32) then Break;
      ValType := TGGUFValueType(ValTypeInt);

      Result.MetadataList[i].Key := MetaKey;
      Result.MetadataList[i].Value := ReadMetadataValue(FS, ValType, Result.Version);
    end;

    ExtractModelSummary(Result);

    // 2. Baca Informasi Tensor
    TotalParamCount := 0;
    if not AHeaderAndMetaOnly and (Header.TensorCount > 0) then
    begin
      SetLength(Result.TensorList, Header.TensorCount);
      for i := 0 to Integer(Header.TensorCount) - 1 do
      begin
        Result.TensorList[i] := ReadTensorInfo(FS, Result.Version);

        DimProd := 1;
        for d := 0 to Min(Integer(Result.TensorList[i].nDims) - 1, 3) do
          DimProd := DimProd * Result.TensorList[i].Dimensions[d];

        TotalParamCount := TotalParamCount + DimProd;
      end;
    end;

    Result.TotalParameters := TotalParamCount;
  finally
    FS.Free;
  end;
end;

end.
