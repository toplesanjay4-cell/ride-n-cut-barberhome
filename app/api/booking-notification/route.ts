import { NextResponse } from "next/server";
import { readJsonObjectRequest } from "@/lib/request-json.mjs";

export const runtime = "nodejs";

const MAX_BODY_BYTES = 20_000;

const json = (body: Record<string, unknown>, status = 200) =>
  NextResponse.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });

export async function POST(request: Request) {
  const publicKey = process.env.EMAILJS_PUBLIC_KEY;
  if (!publicKey) {
    return json({ error: "EmailJS belum dikonfigurasi di server." }, 503);
  }

  const parsedRequest = await readJsonObjectRequest(request, MAX_BODY_BYTES);
  if (!parsedRequest.ok) {
    return json({ error: parsedRequest.error }, parsedRequest.status);
  }

  const body = parsedRequest.data;
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
    return json({ error: "Data booking tidak lengkap atau formatnya tidak valid." }, 400);
  }

  const bookingDate = startAt.toLocaleString("id-ID", {
    dateStyle: "full",
    timeStyle: "short",
    timeZone: "Asia/Jakarta",
  });

  try {
    const response = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
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

    if (!response.ok) {
      return json({ error: "Booking tersimpan, tetapi email notifikasi gagal dikirim." }, 502);
    }
  } catch {
    return json({ error: "Booking tersimpan, tetapi layanan email sedang tidak tersedia." }, 502);
  }

  return json({ success: true });
}
