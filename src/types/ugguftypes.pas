unit ugguftypes;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes;

const
  // GGUF Magic Number: 'GGUF' in Little-Endian ($46554747)
  GGUF_MAGIC = $46554747;

  // Supported GGUF Specifications
  GGUF_VERSION_V1 = 1;
  GGUF_VERSION_V2 = 2;
  GGUF_VERSION_V3 = 3;

  // Default byte alignment if not specified in metadata
  GGUF_DEFAULT_ALIGNMENT = 32;

type
  { GGUF Value Types for Metadata Key-Value pairs }
  TGGUFValueType = (
    gvtUInt8   = 0,
    gvtInt8    = 1,
    gvtUInt16  = 2,
    gvtInt16   = 3,
    gvtUInt32  = 4,
    gvtInt32   = 5,
    gvtFloat32 = 6,
    gvtBool    = 7,
    gvtString  = 8,
    gvtArray   = 9,
    gvtUInt64  = 10,
    gvtInt64   = 11,
    gvtFloat64 = 12
  );

  { GGML Quantization & Numeric Tensor Types }
  TGGMLType = (
    ggmlF32     = 0,
    ggmlF16     = 1,
    ggmlQ4_0    = 2,
    ggmlQ4_1    = 3,
    ggmlQ5_0    = 6,
    ggmlQ5_1    = 7,
    ggmlQ8_0    = 8,
    ggmlQ8_1    = 9,
    ggmlQ2_K    = 10,
    ggmlQ3_K    = 11,
    ggmlQ4_K    = 12,
    ggmlQ5_K    = 13,
    ggmlQ6_K    = 14,
    ggmlQ8_K    = 15,
    ggmlIQ2_XXS = 16,
    ggmlIQ2_XS  = 17,
    ggmlIQ3_XXS = 18,
    ggmlIQ1_S   = 19,
    ggmlIQ4_NL  = 20,
    ggmlIQ3_S   = 21,
    ggmlIQ2_S   = 22,
    ggmlIQ4_XS  = 23,
    ggmlI8      = 24,
    ggmlI16     = 25,
    ggmlI32     = 26,
    ggmlI64     = 27,
    ggmlF64     = 28,
    ggmlIQ1_M   = 29,
    ggmlBF16    = 30,
    ggmlQ4_0_4_4= 31,
    ggmlQ4_0_4_8= 32,
    ggmlQ4_0_8_8= 33,
    ggmlUnknown = 255
  );

  { Raw Binary Header in GGUF File }
  TGGUFHeader = packed record
    Magic: UInt32;
    Version: UInt32;
    TensorCount: UInt64;
    MetadataKVCount: UInt64;
  end;

  { Dynamic Metadata Value Storage }
  TGGUFMetadataValue = record
    ValueType: TGGUFValueType;
    AsUInt8: UInt8;
    AsInt8: Int8;
    AsUInt16: UInt16;
    AsInt16: Int16;
    AsUInt32: UInt32;
    AsInt32: Int32;
    AsFloat32: Single;
    AsBool: Boolean;
    AsString: string;
    AsUInt64: UInt64;
    AsInt64: Int64;
    AsFloat64: Double;
    ArrayType: TGGUFValueType;
    ArrayLen: UInt64;
    ArrayStringPreview: string;
  end;

  { Single Metadata Entry (Key-Value) }
  TGGUFMetadataKV = record
    Key: string;
    Value: TGGUFMetadataValue;
  end;
  TGGUFMetadataKVArray = array of TGGUFMetadataKV;

  { Tensor Information Struct }
  TGGUFTensorInfo = record
    Name: string;
    nDims: UInt32;
    Dimensions: array[0..3] of UInt64;
    TensorType: TGGMLType;
    Offset: UInt64;
    SizeBytes: UInt64;
  end;
  TGGUFTensorInfoArray = array of TGGUFTensorInfo;

  { High-Level Parsed Model Summary for GUI / Inspector }
  TGGUFModelInfo = record
    FilePath: string;
    FileName: string;
    FileSize: Int64;
    Version: UInt32;
    Alignment: UInt32;
    Architecture: string;
    ModelName: string;
    Author: string;
    Description: string;
    License: string;
    QuantizationType: string;

    // Model Dimensions & Hyperparameters
    ContextLength: UInt64;
    EmbeddingLength: UInt64;
    BlockCount: UInt64;          // Layer count
    FeedForwardLength: UInt64;
    AttentionHeadCount: UInt64;
    AttentionHeadCountKV: UInt64;
    RopeDimensionCount: UInt64;
    RopeFreqBase: Single;
    RopeFreqScale: Single;
    VocabSize: UInt64;

    // Calculated & System Properties
    TotalParameters: UInt64;
    TotalTensors: UInt64;
    TotalMetadataKV: UInt64;
    EstimatedVRAMBytes: Int64;
    EstimatedRAMBytes: Int64;

    // Detailed Lists
    MetadataList: TGGUFMetadataKVArray;
    TensorList: TGGUFTensorInfoArray;
  end;

{ Helper Functions }
function GGUFValueTypeToString(const AType: TGGUFValueType): string;
function GGMLTypeToString(const AType: TGGMLType): string;
function IntegerToGGMLType(const AValue: UInt32): TGGMLType;
function GGMLTypeToTypeSize(const AType: TGGMLType): Double;
function EstimateParameterCountStr(const ATotalParams: UInt64): string;

implementation

