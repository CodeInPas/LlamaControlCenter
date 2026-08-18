program LlamaControlCenter;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // LCL Widgetset
  Forms,
  SysUtils,

  // Base Types & Helpers
  uconfigtypes,
  uchattypes,
  ugguftypes,
  ujsonhelper,
  uformatting,
  ulogger,
  // Utilities
  uansiparser,
  upromptformatter,
  // Core Subsystems
  uhardwareinfo,
  uggufparser,
  uprofilemanager,
  ullamaprocess,
  uslotmonitor,
  // Network Clients
  uhttpdownloader,
  usseclient,
  // User Interface Forms
  ufrmmain,
  ufrmservercontrol,
  ufrmmodelhub,
  ufrmplayground,
  ufrmdownloader,
  ufrmquantize,
  ufrmbenchmark,
  ufrmsplash,
  ufrmsettings ;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled:=True;
  Application.Initialize;

  // Primary Application Window
  Application.CreateForm(TfrmMain, frmMain);

  // Auxiliary Module Forms (On-demand creation or pre-registered instances)
  Application.CreateForm(TfrmServerControl, frmServerControl);
  Application.CreateForm(TfrmModelHub, frmModelHub);
  Application.CreateForm(TfrmPlayground, frmPlayground);
  Application.CreateForm(TfrmDownloader, frmDownloader);
  Application.CreateForm(TfrmQuantize, frmQuantize);
  Application.CreateForm(TfrmBenchmark, frmBenchmark);
  Application.CreateForm(TfrmSettings, frmSettings);

  TfrmSplash.ShowSplash;

  // 2. Tahap Inisialisasi Subsistem
  TfrmSplash.UpdateSplash('Memeriksa konfigurasi & pengaturan sistem...', 20);
  Sleep(800);

  TfrmSplash.UpdateSplash('Mendeteksi akselerasi GPU & topologi CPU...', 45);
  Sleep(850);

  TfrmSplash.UpdateSplash('Menyiapkan antarmuka utama...', 75);
  Application.CreateForm(TfrmMain, frmMain);

  TfrmSplash.UpdateSplash('Sistem siap.', 100);
  Sleep(800);

  // 3. Tutup Splash Screen & Tampilkan Form Utama
  TfrmSplash.CloseSplash;

  Application.Run;
end.
