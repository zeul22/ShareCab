import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // ShareCab palette — calm green for trust + clean neutrals.
        brand: {
          50:  '#eefbf3',
          100: '#d6f4e1',
          200: '#aee9c5',
          300: '#7dd9a3',
          400: '#4cc581',
          500: '#27a866',
          600: '#1c8852',
          700: '#176c44',
          800: '#145638',
          900: '#10422c',
        },
        ink: {
          900: '#0e1316',
          700: '#2a3338',
          500: '#566069',
          300: '#9aa3ab',
        },
      },
      fontFamily: {
        sans: ['var(--font-inter)', 'Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: { xl2: '1.25rem' },
    },
  },
  plugins: [],
};

export default config;
