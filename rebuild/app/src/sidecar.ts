import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type {
  AIContextFlags,
  Command,
  PermissionKind,
  RetentionPolicy
} from "./contract";

// Typed client over the frozen NDJSON sidecar contract (see ../../CONTRACT.md and
// ./contract.ts). The Rust shell forwards every sidecar stdout line verbatim as a
// "sidecar-event" Tauri event, and accepts command lines through the "sidecar_send" command.

export type SidecarMessage = Record<string, unknown>;

let counter = 0;

export function newId(): string {
  counter += 1;
  return `c${counter}`;
}

export async function send(command: Command | SidecarMessage): Promise<void> {
  await invoke("sidecar_send", { line: JSON.stringify(command) });
}

export async function hello(): Promise<SidecarMessage | null> {
  const line = await invoke<string | null>("sidecar_hello");
  if (!line) {
    return null;
  }
  try {
    return JSON.parse(line) as SidecarMessage;
  } catch {
    return null;
  }
}

export function onMessage(callback: (message: SidecarMessage) => void): Promise<UnlistenFn> {
  return listen<string>("sidecar-event", (event) => {
    try {
      callback(JSON.parse(event.payload) as SidecarMessage);
    } catch {
      callback({ event: "error", scope: "parse", message: event.payload });
    }
  });
}

export const commands = {
  permissionsStatus: () => ({ id: newId(), cmd: "permissions.status" }) satisfies Command,
  permissionsRequest: (kinds: PermissionKind[] = ["microphone", "screen"]) =>
    ({ id: newId(), cmd: "permissions.request", kinds }) satisfies Command,
  recordStart: (title?: string, localeId?: string, micDeviceId?: string) =>
    ({
      id: newId(),
      cmd: "record.start",
      ...(title ? { title } : {}),
      ...(localeId ? { localeId } : {}),
      ...(micDeviceId ? { micDeviceId } : {})
    }) satisfies Command,
  recordPause: () => ({ id: newId(), cmd: "record.pause" }) satisfies Command,
  recordResume: () => ({ id: newId(), cmd: "record.resume" }) satisfies Command,
  recordMuteMic: (muted: boolean) =>
    ({ id: newId(), cmd: "record.muteMic", muted }) satisfies Command,
  recordStop: () => ({ id: newId(), cmd: "record.stop" }) satisfies Command,
  modelStatus: () => ({ id: newId(), cmd: "model.status" }) satisfies Command,
  modelDownload: (modelId?: string) =>
    ({ id: newId(), cmd: "model.download", ...(modelId ? { modelId } : {}) }) satisfies Command,
  modelSetLocation: (path: string, move = false) =>
    ({ id: newId(), cmd: "model.setLocation", path, move }) satisfies Command,
  libraryList: () => ({ id: newId(), cmd: "library.list" }) satisfies Command,
  libraryDocument: (recordingId: string) =>
    ({ id: newId(), cmd: "library.document", recordingId }) satisfies Command,
  libraryRename: (recordingId: string, title: string) =>
    ({ id: newId(), cmd: "library.rename", recordingId, title }) satisfies Command,
  libraryDelete: (recordingId: string) =>
    ({ id: newId(), cmd: "library.delete", recordingId }) satisfies Command,
  libraryRevealAudio: (recordingId: string) =>
    ({ id: newId(), cmd: "library.revealAudio", recordingId }) satisfies Command,
  exportMarkdown: (recordingId: string) =>
    ({ id: newId(), cmd: "export.markdown", recordingId }) satisfies Command,
  exportAIContext: (recordingId: string, options?: AIContextFlags) =>
    ({
      id: newId(),
      cmd: "export.aiContext",
      recordingId,
      ...(options ? { options } : {})
    }) satisfies Command,
  storageSetRecordingsRoot: (path: string, move = false) =>
    ({ id: newId(), cmd: "storage.setRecordingsRoot", path, move }) satisfies Command,
  storageUsage: () => ({ id: newId(), cmd: "storage.usage" }) satisfies Command,
  storageSetRetention: (policy: RetentionPolicy, limitBytes?: number) =>
    ({
      id: newId(),
      cmd: "storage.setRetention",
      policy,
      ...(limitBytes !== undefined ? { limitBytes } : {})
    }) satisfies Command,
  storageApplyRetention: () => ({ id: newId(), cmd: "storage.applyRetention" }) satisfies Command
};