function GGUFValueTypeToString(const AType: TGGUFValueType): string;
begin
  case AType of
    gvtUInt8:   Result := 'UINT8';
    gvtInt8:    Result := 'INT8';
    gvtUInt16:  Result := 'UINT16';
    gvtInt16:   Result := 'INT16';
    gvtUInt32:  Result := 'UINT32';
    gvtInt32:   Result := 'INT32';
    gvtFloat32: Result := 'FLOAT32';
    gvtBool:    Result := 'BOOL';
    gvtString:  Result := 'STRING';
    gvtArray:   Result := 'ARRAY';
    gvtUInt64:  Result := 'UINT64';
    gvtInt64:   Result := 'INT64';
    gvtFloat64: Result := 'FLOAT64';
    else        Result := 'UNKNOWN';
  end;
end;

function GGMLTypeToString(const AType: TGGMLType): string;
begin
  case AType of
    ggmlF32:      Result := 'F32';
    ggmlF16:      Result := 'F16';
    ggmlQ4_0:     Result := 'Q4_0';
    ggmlQ4_1:     Result := 'Q4_1';
    ggmlQ5_0:     Result := 'Q5_0';
    ggmlQ5_1:     Result := 'Q5_1';
    ggmlQ8_0:     Result := 'Q8_0';
    ggmlQ8_1:     Result := 'Q8_1';
    ggmlQ2_K:     Result := 'Q2_K';
    ggmlQ3_K:     Result := 'Q3_K';
    ggmlQ4_K:     Result := 'Q4_K_M';
    ggmlQ5_K:     Result := 'Q5_K_M';
    ggmlQ6_K:     Result := 'Q6_K';
    ggmlQ8_K:     Result := 'Q8_K';
    ggmlIQ2_XXS:  Result := 'IQ2_XXS';
    ggmlIQ2_XS:   Result := 'IQ2_XS';
    ggmlIQ3_XXS:  Result := 'IQ3_XXS';
    ggmlIQ1_S:    Result := 'IQ1_S';
    ggmlIQ4_NL:   Result := 'IQ4_NL';
    ggmlIQ3_S:    Result := 'IQ3_S';
    ggmlIQ2_S:    Result := 'IQ2_S';
    ggmlIQ4_XS:   Result := 'IQ4_XS';
    ggmlI8:       Result := 'I8';
    ggmlI16:      Result := 'I16';
    ggmlI32:      Result := 'I32';
    ggmlI64:      Result := 'I64';
    ggmlF64:      Result := 'F64';
    ggmlIQ1_M:    Result := 'IQ1_M';
    ggmlBF16:     Result := 'BF16';
    ggmlQ4_0_4_4: Result := 'Q4_0_4_4';
    ggmlQ4_0_4_8: Result := 'Q4_0_4_8';
    ggmlQ4_0_8_8: Result := 'Q4_0_8_8';
    else          Result := 'UNKNOWN';
  end;
end;

function IntegerToGGMLType(const AValue: UInt32): TGGMLType;
begin
  case AValue of
    0:  Result := ggmlF32;
    1:  Result := ggmlF16;
    2:  Result := ggmlQ4_0;
    3:  Result := ggmlQ4_1;
    6:  Result := ggmlQ5_0;
    7:  Result := ggmlQ5_1;
    8:  Result := ggmlQ8_0;
    9:  Result := ggmlQ8_1;
    10: Result := ggmlQ2_K;
    11: Result := ggmlQ3_K;
    12: Result := ggmlQ4_K;
    13: Result := ggmlQ5_K;
    14: Result := ggmlQ6_K;
    15: Result := ggmlQ8_K;
    16: Result := ggmlIQ2_XXS;
    17: Result := ggmlIQ2_XS;
    18: Result := ggmlIQ3_XXS;
    19: Result := ggmlIQ1_S;
    20: Result := ggmlIQ4_NL;
    21: Result := ggmlIQ3_S;
    22: Result := ggmlIQ2_S;
    23: Result := ggmlIQ4_XS;
    24: Result := ggmlI8;
    25: Result := ggmlI16;
    26: Result := ggmlI32;
    27: Result := ggmlI64;
    28: Result := ggmlF64;
    29: Result := ggmlIQ1_M;
    30: Result := ggmlBF16;
    31: Result := ggmlQ4_0_4_4;
    32: Result := ggmlQ4_0_4_8;
    33: Result := ggmlQ4_0_8_8;
    else Result := ggmlUnknown;
  end;
end;

function GGMLTypeToTypeSize(const AType: TGGMLType): Double;
begin
  { Average bits per weight for rough memory estimation }
  case AType of
    ggmlF32:     Result := 32.0;
    ggmlF16,
    ggmlBF16:    Result := 16.0;
    ggmlQ8_0,
    ggmlQ8_1,
    ggmlQ8_K,
    ggmlI8:      Result := 8.5;
    ggmlQ6_K:    Result := 6.56;
    ggmlQ5_0,
    ggmlQ5_1,
    ggmlQ5_K:    Result := 5.5;
    ggmlQ4_0,
    ggmlQ4_1,
    ggmlQ4_K,
    ggmlIQ4_NL,
    ggmlIQ4_XS:  Result := 4.5;
    ggmlQ3_K,
    ggmlIQ3_S,
    ggmlIQ3_XXS: Result := 3.44;
    ggmlQ2_K,
    ggmlIQ2_S,
    ggmlIQ2_XS,
    ggmlIQ2_XXS: Result := 2.56;
    ggmlIQ1_S,
    ggmlIQ1_M:   Result := 1.75;
    else         Result := 16.0;
  end;
end;

function EstimateParameterCountStr(const ATotalParams: UInt64): string;
begin
  if ATotalParams >= 1000000000 then
    Result := Format('%.2fB', [ATotalParams / 1000000000.0])
  else if ATotalParams >= 1000000 then
    Result := Format('%.2fM', [ATotalParams / 1000000.0])
  else if ATotalParams >= 1000 then
    Result := Format('%.2fK', [ATotalParams / 1000.0])
  else
    Result := IntToStr(ATotalParams);
end;

end.

