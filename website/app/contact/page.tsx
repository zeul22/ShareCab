import { Section } from '@/components/Section';
import { ContactForm } from '@/components/ContactForm';
import { env } from '@/lib/env';

export const metadata = { title: 'Contact' };

export default function ContactPage() {
  return (
    <>
      <section className="container-page pt-20 pb-6">
        <h1 className="h-display max-w-3xl">Get in touch.</h1>
        <p className="mt-6 text-lg muted max-w-2xl">
          Questions about a ride, partnerships, or just want to say hi? Reach us through any of the
          channels below — we usually respond within a few hours.
        </p>
      </section>

      <Section eyebrow="Reach us" title="Pick the channel that suits you.">
        <div className="grid sm:grid-cols-3 gap-5">
          <Card
            title="Rider support"
            email={env.supportEmail}
            sub="For ride issues, refunds, lost items."
          />
          <Card
            title="Driver support"
            email={env.driverSupportEmail}
            sub="For onboarding, payouts, vehicle docs."
          />
          <Card
            title="Partnerships"
            email={env.partnershipsEmail}
            sub="Press, business, integrations."
          />
        </div>
      </Section>

      <Section alt eyebrow="Send us a note" title="Quick form.">
        <ContactForm />
      </Section>
    </>
  );
}

function Card({ title, email, sub }: { title: string; email: string; sub: string }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <div className="text-xs font-semibold uppercase tracking-wider text-brand-700">{title}</div>
      <a
        href={`mailto:${email}`}
        className="mt-2 block text-lg font-semibold hover:text-brand-700 break-all"
      >
        {email}
      </a>
      <p className="mt-2 text-sm muted">{sub}</p>
    </div>
  );
}
