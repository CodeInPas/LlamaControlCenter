unit ufrmsplash;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, ComCtrls, Types;

type
  { TfrmSplash }
  TfrmSplash = class(TForm)
  private
    FMainPanel: TPanel;
    FLblTitle: TLabel;
    FLblSubTitle: TLabel;
    FLblStatus: TLabel;
    FLblVersion: TLabel;
    FProgressBar: TProgressBar;
    procedure FormPaint(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetProgress(const AStatus: string; const APercent: Integer);

    // Static Helper Methods
    class procedure ShowSplash; static;
    class procedure UpdateSplash(const AStatus: string; const APercent: Integer); static;
    class procedure CloseSplash; static;
  end;

var
  frmSplash: TfrmSplash = nil;

implementation

{ TfrmSplash }

constructor TfrmSplash.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  // Pengaturan Form Splash
  Caption := 'Llama Control Center';
  BorderStyle := bsNone;
  Position := poScreenCenter;
  Width := 520;
  Height := 280;
  Color := $001A1A18; // Background abu-abu gelap
  OnPaint := @FormPaint;

  // Panel Kontainer Utama
  FMainPanel := TPanel.Create(Self);
  FMainPanel.Parent := Self;
  FMainPanel.Align := alClient;
  FMainPanel.BevelOuter := bvNone;
  FMainPanel.Color := $001E1E1C;

  // Judul Aplikasi
  FLblTitle := TLabel.Create(Self);
  FLblTitle.Parent := FMainPanel;
  FLblTitle.Caption := '🦙 Llama Control Center';
  FLblTitle.Font.Name := 'Segoe UI';
  FLblTitle.Font.Size := 18;
  FLblTitle.Font.Style := [fsBold];
  FLblTitle.Font.Color := $00FFAA55; // Aksen Amber / Oranye Modern
  FLblTitle.Left := 35;
  FLblTitle.Top := 35;

  // Sub-judul / Deskripsi
  FLblSubTitle := TLabel.Create(Self);
  FLblSubTitle.Parent := FMainPanel;
  FLblSubTitle.Caption := 'Local AI Management Studio & High-Performance Inference Suite';
  FLblSubTitle.Font.Name := 'Segoe UI';
  FLblSubTitle.Font.Size := 9;
  FLblSubTitle.Font.Color := $00B0B0B0;
  FLblSubTitle.Left := 38;
  FLblSubTitle.Top := 75;

  // Label Versi
  FLblVersion := TLabel.Create(Self);
  FLblVersion.Parent := FMainPanel;
  FLblVersion.Caption := 'v1.0.0 • Powered by llama.cpp & Free Pascal';
  FLblVersion.Font.Name := 'Segoe UI';
  FLblVersion.Font.Size := 8;
  FLblVersion.Font.Color := $00707070;
  FLblVersion.Left := 38;
  FLblVersion.Top := 100;

  // Progress Bar
  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent := FMainPanel;
  FProgressBar.Left := 35;
  FProgressBar.Top := 195;
  FProgressBar.Width := 450;
  FProgressBar.Height := 10;
  FProgressBar.Min := 0;
  FProgressBar.Max := 100;
  FProgressBar.Position := 0;
  FProgressBar.Smooth := True;

  // Label Status Inisialisasi
  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := FMainPanel;
  FLblStatus.Caption := 'Memulai sistem...';
  FLblStatus.Font.Name := 'Segoe UI';
  FLblStatus.Font.Size := 9;
  FLblStatus.Font.Color := $00E0E0E0;
  FLblStatus.Left := 35;
  FLblStatus.Top := 170;
end;

procedure TfrmSplash.FormPaint(Sender: TObject);
var
  R: TRect;
begin
  R := ClientRect;
  // Gambar border aksen di sekeliling jendela splash
  Canvas.Pen.Color := $003A3A35;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(R);

  // Garis aksen bawah
  Canvas.Pen.Color := $00D0702A;
  Canvas.Line(0, ClientHeight - 2, ClientWidth, ClientHeight - 2);
end;

procedure TfrmSplash.SetProgress(const AStatus: string; const APercent: Integer);
begin
  FLblStatus.Caption := AStatus;
  FProgressBar.Position := APercent;
  Application.ProcessMessages; // Memperbarui tampilan secara real-time
end;

class procedure TfrmSplash.ShowSplash;
begin
  if not Assigned(frmSplash) then
  begin
    frmSplash := TfrmSplash.Create(Application);
    frmSplash.Show;
    frmSplash.BringToFront;
    Application.ProcessMessages;
  end;
end;

class procedure TfrmSplash.UpdateSplash(const AStatus: string; const APercent: Integer);
begin
  if Assigned(frmSplash) then
    frmSplash.SetProgress(AStatus, APercent);
end;

class procedure TfrmSplash.CloseSplash;
begin
  if Assigned(frmSplash) then
  begin
    frmSplash.Hide;
    FreeAndNil(frmSplash);
  end;
end;

end.
