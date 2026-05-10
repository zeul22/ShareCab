import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { Navbar } from '@/components/Navbar';
import { Footer } from '@/components/Footer';
import { Analytics } from '@/components/Analytics';
import { env } from '@/lib/env';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-inter',
});

const description =
  'ShareCab matches you with nearby riders heading the same way, so you save on every short trip — without giving up convenience.';

export const metadata: Metadata = {
  metadataBase: new URL(env.siteUrl),
  title: {
    default: `${env.siteName} — Share the cab. Split the fare.`,
    template: `%s · ${env.siteName}`,
  },
  description,
  icons: {
    icon: [
      { url: '/favicon.svg', type: 'image/svg+xml' },
      { url: '/sharecab-icon.png', sizes: '512x512', type: 'image/png' },
    ],
    apple: '/sharecab-icon.png',
  },
  openGraph: {
    title: `${env.siteName} — Share the cab. Split the fare.`,
    description,
    url: env.siteUrl,
    siteName: env.siteName,
    type: 'website',
    // Wide brand image renders well in social previews; square fallback
    // is for clients that crop to 1:1 (Slack, iMessage thumbnails).
    images: [
      { url: '/sharecab-logo.png', width: 3624, height: 1184, alt: env.siteName },
      { url: '/sharecab-icon.png', width: 1254, height: 1254, alt: env.siteName },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: `${env.siteName} — Share the cab. Split the fare.`,
    description,
    images: ['/sharecab-logo.png'],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="font-sans">
        <Navbar />
        <main>{children}</main>
        <Footer />
        <Analytics />
      </body>
    </html>
  );
}
