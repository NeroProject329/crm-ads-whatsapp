import { NextResponse } from 'next/server';

import { logoutCurrentSession } from '@/lib/auth/server';

export const dynamic = 'force-dynamic';

export async function POST(): Promise<NextResponse> {
  await logoutCurrentSession();
  return NextResponse.json({ success: true }, { status: 200 });
}
