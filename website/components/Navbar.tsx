import Link from 'next/link';
import { env, hasAppLinks } from '@/lib/env';
import { MobileNav } from './MobileNav';

const links = [
  { href: '/', label: 'Home' },
  { href: '/how-it-works', label: 'How it works' },
  { href: '/pricing', label: 'Pricing' },
  { href: '/safety', label: 'Safety' },
  { href: '/about', label: 'About' },
  { href: '/contact', label: 'Contact' },
];

export function Navbar() {
  // Top-right CTA: deep-link to a store when configured, otherwise /contact.
  const ctaHref = env.appStoreUrl || env.playStoreUrl || '/contact';
  const ctaIsExternal = hasAppLinks;

  return (
    <header className="sticky top-0 z-30 border-b border-ink-300/30 bg-white/85 backdrop-blur">
      <div className="container-page flex h-16 items-center justify-between">
        <Link
          href="/"
          className="flex items-center gap-2 rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand-400"
        >
          <span className="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-brand-600 text-white font-bold">
            S
          </span>
          <span className="text-lg font-semibold tracking-tight">ShareCab</span>
        </Link>

        <nav className="hidden md:flex items-center gap-7 text-sm">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="text-ink-700 hover:text-brand-700 rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand-400"
            >
              {l.label}
            </Link>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          <a
            href={ctaHref}
            target={ctaIsExternal ? '_blank' : undefined}
            rel={ctaIsExternal ? 'noreferrer' : undefined}
            className="hidden sm:inline-flex btn-secondary !py-2 !px-4 text-sm"
          >
            Get the app
          </a>
          <MobileNav links={links} />
        </div>
      </div>
    </header>
  );
}
