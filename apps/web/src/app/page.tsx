import { redirect } from 'next/navigation';

import { hasSessionCookie } from '@/lib/auth/server';

export default async function HomePage() {
  redirect((await hasSessionCookie()) ? '/dashboard' : '/login');
}
