unit usmoothbutton;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Types, LCLType;

type
  { Modern Flat Rounded Nav Button }
  TSmoothNavButton = class(TCustomControl)
  private
    FIsHovered: Boolean;
    FIsPressed: Boolean;
    FIsActive: Boolean;
    FBorderRadius: Integer;
    FActiveColor: TColor;
    FHoverColor: TColor;
    FNormalColor: TColor;

    procedure SetIsActive(const AValue: Boolean);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    property IsActive: Boolean read FIsActive write SetIsActive;
  published
    property Caption;
    property Font;
    property OnClick;
    property Align;
    property Anchors;
    property Enabled;
    property Visible;
    property Cursor default crHandPoint;
  end;

implementation

{ TSmoothNavButton }

constructor TSmoothNavButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csReplicatable];
  Width := 130;
  Height := 34;
  Cursor := crHandPoint;
  FBorderRadius := 8;
  FIsHovered := False;
  FIsPressed := False;
  FIsActive := False;

  // Skema Warna Modern Dark UI
  FNormalColor := $002A2A28; // Abu-abu gelap lembut
  FHoverColor  := $003C3C38; // Lebih terang saat di-hover
  FActiveColor := $009C481A; // Aksen biru modern saat dipilih

  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clWhite;
  Font.Quality := fqClearType;
end;

procedure TSmoothNavButton.SetIsActive(const AValue: Boolean);
begin
  if FIsActive <> AValue then
  begin
    FIsActive := AValue;
    Invalidate;
  end;
end;

procedure TSmoothNavButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TSmoothNavButton.MouseEnter;
begin
  inherited MouseEnter;
  FIsHovered := True;
  Invalidate;
end;

procedure TSmoothNavButton.MouseLeave;
begin
  inherited MouseLeave;
  FIsHovered := False;
  FIsPressed := False;
  Invalidate;
end;

procedure TSmoothNavButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FIsPressed := True;
    Invalidate;
  end;
end;

procedure TSmoothNavButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FIsPressed := False;
  Invalidate;
end;

procedure TSmoothNavButton.Paint;
var
  R: TRect;
  BgColor, BorderColor, TextCol: TColor;
  TxtStyle: TTextStyle;
begin
  R := ClientRect;

  // Latar belakang panel utama toolbar
  Canvas.Brush.Color := $001A1A18;
  Canvas.FillRect(R);

  // Tentukan warna berdasarkan state
  if FIsActive then
  begin
    BgColor := FActiveColor;
    BorderColor := $00D0702A;
    TextCol := clWhite;
  end
  else if FIsPressed then
  begin
    BgColor := $00222220;
    BorderColor := $00505048;
    TextCol := $00D0D0D0;
  end
  else if FIsHovered then
  begin
    BgColor := FHoverColor;
    BorderColor := $0055554E;
    TextCol := clWhite;
  end
  else
  begin
    BgColor := FNormalColor;
    BorderColor := $00363632;
    TextCol := $00E0E0E0;
  end;

  // Gambar rounded rectangle yang halus
  Canvas.Brush.Color := BgColor;
  Canvas.Pen.Color := BorderColor;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, FBorderRadius, FBorderRadius);

  // Gambar garis aksen tipis di bawah jika tombol aktif
  if FIsActive then
  begin
    Canvas.Pen.Color := $00FFAA55;
    Canvas.Line(R.Left + 8, R.Bottom - 2, R.Right - 8, R.Bottom - 2);
  end;

  // Gambar teks terpusat (Center Alignment)
  Canvas.Font := Font;
  Canvas.Font.Color := TextCol;
  if FIsActive then
    Canvas.Font.Style := [fsBold]
  else
    Canvas.Font.Style := [];

  FillChar(TxtStyle, SizeOf(TxtStyle), 0);
  TxtStyle.Alignment := taCenter;
  TxtStyle.Layout := tlCenter;
  TxtStyle.SingleLine := True;

  Canvas.TextRect(R, R.Left, R.Top, Caption, TxtStyle);
end;

end.
