import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const publicKey = process.env.EMAILJS_PUBLIC_KEY;
  if (!publicKey) {
    return NextResponse.json({ error: "EmailJS belum dikonfigurasi di server." }, { status: 503 });
  }

  const contentLength = Number(request.headers.get("content-length") || 0);
  if (contentLength > 20_000) {
    return NextResponse.json({ error: "Data notifikasi terlalu besar." }, { status: 413 });
  }

  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return NextResponse.json({ error: "Data booking tidak valid." }, { status: 400 });
  }

  const customerName = String(body.customer_name || "").trim();
  const phone = String(body.phone || "").trim();
  const address = String(body.address || "").trim();
  const barberName = String(body.barber_name || "").trim();
  const bookingCode = String(body.booking_code || "").trim();
  const notes = String(body.notes || "").trim();
  const startAt = new Date(body.start_at);
  const phoneDigits = phone.replace(/[^0-9]/g, "");

  if (
    !customerName || customerName.length > 120 ||
    phoneDigits.length < 8 || phoneDigits.length > 16 ||
    !address || address.length > 1000 ||
    !barberName || barberName.length > 100 ||
    !/^\\d{5}$/.test(bookingCode) ||
    !Number.isFinite(startAt.getTime()) ||
    notes.length > 1000
  ) {
    return NextResponse.json({ error: "Data booking tidak lengkap atau formatnya tidak valid." }, { status: 400 });
  }

  const bookingDate = startAt.toLocaleString("id-ID", {
    dateStyle: "full",
    timeStyle: "short",
    timeZone: "Asia/Jakarta",
  });

  const response = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
    return NextResponse.json({ error: "Booking tersimpan, tetapi email notifikasi gagal dikirim." }, { status: 502 });
  }

  return NextResponse.json({ success: true });
}
