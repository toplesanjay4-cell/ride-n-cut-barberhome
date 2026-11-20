import { NextResponse } from "next/server";
import { createClient, SupabaseClient } from "@supabase/supabase-js";
import { createHmac, randomUUID } from "node:crypto";
import { readJsonObjectRequest, readRequestBytesWithinLimit } from "@/lib/request-json.mjs";
import { isAllowedPaymentProof } from "@/lib/payment-proof.mjs";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_JSON_BYTES = 12_000;
const MAX_PROOF_BYTES = 5 * 1024 * 1024;
const ALLOWED_PROOF_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);

const reply = (body: Record<string, unknown>, status = 200, extraHeaders: Record<string, string> = {}) =>
  NextResponse.json(body, { status, headers: { "Cache-Control": "no-store", ...extraHeaders } });

function getAdminClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return null;
  return createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
}

function normalizedPhone(value: unknown): string {
  return typeof value === "string" ? value.replace(/[^0-9]/g, "") : "";
}

function requestIp(request: Request): string {
  const trusted = request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-real-ip");
  const forwarded = request.headers.get("x-forwarded-for");
  const value = trusted || (forwarded ? forwarded.split(",").map((part) => part.trim()).filter(Boolean).at(-1) : "");
  if (value) return value.trim().slice(0, 128);
  return process.env.NODE_ENV !== "production" ? "127.0.0.1" : "";
}

async function enforceRateLimit(admin: SupabaseClient, request: Request, action: string, phone: string) {
  const secret = process.env.RNC_RATE_LIMIT_HMAC_SECRET;
  const ip = requestIp(request);
  if (!secret || secret.length < 32 || !ip) return { ok: false as const, unavailable: true as const, retryAfter: 0 };
  const ipHash = createHmac("sha256", secret).update("ip:" + action + ":" + ip).digest("hex");
  const phoneHash = createHmac("sha256", secret).update("phone:" + action + ":" + phone).digest("hex");
  const isLookup = action === "lookup";
  const isUpload = action === "upload_proof";
  const { data, error } = await admin.rpc("rnc_consume_customer_rate_limit", {
    p_ip_key_hash: ipHash,
    p_phone_key_hash: phoneHash,
    p_ip_limit: isLookup ? 30 : isUpload ? 20 : 40,
    p_phone_limit: isLookup ? 5 : isUpload ? 4 : 10,
    p_window_seconds: isUpload ? 3600 : 900,
  });
  if (error) return { ok: false as const, unavailable: true as const, retryAfter: 0 };
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row.allowed !== "boolean") return { ok: false as const, unavailable: true as const, retryAfter: 0 };
  return { ok: row.allowed, unavailable: false as const, retryAfter: Number(row.retry_after_seconds) || 0 };
}

function validIdentity(phone: string, code: string) {
  return phone.length >= 8 && phone.length <= 16 && /^\d{5}$/.test(code);
}

