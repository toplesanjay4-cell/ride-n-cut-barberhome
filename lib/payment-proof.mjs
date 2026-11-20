const signatures = {
  "image/jpeg": (bytes) =>
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff,
  "image/png": (bytes) =>
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a,
  "image/webp": (bytes) =>
    bytes.length >= 12 &&
    String.fromCharCode(...bytes.subarray(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.subarray(8, 12)) === "WEBP",
  "application/pdf": (bytes) =>
    bytes.length >= 5 &&
    String.fromCharCode(...bytes.subarray(0, 5)) === "%PDF-",
};

/**
 * Check the file's leading signature instead of trusting the browser-supplied
 * MIME type. This is a format check, not malware scanning or PDF sanitization.
 *
 * @param {string} contentType
 * @param {Uint8Array} bytes
 * @returns {boolean}
 */
export function isAllowedPaymentProof(contentType, bytes) {
  if (!(bytes instanceof Uint8Array)) return false;
  const matchesSignature = Object.hasOwn(signatures, contentType) ? signatures[contentType] : undefined;
  return typeof matchesSignature === "function" && matchesSignature(bytes);
}
