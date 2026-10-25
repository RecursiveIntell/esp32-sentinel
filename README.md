# ESP32 Sentinel

<!-- last-verified: 2026-10-25; scope: gateway model selection and host-script limitations only -->

> Review scope: gateway model selection and host-script limitations. This marker does not indicate an end-to-end or hardware run.

An experimental ESP32-S3 sentinel firmware and host-side gateway workbench. The checked-in code contains two distinct demonstration paths:

1. Rust firmware runs a compiled-in sine-model fixture and sends low-confidence results using a framed TCP protocol
2. A Python HTTP gateway accepts sensor-context JSON and calls a configured Ollama model

The shipped character-LSTM weight artifact is separate from the current `sentinel-wifi` firmware. That firmware does not load the H512 weights, read a DHT22, or drive an OLED. Those integrations need additional implementation and hardware verification.

## Source map

| Path | Current role |
|---|---|
| [esp32-s3/src/bin/sentinel_wifi.rs](esp32-s3/src/bin/sentinel_wifi.rs) | Sine-model fixture, synthetic input, confidence heuristic, WiFi, and TCP wake messages |
| [esp32-s3/models/sine.tflite](esp32-s3/models/sine.tflite) | Model compiled into the firmware with MicroFlow |
| [uno-q/server/server.py](uno-q/server/server.py) | `TEAI` framed TCP receiver with model-loading and mock fallback paths |
| [uno-q/server/sensor_ai_gateway.py](uno-q/server/sensor_ai_gateway.py) | Separate HTTP sensor/Ollama gateway and optional training endpoint |
| [examples/dht22_laptop_gateway/run.sh](examples/dht22_laptop_gateway/run.sh) | Simulated HTTP sensor request on a laptop |
| [models/](models/) | Character-LSTM weights and metadata retained as an artifact |

A TCP firmware demonstration and an HTTP host simulation do not establish a connected sensor-to-LSTM-to-OLED product.

## Inspect the HTTP gateway

The sensor endpoint uses Python's standard library and calls Ollama. It requires a running endpoint and an available model; training additionally imports PyTorch and NumPy.

```bash
# From this repository root, after configuring a local Ollama instance:
python3 uno-q/server/sensor_ai_gateway.py \
  --host 127.0.0.1 --port 8090
```

In another terminal:

```bash
curl http://127.0.0.1:8090/health
```

`/health` shows gateway configuration; it does not prove model availability or successful inference. `/api/sensor_ai` sends supplied context to the configured model. Treat generated environmental advice as unvalidated model output, not a safety assessment or authorization to actuate hardware.

## Firmware build boundary

The [manifest](esp32-s3/Cargo.toml) declares Rust 1.88, edition 2024, ESP32-S3 HAL dependencies, and the `sentinel-wifi` binary. Use the custom Xtensa toolchain installed through [esp-rs/espup](https://github.com/esp-rs/espup), rather than assuming `rustup toolchain install esp` installs it.

Read [.env.example](esp32-s3/.env.example), [build.rs](esp32-s3/build.rs), and [.cargo/config.toml](esp32-s3/.cargo/config.toml) for WiFi, gateway, target, and linker configuration. Once the environment is prepared:

```bash
cd esp32-s3
cargo +esp build --release --bin sentinel-wifi
```

Building does not flash hardware. Before flashing, identify the actual board, serial device, memory configuration, and recovery procedure. The current loop waits for network configuration and awaits gateway I/O with timeouts; it is not a guarantee of uninterrupted sensing when networking fails.

## Known host-script limitations

- `scripts/install.sh` is a preflight checker, not an installer; some printed setup advice is stale
- The HTTP gateway currently uses the source-level `qwen2.5:0.5b` constant and does not read `OLLAMA_MODEL`; setting that variable does not change the gateway's model. The laptop example sets `OLLAMA_MODEL=llama3.2:1b` by default and records that value in its receipt, but the current gateway still uses `qwen2.5:0.5b`, so the receipt field is not proof of which model received the request
- The example's response-validation invocation passes the JSON file as a Python program instead of passing it as data to the heredoc validator. Its success message must not be treated as proof that those schema assertions ran
- `scripts/doctor.sh` expects compact `"status":"ok"` text, while the gateway emits normal spaced JSON; this can produce a false failed-health result
- The doctor also invokes the example, so it is not a read-only inspection command

These are source-level limitations in the current scripts. They are documented here without claiming a repaired or newly reproduced end-to-end run.

## Model artifact and evidence

The repository retains `models/char_lstm_709ff8a9.bin` and its metadata. A matching file hash establishes artifact identity, not integration into this firmware. Historical H512 throughput belongs to the separate [ESP32-S3 LSTM proof repository](https://github.com/RecursiveIntell/esp32-s3-lstm-proof), where a generation step is a character, not a BPE token.

This README makes no competitor-speed, hardware-price, battery-life, power-on-demand, physical sensor/display, or complete deployment claim. Measure those properties on the exact assembled system.

## Privacy and network scope

The firmware contacts its configured TCP gateway. The HTTP service contacts its configured Ollama URL; that endpoint may be local or remote. Model downloads and optional training inputs have their own data paths. Keep bind addresses, endpoint settings, and credentials under operator control.

## License

[Apache-2.0](LICENSE).
