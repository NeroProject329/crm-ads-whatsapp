import { forwardBackendRequest } from '@/lib/backend/forward';

type RouteContext = Readonly<{ params: Promise<Readonly<{ teamId: string }>> }>;

export async function PATCH(request: Request, context: RouteContext): Promise<Response> {
  const { teamId } = await context.params;
  return forwardBackendRequest(request, `/management/teams/${encodeURIComponent(teamId)}`);
}
