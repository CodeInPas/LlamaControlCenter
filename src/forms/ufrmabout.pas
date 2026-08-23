unit ufrmabout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Buttons, klabels;

type

  { TfrmAbout }

  TfrmAbout = class(TForm)
    btnClose: TButton;
    KLinkLabel1: TKLinkLabel;
    lblAppName: TLabel;
    lblVersion: TLabel;
    lblDescription: TLabel;
    lblAuthor: TLabel;
    lblCopyright: TLabel;
    pnlContent: TPanel;
    procedure btnCloseClick(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnOKClick(Sender: TObject);
  private

  public

  end;

var
  frmAbout: TfrmAbout;

implementation

{$R *.lfm}

procedure TfrmAbout.btnOKClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmAbout.btnCloseClick(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  frmAbout := nil;
end;

end.
