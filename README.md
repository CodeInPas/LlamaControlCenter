

# Llama Control Center 🦙💻


**Llama Control Center** is a local AI management suite and modern Graphical User Interface (GUI) for [llama.cpp](https://github.com/ggerganov/llama.cpp), built with **Free Pascal** and **Lazarus LCL**. It is designed to streamline managing GGUF models, running inference servers, monitoring hardware, and benchmarking performance locally.

---

<img width="952" height="502" alt="image" src="https://github.com/user-attachments/assets/c58a2269-19f7-4f72-83b8-4119fc984fb3" />


## 🚀 Key Features

* **Server Control & Real-Time Telemetry**: Manage the inference engine (`llama-server`) with full control (Start, Stop, Restart), real-time PID monitoring, and uptime tracking.
* **Hardware Telemetry**: Monitor live hardware resource usage, including CPU, System RAM, and GPU VRAM utilization.
* **Model Hub (GGUF Browser)**: Explore and inspect in-depth GGUF metadata, including model architecture, parameter count, quantization type, and file size.
* **AI Playground**: Interactive chat interface with streaming support for instant model testing.
* **Performance & Inference Benchmark**: Integrated `llama-bench` to evaluate Prompt Processing (PP) and Text Generation (TG) speeds, complete with CSV export support.
* **Model Downloader & Quantizer Studio**: Unified utility to download models and manage quantization workflows.
* **System Tray & Config Management**: Supports minimize-to-tray and automated JSON-based configuration management with a *Smart Path Resolver*.

---

## 🛠️ Tech Stack

* **Programming Language**: Object Pascal (Free Pascal)
* **GUI Framework**: Lazarus Component Library (LCL)
* **Backend Engine**: `llama.cpp` (`llama-server`, `llama-bench`)

---

## ⚙️ System Requirements & Installation

1. **Operating System**: Windows (x64)
2. **Supporting Binaries**: Ensure `llama-server.exe` and `llama-bench.exe` are placed in the application's binary directory (e.g., `bin/engine/`) or configured via the settings menu.
3. **Lazarus IDE** (optional, for development):
* Latest version of Lazarus with a Free Pascal compiler supporting `objfpc` mode.



---

## 🚀 Quick Start

1. Clone this repository to your local machine:
```bash
git clone https://github.com/username/LlamaControlCenter.git

```

---
## Download

Download Binary => https://github.com/CodeInPas/LlamaControlCenter/releases/ 
