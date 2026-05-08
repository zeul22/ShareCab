import Script from 'next/script';
import { env } from '@/lib/env';

// Renders nothing unless one of the analytics env vars is set.
// We intentionally don't ship a fallback — silent is the right default.
export function Analytics() {
  return (
    <>
      {env.gaId && (
        <>
          <Script
            src={`https://www.googletagmanager.com/gtag/js?id=${env.gaId}`}
            strategy="afterInteractive"
          />
          <Script id="ga-init" strategy="afterInteractive">
            {`
              window.dataLayer = window.dataLayer || [];
              function gtag(){dataLayer.push(arguments);}
              gtag('js', new Date());
              gtag('config', '${env.gaId}', { anonymize_ip: true });
            `}
          </Script>
        </>
      )}

      {env.plausibleDomain && (
        <Script
          src="https://plausible.io/js/script.js"
          data-domain={env.plausibleDomain}
          strategy="afterInteractive"
          defer
        />
      )}
    </>
  );
}
