import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";

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

  let body: { name?: string; email?: string; password?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Data permintaan tidak valid." }, { status: 400 });
  }

  const name = String(body.name || "").trim();
  const email = String(body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
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
    return NextResponse.json({ error: createError?.message || "Akun staff gagal dibuat." }, { status: 400 });
  }

  const { error: roleInsertError } = await admin.from("user_roles").insert({
    user_id: created.user.id,
    role: "staff",
    display_name: name,
    is_active: true
  });

  if (roleInsertError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return NextResponse.json({ error: "Peran staff gagal disimpan; akun sementara sudah dibatalkan. " + roleInsertError.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, user_id: created.user.id });
}
