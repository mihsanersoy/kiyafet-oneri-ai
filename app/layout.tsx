import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Hava Durumu & Kişiselleştirilmiş Kombin Önerisi",
  description:
    "Vücut yapınıza, termal hassasiyetinize ve şehrinizin hissedilen sıcaklığına göre yapay zeka destekli kıyafet önerisi.",
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
