import { MAX_ATTACHMENT_INLINE_TEXT } from './format';

export function isTextLikeFile(file) {
  return file && (
    file.type.startsWith('text/')
    || /json|xml|javascript|typescript|markdown|yaml|yml/.test(file.type)
    || /\.(txt|md|json|js|jsx|ts|tsx|css|html|xml|yml|yaml|py|ps1|toml|log|csv)$/i.test(file.name || '')
  );
}

export function readFileAsBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = String(reader.result || '');
      const base64 = result.includes(',') ? result.split(',').pop() : result;
      resolve(base64 || '');
    };
    reader.onerror = () => reject(reader.error || new Error('Failed to read file'));
    reader.readAsDataURL(file);
  });
}

export function readFileAsText(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => reject(reader.error || new Error('Failed to read text file'));
    reader.readAsText(file);
  });
}

export function readBlobAsBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = String(reader.result || '');
      const base64 = result.includes(',') ? result.split(',').pop() : result;
      resolve(base64 || '');
    };
    reader.onerror = () => reject(reader.error || new Error('Failed to read audio blob'));
    reader.readAsDataURL(blob);
  });
}

export function getSupportedRecordingMimeType() {
  if (!window.MediaRecorder) return '';
  const candidates = [
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/mp4',
    'audio/mpeg'
  ];
  return candidates.find((candidate) => window.MediaRecorder.isTypeSupported?.(candidate)) || '';
}

export function buildMessagePayload(text, attachments) {
  const trimmed = text.trim();
  const readyAttachments = (attachments || [])
    .filter((item) => item.status === 'ready' && item.serverFile?.path)
    .map((item) => ({
      name: item.name,
      type: item.type || item.serverFile?.type || '',
      size: item.size || item.serverFile?.size || 0,
      path: item.serverFile.path
    }));

  return {
    text: trimmed,
    attachments: readyAttachments,
    hasContent: Boolean(trimmed || readyAttachments.length)
  };
}

export async function uploadSelectedFiles(fileList, uploadFile, formatBytes) {
  const files = [...(fileList || [])];
  const pending = files.map((file) => ({
    id: `attachment-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    name: file.name,
    type: file.type || 'application/octet-stream',
    size: file.size,
    sizeLabel: formatBytes(file.size),
    status: 'uploading',
    inlineText: '',
    serverFile: null
  }));

  const resolved = [];
  for (let index = 0; index < files.length; index += 1) {
    const file = files[index];
    const attachment = pending[index];
    try {
      const [contentBase64, inlineText] = await Promise.all([
        readFileAsBase64(file),
        isTextLikeFile(file) ? readFileAsText(file).then((text) => text.slice(0, MAX_ATTACHMENT_INLINE_TEXT)) : Promise.resolve('')
      ]);
      const serverFile = await uploadFile({
        name: file.name,
        type: file.type || 'application/octet-stream',
        size: file.size,
        contentBase64
      });
      resolved.push({ ...attachment, status: 'ready', serverFile, inlineText });
    } catch {
      resolved.push({ ...attachment, status: 'failed' });
    }
  }

  return resolved;
}
