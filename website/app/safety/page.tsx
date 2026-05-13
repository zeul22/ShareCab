import { Section } from '@/components/Section';
import { FeatureCard } from '@/components/FeatureCard';

export const metadata = { title: 'Safety — ShareCab' };

export default function SafetyPage() {
  return (
    <>
      <section className="container-page pt-20 pb-6">
        <h1 className="h-display max-w-3xl">Safety, built into every ride.</h1>
        <p className="mt-6 text-lg muted max-w-2xl">
          Sharing your ride should not mean losing control. ShareCab combines OTP,
          ratings, live trip state, driver verification goals, private chat, and public/private
          release boundaries so sensitive safety operations do not become public playbooks.
        </p>
      </section>

      <Section eyebrow="Protections" title="What you get on every trip.">
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <FeatureCard
            icon="✓"
            title="Verified drivers"
            description="License, ID, vehicle, and background checks before any driver can take rides."
          />
          <FeatureCard
            icon="◷"
            title="Live trip tracking"
            description="Your trip is tracked end to end. Share a live link with anyone in one tap."
          />
          <FeatureCard
            icon="!"
            title="In-app SOS"
            description="One-tap SOS pings emergency contacts and our 24/7 support team with your location."
          />
          <FeatureCard
            icon="★"
            title="Two-way ratings"
            description="Riders rate co-riders too. Riders below threshold lose access to shared rides."
          />
          <FeatureCard
            icon="◎"
            title="Phone-verified accounts"
            description="Every rider signs in with a real OTP via MSG91. No anonymous accounts, no shared logins, no fake numbers."
          />
          <FeatureCard
            icon="💬"
            title="In-app chat, no numbers"
            description="Coordinate the pickup spot with your co-rider through the app. Phone numbers stay private to both sides."
          />
          <FeatureCard
            icon="?"
            title="24/7 support"
            description="Real humans on call. Reachable from inside the app — during and after every trip."
          />
        </div>
      </Section>

      <Section
        alt
        eyebrow="Privacy"
        title="Your details stay yours."
        intro="Co-riders see only your first name and rating — never your phone number, address, or last name. The in-app chat is wiped automatically when the group composition changes (someone joins or leaves), so no leftover messages from a stranger."
      >
        <div className="grid sm:grid-cols-3 gap-5">
          <SafetyNote title="Public source">
            General safety UX, OTP flows, ratings, and trip-state logic can be reviewed publicly.
          </SafetyNote>
          <SafetyNote title="Private ops">
            Escalation contacts, fraud thresholds, incident playbooks, and production safety
            operations stay private.
          </SafetyNote>
          <SafetyNote title="No real user data">
            The public repository must not include rider, driver, trip, GPS, payment, complaint,
            or KYC data.
          </SafetyNote>
        </div>
      </Section>
    </>
  );
}

function SafetyNote({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-sm muted leading-relaxed">{children}</p>
    </div>
  );
}
