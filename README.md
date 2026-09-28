# Cortex

A local AI harness for iPhone. GGUF chat models run entirely on-device through llama.cpp,
with image input (vision projectors), file attachments, TTS and multi-chat history.

- **Chat**: streaming responses, stop/regenerate, per-chat history, editable system prompt.
- **Vision**: pick any `mmproj-*.gguf` projector and attach photos from the library or camera.
- **Files**: attach text, code, JSON, CSV or PDF; text is extracted and injected into the prompt.
- **Audio**: speak any reply with the system voice.
- **Models**: import any GGUF from Files; models live in the app's Documents/Models folder.

## Build

The IPA is built on a macOS GitHub Actions runner (there is no Mac in the loop) and is unsigned,
so it installs through LiveContainer:

1. Actions -> *Build unsigned IPA* -> Run workflow (or push to `main`).
2. Download the `cortex-ipa` artifact, import `Cortex-unsigned.ipa` into LiveContainer.

llama.cpp `v0.5.0` is compiled into `llama.xcframework` (Metal, `LLAMA_BUILD_MTMD=ON`) and cached
between runs.
