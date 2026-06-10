// TypeScript mirror of the frozen sidecar contract. The authoritative description is
// ../../CONTRACT.md; the Swift reference shapes live in the root package. Keep this file
// in lockstep with both. Protocol changes require a version bump and a deliberate review.

export const PROTOCOL_VERSION = 1;

export type PermissionState = "unknown" | "authorized" | "denied" | "restricted";

export type PermissionRequestResult =
  | "granted"
  | "microphoneDenied"
  | "screenRecordingNotReady";

export type PermissionKind = "microphone" | "screen";

export type RecordingStatus =
  | "idle"
  | "requestingPermissions"
  | "recording"
  | "paused"
  | "finalizing"
  | "completed"
  | "failed";

export type RetentionPolicy =
  | "never"
  | "after7Days"
  | "after30Days"
  | "after90Days"
  | "storageLimit";

export type ModelStatusValue =
  | "unknown"
  | "notDownloaded"
  | "downloading"
  | "waitingForNetwork"
  | "downloaded"
  | "loading"
  | "ready"
  | "failed";

export type ErrorCode =
  | "badRequest"
  | "unsupportedCommand"
  | "internal"
  | "alreadyRecording"
  | "notRecording"
  | "notPaused"
  | "notFound"
  | "startFailed"
  | "stopFailed"
  | "writeFailure"
  | "readFailed"
  | "eof";

// Commands (UI to core). Recording references use "recordingId" because "id" is taken by
// the command envelope.

export interface CommandBase {
  id: string;
  cmd: string;
}

export interface PermissionsStatusCommand extends CommandBase {
  cmd: "permissions.status";
}

export interface PermissionsRequestCommand extends CommandBase {
  cmd: "permissions.request";
  kinds?: PermissionKind[];
}

export interface RecordStartCommand extends CommandBase {
  cmd: "record.start";
  title?: string;
  localeId?: string;
  micDeviceId?: string;
}

export interface RecordPauseCommand extends CommandBase {
  cmd: "record.pause";
}

export interface RecordResumeCommand extends CommandBase {
  cmd: "record.resume";
}

export interface RecordMuteMicCommand extends CommandBase {
  cmd: "record.muteMic";
  muted: boolean;
}

export interface RecordStopCommand extends CommandBase {
  cmd: "record.stop";
}

export interface ModelStatusCommand extends CommandBase {
  cmd: "model.status";
}

export interface ModelDownloadCommand extends CommandBase {
  cmd: "model.download";
  modelId?: string;
}

export interface ModelSetLocationCommand extends CommandBase {
  cmd: "model.setLocation";
  path: string;
  move?: boolean;
}

export interface LibraryListCommand extends CommandBase {
  cmd: "library.list";
}

export interface LibraryDocumentCommand extends CommandBase {
  cmd: "library.document";
  recordingId: string;
}

export interface LibraryRenameCommand extends CommandBase {
  cmd: "library.rename";
  recordingId: string;
  title: string;
}

export interface LibraryDeleteCommand extends CommandBase {
  cmd: "library.delete";
  recordingId: string;
}

export interface LibraryRevealAudioCommand extends CommandBase {
  cmd: "library.revealAudio";
  recordingId: string;
}

export interface AIContextFlags {
  date?: boolean;
  duration?: boolean;
  locale?: boolean;
  status?: boolean;
  files?: boolean;
  pauses?: boolean;
}

export interface ExportMarkdownCommand extends CommandBase {
  cmd: "export.markdown";
  recordingId: string;
}

export interface ExportAIContextCommand extends CommandBase {
  cmd: "export.aiContext";
  recordingId: string;
  options?: AIContextFlags;
}

export interface StorageSetRecordingsRootCommand extends CommandBase {
  cmd: "storage.setRecordingsRoot";
  path: string;
  move?: boolean;
}

export interface StorageUsageCommand extends CommandBase {
  cmd: "storage.usage";
}

export interface StorageSetRetentionCommand extends CommandBase {
  cmd: "storage.setRetention";
  policy: RetentionPolicy;
  limitBytes?: number;
}

export interface StorageApplyRetentionCommand extends CommandBase {
  cmd: "storage.applyRetention";
}

export type Command =
  | PermissionsStatusCommand
  | PermissionsRequestCommand
  | RecordStartCommand
  | RecordPauseCommand
  | RecordResumeCommand
  | RecordMuteMicCommand
  | RecordStopCommand
  | ModelStatusCommand
  | ModelDownloadCommand
  | ModelSetLocationCommand
  | LibraryListCommand
  | LibraryDocumentCommand
  | LibraryRenameCommand
  | LibraryDeleteCommand
  | LibraryRevealAudioCommand
  | ExportMarkdownCommand
  | ExportAIContextCommand
  | StorageSetRecordingsRootCommand
  | StorageUsageCommand
  | StorageSetRetentionCommand
  | StorageApplyRetentionCommand;

// Responses (core to UI)

export interface ProtocolError {
  code: ErrorCode | string;
  message: string;
}

export interface OkResponse<R> {
  id: string;
  ok: true;
  result: R;
}

