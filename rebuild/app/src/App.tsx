import { useEffect, useRef, useState } from "react";
import {
  commands,
  hello,
  onMessage,
  send,
  type SidecarMessage
} from "./sidecar";

type Identity = {
  pid?: number;
  bundleId?: string;
  sidecar?: string;
  protocol?: number;
};

type CaptureResult = {
  systemAudioPath?: string;
  microphoneAudioPath?: string;
  systemBytes?: number;
  microphoneBytes?: number;
  outputDir?: string;
};

const RECORD_SECONDS = 3;

function str(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function num(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

export function App() {
  const [identity, setIdentity] = useState<Identity>({});
  const [microphone, setMicrophone] = useState("unknown");
  const [screen, setScreen] = useState("unknown");
  const [status, setStatus] = useState("idle");
  const [permissionResult, setPermissionResult] = useState<string | null>(null);
  const [micLevel, setMicLevel] = useState(0);
  const [systemLevel, setSystemLevel] = useState(0);
  const [capture, setCapture] = useState<CaptureResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [log, setLog] = useState<string[]>([]);
  const stopTimer = useRef<number | null>(null);

  function appendLog(line: string) {
    setLog((current) => [line, ...current].slice(0, 60));
  }

  function applyMessage(message: SidecarMessage) {
    appendLog(JSON.stringify(message));

    const event = str(message.event);
    if (event === "ready") {
      setIdentity({
        pid: num(message.pid),
        bundleId: str(message.bundleId),
        sidecar: str(message.sidecar),
        protocol: num(message.protocol)
      });
      return;
    }
    if (event === "levels") {
      setMicLevel(num(message.mic) ?? 0);
      setSystemLevel(num(message.system) ?? 0);
      return;
    }
    if (event === "status") {
      setStatus(str(message.value) ?? "unknown");
      return;
    }
    if (event === "permission.result") {
      setPermissionResult(str(message.value) ?? null);
      return;
    }
    if (event === "error") {
      return;
    }

    const result = message.result as Record<string, unknown> | undefined;
    if (message.ok === true && result) {
      const mic = str(result.microphone);
      const scr = str(result.screen);
      if (mic) setMicrophone(mic);
      if (scr) setScreen(scr);
      if (typeof result.systemBytes !== "undefined" || typeof result.microphoneBytes !== "undefined") {
        setCapture({
          systemAudioPath: str(result.systemAudioPath),
          microphoneAudioPath: str(result.microphoneAudioPath),
          systemBytes: num(result.systemBytes),
          microphoneBytes: num(result.microphoneBytes),
          outputDir: str(result.outputDir)
        });
      } else if (str(result.systemAudioPath)) {
        setCapture({
          systemAudioPath: str(result.systemAudioPath),
          microphoneAudioPath: str(result.microphoneAudioPath),
          outputDir: str(result.outputDir)
        });
      }
    }
  }

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    onMessage(applyMessage).then((fn) => {
      unlisten = fn;
    });
    hello().then((message) => {
      if (message) applyMessage(message);
    });
    send(commands.permissionsStatus());
    return () => {
      if (unlisten) unlisten();
      if (stopTimer.current) window.clearTimeout(stopTimer.current);
    };
  }, []);

  async function checkPermissions() {
    await send(commands.permissionsStatus());
  }

  async function requestPermissions() {
    await send(commands.permissionsRequest());
  }

  async function recordThreeSeconds() {
    setBusy(true);
    setCapture(null);
    await send(commands.recordStart());
    stopTimer.current = window.setTimeout(async () => {
      await send(commands.recordStop());
      setBusy(false);
    }, RECORD_SECONDS * 1000);
  }

  const ready = typeof identity.pid === "number";

  return (
    <main className="app">
      <header>
        <h1>MeetingAssistant Rebuild</h1>
        <p className="subtitle">Phase 1 spike: permissions and three-second capture</p>
      </header>

      <section className="card">
        <h2>Sidecar</h2>
        <div className="row">
          <span className={ready ? "pill ok" : "pill"}>{ready ? "running" : "waiting"}</span>
          <dl>
            <dt>pid</dt>
            <dd>{identity.pid ?? "?"}</dd>
            <dt>bundle id</dt>
            <dd>{identity.bundleId ?? "?"}</dd>
            <dt>version</dt>
            <dd>{identity.sidecar ?? "?"} (protocol {identity.protocol ?? "?"})</dd>
          </dl>
        </div>
      </section>

      <section className="card">
        <h2>Permissions</h2>
        <div className="row">
          <span className={microphone === "authorized" ? "pill ok" : "pill"}>microphone: {microphone}</span>
          <span className={screen === "authorized" ? "pill ok" : "pill"}>screen: {screen}</span>
        </div>
        {permissionResult && <p className="note">Last request result: {permissionResult}</p>}
        <div className="buttons">
          <button onClick={checkPermissions}>Check permissions</button>
          <button onClick={requestPermissions}>Request permissions</button>
        </div>
      </section>

      <section className="card">
        <h2>Capture</h2>
        <p>Status: <strong>{status}</strong></p>
        <Meter label="microphone" value={micLevel} />
        <Meter label="system" value={systemLevel} />
        <div className="buttons">
          <button onClick={recordThreeSeconds} disabled={busy}>
            {busy ? `Recording ${RECORD_SECONDS}s...` : `Record ${RECORD_SECONDS} seconds`}
          </button>
        </div>
        {capture && (
          <dl className="result">
            <dt>output</dt>
            <dd>{capture.outputDir}</dd>
            <dt>system.caf</dt>
            <dd>{capture.systemAudioPath} {typeof capture.systemBytes === "number" ? `(${capture.systemBytes} bytes)` : ""}</dd>
            <dt>microphone.caf</dt>
            <dd>{capture.microphoneAudioPath} {typeof capture.microphoneBytes === "number" ? `(${capture.microphoneBytes} bytes)` : ""}</dd>
          </dl>
        )}
      </section>

      <section className="card">
        <h2>Raw protocol log</h2>
        <pre className="log">{log.join("\n")}</pre>
      </section>
    </main>
  );
}

function Meter({ label, value }: { label: string; value: number }) {
  const width = Math.max(0, Math.min(1, value)) * 100;
  return (
    <div className="meter">
      <span className="meter-label">{label}</span>
      <div className="meter-track">
        <div className="meter-fill" style={{ width: `${width}%` }} />
      </div>
    </div>
  );
}
