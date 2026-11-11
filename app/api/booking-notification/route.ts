import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const publicKey = process.env.EMAILJS_PUBLIC_KEY;
  if (!publicKey) {
    return NextResponse.json({ error: "EmailJS belum dikonfigurasi di server." }, { status: 503 });
  }

  const body = await request.json().catch(() => null);
  if (!body || !body.customer_name || !body.phone || !body.address || !body.start_at || !body.barber_name || !body.booking_code) {
    return NextResponse.json({ error: "Data booking tidak lengkap." }, { status: 400 });
  }

  const bookingDate = new Date(body.start_at).toLocaleString("id-ID", {
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
        customer_name: body.customer_name,
        phone: body.phone,
        address: body.address,
        barber_name: body.barber_name,
        booking_date: bookingDate,
        notes: body.notes || "-",
        booking_code: body.booking_code,
      },
    }),
  });

  if (!response.ok) {
    const details = await response.text().catch(() => "");
    console.error("EmailJS notification failed:", details);
    return NextResponse.json({ error: "Booking tersimpan, tetapi email notifikasi gagal dikirim." }, { status: 502 });
  }

  return NextResponse.json({ success: true });
}
