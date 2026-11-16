import { NextResponse } from "next/server";

export const runtime = "nodejs";

const MAX_BODY_BYTES = 20_000;

export async function POST(request: Request) {
  const publicKey = process.env.EMAILJS_PUBLIC_KEY;
  if (!publicKey) {
    return NextResponse.json({ error: "EmailJS belum dikonfigurasi di server." }, { status: 503 });
  }

  const contentType = request.headers.get("content-type") || "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return NextResponse.json({ error: "Content-Type harus application/json." }, { status: 415 });
  }

  const contentLength = Number(request.headers.get("content-length") || 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Data notifikasi terlalu besar." }, { status: 413 });
  }

  // Enforce the limit on the actual body too; Content-Length can be omitted.
  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return NextResponse.json({ error: "Data notifikasi tidak dapat dibaca." }, { status: 400 });
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Data notifikasi terlalu besar." }, { status: 413 });
  }

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(rawBody);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return NextResponse.json({ error: "Data booking tidak valid." }, { status: 400 });
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "Data booking tidak valid." }, { status: 400 });
  }

  const customerName = typeof body.customer_name === "string" ? body.customer_name.trim() : "";
  const phone = typeof body.phone === "string" ? body.phone.trim() : "";
  const address = typeof body.address === "string" ? body.address.trim() : "";
  const barberName = typeof body.barber_name === "string" ? body.barber_name.trim() : "";
  const bookingCode = typeof body.booking_code === "string" ? body.booking_code.trim() : "";
  const notes = typeof body.notes === "string" ? body.notes.trim() : "";
  const startAtValue = typeof body.start_at === "string" ? body.start_at : "";
  const startAt = new Date(startAtValue);
  const phoneDigits = phone.replace(/[^0-9]/g, "");

  if (
    !customerName || customerName.length > 120 ||
    phoneDigits.length < 8 || phoneDigits.length > 16 ||
    !address || address.length > 1000 ||
    !barberName || barberName.length > 100 ||
    !/^\d{5}$/.test(bookingCode) ||
    !startAtValue || !Number.isFinite(startAt.getTime()) ||
    notes.length > 1000
  ) {
    return NextResponse.json({ error: "Data booking tidak lengkap atau formatnya tidak valid." }, { status: 400 });
  }

  const bookingDate = startAt.toLocaleString("id-ID", {
    dateStyle: "full",
    timeStyle: "short",
    timeZone: "Asia/Jakarta",
  });

  let response: Response;
  try {
    response = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: AbortSignal.timeout(8_000),
      body: JSON.stringify({
        service_id: "service_u6yhrju",
        template_id: "template_srgzub4",
        user_id: publicKey,
        template_params: {
          customer_name: customerName,
          phone,
          address,
          barber_name: barberName,
          booking_date: bookingDate,
          notes: notes || "-",
          booking_code: bookingCode,
        },
      }),
    });
  } catch {
    return NextResponse.json({ error: "Booking tersimpan, tetapi layanan email sedang tidak tersedia." }, { status: 502 });
  }

  if (!response.ok) {
    return NextResponse.json({ error: "Booking tersimpan, tetapi email notifikasi gagal dikirim." }, { status: 502 });
  }

  return NextResponse.json({ success: true });
}
