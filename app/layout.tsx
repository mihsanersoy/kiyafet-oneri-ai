import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "OptiWear - Akıllı Hava Durumu & Kişiselleştirilmiş Giyim Asistanı",
  description:
    "OptiWear; vücut yapınıza, termal hassasiyetinize ve anlık mikro-lokasyon hava durumuna göre yapay zeka destekli katmanlı giyim ve fonksiyonel ekipman önerisi sunar.",
  icons: {
    icon: "/logo.png",
    apple: "/logo.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="tr">
      <body className="antialiased">{children}</body>
    </html>
  );
}
