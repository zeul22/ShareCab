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
  icons: { icon: '/favicon.svg' },
  openGraph: {
    title: `${env.siteName} — Share the cab. Split the fare.`,
    description,
    url: env.siteUrl,
    siteName: env.siteName,
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: `${env.siteName} — Share the cab. Split the fare.`,
    description,
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