export async function POST(request: Request) {
  const contentType = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  let body: Record<string, unknown> = {};
  let form: FormData | null = null;

  if (contentType === "multipart/form-data") {
    const contentTypeHeader = request.headers.get("content-type") || "";
    const limitedBody = await readRequestBytesWithinLimit(request, MAX_PROOF_BYTES + 32_000, "Data upload");
    if (!limitedBody.ok) return reply({ error: limitedBody.error }, limitedBody.status);
    try {
      const bodyBuffer = new ArrayBuffer(limitedBody.bytes.byteLength);
      new Uint8Array(bodyBuffer).set(limitedBody.bytes);
      form = await new Response(bodyBuffer, { headers: { "content-type": contentTypeHeader } }).formData();
    } catch {
      return reply({ error: "Data upload tidak valid." }, 400);
    }
    body = Object.fromEntries(Array.from(form.entries()).filter((entry) => typeof entry[1] === "string")) as Record<string, unknown>;
  } else {
    const parsedRequest = await readJsonObjectRequest(request, MAX_JSON_BYTES);
    if (!parsedRequest.ok) return reply({ error: parsedRequest.error }, parsedRequest.status);
    body = parsedRequest.data;
  }

  const action = typeof body.action === "string" ? body.action : "";
  const phone = normalizedPhone(body.phone);
  const code = typeof body.code === "string" ? body.code.trim() : "";
  const bookingId = typeof body.booking_id === "string" ? body.booking_id : "";
  if (!["lookup", "approve_quote", "select_payment", "cancel_booking", "upload_proof"].includes(action)) return reply({ error: "Permintaan tidak valid." }, 400);
  if (!validIdentity(phone, code)) return reply({ error: "Nomor WhatsApp atau kode booking tidak valid." }, 400);
  if (["approve_quote", "select_payment", "cancel_booking", "upload_proof"].includes(action) && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(bookingId)) return reply({ error: "Booking tidak ditemukan." }, 400);

  const admin = getAdminClient();
  if (!admin) return reply({ error: "Layanan pelanggan belum dikonfigurasi. Silakan hubungi admin." }, 503);
  const limit = await enforceRateLimit(admin, request, action, phone);
  if (limit.unavailable) return reply({ error: "Layanan sementara tidak tersedia. Coba lagi beberapa saat." }, 503);
  if (!limit.ok) return reply({ error: "Terlalu banyak percobaan. Coba lagi nanti." }, 429, { "Retry-After": String(Math.max(1, limit.retryAfter)) });

  if (action === "lookup") {
    const { data, error } = await admin.rpc("customer_booking_history", { p_phone: phone, p_code: code });
    if (error) return reply({ error: "Riwayat belum bisa dimuat. Periksa data atau coba lagi." }, 400);
    const bookings = (data || []) as Array<{ id: string }>;
    const details = await Promise.all(bookings.map(async (booking) => {
      const [quoteResult, paymentResult, cancellationResult] = await Promise.all([
        admin.rpc("customer_booking_quote", { p_phone: phone, p_code: code, p_booking_id: booking.id }),
        admin.rpc("customer_booking_payment", { p_phone: phone, p_code: code, p_booking_id: booking.id }),
        admin.rpc("customer_booking_cancellation_status", { p_phone: phone, p_code: code, p_booking_id: booking.id }),
      ]);
      return {
        bookingId: booking.id,
        quote: quoteResult.error ? null : quoteResult.data?.[0] || null,
        payment: paymentResult.error ? null : paymentResult.data?.[0] || null,
        cancellationStatus: cancellationResult.error ? "none" : cancellationResult.data?.[0]?.cancellation_status || "none",
        failed: Boolean(quoteResult.error || paymentResult.error || cancellationResult.error),
      };
    }));
    return reply({ bookings, details });
  }

  if (action === "approve_quote") {
    const { data, error } = await admin.rpc("customer_approve_booking_quote", { p_phone: phone, p_code: code, p_booking_id: bookingId, p_approval_channel: "website" });
    if (error || data !== true) return reply({ error: "Persetujuan gagal diproses. Pastikan penawaran masih berlaku." }, 400);
    return reply({ success: true });
  }

  if (action === "select_payment") {
    const method = typeof body.method === "string" ? body.method : "";
    if (!["cash", "bank_transfer", "e_wallet", "qris"].includes(method)) return reply({ error: "Metode pembayaran tidak valid." }, 400);
    const { data, error } = await admin.rpc("customer_select_booking_payment", { p_phone: phone, p_code: code, p_booking_id: bookingId, p_method: method });
    if (error || data !== true) return reply({ error: "Metode pembayaran belum bisa disimpan." }, 400);
    return reply({ success: true });
  }

  if (action === "cancel_booking") {
    const { data, error } = await admin.rpc("customer_request_booking_cancellation", { p_phone: phone, p_code: code, p_booking_id: bookingId });
    if (error || data !== true) return reply({ error: "Permintaan pembatalan gagal dikirim. Periksa status booking." }, 400);
    return reply({ success: true });
  }

  const file = form?.get("file");
  if (typeof File === "undefined" || !(file instanceof File) || file.size < 1 || file.size > MAX_PROOF_BYTES || !ALLOWED_PROOF_TYPES.has(file.type)) {
    return reply({ error: "File harus JPG, PNG, WEBP, atau PDF dengan ukuran maksimal 5 MB." }, 400);
  }
  const proofBytes = new Uint8Array(await file.arrayBuffer());
  if (!isAllowedPaymentProof(file.type, proofBytes)) {
    return reply({ error: "Isi file tidak sesuai dengan format bukti pembayaran yang dipilih." }, 400);
  }
  const extension = file.type === "image/jpeg" ? "jpg" : file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "pdf";
  const path = bookingId + "/" + randomUUID() + "." + extension;
  const { error: uploadError } = await admin.storage.from("rnc-payment-proofs").upload(path, proofBytes, { upsert: false, contentType: file.type });
  if (uploadError) return reply({ error: "Upload bukti pembayaran gagal. Coba lagi atau hubungi admin." }, 400);
  const { data, error } = await admin.rpc("customer_attach_payment_proof", { p_phone: phone, p_code: code, p_booking_id: bookingId, p_proof_path: path });
  if (error || data !== true) {
    await admin.storage.from("rnc-payment-proofs").remove([path]);
    return reply({ error: "Bukti belum berhasil ditautkan ke pembayaran. Hubungi admin." }, 400);
  }
  return reply({ success: true });
}