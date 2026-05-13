import { Section } from '@/components/Section';

export const metadata = { title: 'About — ShareCab' };

export default function AboutPage() {
  return (
    <>
      <section className="container-page pt-20 pb-10">
        <h1 className="h-display max-w-3xl">
          We&rsquo;re building cheaper, smarter rides for everyday city trips.
        </h1>
        <p className="mt-6 text-lg muted max-w-2xl">
          ShareCab exists because many short cab rides are duplicated: two or three people
          travel in the same direction, but each books separately. We are building a structured
          way to match compatible riders, split fares, and coordinate the ride safely.
        </p>
      </section>

      <Section
        eyebrow="Our mission"
        title="Make city travel affordable, fair, and simple."
        intro="We focus only on short-distance shared rides — the trips you take to work, to a friend's place, to the metro, to dinner. The simpler the route, the better we do."
      />

      <Section
        eyebrow="Public-source direction"
        title="Transparent by design, protected where it matters."
        intro="ShareCab is being prepared as a source-available project under PolyForm Shield. The rider-side mechanics, matching, pricing, unlocks, and backend state transitions are intended to be reviewable; production driver operations, provider credentials, fraud controls, KYC, and safety playbooks remain private."
      />

      <Section
        alt
        eyebrow="What we believe"
        title="Three principles guide ShareCab."
      >
        <div className="grid sm:grid-cols-3 gap-5">
          <Principle title="Affordability">
            Sharing should always be cheaper than going solo. Our pricing is transparent and predictable.
          </Principle>
          <Principle title="Trust">
            Verified drivers, two-way ratings, live tracking, and SOS — built into every ride.
          </Principle>
          <Principle title="Simplicity">
            No complicated rules. Tap a destination, see your match, and ride.
          </Principle>
        </div>
      </Section>
    </>
  );
}

function Principle({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-sm muted leading-relaxed">{children}</p>
    </div>
  );
}
