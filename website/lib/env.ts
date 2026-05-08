// One place for every NEXT_PUBLIC_* the site reads. Keep defaults safe for
// local dev so the site builds even with no .env.local.
//
// Note: process.env values must be referenced as static property accesses
// (process.env.NEXT_PUBLIC_FOO) for Next.js to inline them at build time —
// don't refactor this to a dynamic loop.

const fallbackSiteUrl = 'http://localhost:3000';

export const env = {
  siteName: process.env.NEXT_PUBLIC_SITE_NAME ?? 'ShareCab',
  siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? fallbackSiteUrl,

  appStoreUrl: process.env.NEXT_PUBLIC_APP_STORE_URL ?? '',
  playStoreUrl: process.env.NEXT_PUBLIC_PLAY_STORE_URL ?? '',

  supportEmail: process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? 'support@sharecab.example',
  driverSupportEmail:
    process.env.NEXT_PUBLIC_DRIVER_SUPPORT_EMAIL ?? 'drivers@sharecab.example',
  partnershipsEmail:
    process.env.NEXT_PUBLIC_PARTNERSHIPS_EMAIL ?? 'hello@sharecab.example',

  contactFormEndpoint: process.env.NEXT_PUBLIC_CONTACT_FORM_ENDPOINT ?? '',

  gaId: process.env.NEXT_PUBLIC_GA_ID ?? '',
  plausibleDomain: process.env.NEXT_PUBLIC_PLAUSIBLE_DOMAIN ?? '',
};

export const hasAppLinks = Boolean(env.appStoreUrl || env.playStoreUrl);
