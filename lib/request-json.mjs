/**
 * Read a request body as bytes while enforcing a hard streamed byte limit.
 * Use this for multipart bodies where Content-Length may be absent or inaccurate.
 *
 * @param {Request} request
 * @param {number} maxBytes
 * @param {string} label
 * @returns {Promise<{ok:true,bytes:Uint8Array}|{ok:false,status:400|413,error:string}>}
 */
export async function readRequestBytesWithinLimit(request, maxBytes, label = "Data permintaan") {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1) {
    throw new RangeError("Batas ukuran body tidak valid.");
  }

  const contentLengthHeader = request.headers.get("content-length");
  if (contentLengthHeader !== null) {
    const normalizedLength = contentLengthHeader.trim();
    if (!/^\\d+$/.test(normalizedLength)) {
      return { ok: false, status: 400, error: "Content-Length tidak valid." };
    }
    const contentLength = Number(normalizedLength);
    if (!Number.isSafeInteger(contentLength)) {
      return { ok: false, status: 400, error: "Content-Length tidak valid." };
    }
    if (contentLength > maxBytes) {
      return { ok: false, status: 413, error: label + " terlalu besar." };
    }
  }

  const reader = request.body?.getReader();
  if (!reader) return { ok: false, status: 400, error: label + " tidak ditemukan." };

  const chunks = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel().catch(() => undefined);
        return { ok: false, status: 413, error: label + " terlalu besar." };
      }
      chunks.push(value);
    }
  } catch {
    return { ok: false, status: 400, error: label + " tidak dapat dibaca." };
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { ok: true, bytes };
}

/**
 * Read a JSON object from a request while enforcing a byte limit before buffering
 * the complete body. This protects public endpoints when Content-Length is absent
 * or does not match the actual streamed payload.
 *
 * @param {Request} request
 * @param {number} maxBytes
 * @returns {Promise<
 *   | { ok: true, data: Record<string, unknown> }
 *   | { ok: false, status: 400 | 413 | 415, error: string }
 * >}
 */
export async function readJsonObjectRequest(request, maxBytes) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1) {
    throw new RangeError("Batas ukuran body tidak valid.");
  }

  const contentType = (request.headers.get("content-type") || "")
    .split(";", 1)[0]
    .trim()
    .toLowerCase();

  if (contentType !== "application/json") {
    return {
      ok: false,
      status: 415,
      error: "Content-Type harus application/json.",
    };
  }

  const contentLengthHeader = request.headers.get("content-length");
  if (contentLengthHeader !== null) {
    const normalizedLength = contentLengthHeader.trim();
    if (!/^\d+$/.test(normalizedLength)) {
      return {
        ok: false,
        status: 400,
        error: "Content-Length tidak valid.",
      };
    }

    const contentLength = Number(normalizedLength);
    if (!Number.isSafeInteger(contentLength)) {
      return {
        ok: false,
        status: 400,
        error: "Content-Length tidak valid.",
      };
    }
    if (contentLength > maxBytes) {
      return {
        ok: false,
        status: 413,
        error: "Data notifikasi terlalu besar.",
      };
    }
  }

  const reader = request.body?.getReader();
  if (!reader) {
    return {
      ok: false,
      status: 400,
      error: "Data notifikasi tidak ditemukan.",
    };
  }

  const chunks = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel().catch(() => undefined);
        return {
          ok: false,
          status: 413,
          error: "Data notifikasi terlalu besar.",
        };
      }

      chunks.push(value);
    }
  } catch {
    return {
      ok: false,
      status: 400,
      error: "Data notifikasi tidak dapat dibaca.",
    };
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  let rawBody;
  try {
    rawBody = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return {
      ok: false,
      status: 400,
      error: "Data notifikasi tidak menggunakan UTF-8 yang valid.",
    };
  }

  let parsed;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return {
      ok: false,
      status: 400,
      error: "Data booking tidak valid.",
    };
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return {
      ok: false,
      status: 400,
      error: "Data booking tidak valid.",
    };
  }

  return { ok: true, data: parsed };
}
