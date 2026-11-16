import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";

const MAX_BODY_BYTES = 8_000;

export async function POST(request: NextRequest) {
  const authorization = request.headers.get("authorization") || "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return NextResponse.json({ error: "Sesi login tidak ditemukan." }, { status: 401 });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    return NextResponse.json({ error: "Konfigurasi server belum lengkap. Owner perlu mengatur SUPABASE_SERVICE_ROLE_KEY di environment server." }, { status: 503 });
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) {
    return NextResponse.json({ error: "Sesi login tidak valid. Silakan login ulang." }, { status: 401 });
  }

  const { data: role, error: roleError } = await admin
    .from("user_roles")
    .select("role,is_active")
    .eq("user_id", authData.user.id)
    .maybeSingle();

  if (roleError || role?.role !== "owner" || role.is_active !== true) {
    return NextResponse.json({ error: "Hanya owner aktif yang dapat membuat akun staff." }, { status: 403 });
  }

  const contentType = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (contentType !== "application/json") {
    return NextResponse.json({ error: "Content-Type harus application/json." }, { status: 415 });
  }

  const contentLength = Number(request.headers.get("content-length") || 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Data permintaan terlalu besar." }, { status: 413 });
  }

  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return NextResponse.json({ error: "Data permintaan tidak dapat dibaca." }, { status: 400 });
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Data permintaan terlalu besar." }, { status: 413 });
  }

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(rawBody);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return NextResponse.json({ error: "Data permintaan tidak valid." }, { status: 400 });
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "Data permintaan tidak valid." }, { status: 400 });
  }

  const name = typeof body.name === "string" ? body.name.trim() : "";
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!name || name.length > 100 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || password.length < 8 || password.length > 128) {
    return NextResponse.json({ error: "Periksa nama, email, dan password (8–128 karakter)." }, { status: 400 });
  }

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: name, created_for: "ride-n-cut-staff" }
  });
  if (createError || !created.user) {
    return NextResponse.json({ error: "Akun staff gagal dibuat. Periksa email dan coba lagi." }, { status: 400 });
  }

  const { error: roleInsertError } = await admin.from("user_roles").insert({
    user_id: created.user.id,
    role: "staff",
    display_name: name,
    is_active: true
  });

  if (roleInsertError) {
    const { error: cleanupError } = await admin.auth.admin.deleteUser(created.user.id);
    if (cleanupError) {
      console.error("Ride N Cut staff provisioning rollback failed.");
      return NextResponse.json({ error: "Pembuatan akun belum selesai dan perlu ditangani administrator. Jangan membuat akun staff ulang sebelum diperiksa." }, { status: 500 });
    }
    return NextResponse.json({ error: "Peran staff gagal disimpan. Akun sementara sudah dibatalkan; coba lagi." }, { status: 500 });
  }

  return NextResponse.json({ ok: true, user_id: created.user.id });
}
