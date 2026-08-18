# Llama Control Center 🦙💻

![Uploading image.png…]()

**Llama Control Center** adalah aplikasi *suite* manajemen AI lokal dan antarmuka grafis (GUI) modern untuk [llama.cpp](https://github.com/ggerganov/llama.cpp), yang dibangun menggunakan **Free Pascal** dan **Lazarus LCL**. Aplikasi ini dirancang untuk memudahkan pengguna dalam mengelola model GGUF, menjalankan server inferensi, memantau perangkat keras, hingga melakukan *benchmark* performa secara lokal.

---

## 🚀 Fitur Utama

* **Server Control & Real-Time Telemetry**: Mengelola *inference engine* (`llama-server`) dengan kontrol penuh (Start, Stop, Restart), pemantauan PID secara *real-time*, serta pelacakan status *uptime*.
* **Hardware Telemetry**: Memantau penggunaan sumber daya perangkat keras secara langsung meliputi pemanfaatan CPU, System RAM, dan VRAM GPU.
* **Model Hub (GGUF Browser)**: Menjelajahi dan menginspeksi metadata file GGUF secara mendalam termasuk arsitektur model, jumlah parameter, tipe kuantisasi, dan ukuran file.
* **AI Playground**: Antarmuka obrolan interaktif dengan dukungan *streaming* untuk menguji model secara langsung.
* **Performance & Inference Benchmark**: Mengintegrasikan `llama-bench` untuk menguji kecepatan *Prompt Processing* (PP) dan *Text Generation* (TG) lengkap dengan fitur ekspor hasil ke format CSV.
* **Model Downloader & Quantizer Studio**: Utilitas terpadu untuk mengunduh model dan mengelola proses kuantisasi.
* **System Tray & Config Management**: Mendukung fitur minimisasi ke *system tray* serta penyimpanan konfigurasi otomatis berbasis JSON dengan fitur *Smart Path Resolver*

---

## 🛠️ Teknologi yang Digunakan

* **Bahasa Pemrograman**: Object Pascal (Free Pascal)
* **Framework GUI**: Lazarus Component Library (LCL)
* **Backend Engine**: `llama.cpp` (`llama-server`, `llama-bench`)

---

## ⚙️ Persyaratan Sistem & Instalasi

1. **Sistem Operasi**: Windows (x64)
2. **Biner Pendukung**: Pastikan file eksekusi `llama-server.exe` dan `llama-bench.exe` diletakkan di dalam folder direktori biner aplikasi (misalnya `bin/engine/`) atau dikonfigurasi melalui menu pengaturan
3. **Lazarus IDE** (opsional untuk *development*):
   * Lazarus versi terbaru dengan kompiler Free Pascal yang mendukung mode `objfpc`

---

## 🚀 Memulai (Quick Start)

1. Clone repositori ini ke komputer Anda:
   ```bash
   git clone [https://github.com/username/LlamaControlCenter.git](https://github.com/username/LlamaControlCenter.git)
