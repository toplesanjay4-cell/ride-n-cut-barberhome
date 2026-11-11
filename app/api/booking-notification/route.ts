import { NextResponse } from "next/server";

const recipients = ["mascukurbarberhometa@gmail.com", "nizarsetiawan620@gmail.com"];

function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[char] || char);
}

export async function POST(request: Request) {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.RESEND_FROM_EMAIL;
  if (!apiKey || !from) {
    return NextResponse.json({ error: "Email belum dikonfigurasi di server." }, { status: 503 });
  }

  const body = await request.json().catch(() => null);
  if (!body || !body.customer_name || !body.phone || !body.address || !body.start_at || !body.barber_name || !body.booking_code) {
    return NextResponse.json({ error: "Data booking tidak lengkap." }, { status: 400 });
  }

  const rows = [
    ["Nama customer", body.customer_name],
    ["Nomor WhatsApp", body.phone],
    ["Alamat", body.address],
    ["Barber", body.barber_name],
    ["Jadwal", new Date(body.start_at).toLocaleString("id-ID", { dateStyle: "full", timeStyle: "short", timeZone: "Asia/Jakarta" })],
    ["Catatan", body.notes || "-"],
    ["Kode booking", body.booking_code],
  ];
  const html = `<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;color:#171717"><h2>Pesanan Booking Baru — Ride N Cut</h2><p>Ada pesanan baru yang masuk dari website Ride N Cut Barberhome.</p><table style="border-collapse:collapse;width:100%">${rows.map(([label,value]) => `<tr><td style="padding:10px;border:1px solid #ddd;font-weight:bold;width:36%">${escapeHtml(label)}</td><td style="padding:10px;border:1px solid #ddd">${escapeHtml(value)}</td></tr>`).join("")}</table><p style="margin-top:20px">Silakan buka halaman admin untuk mengelola pesanan.</p></div>`;

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to: recipients,
      subject: `Booking baru: ${body.customer_name} — Ride N Cut`,
      html,
    }),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("Resend email error:", result);
    return NextResponse.json({ error: "Booking tersimpan, tetapi email notifikasi gagal dikirim." }, { status: 502 });
  }
  return NextResponse.json({ success: true });
}
