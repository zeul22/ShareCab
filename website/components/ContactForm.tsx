'use client';

import { FormEvent, useState } from 'react';
import { env } from '@/lib/env';

type Status = 'idle' | 'sending' | 'sent' | 'error';

export function ContactForm() {
  const [status, setStatus] = useState<Status>('idle');
  const [error, setError] = useState<string>('');

  const endpoint = env.contactFormEndpoint;
  const fallbackMailto = `mailto:${env.supportEmail}`;

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError('');

    const data = new FormData(e.currentTarget);
    const payload = {
      name: String(data.get('name') ?? ''),
      email: String(data.get('email') ?? ''),
      message: String(data.get('message') ?? ''),
    };

    // No endpoint configured → open the user's mail client with a prefilled message.
    if (!endpoint) {
      const subject = encodeURIComponent(`ShareCab contact — ${payload.name || 'no name'}`);
      const body = encodeURIComponent(
        `${payload.message}\n\n— ${payload.name}${payload.email ? ` <${payload.email}>` : ''}`,
      );
      window.location.href = `${fallbackMailto}?subject=${subject}&body=${body}`;
      setStatus('sent');
      return;
    }

    setStatus('sending');
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'application/json' },
        body: JSON.stringify(payload),
      });
      if (!res.ok) throw new Error(`Request failed (${res.status})`);
      setStatus('sent');
      e.currentTarget.reset();
    } catch (err) {
      setStatus('error');
      setError(err instanceof Error ? err.message : 'Something went wrong');
    }
  }

  if (status === 'sent') {
    return (
      <div className="rounded-2xl border border-brand-200 bg-brand-50 p-5 text-sm text-brand-800 sm:max-w-xl">
        Thanks — we&rsquo;ve got your message and will get back to you soon.
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="grid gap-4 sm:max-w-xl">
      <input
        type="text"
        name="name"
        required
        placeholder="Your name"
        className="rounded-xl border border-ink-300/60 bg-white px-4 py-3 focus:outline-none focus:ring-2 focus:ring-brand-400"
      />
      <input
        type="email"
        name="email"
        required
        placeholder="Your email"
        className="rounded-xl border border-ink-300/60 bg-white px-4 py-3 focus:outline-none focus:ring-2 focus:ring-brand-400"
      />
      <textarea
        name="message"
        rows={5}
        required
        placeholder="How can we help?"
        className="rounded-xl border border-ink-300/60 bg-white px-4 py-3 focus:outline-none focus:ring-2 focus:ring-brand-400"
      />
      <button
        type="submit"
        className="btn-primary self-start"
        disabled={status === 'sending'}
        aria-busy={status === 'sending'}
      >
        {status === 'sending' ? 'Sending…' : 'Send message'}
      </button>
      {status === 'error' && (
        <p className="text-sm text-red-600">{error || 'Could not send. Please try again.'}</p>
      )}
      {!endpoint && (
        <p className="text-xs muted">
          Tip: this form opens your mail app. Or write directly to{' '}
          <a className="underline" href={fallbackMailto}>
            {env.supportEmail}
          </a>
          .
        </p>
      )}
    </form>
  );
}