export interface ErrResponse {
  id: string;
  ok: false;
  error: ProtocolError;
}

export type Response<R> = OkResponse<R> | ErrResponse;

export interface PermissionsStatusResult {
  microphone: PermissionState;
  screen: PermissionState;
}

export interface PermissionsRequestResult extends PermissionsStatusResult {
  result: PermissionRequestResult;
}

export interface RecordStartResult {
  recordingId: string;
  folderName: string;
  outputDir: string;
  title: string;
  localeId: string;
  systemAudioPath?: string;
  microphoneAudioPath?: string;
}

export interface RecordStopResult {
  recordingId: string;
  folderName: string;
  outputDir: string;
  title: string;
  status: RecordingStatus;
  durationSeconds: number;
  activeDurationSeconds: number;
  transcriptSegments: number;
  systemAudioPath?: string;
  microphoneAudioPath?: string;
  systemBytes?: number;
  microphoneBytes?: number;
}

export interface RecordPauseResumeResult {
  status: RecordingStatus;
}

export interface RecordMuteMicResult {
  muted: boolean;
}

export interface ModelStatusResult {
  value: ModelStatusValue;
  modelId: string;
  modelPath: string;
  isOnDisk: boolean;
  fraction?: number;
  attempt?: number;
  message?: string;
  onDiskBytes?: number;
}

export interface ModelDownloadResult {
  started: boolean;
  modelId: string;
}

export interface ModelSetLocationResult {
  downloadBase: string;
  modelPath: string;
  isOnDisk: boolean;
}

export interface LibraryRecording extends RecordingMetadata {
  hasAudio: boolean;
}

export interface LibraryListResult {
  recordings: LibraryRecording[];
  rootDir: string;
  audioStorageBytes: number;
  warning?: string;
}

export type LibraryDocumentResult = RecordingDocument;

export interface LibraryRenameResult {
  recordingId: string;
  title: string;
}

export interface LibraryDeleteResult {
  deleted: boolean;
}

export interface LibraryRevealAudioResult {
  revealed: boolean;
}

export interface ExportMarkdownResult {
  markdown: string;
}

export interface ExportAIContextResult {
  text: string;
}

export interface StorageSetRecordingsRootResult {
  rootDir: string;
}

export interface StorageUsageResult {
  rootDir: string;
  audioStorageBytes: number;
  recordings: number;
  isReachable: boolean;
  retentionPolicy: RetentionPolicy;
  storageLimitBytes: number;
}

export interface StorageRetentionResult {
  retentionPolicy: RetentionPolicy;
  storageLimitBytes?: number;
  audioStorageBytes?: number;
}

// Events (core to UI)

export interface ReadyEvent {
  event: "ready";
  protocol: number;
  sidecar: string;
  pid: number;
  bundleId: string;
}

export interface LevelsEvent {
  event: "levels";
  mic: number;
  system: number;
}

export interface StatusEvent {
  event: "status";
  value: RecordingStatus;
}

export interface PermissionResultEvent {
  event: "permission.result";
  value: PermissionRequestResult;
}

export interface TranscriptionProgressEvent {
  event: "transcription.progress";
  phase: "download" | "load" | "transcribe";
  fraction?: number;
  model: string;
}

export interface ModelStatusEvent {
  event: "model.status";
  value: ModelStatusValue;
  fraction?: number;
  attempt?: number;
  message?: string;
}

export interface LibraryChangedEvent {
  event: "library.changed";
}

export interface ErrorEvent {
  event: "error";
  scope: string;
  code?: ErrorCode | string;
  message: string;
}

export type SidecarEvent =
  | ReadyEvent
  | LevelsEvent
  | StatusEvent
  | PermissionResultEvent
  | TranscriptionProgressEvent
  | ModelStatusEvent
  | LibraryChangedEvent
  | ErrorEvent;

// On-disk recording format (recording.json), mirroring the frozen Codable shapes in
// Sources/MeetingAssistantCore/Models/. Dates are ISO8601 strings, ids are UUID strings.
// Optional Swift fields are absent keys, hence the ? markers.

export type SpeakerLabel = "You" | "Computer audio" | "Mixed";

export interface RecordingMetadata {
  id: string;
  title: string;
  createdAt: string;
  startedAt: string;
  endedAt?: string;
  duration: number;
  activeDuration: number;
  localeIdentifier: string;
  folderName: string;
  transcriptFileName: string;
  systemAudioFileName?: string;
  microphoneAudioFileName?: string;
  mixedAudioFileName?: string;
  status: RecordingStatus;
  errorMessage?: string;
}

export interface TranscriptSegment {
  id: string;
  startTime: number;
  endTime?: number;
  speaker: SpeakerLabel;
  text: string;
  confidence?: number;
  isFinal: boolean;
}

export interface PauseInterval {
  id: string;
  startedAt: string;
  endedAt: string;
  startOffset: number;
  endOffset: number;
}

export interface RecordingDocument {
  metadata: RecordingMetadata;
  pauses: PauseInterval[];
  transcript: TranscriptSegment[];
}
