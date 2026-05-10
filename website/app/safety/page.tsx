import { Section } from '@/components/Section';
import { FeatureCard } from '@/components/FeatureCard';

export const metadata = { title: 'Safety — ShareCab' };

export default function SafetyPage() {
  return (
    <>
      <section className="container-page pt-20 pb-6">
        <h1 className="h-display max-w-3xl">Safety, built into every ride.</h1>
        <p className="mt-6 text-lg muted max-w-2xl">
          Sharing your ride doesn&rsquo;t mean compromising on safety. Every ShareCab trip ships with
          verification, tracking, and accountability — for both you and your co-rider.
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
      />
    </>
  );
}
