'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';

type Link = { href: string; label: string };

export function MobileNav({ links }: { links: Link[] }) {
  const [open, setOpen] = useState(false);
  // SSR guard for createPortal — document is undefined during prerender.
  // We flip to true on first client render so the portal target is safe.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  // Close on Escape; lock body scroll while open.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  }, [open]);

  // The drawer is always rendered (when mounted) so we can animate the
  // close transition too — conditionally mounting would yank it out of
  // the DOM the moment `open` flips false, skipping the slide-out. The
  // backdrop fades and the panel slides from the right; both are
  // pointer-events:none when closed so they don't intercept clicks.
  const isOpen = open && mounted;
  const drawer = (
    <div
      className={`md:hidden fixed inset-0 z-40 transition-opacity duration-300 ease-out ${
        isOpen ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'
      }`}
      onClick={() => setOpen(false)}
      aria-hidden={!isOpen}
    >
      {/* Dimmed backdrop — separate layer from the panel so the panel
          can slide while the backdrop just fades. */}
      <div className="absolute inset-0 bg-ink-900/30" />

      {/* Sliding panel. translate-x-full when closed pushes it offscreen
          to the right; translate-x-0 brings it back in. duration tuned
          to feel snappy but not abrupt. */}
      <aside
        className={`absolute inset-y-0 right-0 w-[88%] max-w-sm bg-white shadow-2xl flex flex-col transform transition-transform duration-300 ease-out ${
          isOpen ? 'translate-x-0' : 'translate-x-full'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header: app icon + wordmark + close. Mirrors the navbar's
            visual identity so the drawer feels like a continuation of
            the page chrome, not an alien overlay. */}
        <div className="flex h-16 items-center justify-between border-b border-ink-300/30 px-5">
          <Link
            href="/"
            onClick={() => setOpen(false)}
            aria-label="ShareCab home"
            className="flex items-center gap-3 rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-400"
          >
            <Image
              src="/sharecab-icon.png"
              alt=""
              width={32}
              height={32}
              priority
              className="h-8 w-8 rounded-lg"
            />
            <span className="text-base font-semibold tracking-tight">ShareCab</span>
          </Link>
          <button
            type="button"
            aria-label="Close menu"
            onClick={() => setOpen(false)}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg text-ink-700 hover:bg-brand-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-400"
          >
            <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
              <path d="M6 6l12 12" />
              <path d="M18 6L6 18" />
            </svg>
          </button>
        </div>

        <nav className="flex flex-col gap-1 overflow-y-auto px-3 py-5">
          {links.map((l, i) => (
            <Link
              key={l.href}
              href={l.href}
              onClick={() => setOpen(false)}
              // Staggered fade-in: each row starts 30ms after the
              // previous, so the list cascades in as the panel slides.
              // `style` is unavoidable here because Tailwind doesn't
              // generate per-row arbitrary delays.
              style={{
                transitionDelay: isOpen ? `${100 + i * 30}ms` : '0ms',
              }}
              className={`rounded-xl px-4 py-3 text-base font-medium text-ink-900 transition-all duration-300 ease-out hover:bg-brand-50 ${
                isOpen
                  ? 'opacity-100 translate-x-0'
                  : 'opacity-0 translate-x-3'
              }`}
            >
              {l.label}
            </Link>
          ))}
        </nav>

        {/* Footer tagline — small touch, keeps the drawer from feeling empty. */}
        <div className="mt-auto border-t border-ink-300/30 px-5 py-4 text-xs muted">
          Share the cab. Split the fare.
        </div>
      </aside>
    </div>
  );

  return (
    <>
      <button
        type="button"
        aria-label={open ? 'Close menu' : 'Open menu'}
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="md:hidden inline-flex h-10 w-10 items-center justify-center rounded-lg text-ink-700 hover:bg-brand-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-400 relative z-50"
      >
        <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          {open ? (
            <>
              <path d="M6 6l12 12" />
              <path d="M18 6L6 18" />
            </>
          ) : (
            <>
              <path d="M4 7h16" />
              <path d="M4 12h16" />
              <path d="M4 17h16" />
            </>
          )}
        </svg>
      </button>

      {mounted && createPortal(drawer, document.body)}
    </>
  );
}
