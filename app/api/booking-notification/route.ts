import { NextResponse } from "next/server";

const json = (body: Record<string, string>, status = 200) =>
  NextResponse.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });

export async function POST(request: Request) {
  const publicKey = process.env.EMAILJS_PUBLIC_KEY;
  if (!publicKey) {
    return json({ error: "EmailJS belum dikonfigurasi di server." }, 503);
  }

  const contentLengthHeader = request.headers.get("content-length");
  const contentLength = contentLengthHeader ? Number(contentLengthHeader) : 0;
  if ((contentLengthHeader && !Number.isFinite(contentLength)) || contentLength > 12_000) {
    return json({ error: "Ukuran data booking terlalu besar." }, 413);
  }

  let rawBody = "";
  const reader = request.body?.getReader();
  if (!reader) return json({ error: "Data booking tidak ditemukan." }, 400);
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > 12_000) {
        await reader.cancel();
        return json({ error: "Ukuran data booking terlalu besar." }, 413);
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(totalBytes);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    rawBody = new TextDecoder().decode(bytes);
  } catch {
    return json({ error: "Data booking tidak dapat dibaca." }, 400);
  }

  const body: unknown = (() => {
    try { return JSON.parse(rawBody); } catch { return null; }
  })();
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "Format data booking tidak valid." }, 400);
  }

  const data = body as Record<string, unknown>;
  const fields = ["customer_name", "phone", "address", "start_at", "barber_name", "booking_code"];
  if (fields.some((field) => typeof data[field] !== "string" || !(data[field] as string).trim())) {
    return json({ error: "Data booking tidak lengkap." }, 400);
  }

  const customerName = (data.customer_name as string).trim();
  const phone = (data.phone as string).replace(/\D/g, "");
  const address = (data.address as string).trim();
  const barberName = (data.barber_name as string).trim();
  const bookingCode = (data.booking_code as string).trim();
  const startAt = new Date(data.start_at as string);

  if (customerName.length > 100 || address.length > 1_000 || barberName.length > 100) {
    return json({ error: "Ada data booking yang melebihi batas karakter." }, 400);
  }
  if (phone.length < 8 || phone.length > 16) {
    return json({ error: "Nomor WhatsApp tidak valid." }, 400);
  }
  if (!/^\d{5}$/.test(bookingCode)) {
    return json({ error: "Kode booking harus terdiri dari 5 angka." }, 400);
  }
  if (Number.isNaN(startAt.getTime())) {
    return json({ error: "Tanggal booking tidak valid." }, 400);
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
      signal: AbortSignal.timeout(10_000),
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
          notes: typeof data.notes === "string" ? data.notes.slice(0, 1_000) : "-",
          booking_code: bookingCode,
        },
      }),
    });

    if (!response.ok) {
      const details = await response.text().catch(() => "");
      console.error("EmailJS notification failed:", response.status, details.slice(0, 500));
      return json({ error: "Booking tersimpan, tetapi email notifikasi gagal dikirim." }, 502);
    }

    return json({ success: "true" });
  } catch (error) {
    console.error("EmailJS notification request failed:", error);
    return json({ error: "Layanan notifikasi sedang tidak tersedia." }, 502);
  }
}
