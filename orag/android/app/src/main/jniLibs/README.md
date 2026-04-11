# Android llama-server binary placement

Place the Android ARM64 server binary here:

- `android/app/src/main/jniLibs/arm64-v8a/llama-server.so`
- or legacy name: `android/app/src/main/jniLibs/arm64-v8a/libllama_server.so`

This project expects a llama server binary to be packaged in the APK and resolved at runtime from Android `nativeLibraryDir`.

## Notes

- ABI expected: `arm64-v8a`
- Preferred file name: `llama-server.so`
- After adding/replacing the file, rebuild the app (`flutter clean`, then `flutter run`).
