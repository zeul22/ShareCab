import Image from 'next/image';
import Link from 'next/link';
import { AppStoreButtons } from './AppStoreButtons';
import { env } from '@/lib/env';

export function Footer() {
  return (
    <footer className="border-t border-ink-300/30 bg-brand-50/40">
      <div className="container-page py-12 grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <Image
            src="/sharecab-logo.png"
            alt={env.siteName}
            width={147}
            height={48}
            className="h-9 w-auto"
          />
          <p className="mt-3 text-sm muted max-w-xs">
            Share the cab. Split the fare. Get there together.
          </p>
        </div>

        <div>
          <h4 className="text-sm font-semibold">Product</h4>
          <ul className="mt-3 space-y-2 text-sm text-ink-700">
            <li><Link href="/how-it-works" className="hover:text-brand-700">How it works</Link></li>
            <li><Link href="/pricing" className="hover:text-brand-700">Pricing</Link></li>
            <li><Link href="/drivers" className="hover:text-brand-700">For drivers</Link></li>
            <li><Link href="/safety" className="hover:text-brand-700">Safety</Link></li>
            <li><Link href="/technology" className="hover:text-brand-700">Technology</Link></li>
          </ul>
        </div>

        <div>
          <h4 className="text-sm font-semibold">Company</h4>
          <ul className="mt-3 space-y-2 text-sm text-ink-700">
            <li><Link href="/about" className="hover:text-brand-700">About</Link></li>
            <li><Link href="/contact" className="hover:text-brand-700">Contact</Link></li>
            <li>
              <a href={`mailto:${env.supportEmail}`} className="hover:text-brand-700">
                {env.supportEmail}
              </a>
            </li>
          </ul>
        </div>

        <div>
          <h4 className="text-sm font-semibold">Get the app</h4>
          <div className="mt-3">
            <AppStoreButtons variant="inline" />
          </div>
        </div>
      </div>
      <div className="border-t border-ink-300/30">
        <div className="container-page py-5 text-xs muted flex flex-col sm:flex-row gap-2 justify-between">
          <span>© {new Date().getFullYear()} {env.siteName}. All rights reserved.</span>
          <span>Made for shorter trips, smaller bills.</span>
        </div>
      </div>
    </footer>
  );
}
