#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::Mutex;

use tauri::{Emitter, Manager, State};

// Holds the spawned sidecar so it is not dropped, plus its stdin for sending commands. The
// last "ready" line is buffered so the webview can read the sidecar identity (pid, bundleId)
// even when it mounts after the sidecar has already announced itself.
struct SidecarState {
  child: Mutex<Option<Child>>,
  stdin: Mutex<Option<ChildStdin>>,
  ready: Mutex<Option<String>>,
}

// Sends one NDJSON command line to the sidecar's stdin.
#[tauri::command]
fn sidecar_send(state: State<SidecarState>, line: String) -> Result<(), String> {
  let mut guard = state.stdin.lock().map_err(|e| e.to_string())?;
  let stdin = guard.as_mut().ok_or_else(|| "sidecar is not running".to_string())?;
  stdin.write_all(line.as_bytes()).map_err(|e| e.to_string())?;
  stdin.write_all(b"\n").map_err(|e| e.to_string())?;
  stdin.flush().map_err(|e| e.to_string())?;
  Ok(())
}

// Returns the buffered sidecar "ready" line, if one has arrived yet.
#[tauri::command]
fn sidecar_hello(state: State<SidecarState>) -> Option<String> {
  state.ready.lock().ok().and_then(|guard| guard.clone())
}

// Resolves the sidecar binary path. MEETINGCORE_SIDECAR overrides for dev runs; otherwise the
// sidecar is expected next to this executable (Contents/MacOS/meetingcore-sidecar in the bundle).
fn resolve_sidecar_path() -> PathBuf {
  if let Ok(path) = std::env::var("MEETINGCORE_SIDECAR") {
    return PathBuf::from(path);
  }
  let exe = std::env::current_exe().expect("could not resolve current executable path");
  exe.parent()
    .expect("executable has no parent directory")
    .join("meetingcore-sidecar")
}

fn main() {
  tauri::Builder::default()
    .manage(SidecarState {
      child: Mutex::new(None),
      stdin: Mutex::new(None),
      ready: Mutex::new(None),
    })
    .invoke_handler(tauri::generate_handler![sidecar_send, sidecar_hello])
    .setup(|app| {
      let path = resolve_sidecar_path();
      let mut child = Command::new(&path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| format!("failed to spawn sidecar at {:?}: {}", path, e))?;

      let stdout = child.stdout.take().expect("sidecar stdout was not piped");
      let stdin = child.stdin.take().expect("sidecar stdin was not piped");

      let state = app.state::<SidecarState>();
      *state.stdin.lock().unwrap() = Some(stdin);
      *state.child.lock().unwrap() = Some(child);

      if let Some(window) = app.get_webview_window("main") {
        window.open_devtools();
      }

      let handle = app.handle().clone();
      std::thread::spawn(move || {
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
          match line {
            Ok(payload) => {
              if payload.contains("\"event\":\"ready\"") {
                if let Ok(mut guard) = handle.state::<SidecarState>().ready.lock() {
                  *guard = Some(payload.clone());
                }
              }
              let _ = handle.emit("sidecar-event", payload);
            }
            Err(_) => break,
          }
        }
        let _ = handle.emit(
          "sidecar-event",
          "{\"event\":\"error\",\"scope\":\"sidecar\",\"code\":\"eof\",\"message\":\"sidecar stdout closed\"}".to_string(),
        );
      });

      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running the Tauri application");
}
