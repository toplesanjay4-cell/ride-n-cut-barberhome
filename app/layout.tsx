import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "Ride N Cut Barberhome", description: "Booking barber home service — rapi, praktis, dan sesuai jadwal." };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="id"><body>{children}</body></html>; }